// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../../libraries/HedgepieLibraryBsc.sol";

interface IStrategy {
    function pendingCake(
        uint256 _pid,
        address _user
    ) external view returns (uint256);

    function deposit(uint256 pid, uint256 shares) external;

    function withdraw(uint256 pid, uint256 shares) external;
}

contract PancakeSwapFarmLPAdapterBsc is BaseAdapter {
    using SafeERC20 for IERC20;

    /**
     * @notice Construct
     * @param _pid  pool id of strategy
     * @param _strategy  address of strategy
     * @param _stakingToken  address of staking token
     * @param _rewardToken  address of reward token
     * @param _router  address of router for lp token
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
        address _wbnb,
        string memory _name,
        address _hedgepieAuthority
    ) BaseAdapter(_hedgepieAuthority) {
        require(_rewardToken != address(0), "Invalid reward token");
        require(_stakingToken != address(0), "Invalid staking token");
        require(_strategy != address(0), "Invalid strategy address");

        pid = _pid;
        stakingToken = _stakingToken;
        rewardToken = _rewardToken;
        strategy = _strategy;
        router = _router;
        swapRouter = _router;
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

        // 1. swap to staking token
        if (router == address(0)) {
            amountOut = HedgepieLibraryBsc.swapOnRouter(
                msg.value,
                address(this),
                stakingToken,
                router
            );
        } else {
            amountOut = HedgepieLibraryBsc.getLP(
                IYBNFT.AdapterParam(0, address(this)),
                stakingToken,
                msg.value
            );
        }

        // 2. calc reward amount
        uint256 rewardAmt0 = IERC20(rewardToken).balanceOf(address(this));
        IERC20(stakingToken).safeApprove(strategy, 0);
        IERC20(stakingToken).safeApprove(strategy, amountOut);
        IStrategy(strategy).deposit(pid, amountOut);
        rewardAmt0 = IERC20(rewardToken).balanceOf(address(this)) - rewardAmt0;

        // 3. update accTokenPerShare if reward is generated
        if (rewardAmt0 != 0 && mAdapter.totalStaked != 0) {
            mAdapter.accTokenPerShare1 +=
                (rewardAmt0 * 1e12) /
                mAdapter.totalStaked;
        }

        // 4. update user's rewardDebt value when user staked several times
        if (userInfo.amount != 0) {
            userInfo.rewardDebt1 +=
                (userInfo.amount *
                    (mAdapter.accTokenPerShare1 - userInfo.userShare1)) /
                1e12;
        }

        // 5. update mAdapter & userInfo
        userInfo.amount += amountOut;
        userInfo.userShare1 = mAdapter.accTokenPerShare1;
        mAdapter.totalStaked += amountOut;

        return msg.value;
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

        // 1. calc reward and withdraw from adapter
        uint256 rewardAmt0 = IERC20(rewardToken).balanceOf(address(this));
        amountOut = IERC20(stakingToken).balanceOf(address(this));
        IStrategy(strategy).withdraw(pid, _amount);
        rewardAmt0 = IERC20(rewardToken).balanceOf(address(this)) - rewardAmt0;
        amountOut = IERC20(stakingToken).balanceOf(address(this)) - amountOut;
        require(_amount == amountOut, "Failed to withdraw");

        // 2. update accTokenPerShare if reward is generated
        if (rewardAmt0 != 0) {
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
        if (amountOut != 0) _sendToInvestor(_tokenId, amountOut, rewardBnb);
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
        IStrategy(strategy).withdraw(pid, 0);
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
            amountOut = HedgepieLibraryBsc.swapForBnb(
                reward,
                address(this),
                rewardToken,
                swapRouter
            );

            _sendToInvestor(_tokenId, amountOut, amountOut);
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
            updatedAccTokenPerShare += ((IStrategy(strategy).pendingCake(
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
        IStrategy(strategy).withdraw(pid, userInfo.amount);
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
        IStrategy(strategy).deposit(pid, amountOut);
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
