// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../../libraries/HedgepieLibraryBsc.sol";

interface IStrategy {
    function pendingReward(address _user) external view returns (uint256);

    function deposit(uint256 amount) external;

    function withdraw(uint256 amount) external;
}

contract PancakeStakeAdapterBsc is BaseAdapter {
    using SafeERC20 for IERC20;

    /**
     * @notice Construct
     * @param _strategy  address of strategy
     * @param _stakingToken  address of staking token
     * @param _swapRouter  address of swap router
     * @param _rewardToken  address of reward token
     * @param _wbnb  address of wbnb
     * @param _name  name of adapter
     * @param _hedgepieAuthority  hedgepieAuthority address
     */
    constructor(
        address _strategy,
        address _stakingToken,
        address _rewardToken,
        address _swapRouter,
        address _wbnb,
        string memory _name,
        address _hedgepieAuthority
    ) BaseAdapter(_hedgepieAuthority) {
        require(_rewardToken != address(0), "Invalid reward token");
        require(_stakingToken != address(0), "Invalid staking token");
        require(_strategy != address(0), "Invalid strategy address");

        stakingToken = _stakingToken;
        rewardToken = _rewardToken;
        swapRouter = _swapRouter;
        strategy = _strategy;
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
        uint256 _amountIn = msg.value;
        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId];

        // get staking token
        if (router == address(0)) {
            amountOut = HedgepieLibraryBsc.swapOnRouter(
                _amountIn,
                address(this),
                stakingToken,
                swapRouter
            );
        } else {
            amountOut = HedgepieLibraryBsc.getLP(
                IYBNFT.AdapterParam(0, address(this)),
                stakingToken,
                _amountIn
            );
        }

        // calc reward amount
        uint256 rewardAmt0 = IERC20(rewardToken).balanceOf(address(this));
        IERC20(stakingToken).safeApprove(strategy, 0);
        IERC20(stakingToken).safeApprove(strategy, amountOut);
        IStrategy(strategy).deposit(amountOut);
        rewardAmt0 = IERC20(rewardToken).balanceOf(address(this)) - rewardAmt0;

        // update accTokenPerShare if reward is generated
        if (rewardAmt0 != 0 && mAdapter.totalStaked != 0) {
            mAdapter.accTokenPerShare1 +=
                (rewardAmt0 * 1e12) /
                mAdapter.totalStaked;
        }

        // update user's info - rewardDebt, userShare
        if (userInfo.amount != 0) {
            userInfo.rewardDebt1 +=
                (userInfo.amount *
                    (mAdapter.accTokenPerShare1 - userInfo.userShare1)) /
                1e12;
        }

        // update mAdapter & user Info
        mAdapter.totalStaked += amountOut;
        userInfo.userShare1 = mAdapter.accTokenPerShare1;
        userInfo.amount += amountOut;

        return _amountIn;
    }

    /**
     * @notice Withdraw the deposited Bnb
     * @param _tokenId YBNFT token id
     * @param _amount staking token amount to withdraw
     */
    function withdraw(
        uint256 _tokenId,
        uint256 _amount
    ) external payable override onlyInvestor returns (uint256 amountOut) {
        if (_amount == 0) return 0;

        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId];

        // validation of _amount parameter
        require(_amount <= userInfo.amount, "Not enough balance to withdraw");

        // 1. calc reward and withdraw from adapter
        uint256 rewardAmt0 = IERC20(rewardToken).balanceOf(address(this));
        amountOut = IERC20(stakingToken).balanceOf(address(this));
        IStrategy(strategy).withdraw(_amount);
        rewardAmt0 = IERC20(rewardToken).balanceOf(address(this)) - rewardAmt0;
        amountOut = IERC20(stakingToken).balanceOf(address(this)) - amountOut;
        require(_amount == amountOut, "Failed to withdraw");

        // 2. update accTokenPerShare if reward is generated
        if (rewardAmt0 != 0 && mAdapter.totalStaked != 0) {
            mAdapter.accTokenPerShare1 +=
                (rewardAmt0 * 1e12) /
                mAdapter.totalStaked;
        }

        // 3. swap withdrawn staking tokens to bnb
        if (router == address(0)) {
            amountOut = HedgepieLibraryBsc.swapForBnb(
                amountOut,
                address(this),
                stakingToken,
                swapRouter
            );
        } else {
            amountOut = HedgepieLibraryBsc.withdrawLP(
                IYBNFT.AdapterParam(0, address(this)),
                stakingToken,
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
                swapRouter
            );
        }

        if (rewardBnb != 0) amountOut += rewardBnb;

        // 6. update mAdapter & user Info
        mAdapter.totalStaked -= _amount;
        userInfo.amount -= _amount;
        userInfo.userShare1 = mAdapter.accTokenPerShare1;
        userInfo.rewardDebt1 = 0;

        // 7. send bnb to treasury and investor
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

        // 1. check if reward is generated
        uint256 rewardAmt0 = IERC20(rewardToken).balanceOf(address(this));
        IStrategy(strategy).withdraw(0);
        rewardAmt0 = IERC20(rewardToken).balanceOf(address(this)) - rewardAmt0;
        if (rewardAmt0 != 0 && mAdapter.totalStaked != 0) {
            mAdapter.accTokenPerShare1 +=
                (rewardAmt0 * 1e12) /
                mAdapter.totalStaked;
        }

        // 2. get reward amount
        (uint256 reward, ) = HedgepieLibraryBsc.getMRewards(
            _tokenId,
            address(this)
        );

        // 3. update user info
        userInfo.userShare1 = mAdapter.accTokenPerShare1;
        userInfo.rewardDebt1 = 0;

        // 4. swap reward to bnb and send to investor
        if (reward != 0) {
            amountOut += HedgepieLibraryBsc.swapForBnb(
                reward,
                address(this),
                rewardToken,
                swapRouter
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
            updatedAccTokenPerShare += ((IStrategy(strategy).pendingReward(
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

    /**
     * @notice Remove funds
     * @param _tokenId YBNFT token id
     */
    function removeFunds(
        uint256 _tokenId
    ) external payable override onlyInvestor returns (uint256 amountOut) {
        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId];
        if (userInfo.amount == 0) return 0;

        // 1. update reward infor after withdraw all staking tokens
        uint256 rewardAmt0 = IERC20(rewardToken).balanceOf(address(this));
        amountOut = IERC20(stakingToken).balanceOf(address(this));
        IStrategy(strategy).withdraw(userInfo.amount);
        amountOut = IERC20(stakingToken).balanceOf(address(this)) - amountOut;
        rewardAmt0 = IERC20(rewardToken).balanceOf(address(this)) - rewardAmt0;
        require(userInfo.amount == amountOut, "Failed to remove funds");

        // 2. update mAdapter infor
        if (rewardAmt0 != 0) {
            mAdapter.accTokenPerShare1 +=
                (rewardAmt0 * 1e12) /
                mAdapter.totalStaked;
        }

        // 3. update user rewardDebt value
        if (userInfo.amount != 0) {
            userInfo.rewardDebt1 +=
                (userInfo.amount *
                    (mAdapter.accTokenPerShare1 - userInfo.userShare1)) /
                1e12;
        }

        // 4. swap withdrawn lp to bnb
        if (router == address(0)) {
            amountOut = HedgepieLibraryBsc.swapForBnb(
                amountOut,
                address(this),
                stakingToken,
                swapRouter
            );
        } else {
            amountOut = HedgepieLibraryBsc.withdrawLP(
                IYBNFT.AdapterParam(0, address(this)),
                stakingToken,
                amountOut
            );
        }

        // 5. update invested information for token id
        mAdapter.totalStaked -= userInfo.amount;
        userInfo.amount = 0;
        userInfo.userShare1 = mAdapter.accTokenPerShare1;

        // 6. send to investor
        (bool success, ) = payable(authority.hInvestor()).call{
            value: amountOut
        }("");
        require(success, "Failed to send bnb to investor");
    }

    /**
     * @notice Update funds
     * @param _tokenId YBNFT token id
     */
    function updateFunds(
        uint256 _tokenId
    ) external payable override onlyInvestor returns (uint256 amountOut) {
        if (msg.value == 0) return 0;

        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId];

        // 1. swap bnb to staking token
        if (router == address(0)) {
            amountOut = HedgepieLibraryBsc.swapOnRouter(
                msg.value,
                address(this),
                stakingToken,
                swapRouter
            );
        } else {
            amountOut = HedgepieLibraryBsc.getLP(
                IYBNFT.AdapterParam(0, address(this)),
                stakingToken,
                msg.value
            );
        }

        // 2. get reward amount after deposit
        uint256 rewardAmt0 = IERC20(rewardToken).balanceOf(address(this));
        IERC20(stakingToken).safeApprove(strategy, 0);
        IERC20(stakingToken).safeApprove(strategy, amountOut);
        IStrategy(strategy).deposit(amountOut);
        rewardAmt0 = IERC20(rewardToken).balanceOf(address(this)) - rewardAmt0;

        // 3. update reward infor
        if (rewardAmt0 != 0 && mAdapter.totalStaked != 0) {
            mAdapter.accTokenPerShare1 +=
                (rewardAmt0 * 1e12) /
                mAdapter.totalStaked;
        }

        // 4. update mAdapter & userInfo
        mAdapter.totalStaked += amountOut;
        userInfo.amount = amountOut;
        userInfo.userShare1 = mAdapter.accTokenPerShare1;

        return msg.value;
    }
}
