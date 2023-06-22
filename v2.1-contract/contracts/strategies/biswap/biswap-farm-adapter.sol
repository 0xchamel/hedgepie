// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../../libraries/HedgepieLibraryBsc.sol";

interface IStrategy {
    function pendingBSW(uint256 _pid, address _user) external view returns (uint256);

    function deposit(uint256 pid, uint256 amount) external;

    function withdraw(uint256 pid, uint256 amount) external;

    function enterStaking(uint256 amount) external;

    function leaveStaking(uint256 amount) external;
}

contract BiSwapFarmLPAdapterBsc is BaseAdapter {
    using SafeERC20 for IERC20;

    /**
     * @notice Constructor
     * @param _strategy  address of strategy
     * @param _stakingToken  address of staking token
     * @param _rewardToken  address of reward token
     * @param _router  address of biswap
     * @param _swapRouter  address of swap router
     * @param _label  adatper label
     * @param _authority  hedgepieAuthority address
     */
    constructor(
        uint256 _pid,
        address _strategy,
        address _stakingToken,
        address _rewardToken,
        address _router,
        address _swapRouter,
        string memory _label,
        address _authority
    ) BaseAdapter(_authority) {
        require(_rewardToken != address(0), "Invalid reward token");
        require(_stakingToken != address(0), "Invalid staking token");
        require(_strategy != address(0), "Invalid strategy address");

        pid = _pid;
        stakingToken = _stakingToken;
        rewardToken1 = _rewardToken;
        strategy = _strategy;
        router = _router;
        swapRouter = _swapRouter;
        label = _label;
    }

    /**
     * @notice Deposit with BNB
     * @param _tokenId YBNFT token id
     */
    /// #if_succeeds {:msg "deposit failed"}  userAdapterInfos[_tokenId].userShare1 == mAdapter.accTokenPerShare1 && mAdapter.totalStaked > old(mAdapter.totalStaked);
    function deposit(uint256 _tokenId) external payable override onlyInvestor returns (uint256 amountOut) {
        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId];

        uint256 rewardAmt = IERC20(rewardToken1).balanceOf(address(this));

        // 1. swap to staking token
        if (router == address(0)) {
            amountOut = HedgepieLibraryBsc.swapOnRouter(msg.value, address(this), stakingToken, swapRouter);
        } else {
            amountOut = HedgepieLibraryBsc.getLP(IYBNFT.AdapterParam(0, address(this)), stakingToken, msg.value);
        }

        // 2. deposit staking token to strategy
        IERC20(stakingToken).safeApprove(strategy, 0);
        IERC20(stakingToken).safeApprove(strategy, amountOut);
        if (pid == 0) IStrategy(strategy).enterStaking(amountOut);
        else IStrategy(strategy).deposit(pid, amountOut);

        unchecked {
            // 3. check reward amount
            rewardAmt = IERC20(rewardToken1).balanceOf(address(this)) - rewardAmt;

            // 4. update accTokenPerShare if reward is generated
            if (rewardAmt != 0 && mAdapter.totalStaked != 0) {
                mAdapter.accTokenPerShare1 += (rewardAmt * 1e12) / mAdapter.totalStaked;
            }

            // 5. update user's rewardDebt value when user staked several times
            if (userInfo.amount != 0) {
                userInfo.rewardDebt1 += (userInfo.amount * (mAdapter.accTokenPerShare1 - userInfo.userShare1)) / 1e12;
            }

            // 6. update mAdapter & userInfo
            userInfo.amount += amountOut;
            userInfo.userShare1 = mAdapter.accTokenPerShare1;
            mAdapter.totalStaked += amountOut;

            amountOut = msg.value;
        }
    }

    /**
     * @notice Withdraw from strategy
     * @param _tokenId YBNFT token id
     * @param _amount amount of staking token to withdraw
     */
    /// #if_succeeds {:msg "withdraw failed"}  userAdapterInfos[_tokenId].userShare1 == mAdapter.accTokenPerShare1 && userAdapterInfos[_tokenId].rewardDebt1 == 0;
    function withdraw(
        uint256 _tokenId,
        uint256 _amount
    ) external payable override onlyInvestor returns (uint256 amountOut) {
        if (_amount == 0) return 0;

        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId];

        // validation of _amount parameter
        require(_amount <= userInfo.amount, "Not enough balance to withdraw");

        amountOut = IERC20(stakingToken).balanceOf(address(this));
        uint256 rewardAmt = pid == 0 ? amountOut : IERC20(rewardToken1).balanceOf(address(this));

        if (pid == 0) IStrategy(strategy).leaveStaking(_amount);
        else IStrategy(strategy).withdraw(pid, _amount);

        unchecked {
            amountOut = IERC20(stakingToken).balanceOf(address(this)) - amountOut;

            if (pid == 0) {
                rewardAmt = amountOut - _amount;
                amountOut = _amount;
            } else {
                rewardAmt = IERC20(rewardToken1).balanceOf(address(this)) - rewardAmt;
            }

            require(_amount == amountOut, "Failed to withdraw");

            // 2. update accTokenPerShare if reward is generated
            if (rewardAmt != 0) {
                mAdapter.accTokenPerShare1 += (rewardAmt * 1e12) / mAdapter.totalStaked;
            }
        }

        // 3. swap withdrawn staking tokens to bnb
        if (router == address(0)) {
            amountOut = HedgepieLibraryBsc.swapForBnb(amountOut, address(this), stakingToken, swapRouter);
        } else {
            amountOut = HedgepieLibraryBsc.withdrawLP(IYBNFT.AdapterParam(0, address(this)), stakingToken, amountOut);
        }

        // 4. get user's rewards
        (uint256 reward, ) = HedgepieLibraryBsc.getMRewards(_tokenId, address(this));

        // 5. swap reward to bnb
        uint256 rewardBnb;
        if (reward != 0) {
            rewardBnb = HedgepieLibraryBsc.swapForBnb(reward, address(this), rewardToken1, swapRouter);

            amountOut += rewardBnb;
        }

        // 6. update mAdapter & user Info
        unchecked {
            mAdapter.totalStaked -= _amount;

            userInfo.amount -= _amount;
            userInfo.userShare1 = mAdapter.accTokenPerShare1;
            userInfo.rewardDebt1 = 0;
        }

        // 7. charge fee and send BNB to investor
        if (amountOut != 0) _chargeFeeAndSendToInvestor(_tokenId, amountOut, rewardBnb);
    }

    /**
     * @notice Claim the pending reward
     * @param _tokenId YBNFT token id
     */
    /// #if_succeeds {:msg "claim failed"}  userAdapterInfos[_tokenId].userShare1 == mAdapter.accTokenPerShare1 && userAdapterInfos[_tokenId].rewardDebt1 == 0;
    function claim(uint256 _tokenId) external payable override onlyInvestor returns (uint256 amountOut) {
        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId];

        // 1. calc & claim rewards
        uint256 rewardAmt = IERC20(rewardToken1).balanceOf(address(this));

        if (pid == 0) IStrategy(strategy).leaveStaking(0);
        else IStrategy(strategy).withdraw(pid, 0);

        // 2. update mAdapter info
        unchecked {
            rewardAmt = IERC20(rewardToken1).balanceOf(address(this)) - rewardAmt;

            if (rewardAmt != 0 && mAdapter.totalStaked != 0) {
                mAdapter.accTokenPerShare1 += (rewardAmt * 1e12) / mAdapter.totalStaked;
            }
        }

        // 3. get user's rewards
        (uint256 reward, ) = HedgepieLibraryBsc.getMRewards(_tokenId, address(this));

        // 4. update user info
        userInfo.userShare1 = mAdapter.accTokenPerShare1;
        userInfo.rewardDebt1 = 0;

        // 4. swap reward to bnb and send to investor
        if (reward != 0) {
            amountOut = HedgepieLibraryBsc.swapForBnb(reward, address(this), rewardToken1, swapRouter);
            // 5. charge fee and send BNB to investor
            _chargeFeeAndSendToInvestor(_tokenId, amountOut, amountOut);
        }
    }

    /**
     * @notice Return the pending reward by Bnb
     * @param _tokenId YBNFT token id
     */
    function pendingReward(uint256 _tokenId) external view override returns (uint256 reward, uint256 withdrawable) {
        UserAdapterInfo memory userInfo = userAdapterInfos[_tokenId];

        // 1. calc updatedAccTokenPerShare
        uint256 updatedAccTokenPerShare = mAdapter.accTokenPerShare1;
        if (mAdapter.totalStaked != 0)
            updatedAccTokenPerShare += ((IStrategy(strategy).pendingBSW(pid, address(this)) * 1e12) /
                mAdapter.totalStaked);

        // 2. calc rewards from updatedAccTokenPerShare
        uint256 tokenRewards = ((updatedAccTokenPerShare - userInfo.userShare1) * userInfo.amount) /
            1e12 +
            userInfo.rewardDebt1;

        // 3. calc pending reward in bnb
        if (tokenRewards != 0) {
            if (rewardToken1 == HedgepieLibraryBsc.WBNB) reward = tokenRewards;
            else {
                address[] memory paths = IPathFinder(authority.pathFinder()).getPaths(
                    swapRouter,
                    rewardToken1,
                    HedgepieLibraryBsc.WBNB
                );

                reward = IPancakeRouter(swapRouter).getAmountsOut(tokenRewards, paths)[paths.length - 1];
            }

            withdrawable = reward;
        }
    }

    /**
     * @notice Remove funds
     * @param _tokenId YBNFT token id
     */
    /// #if_succeeds {:msg "removeFunds failed"}  userAdapterInfos[_tokenId].userShare1 == mAdapter.accTokenPerShare1 && userAdapterInfos[_tokenId].amount == 0;
    function removeFunds(uint256 _tokenId) external payable override onlyInvestor returns (uint256 amountOut) {
        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId];
        if (userInfo.amount == 0) return 0;

        // 1. update reward infor after withdraw all staking tokens
        uint256 rewardAmt = IERC20(rewardToken1).balanceOf(address(this));
        amountOut = IERC20(stakingToken).balanceOf(address(this));

        // withdraw from strategy
        if (pid == 0) IStrategy(strategy).leaveStaking(userInfo.amount);
        else IStrategy(strategy).withdraw(pid, userInfo.amount);

        unchecked {
            amountOut = IERC20(stakingToken).balanceOf(address(this)) - amountOut;

            if (pid == 0) {
                rewardAmt = amountOut - userInfo.amount;
                amountOut = userInfo.amount;
            } else {
                rewardAmt = IERC20(rewardToken1).balanceOf(address(this)) - rewardAmt;
            }

            require(userInfo.amount == amountOut, "Failed to remove funds");

            // 2. update mAdapter info
            if (rewardAmt != 0) {
                mAdapter.accTokenPerShare1 += (rewardAmt * 1e12) / mAdapter.totalStaked;
            }

            // 3. update user rewardDebt value
            if (userInfo.amount != 0) {
                userInfo.rewardDebt1 += (userInfo.amount * (mAdapter.accTokenPerShare1 - userInfo.userShare1)) / 1e12;
            }
        }

        // 4. swap withdrawn lp to bnb
        if (router == address(0)) {
            amountOut = HedgepieLibraryBsc.swapForBnb(amountOut, address(this), stakingToken, swapRouter);
        } else {
            amountOut = HedgepieLibraryBsc.withdrawLP(IYBNFT.AdapterParam(0, address(this)), stakingToken, amountOut);
        }

        // 5. update invested information for token id
        mAdapter.totalStaked -= userInfo.amount;
        userInfo.amount = 0;
        userInfo.userShare1 = mAdapter.accTokenPerShare1;

        // 6. send to investor
        if (amountOut != 0) _chargeFeeAndSendToInvestor(_tokenId, amountOut, 0);
    }

    /**
     * @notice Update funds
     * @param _tokenId YBNFT token id
     */
    /// #if_succeeds {:msg "updateFunds failed"}  userAdapterInfos[_tokenId].userShare1 == mAdapter.accTokenPerShare1;
    function updateFunds(uint256 _tokenId) external payable override onlyInvestor returns (uint256 amountOut) {
        if (msg.value == 0) return 0;

        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId];

        uint256 rewardAmt = IERC20(rewardToken1).balanceOf(address(this));

        // 1. swap bnb to staking token
        if (router == address(0)) {
            amountOut = HedgepieLibraryBsc.swapOnRouter(msg.value, address(this), stakingToken, swapRouter);
        } else {
            amountOut = HedgepieLibraryBsc.getLP(IYBNFT.AdapterParam(0, address(this)), stakingToken, msg.value);
        }

        // 2. get reward amount after deposit
        IERC20(stakingToken).safeApprove(strategy, 0);
        IERC20(stakingToken).safeApprove(strategy, amountOut);
        if (pid == 0) IStrategy(strategy).enterStaking(amountOut);
        else IStrategy(strategy).deposit(pid, amountOut);

        // 3. update reward info
        unchecked {
            rewardAmt = IERC20(rewardToken1).balanceOf(address(this)) - rewardAmt;

            // update reward info
            if (rewardAmt != 0 && mAdapter.totalStaked != 0) {
                mAdapter.accTokenPerShare1 += (rewardAmt * 1e12) / mAdapter.totalStaked;
            }

            // 4. update mAdapter & userInfo
            mAdapter.totalStaked += amountOut;
            userInfo.amount = amountOut;
            userInfo.userShare1 = mAdapter.accTokenPerShare1;
        }

        return msg.value;
    }
}
