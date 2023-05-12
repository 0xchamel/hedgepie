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

    address public compounder;

    /**
     * @notice Constructor
     * @param _strategy  address of strategy
     * @param _stakingToken  address of staking token
     * @param _rewardToken  address of reward token
     * @param _repayToken  address of repay token
     * @param _swapRouter  address of swap router
     * @param _compounder  address of compounder
     * @param _name  adatper name
     * @param _authority  hedgepieAuthority address
     */
    constructor(
        address _strategy,
        address _stakingToken,
        address _rewardToken,
        address _repayToken,
        address _swapRouter,
        address _compounder,
        string memory _name,
        address _authority
    ) BaseAdapter(_authority) {
        require(_stakingToken != address(0), "Invalid staking token");
        require(_strategy != address(0), "Invalid strategy address");

        stakingToken = _stakingToken;
        strategy = _strategy;
        rewardToken1 = _rewardToken;
        rewardToken2 = stakingToken;
        repayToken = _repayToken;
        swapRouter = _swapRouter;
        compounder = _compounder;
        name = _name;
    }

    /**
     * @notice Deposit with BNB
     * @param _tokenId YBNFT token id
     */
    /// #if_succeeds {:msg "deposit failed"}  userAdapterInfos[_tokenId].userShare1 == mAdapter.accTokenPerShare1 && mAdapter.totalStaked > old(mAdapter.totalStaked);
    function deposit(uint256 _tokenId) external payable override onlyInvestor returns (uint256 amountOut) {
        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId];

        // 1. swap to staking token
        amountOut = stakingToken == HedgepieLibraryBsc.WBNB
            ? HedgepieLibraryBsc.wrapBNB(msg.value)
            : HedgepieLibraryBsc.swapOnRouter(msg.value, address(this), stakingToken, swapRouter);

        // 2. deposit to vault
        uint256 repayAmt = IERC20(repayToken).balanceOf(address(this));
        IERC20(stakingToken).safeApprove(strategy, 0);
        IERC20(stakingToken).safeApprove(strategy, amountOut);
        IStrategy(strategy).deposit(stakingToken, amountOut, address(this), 0);

        repayAmt = IERC20(repayToken).balanceOf(address(this)) - repayAmt;
        require(repayAmt != 0, "Failed to deposit");

        // 3. update user info
        unchecked {
            mAdapter.totalStaked += repayAmt;

            userInfo.amount += repayAmt;
            userInfo.invested += amountOut;
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

        // 1. withdraw from vault
        amountOut = IStrategy(strategy).withdraw(stakingToken, _amount, address(this));

        // 2. swap withdrawn lp to bnb
        amountOut = HedgepieLibraryBsc.swapForBnb(amountOut, address(this), stakingToken, swapRouter);

        // 3. update userInfo
        unchecked {
            mAdapter.totalStaked -= _amount;
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
    function _calcReward() internal {
        if (ICompounder(compounder).userEligibleForCompound(address(this))) {
            // 1. compound from compounder
            uint256 rewardAmt1 = IERC20(rewardToken1).balanceOf(address(this));
            uint256 rewardAmt2 = IERC20(rewardToken2).balanceOf(address(this));
            ICompounder(compounder).selfCompound();

            unchecked {
                rewardAmt1 = IERC20(rewardToken1).balanceOf(address(this)) - rewardAmt1;
                rewardAmt2 = IERC20(rewardToken2).balanceOf(address(this)) - rewardAmt2;

                if (mAdapter.totalStaked != 0) {
                    if (rewardAmt1 != 0) mAdapter.accTokenPerShare1 += (rewardAmt1 * 1e12) / mAdapter.totalStaked;

                    if (rewardAmt2 != 0) mAdapter.accTokenPerShare2 += (rewardAmt2 * 1e12) / mAdapter.totalStaked;
                }
            }
        }
    }

    /**
     * @notice Claim the pending reward
     * @param _tokenId YBNFT token id
     */
    /// #if_succeeds {:msg "claim failed"}  userAdapterInfos[_tokenId].userShare1 == mAdapter.accTokenPerShare1 && userAdapterInfos[_tokenId].rewardDebt1 == 0;
    function claim(uint256 _tokenId) external payable override onlyInvestor returns (uint256 amountOut) {
        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId];

        // 1. claim rewards
        _calcReward();

        // 2. get reward amount
        (uint256 reward1, uint256 reward2) = HedgepieLibraryBsc.getMRewards(_tokenId, address(this));

        // 3. update user info
        userInfo.userShare1 = mAdapter.accTokenPerShare1;
        userInfo.userShare2 = mAdapter.accTokenPerShare2;
        userInfo.rewardDebt1 = 0;
        userInfo.rewardDebt2 = 0;

        if (reward1 != 0) {
            amountOut = HedgepieLibraryBsc.swapForBnb(reward1, address(this), rewardToken1, swapRouter);
        }

        if (reward2 != 0) {
            amountOut += HedgepieLibraryBsc.swapForBnb(reward2, address(this), rewardToken2, swapRouter);
        }

        // 6. charge fee and send BNB to investor
        if (amountOut != 0) _chargeFeeAndSendToInvestor(_tokenId, amountOut, amountOut);
    }

    /**
     * @notice Return the pending reward by Bnb
     * @param _tokenId YBNFT token id
     */
    function pendingReward(uint256 _tokenId) external view override returns (uint256 reward, uint256 withdrawable) {
        if (ICompounder(compounder).userEligibleForCompound(address(this))) {
            UserAdapterInfo memory userInfo = userAdapterInfos[_tokenId];

            // 1. calc want amount
            (address[] memory tokens, uint256[] memory amts) = ICompounder(compounder).viewPendingRewards(msg.sender);

            uint256 rewardAmt1;
            uint256 rewardAmt2;
            for (uint8 i; i < tokens.length; ++i) {
                if (amts[i] != 0) {
                    if (tokens[i] == rewardToken1) rewardAmt1 = amts[i];
                    else if (tokens[i] == rewardToken2) rewardAmt2 = amts[i];
                }
            }

            // 1. calc updatedAccTokenPerShares
            uint256 updatedAccTokenPerShare1 = mAdapter.accTokenPerShare1;
            uint256 updatedAccTokenPerShare2 = mAdapter.accTokenPerShare2;

            if (mAdapter.totalStaked != 0) {
                updatedAccTokenPerShare1 += (rewardAmt1 * 1e12) / mAdapter.totalStaked;

                updatedAccTokenPerShare2 += (rewardAmt2 * 1e12) / mAdapter.totalStaked;
            }

            // 2. calc rewards from updatedAccTokenPerShare
            uint256 tokenRewards1 = ((updatedAccTokenPerShare1 - userInfo.userShare1) * userInfo.amount) /
                1e12 +
                userInfo.rewardDebt1;

            uint256 tokenRewards2 = ((updatedAccTokenPerShare2 - userInfo.userShare2) * userInfo.amount) /
                1e12 +
                userInfo.rewardDebt2;

            if (tokenRewards1 != 0) {
                reward = _getAmountOut(rewardToken1, tokenRewards1);
            }

            if (tokenRewards2 != 0) {
                reward += _getAmountOut(rewardToken2, tokenRewards2);
            }

            reward += userInfo.rewardDebt1;
            withdrawable = reward;
        }
    }

    function _getAmountOut(address _token, uint256 _amt) internal view returns (uint256 amountOut) {
        if (_token == HedgepieLibraryBsc.WBNB) amountOut = _amt;
        else {
            address[] memory paths = IPathFinder(authority.pathFinder()).getPaths(
                swapRouter,
                _token,
                HedgepieLibraryBsc.WBNB
            );

            amountOut = IPancakeRouter(swapRouter).getAmountsOut(_amt, paths)[paths.length - 1];
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
        _calcReward();

        // 1. withdraw all from Vault
        amountOut = IStrategy(strategy).withdraw(stakingToken, type(uint256).max, address(this));

        // 2. update user rewardDebt value
        unchecked {
            if (userInfo.amount != 0) {
                userInfo.rewardDebt1 += (userInfo.amount * (mAdapter.accTokenPerShare1 - userInfo.userShare1)) / 1e12;
                userInfo.rewardDebt2 += (userInfo.amount * (mAdapter.accTokenPerShare2 - userInfo.userShare2)) / 1e12;
            }
        }

        // 3. swap withdrawn staking token to bnb
        amountOut = HedgepieLibraryBsc.swapForBnb(amountOut, address(this), stakingToken, swapRouter);

        // 4. update invested information for token id
        unchecked {
            mAdapter.totalStaked -= userInfo.amount;
            userInfo.amount = 0;
            userInfo.invested = 0;
            userInfo.userShare1 = mAdapter.accTokenPerShare1;
            userInfo.userShare2 = mAdapter.accTokenPerShare2;
        }

        // 5. send withdrawn bnb to investor
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

        // 1. get LP
        amountOut = stakingToken == HedgepieLibraryBsc.WBNB
            ? HedgepieLibraryBsc.wrapBNB(msg.value)
            : HedgepieLibraryBsc.swapOnRouter(msg.value, address(this), stakingToken, swapRouter);

        // 2. deposit to vault
        uint256 repayAmt = IERC20(repayToken).balanceOf(address(this));

        IERC20(stakingToken).safeApprove(strategy, 0);
        IERC20(stakingToken).safeApprove(strategy, amountOut);
        IStrategy(strategy).deposit(stakingToken, amountOut, address(this), 0);

        repayAmt = IERC20(repayToken).balanceOf(address(this)) - repayAmt;
        require(repayAmt != 0, "Failed to update funds");

        // 3. update user info
        unchecked {
            mAdapter.totalStaked += repayAmt;

            userInfo.amount = repayAmt;
            userInfo.invested = amountOut;
            userInfo.userShare1 = mAdapter.accTokenPerShare1;
            userInfo.userShare2 = mAdapter.accTokenPerShare2;
        }
    }
}
