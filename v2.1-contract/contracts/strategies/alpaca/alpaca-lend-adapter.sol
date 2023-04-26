// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../../libraries/HedgepieLibraryBsc.sol";

interface IStrategy {
    function deposit(uint256 amountToken) external payable;

    function withdraw(uint256 share) external;

    function totalToken() external view returns (uint256);
}

contract AlpacaLendAdapterBsc is BaseAdapter {
    using SafeERC20 for IERC20;

    /**
     * @notice Constructor
     * @param _strategy  address of strategy
     * @param _stakingToken  address of staking token
     * @param _swapRouter  address of swap router
     * @param _name  adatper name
     * @param _authority  hedgepieAuthority address
     */
    constructor(
        address _strategy,
        address _stakingToken,
        address _swapRouter,
        string memory _name,
        address _authority
    ) BaseAdapter(_authority) {
        require(_stakingToken != address(0), "Invalid staking token");
        require(_strategy != address(0), "Invalid strategy address");

        stakingToken = _stakingToken;
        strategy = _strategy;
        swapRouter = _swapRouter;
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
        amountOut = HedgepieLibraryBsc.swapOnRouter(msg.value, address(this), stakingToken, swapRouter);

        // 2. deposit to vault
        uint256 repayAmt = IERC20(strategy).balanceOf(address(this));
        IERC20(stakingToken).safeApprove(strategy, 0);
        IERC20(stakingToken).safeApprove(strategy, amountOut);
        IStrategy(strategy).deposit(amountOut);
        repayAmt = IERC20(strategy).balanceOf(address(this)) - repayAmt;
        require(repayAmt != 0, "Failed to deposit");

        // 3. update user info
        userInfo.amount += repayAmt;
        userInfo.invested += amountOut;

        return msg.value;
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
        uint256 tokenAmt = IERC20(stakingToken).balanceOf(address(this));
        IStrategy(strategy).withdraw(_amount);
        tokenAmt = IERC20(stakingToken).balanceOf(address(this)) - tokenAmt;

        // 2. swap withdrawn lp to bnb
        amountOut = HedgepieLibraryBsc.swapForBnb(tokenAmt, address(this), stakingToken, swapRouter);

        // 3. update userInfo
        userInfo.amount -= _amount;
        if (tokenAmt >= userInfo.invested) userInfo.invested = 0;
        else userInfo.invested -= tokenAmt;

        // 4. send withdrawn bnb to investor
        if (amountOut != 0) {
            (bool success, ) = payable(msg.sender).call{value: amountOut}("");
            require(success, "Failed to send bnb");
        }
    }

    /**
     * @notice Claim the pending reward
     * @param _tokenId YBNFT token id
     */
    /// #if_succeeds {:msg "claim failed"}  userAdapterInfos[_tokenId].userShare1 == mAdapter.accTokenPerShare1 && userAdapterInfos[_tokenId].rewardDebt1 == 0;
    function claim(uint256 _tokenId) external payable override onlyInvestor returns (uint256 amountOut) {
        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId];

        // 1. check if reward is generated
        uint256 wantAmt = (((userInfo.amount * IStrategy(strategy).totalToken()) / IERC20(strategy).totalSupply()) /
            1e18);
        uint256 wantShare = ((wantAmt > userInfo.invested ? wantAmt - userInfo.invested : 0) *
            1e18 *
            IERC20(strategy).totalSupply()) / IStrategy(strategy).totalToken();

        // 2. if reward is not generated
        if (wantAmt <= userInfo.invested || wantShare == 0) {
            if (userInfo.rewardDebt1 == 0) return 0;

            amountOut = userInfo.rewardDebt1;
            userInfo.rewardDebt1 = 0;

            // 3. charge fee and send BNB to investor
            _chargeFeeAndSendToInvestor(_tokenId, amountOut, amountOut);
            return amountOut;
        }

        // 3. withdraw reward from vault
        uint256 lpOut = IERC20(stakingToken).balanceOf(address(this));
        IStrategy(strategy).withdraw(wantShare);
        lpOut = IERC20(stakingToken).balanceOf(address(this)) - lpOut;
        require(lpOut != 0, "Failed to claim");

        // 4. swap reward to bnb
        if (router == address(0)) {
            amountOut =
                HedgepieLibraryBsc.swapForBnb(lpOut, address(this), stakingToken, swapRouter) +
                userInfo.rewardDebt1;
        } else {
            amountOut =
                HedgepieLibraryBsc.withdrawLP(IYBNFT.AdapterParam(0, address(this)), stakingToken, lpOut) +
                userInfo.rewardDebt1;
        }

        // 5. update user info
        userInfo.amount -= wantShare;
        userInfo.rewardDebt1 = 0;

        // 6. charge fee and send BNB to investor
        if (amountOut != 0) _chargeFeeAndSendToInvestor(_tokenId, amountOut, amountOut);
    }

    /**
     * @notice Return the pending reward by Bnb
     * @param _tokenId YBNFT token id
     */
    function pendingReward(uint256 _tokenId) external view override returns (uint256 reward, uint256 withdrawable) {
        UserAdapterInfo memory userInfo = userAdapterInfos[_tokenId];

        // 1. calc want amount
        uint256 wantAmt = (((userInfo.amount * IStrategy(strategy).totalToken()) / IERC20(strategy).totalSupply()) /
            1e18);

        if (wantAmt <= userInfo.invested) return (userInfo.rewardDebt1, userInfo.rewardDebt1);

        // 2. calc reward
        wantAmt -= userInfo.invested;

        address[] memory pathStake = IPathFinder(authority.pathFinder()).getPaths(
            swapRouter,
            stakingToken,
            HedgepieLibraryBsc.WBNB
        );

        if (stakingToken != HedgepieLibraryBsc.WBNB)
            reward = IPancakeRouter(swapRouter).getAmountsOut(wantAmt, pathStake)[pathStake.length - 1];

        reward += userInfo.rewardDebt1;
        withdrawable = reward;
    }

    /**
     * @notice Remove funds
     * @param _tokenId YBNFT token id
     */
    /// #if_succeeds {:msg "removeFunds failed"}  userAdapterInfos[_tokenId].userShare1 == mAdapter.accTokenPerShare1 && userAdapterInfos[_tokenId].amount == 0;
    function removeFunds(uint256 _tokenId) external payable override onlyInvestor returns (uint256 amountOut) {
        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId];
        if (userInfo.amount == 0) return 0;

        // 1. withdraw all from Vault
        amountOut = IERC20(stakingToken).balanceOf(address(this));
        IStrategy(strategy).withdraw(userInfo.amount);
        amountOut = IERC20(stakingToken).balanceOf(address(this)) - amountOut;

        // 2. calc reward
        uint256 rewardPercent = 0;
        if (amountOut > userInfo.invested) {
            rewardPercent = ((amountOut - userInfo.invested) * 1e12) / amountOut;
        }

        // 3. swap withdrawn lp to bnb
        amountOut = HedgepieLibraryBsc.swapForBnb(amountOut, address(this), stakingToken, swapRouter);

        // 4. remove userInfo and stake pendingReward to rewardDebt1
        uint256 reward = (amountOut * rewardPercent) / 1e12;
        userInfo.amount = 0;
        userInfo.invested = 0;
        userInfo.rewardDebt1 += reward;

        // 5. send withdrawn bnb to investor
        (bool success, ) = payable(authority.hInvestor()).call{value: amountOut - reward}("");
        require(success, "Failed to send bnb to investor");
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
        amountOut = HedgepieLibraryBsc.swapOnRouter(msg.value, address(this), stakingToken, swapRouter);

        // 2. deposit to vault
        uint256 repayAmt = IERC20(strategy).balanceOf(address(this));
        IERC20(stakingToken).safeApprove(strategy, 0);
        IERC20(stakingToken).safeApprove(strategy, amountOut);
        IStrategy(strategy).deposit(amountOut);
        repayAmt = IERC20(strategy).balanceOf(address(this)) - repayAmt;
        require(repayAmt != 0, "Failed to update funds");

        // 3. update user info
        userInfo.amount = repayAmt;
        userInfo.invested = amountOut;

        return msg.value;
    }
}
