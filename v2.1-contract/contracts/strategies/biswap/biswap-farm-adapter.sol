// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../../libraries/HedgepieLibraryBsc.sol";
import "../../interfaces/IHedgepieInvestor.sol";

interface IStrategy {
    function pendingBSW(
        uint256 _pid,
        address _user
    ) external view returns (uint256);

    function deposit(uint256 pid, uint256 amount) external;

    function withdraw(uint256 pid, uint256 amount) external;

    function enterStaking(uint256 amount) external;

    function leaveStaking(uint256 amount) external;
}

contract BiSwapFarmLPAdapterBsc is BaseAdapter {
    /**
     * @notice Construct
     * @param _strategy  address of strategy
     * @param _stakingToken  address of staking token
     * @param _rewardToken  address of reward token
     * @param _router  address of biswap
     * @param _swapRouter  address of swap router
     * @param _wbnb  wbnb address
     * @param _name  adatper name
     * @param _hedgepieAuthority  hedgepieAuthority address
     */
    constructor(
        uint256 _pid,
        address _strategy,
        address _stakingToken,
        address _rewardToken,
        address _router,
        address _swapRouter,
        address _wbnb,
        string memory _name,
        address _hedgepieAuthority
    ) BaseAdapter(_hedgepieAuthority) {
        pid = _pid;
        stakingToken = _stakingToken;
        rewardToken = _rewardToken;
        strategy = _strategy;
        router = _router;
        swapRouter = _swapRouter;
        wbnb = _wbnb;
        name = _name;
    }

    /**
     * @notice Deposit with BNB
     * @param _tokenId YBNFT token id
     */
    function deposit(
        uint256 _tokenId
    ) external payable override onlyInvestor returns (uint256 amountOut) {
        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId];

        uint256 rewardAmt = IERC20(rewardToken).balanceOf(address(this));

        // 1. swap to staking token
        if (router == address(0)) {
            amountOut = HedgepieLibraryBsc.swapOnRouter(
                msg.value,
                address(this),
                stakingToken,
                swapRouter,
                wbnb
            );
        } else {
            amountOut = HedgepieLibraryBsc.getLP(
                IYBNFT.AdapterParam(0, stakingToken, address(this)),
                wbnb,
                msg.value
            );
        }

        // 2. deposit staking token to strategy
        IERC20(stakingToken).approve(strategy, amountOut);
        if (pid == 0) IStrategy(strategy).enterStaking(amountOut);
        else IStrategy(strategy).deposit(pid, amountOut);

        unchecked {
            // 3. check reward amount
            rewardAmt =
                IERC20(rewardToken).balanceOf(address(this)) -
                rewardAmt;

            // 4. update accTokenPerShare if reward is generated
            if (rewardAmt != 0 && mAdapter.totalStaked != 0) {
                mAdapter.accTokenPerShare1 +=
                    (rewardAmt * 1e12) /
                    mAdapter.totalStaked;
            }

            // 5. update user's rewardDebt value when user staked several times
            if (userInfo.amount != 0) {
                userInfo.rewardDebt1 +=
                    (userInfo.amount *
                        (mAdapter.accTokenPerShare1 - userInfo.userShare1)) /
                    1e12;
            }

            // 6. update mAdapter & userInfo
            userInfo.amount += amountOut;
            userInfo.userShare1 = mAdapter.accTokenPerShare1;
            mAdapter.totalStaked += amountOut;

            amountOut = msg.value;
        }
    }

    /**
     * @notice Withdraw the deposited Bnb
     * @param _tokenId YBNFT token id
     * @param _amount amount of staking token to withdraw
     */
    function withdraw(
        uint256 _tokenId,
        uint256 _amount
    ) external payable override onlyInvestor returns (uint256 amountOut) {
        if (_amount == 0) return 0;

        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId];

        // validation of _amount parameter
        require(_amount <= userInfo.amount, "Not enough balance to withdraw");

        // 1. calc reward after withdraw
        bool isSame = stakingToken == rewardToken;
        amountOut = IERC20(stakingToken).balanceOf(address(this));
        uint256 rewardAmt = isSame
            ? amountOut
            : IERC20(rewardToken).balanceOf(address(this));

        if (pid == 0) IStrategy(strategy).leaveStaking(_amount);
        else IStrategy(strategy).withdraw(pid, _amount);

        unchecked {
            amountOut =
                IERC20(stakingToken).balanceOf(address(this)) -
                amountOut;

            if (isSame) {
                amountOut = amountOut > _amount ? _amount : amountOut;
                rewardAmt = amountOut > _amount ? amountOut - _amount : 0;
            } else {
                rewardAmt =
                    IERC20(rewardToken).balanceOf(address(this)) -
                    rewardAmt;
            }

            require(_amount == amountOut, "Failed to withdraw");

            // 2. update accTokenPerShare if reward is generated
            if (rewardAmt != 0) {
                mAdapter.accTokenPerShare1 +=
                    (rewardAmt * 1e12) /
                    mAdapter.totalStaked;
            }
        }

        // 3. swap withdrawn staking tokens to bnb
        if (router == address(0)) {
            amountOut = HedgepieLibraryBsc.swapForBnb(
                amountOut,
                address(this),
                stakingToken,
                swapRouter,
                wbnb
            );
        } else {
            amountOut = HedgepieLibraryBsc.withdrawLP(
                IYBNFT.AdapterParam(0, stakingToken, address(this)),
                wbnb,
                amountOut
            );
        }

        // 4. get user's rewards
        (uint256 reward, ) = HedgepieLibraryBsc.getMRewards(
            _tokenId,
            address(this)
        );

        // 5. swap reward to bnb
        uint256 rewardBnb;
        if (reward != 0) {
            rewardBnb = HedgepieLibraryBsc.swapForBnb(
                reward,
                address(this),
                rewardToken,
                swapRouter,
                wbnb
            );

            amountOut += rewardBnb;
        }

        // 6. update mAdapter & user Info
        unchecked {
            mAdapter.totalStaked -= _amount;

            userInfo.amount -= _amount;
            userInfo.userShare1 = mAdapter.accTokenPerShare1;
            userInfo.rewardDebt1 = 0;
        }

        // 7. send to treasury and investor
        if (amountOut != 0) {
            bool success;
            if (rewardBnb != 0) {
                rewardBnb =
                    (rewardBnb *
                        IYBNFT(authority.hYBNFT()).performanceFee(_tokenId)) /
                    1e4;
                (success, ) = payable(
                    IHedgepieInvestor(authority.hInvestor()).treasury()
                ).call{value: rewardBnb}("");
                require(success, "Failed to send bnb to Treasury");
            }

            (success, ) = payable(msg.sender).call{
                value: amountOut - rewardBnb
            }("");
            require(success, "Failed to send bnb");
        }
    }

    /**
     * @notice Claim the pending reward
     * @param _tokenId YBNFT token id
     */
    function claim(
        uint256 _tokenId
    ) external payable override onlyInvestor returns (uint256 amountOut) {
        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId];

        // 1. calc & claim rewards
        uint256 rewardAmt = IERC20(rewardToken).balanceOf(address(this));

        if (pid == 0) IStrategy(strategy).leaveStaking(0);
        else IStrategy(strategy).withdraw(pid, 0);

        unchecked {
            rewardAmt =
                IERC20(rewardToken).balanceOf(address(this)) -
                rewardAmt;

            // 2. update mAdapter infor
            if (
                rewardAmt != 0 &&
                rewardToken != address(0) &&
                mAdapter.totalStaked != 0
            ) {
                mAdapter.accTokenPerShare1 +=
                    (rewardAmt * 1e12) /
                    mAdapter.totalStaked;
            }
        }

        // 3. get user's rewards
        (uint256 reward, ) = HedgepieLibraryBsc.getMRewards(
            _tokenId,
            address(this)
        );

        // 4. update user info
        unchecked {
            userInfo.userShare1 = mAdapter.accTokenPerShare1;
            userInfo.rewardDebt1 = 0;
        }

        if (reward != 0) {
            // 5. swap reward to bnb
            amountOut = HedgepieLibraryBsc.swapForBnb(
                reward,
                address(this),
                rewardToken,
                swapRouter,
                wbnb
            );

            _sendToInvestor(amountOut, _tokenId);
        }
    }

    /**
     * @notice Return the pending reward by Bnb
     * @param _tokenId YBNFT token id
     */
    function pendingReward(
        uint256 _tokenId
    ) external view override returns (uint256 reward, uint256 withdrawable) {
        UserAdapterInfo memory userInfo = userAdapterInfos[_tokenId];

        // 1. calc updatedAccTokenPerShare
        uint256 updatedAccTokenPerShare = mAdapter.accTokenPerShare1;
        if (mAdapter.totalStaked != 0)
            updatedAccTokenPerShare += ((IStrategy(strategy).pendingBSW(
                pid,
                address(this)
            ) * 1e12) / mAdapter.totalStaked);

        // 2. calc rewards from updatedAccTokenPerShare
        uint256 tokenRewards = ((updatedAccTokenPerShare -
            userInfo.userShare1) * userInfo.amount) /
            1e12 +
            userInfo.rewardDebt1;

        // 3. calc pending reward in bnb
        if (tokenRewards != 0) {
            if (rewardToken == wbnb) reward = tokenRewards;
            else {
                address[] memory paths = IPathFinder(authority.pathFinder())
                    .getPaths(swapRouter, rewardToken, wbnb);

                reward = IPancakeRouter(swapRouter).getAmountsOut(
                    tokenRewards,
                    paths
                )[paths.length - 1];
            }

            withdrawable = reward;
        }
    }

    receive() external payable {}
}
