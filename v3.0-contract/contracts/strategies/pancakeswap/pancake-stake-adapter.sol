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
     * @notice Initializer
     * @param _strategy  address of strategy
     * @param _stakingToken  address of staking token
     * @param _swapRouter  address of swap router
     * @param _rewardToken  address of reward token
     * @param _name  name of adapter
     * @param _authority  hedgepieAuthority address
     */
    function initialize(
        address _strategy,
        address _stakingToken,
        address _rewardToken,
        address _swapRouter,
        string memory _name,
        address _authority
    ) external initializer {
        require(_rewardToken != address(0), "Invalid reward token");
        require(_stakingToken != address(0), "Invalid staking token");
        require(_strategy != address(0), "Invalid strategy address");

        __BaseAdapter__init(_authority);

        adapterDetails.push(
            AdapterDetail({
                pid: 0,
                stakingToken: _stakingToken,
                rewardToken1: _rewardToken,
                rewardToken2: address(0),
                repayToken: address(0),
                strategy: _strategy,
                router: address(0),
                swapRouter: _swapRouter,
                name: _name
            })
        );
    }

    /**
     * @notice Deposit with BNB
     * @param _tokenId YBNFT token id
     * @param _index index of strategies
     */
    /// #if_succeeds {:msg "deposit failed"}  userAdapterInfos[_tokenId].userShare1 == mAdapters[_index].accTokenPerShare1 && mAdapters[_index].totalStaked > old(mAdapters[_index].totalStaked);
    function deposit(
        uint256 _tokenId,
        uint256 _index
    ) external payable override onlyInvestor returns (uint256 amountOut) {
        uint256 _amountIn = msg.value;
        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId][_index];
        AdapterDetail memory aDetail = adapterDetails[_index];

        // get staking token
        if (aDetail.router == address(0)) {
            amountOut = HedgepieLibraryBsc.swapOnRouter(
                _amountIn,
                address(this),
                aDetail.stakingToken,
                aDetail.swapRouter
            );
        } else {
            amountOut = HedgepieLibraryBsc.getLP(
                aDetail,
                IYBNFT.AdapterParam(0, address(this), _index),
                aDetail.stakingToken,
                _amountIn
            );
        }

        // calc reward amount
        uint256 rewardAmt0 = IERC20(aDetail.rewardToken1).balanceOf(address(this));
        IERC20(aDetail.stakingToken).safeApprove(aDetail.strategy, 0);
        IERC20(aDetail.stakingToken).safeApprove(aDetail.strategy, amountOut);
        IStrategy(aDetail.strategy).deposit(amountOut);
        rewardAmt0 = IERC20(aDetail.rewardToken1).balanceOf(address(this)) - rewardAmt0;

        // update accTokenPerShare if reward is generated
        if (rewardAmt0 != 0 && mAdapters[_index].totalStaked != 0) {
            mAdapters[_index].accTokenPerShare1 += (rewardAmt0 * 1e12) / mAdapters[_index].totalStaked;
        }

        // update user's info - rewardDebt, userShare
        if (userInfo.amount != 0) {
            userInfo.rewardDebt1 +=
                (userInfo.amount * (mAdapters[_index].accTokenPerShare1 - userInfo.userShare1)) /
                1e12;
        }

        // update mAdapter & user Info
        mAdapters[_index].totalStaked += amountOut;
        userInfo.userShare1 = mAdapters[_index].accTokenPerShare1;
        userInfo.amount += amountOut;

        return _amountIn;
    }

    /**
     * @notice Withdraw from strategy
     * @param _tokenId YBNFT token id
     * @param _index index of strategies
     * @param _amount staking token amount to withdraw
     */
    /// #if_succeeds {:msg "withdraw failed"}  userAdapterInfos[_tokenId].userShare1 == mAdapters[_index].accTokenPerShare1 && userAdapterInfos[_tokenId].rewardDebt1 == 0;
    function withdraw(
        uint256 _tokenId,
        uint256 _index,
        uint256 _amount
    ) external payable override onlyInvestor returns (uint256 amountOut) {
        if (_amount == 0) return 0;

        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId][_index];
        AdapterDetail memory aDetail = adapterDetails[_index];

        // validation of _amount parameter
        require(_amount <= userInfo.amount, "Not enough balance to withdraw");

        // 1. calc reward and withdraw from adapter
        uint256 rewardAmt0 = IERC20(aDetail.rewardToken1).balanceOf(address(this));
        amountOut = IERC20(aDetail.stakingToken).balanceOf(address(this));
        IStrategy(aDetail.strategy).withdraw(_amount);
        rewardAmt0 = IERC20(aDetail.rewardToken1).balanceOf(address(this)) - rewardAmt0;
        amountOut = IERC20(aDetail.stakingToken).balanceOf(address(this)) - amountOut;
        require(_amount == amountOut, "Failed to withdraw");

        // 2. update accTokenPerShare if reward is generated
        if (rewardAmt0 != 0 && mAdapters[_index].totalStaked != 0) {
            mAdapters[_index].accTokenPerShare1 += (rewardAmt0 * 1e12) / mAdapters[_index].totalStaked;
        }

        // 3. swap withdrawn staking tokens to bnb
        if (aDetail.router == address(0)) {
            amountOut = HedgepieLibraryBsc.swapForBnb(
                amountOut,
                address(this),
                aDetail.stakingToken,
                aDetail.swapRouter
            );
        } else {
            amountOut = HedgepieLibraryBsc.withdrawLP(
                aDetail,
                IYBNFT.AdapterParam(0, address(this), _index),
                aDetail.stakingToken,
                amountOut
            );
        }

        // 4. get user's rewards
        (uint256 reward, ) = HedgepieLibraryBsc.getMRewards(_tokenId, _index, adapterDetails[_index], address(this));

        // 5. swap reward to bnb
        uint256 rewardBnb;
        if (reward != 0) {
            rewardBnb = HedgepieLibraryBsc.swapForBnb(reward, address(this), aDetail.rewardToken1, aDetail.swapRouter);
        }

        if (rewardBnb != 0) amountOut += rewardBnb;

        // 6. update mAdapter & user Info
        mAdapters[_index].totalStaked -= _amount;
        userInfo.amount -= _amount;
        userInfo.userShare1 = mAdapters[_index].accTokenPerShare1;
        userInfo.rewardDebt1 = 0;

        // 7. charge fee and send BNB to investor
        if (amountOut != 0) _chargeFeeAndSendToInvestor(_tokenId, amountOut, rewardBnb);
    }

    /**
     * @notice Claim the pending reward
     * @param _tokenId YBNFT token id
     * @param _index index of strategies
     */
    /// #if_succeeds {:msg "claim failed"}  userAdapterInfos[_tokenId].userShare1 == mAdapters[_index].accTokenPerShare1 && userAdapterInfos[_tokenId].rewardDebt1 == 0;
    function claim(
        uint256 _tokenId,
        uint256 _index
    ) external payable override onlyInvestor returns (uint256 amountOut) {
        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId][_index];
        AdapterDetail memory aDetail = adapterDetails[_index];

        // 1. check if reward is generated
        uint256 rewardAmt0 = IERC20(aDetail.rewardToken1).balanceOf(address(this));
        IStrategy(aDetail.strategy).withdraw(0);
        rewardAmt0 = IERC20(aDetail.rewardToken1).balanceOf(address(this)) - rewardAmt0;
        if (rewardAmt0 != 0 && mAdapters[_index].totalStaked != 0) {
            mAdapters[_index].accTokenPerShare1 += (rewardAmt0 * 1e12) / mAdapters[_index].totalStaked;
        }

        // 2. get reward amount
        (uint256 reward, ) = HedgepieLibraryBsc.getMRewards(_tokenId, _index, adapterDetails[_index], address(this));

        // 3. update user info
        userInfo.userShare1 = mAdapters[_index].accTokenPerShare1;
        userInfo.rewardDebt1 = 0;

        // 4. swap reward to bnb and send to investor
        if (reward != 0) {
            amountOut += HedgepieLibraryBsc.swapForBnb(reward, address(this), aDetail.rewardToken1, aDetail.swapRouter);

            // 5. charge fee and send BNB to investor
            _chargeFeeAndSendToInvestor(_tokenId, amountOut, amountOut);
        }
    }

    /**
     * @notice Return the pending reward by Bnb
     * @param _tokenId YBNFT token id
     * @param _index index of strategies
     */
    function pendingReward(
        uint256 _tokenId,
        uint256 _index
    ) external view override returns (uint256 reward, uint256 withdrawable) {
        UserAdapterInfo memory userInfo = userAdapterInfos[_tokenId][_index];
        AdapterDetail memory aDetail = adapterDetails[_index];

        // 1. calc updatedAccTokenPerShare
        uint256 updatedAccTokenPerShare = mAdapters[_index].accTokenPerShare1;
        if (mAdapters[_index].totalStaked != 0)
            updatedAccTokenPerShare += ((IStrategy(aDetail.strategy).pendingReward(address(this)) * 1e12) /
                mAdapters[_index].totalStaked);

        // 2. calc rewards from updatedAccTokenPerShare
        uint256 tokenRewards = ((updatedAccTokenPerShare - userInfo.userShare1) * userInfo.amount) /
            1e12 +
            userInfo.rewardDebt1;

        // 3. calc pending reward in bnb
        if (tokenRewards != 0) {
            if (aDetail.rewardToken1 == HedgepieLibraryBsc.WBNB) reward = tokenRewards;
            else {
                address[] memory paths = IPathFinder(authority.pathFinder()).getPaths(
                    aDetail.swapRouter,
                    aDetail.rewardToken1,
                    HedgepieLibraryBsc.WBNB
                );

                reward = IPancakeRouter(aDetail.swapRouter).getAmountsOut(tokenRewards, paths)[paths.length - 1];
            }

            withdrawable = reward;
        }
    }

    /**
     * @notice Remove funds
     * @param _tokenId YBNFT token id
     * @param _index index of strategies
     */
    /// #if_succeeds {:msg "removeFunds failed"}  userAdapterInfos[_tokenId].userShare1 == mAdapters[_index].accTokenPerShare1 && userAdapterInfos[_tokenId].amount == 0;
    function removeFunds(
        uint256 _tokenId,
        uint256 _index
    ) external payable override onlyInvestor returns (uint256 amountOut) {
        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId][_index];
        AdapterDetail memory aDetail = adapterDetails[_index];

        if (userInfo.amount == 0) return 0;

        // 1. update reward infor after withdraw all staking tokens
        uint256 rewardAmt0 = IERC20(aDetail.rewardToken1).balanceOf(address(this));
        amountOut = IERC20(aDetail.stakingToken).balanceOf(address(this));
        IStrategy(aDetail.strategy).withdraw(userInfo.amount);
        amountOut = IERC20(aDetail.stakingToken).balanceOf(address(this)) - amountOut;
        rewardAmt0 = IERC20(aDetail.rewardToken1).balanceOf(address(this)) - rewardAmt0;
        require(userInfo.amount == amountOut, "Failed to remove funds");

        // 2. update mAdapter infor
        if (rewardAmt0 != 0) {
            mAdapters[_index].accTokenPerShare1 += (rewardAmt0 * 1e12) / mAdapters[_index].totalStaked;
        }

        // 3. update user rewardDebt value
        if (userInfo.amount != 0) {
            userInfo.rewardDebt1 +=
                (userInfo.amount * (mAdapters[_index].accTokenPerShare1 - userInfo.userShare1)) /
                1e12;
        }

        // 4. swap withdrawn lp to bnb
        if (aDetail.router == address(0)) {
            amountOut = HedgepieLibraryBsc.swapForBnb(
                amountOut,
                address(this),
                aDetail.stakingToken,
                aDetail.swapRouter
            );
        } else {
            amountOut = HedgepieLibraryBsc.withdrawLP(
                aDetail,
                IYBNFT.AdapterParam(0, address(this), _index),
                aDetail.stakingToken,
                amountOut
            );
        }

        // 5. update invested information for token id
        mAdapters[_index].totalStaked -= userInfo.amount;
        userInfo.amount = 0;
        userInfo.userShare1 = mAdapters[_index].accTokenPerShare1;

        // 6. send to investor
        (bool success, ) = payable(authority.hInvestor()).call{value: amountOut}("");
        require(success, "Failed to send bnb to investor");
    }

    /**
     * @notice Update funds
     * @param _tokenId YBNFT token id
     * @param _index index of strategies
     */
    /// #if_succeeds {:msg "updateFunds failed"}  userAdapterInfos[_tokenId].userShare1 == mAdapters[_index].accTokenPerShare1;
    function updateFunds(
        uint256 _tokenId,
        uint256 _index
    ) external payable override onlyInvestor returns (uint256 amountOut) {
        if (msg.value == 0) return 0;

        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId][_index];
        AdapterDetail memory aDetail = adapterDetails[_index];

        // 1. swap bnb to staking token
        if (aDetail.router == address(0)) {
            amountOut = HedgepieLibraryBsc.swapOnRouter(
                msg.value,
                address(this),
                aDetail.stakingToken,
                aDetail.swapRouter
            );
        } else {
            amountOut = HedgepieLibraryBsc.getLP(
                aDetail,
                IYBNFT.AdapterParam(0, address(this), _index),
                aDetail.stakingToken,
                msg.value
            );
        }

        // 2. get reward amount after deposit
        uint256 rewardAmt0 = IERC20(aDetail.rewardToken1).balanceOf(address(this));
        IERC20(aDetail.stakingToken).safeApprove(aDetail.strategy, 0);
        IERC20(aDetail.stakingToken).safeApprove(aDetail.strategy, amountOut);
        IStrategy(aDetail.strategy).deposit(amountOut);
        rewardAmt0 = IERC20(aDetail.rewardToken1).balanceOf(address(this)) - rewardAmt0;

        // 3. update reward infor
        if (rewardAmt0 != 0 && mAdapters[_index].totalStaked != 0) {
            mAdapters[_index].accTokenPerShare1 += (rewardAmt0 * 1e12) / mAdapters[_index].totalStaked;
        }

        // 4. update mAdapter & userInfo
        mAdapters[_index].totalStaked += amountOut;
        userInfo.amount = amountOut;
        userInfo.userShare1 = mAdapters[_index].accTokenPerShare1;

        return msg.value;
    }
}
