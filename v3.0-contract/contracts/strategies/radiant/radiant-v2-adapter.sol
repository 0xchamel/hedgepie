// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../../libraries/HedgepieLibraryBsc.sol";

interface IStrategy {
    function deposit(address, uint256, address, uint16) external;

    function withdraw(address, uint256, address) external returns (uint256);
}

interface ICompounder {
    function selfCompound() external;

    function viewPendingRewards(address) external view returns (address[] memory tokens, uint256[] memory amts);

    function userEligibleForCompound(address) external view returns (bool);
}

contract RadiantV2Bsc is BaseAdapter {
    using SafeERC20 for IERC20;

    mapping(uint256 => address) public compounder;

    /**
     * @notice Initializer
     * @param _strategy  address of strategy
     * @param _stakingToken  address of staking token
     * @param _rewardToken  address of reward token
     * @param _repayToken  address of repay token
     * @param _swapRouter  address of swap router
     * @param _compounder  address of compounder
     * @param _name  adatper name
     * @param _authority  hedgepieAuthority address
     */
    function initialize(
        address _strategy,
        address _stakingToken,
        address _rewardToken,
        address _repayToken,
        address _swapRouter,
        address _compounder,
        string memory _name,
        address _authority
    ) external initializer {
        require(_stakingToken != address(0), "Invalid staking token");
        require(_strategy != address(0), "Invalid strategy address");

        __BaseAdapter__init(_authority);

        adapterDetails.push(
            AdapterDetail({
                pid: 0,
                stakingToken: _stakingToken,
                rewardToken1: _rewardToken,
                rewardToken2: _stakingToken,
                repayToken: _repayToken,
                strategy: _strategy,
                router: address(0),
                swapRouter: _swapRouter,
                name: _name
            })
        );
        compounder[0] = _compounder;
    }

    /**
     * @notice Deposit with BNB
     * @param _tokenId YBNFT token id
     * @param _index index of strategies
     */
    /// #if_succeeds {:msg "deposit failed"}  userAdapterInfos[_tokenId][_index].userShare1 == mAdapters[_index].accTokenPerShare1 && mAdapters[_index].totalStaked > old(mAdapters[_index].totalStaked);
    function deposit(
        uint256 _tokenId,
        uint256 _index
    ) external payable override onlyInvestor returns (uint256 amountOut) {
        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId][_index];
        AdapterDetail memory aDetail = adapterDetails[_index];

        // 1. swap to staking token
        amountOut = aDetail.stakingToken == HedgepieLibraryBsc.WBNB
            ? HedgepieLibraryBsc.wrapBNB(msg.value)
            : HedgepieLibraryBsc.swapOnRouter(msg.value, address(this), aDetail.stakingToken, aDetail.swapRouter);

        // 2. deposit to vault
        uint256 repayAmt = IERC20(aDetail.repayToken).balanceOf(address(this));
        IERC20(aDetail.stakingToken).safeApprove(aDetail.strategy, 0);
        IERC20(aDetail.stakingToken).safeApprove(aDetail.strategy, amountOut);
        IStrategy(aDetail.strategy).deposit(aDetail.stakingToken, amountOut, address(this), 0);

        repayAmt = IERC20(aDetail.repayToken).balanceOf(address(this)) - repayAmt;
        require(repayAmt != 0, "Failed to deposit");

        // 3. update user info
        unchecked {
            mAdapters[_index].totalStaked += repayAmt;

            userInfo.amount += repayAmt;
            userInfo.invested += amountOut;
        }
    }

    /**
     * @notice Withdraw from strategy
     * @param _tokenId YBNFT token id
     * @param _index index of strategies
     * @param _amount amount of staking token to withdraw
     */
    /// #if_succeeds {:msg "withdraw failed"}  userAdapterInfos[_tokenId][_index].userShare1 == mAdapters[_index].accTokenPerShare1 && userAdapterInfos[_tokenId][_index].rewardDebt1 == 0;
    function withdraw(
        uint256 _tokenId,
        uint256 _index,
        uint256 _amount
    ) external payable override onlyInvestor returns (uint256 amountOut) {
        if (_amount == 0) return 0;

        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId][_index];
        AdapterDetail memory aDetail = adapterDetails[_index];

        // 1. remove rewards first
        _calcReward(aDetail, _index);

        // 2. withdraw from vault
        amountOut = IStrategy(aDetail.strategy).withdraw(aDetail.stakingToken, _amount, address(this));

        // 3. swap withdrawn lp to bnb
        amountOut = HedgepieLibraryBsc.swapForBnb(amountOut, address(this), aDetail.stakingToken, aDetail.swapRouter);

        // 4. update userInfo
        unchecked {
            mAdapters[_index].totalStaked -= _amount;
            userInfo.amount -= _amount;
            userInfo.invested = userInfo.invested > amountOut ? userInfo.invested - amountOut : 0;
            userInfo.rewardDebt1 = 0;
            userInfo.rewardDebt2 = 0;
        }

        // 4. send withdrawn bnb to investor
        if (amountOut != 0) _chargeFeeAndSendToInvestor(_tokenId, amountOut, 0);
    }

    /**
     * @notice calculate RDNT & supply rewards
     */
    function _calcReward(AdapterDetail memory _aDetail, uint256 _index) internal {
        if (ICompounder(compounder[_index]).userEligibleForCompound(address(this))) {
            // 1. compound from compounder
            uint256 rewardAmt1 = IERC20(_aDetail.rewardToken1).balanceOf(address(this));
            uint256 rewardAmt2 = IERC20(_aDetail.rewardToken2).balanceOf(address(this));
            ICompounder(compounder[_index]).selfCompound();

            unchecked {
                rewardAmt1 = IERC20(_aDetail.rewardToken1).balanceOf(address(this)) - rewardAmt1;
                rewardAmt2 = IERC20(_aDetail.rewardToken2).balanceOf(address(this)) - rewardAmt2;

                if (mAdapters[_index].totalStaked != 0) {
                    if (rewardAmt1 != 0)
                        mAdapters[_index].accTokenPerShare1 += (rewardAmt1 * 1e12) / mAdapters[_index].totalStaked;

                    if (rewardAmt2 != 0)
                        mAdapters[_index].accTokenPerShare2 += (rewardAmt2 * 1e12) / mAdapters[_index].totalStaked;
                }
            }
        }
    }

    /**
     * @notice Claim the pending reward
     * @param _tokenId YBNFT token id
     * @param _index index of strategies
     */
    /// #if_succeeds {:msg "claim failed"}  userAdapterInfos[_tokenId][_index].userShare1 == mAdapters[_index].accTokenPerShare1 && userAdapterInfos[_tokenId][_index].rewardDebt1 == 0;
    function claim(
        uint256 _tokenId,
        uint256 _index
    ) external payable override onlyInvestor returns (uint256 amountOut) {
        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId][_index];
        AdapterDetail memory aDetail = adapterDetails[_index];

        // 1. claim rewards
        _calcReward(aDetail, _index);

        // 2. get reward amount
        (uint256 reward1, uint256 reward2) = HedgepieLibraryBsc.getMRewards(
            _tokenId,
            _index,
            adapterDetails[_index],
            address(this)
        );

        // 3. update user info
        userInfo.userShare1 = mAdapters[_index].accTokenPerShare1;
        userInfo.userShare2 = mAdapters[_index].accTokenPerShare2;
        userInfo.rewardDebt1 = 0;
        userInfo.rewardDebt2 = 0;

        if (reward1 != 0) {
            amountOut = HedgepieLibraryBsc.swapForBnb(reward1, address(this), aDetail.rewardToken1, aDetail.swapRouter);
        }

        if (reward2 != 0) {
            amountOut += HedgepieLibraryBsc.swapForBnb(
                reward2,
                address(this),
                aDetail.rewardToken2,
                aDetail.swapRouter
            );
        }

        // 6. charge fee and send BNB to investor
        if (amountOut != 0) _chargeFeeAndSendToInvestor(_tokenId, amountOut, amountOut);
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
        if (ICompounder(compounder[_index]).userEligibleForCompound(address(this))) {
            UserAdapterInfo memory userInfo = userAdapterInfos[_tokenId][_index];
            AdapterDetail memory aDetail = adapterDetails[_index];

            // 1. calc want amount
            (address[] memory tokens, uint256[] memory amts) = ICompounder(compounder[_index]).viewPendingRewards(
                msg.sender
            );

            uint256 rewardAmt1;
            uint256 rewardAmt2;
            for (uint8 i; i < tokens.length; ++i) {
                if (amts[i] != 0) {
                    if (tokens[i] == aDetail.rewardToken1) rewardAmt1 = amts[i];
                    else if (tokens[i] == aDetail.rewardToken2) rewardAmt2 = amts[i];
                }
            }

            // 1. calc updatedAccTokenPerShares
            uint256 updatedAccTokenPerShare1 = mAdapters[_index].accTokenPerShare1;
            uint256 updatedAccTokenPerShare2 = mAdapters[_index].accTokenPerShare2;

            if (mAdapters[_index].totalStaked != 0) {
                updatedAccTokenPerShare1 += (rewardAmt1 * 1e12) / mAdapters[_index].totalStaked;

                updatedAccTokenPerShare2 += (rewardAmt2 * 1e12) / mAdapters[_index].totalStaked;
            }

            // 2. calc rewards from updatedAccTokenPerShare
            uint256 tokenRewards1 = ((updatedAccTokenPerShare1 - userInfo.userShare1) * userInfo.amount) /
                1e12 +
                userInfo.rewardDebt1;

            uint256 tokenRewards2 = ((updatedAccTokenPerShare2 - userInfo.userShare2) * userInfo.amount) /
                1e12 +
                userInfo.rewardDebt2;

            if (tokenRewards1 != 0) {
                reward = _getAmountOut(aDetail, aDetail.rewardToken1, tokenRewards1);
            }

            if (tokenRewards2 != 0) {
                reward += _getAmountOut(aDetail, aDetail.rewardToken2, tokenRewards2);
            }

            reward += userInfo.rewardDebt1;
            withdrawable = reward;
        }
    }

    function _getAmountOut(
        AdapterDetail memory _aDetail,
        address _token,
        uint256 _amt
    ) internal view returns (uint256 amountOut) {
        if (_token == HedgepieLibraryBsc.WBNB) amountOut = _amt;
        else {
            address[] memory paths = IPathFinder(authority.pathFinder()).getPaths(
                _aDetail.swapRouter,
                _token,
                HedgepieLibraryBsc.WBNB
            );

            amountOut = IPancakeRouter(_aDetail.swapRouter).getAmountsOut(_amt, paths)[paths.length - 1];
        }
    }

    /**
     * @notice Remove funds
     * @param _tokenId YBNFT token id
     * @param _index index of strategies
     */
    /// #if_succeeds {:msg "removeFunds failed"}  userAdapterInfos[_tokenId][_index].userShare1 == mAdapters[_index].accTokenPerShare1 && userAdapterInfos[_tokenId][_index].amount == 0;
    function removeFunds(
        uint256 _tokenId,
        uint256 _index
    ) external payable override onlyInvestor returns (uint256 amountOut) {
        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId][_index];
        AdapterDetail memory aDetail = adapterDetails[_index];

        if (userInfo.amount == 0) return 0;

        // 1. update reward infor after withdraw all staking tokens
        _calcReward(aDetail, _index);

        // 1. withdraw all from Vault
        amountOut = IStrategy(aDetail.strategy).withdraw(aDetail.stakingToken, type(uint256).max, address(this));

        // 2. update user rewardDebt value
        unchecked {
            if (userInfo.amount != 0) {
                userInfo.rewardDebt1 +=
                    (userInfo.amount * (mAdapters[_index].accTokenPerShare1 - userInfo.userShare1)) /
                    1e12;
                userInfo.rewardDebt2 +=
                    (userInfo.amount * (mAdapters[_index].accTokenPerShare2 - userInfo.userShare2)) /
                    1e12;
            }
        }

        // 3. swap withdrawn staking token to bnb
        amountOut = HedgepieLibraryBsc.swapForBnb(amountOut, address(this), aDetail.stakingToken, aDetail.swapRouter);

        // 4. update invested information for token id
        unchecked {
            mAdapters[_index].totalStaked -= userInfo.amount;
            userInfo.amount = 0;
            userInfo.invested = 0;
            userInfo.userShare1 = mAdapters[_index].accTokenPerShare1;
            userInfo.userShare2 = mAdapters[_index].accTokenPerShare2;
        }

        // 5. send withdrawn bnb to investor
        if (amountOut != 0) _chargeFeeAndSendToInvestor(_tokenId, amountOut, 0);
    }

    /**
     * @notice Update funds
     * @param _tokenId YBNFT token id
     * @param _index index of strategies
     */
    /// #if_succeeds {:msg "updateFunds failed"}  userAdapterInfos[_tokenId][_index].userShare1 == mAdapters[_index].accTokenPerShare1;
    function updateFunds(
        uint256 _tokenId,
        uint256 _index
    ) external payable override onlyInvestor returns (uint256 amountOut) {
        if (msg.value == 0) return 0;

        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId][_index];
        AdapterDetail memory aDetail = adapterDetails[_index];

        // 1. get LP
        amountOut = aDetail.stakingToken == HedgepieLibraryBsc.WBNB
            ? HedgepieLibraryBsc.wrapBNB(msg.value)
            : HedgepieLibraryBsc.swapOnRouter(msg.value, address(this), aDetail.stakingToken, aDetail.swapRouter);

        // 2. deposit to vault
        uint256 repayAmt = IERC20(aDetail.repayToken).balanceOf(address(this));

        IERC20(aDetail.stakingToken).safeApprove(aDetail.strategy, 0);
        IERC20(aDetail.stakingToken).safeApprove(aDetail.strategy, amountOut);
        IStrategy(aDetail.strategy).deposit(aDetail.stakingToken, amountOut, address(this), 0);

        repayAmt = IERC20(aDetail.repayToken).balanceOf(address(this)) - repayAmt;
        require(repayAmt != 0, "Failed to update funds");

        // 3. update user info
        unchecked {
            mAdapters[_index].totalStaked += repayAmt;

            userInfo.amount = repayAmt;
            userInfo.invested = amountOut;
            userInfo.userShare1 = mAdapters[_index].accTokenPerShare1;
            userInfo.userShare2 = mAdapters[_index].accTokenPerShare2;
        }
    }

    /**
     * @notice Set compounder
     * @param _index index of strategies
     * @param _compounder address of Compounder
     */
    function setvStrategy(uint256 _index, address _compounder) external onlyAdapterManager {
        compounder[_index] = _compounder;
    }
}
