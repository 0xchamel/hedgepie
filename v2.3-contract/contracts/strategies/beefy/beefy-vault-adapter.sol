// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../../libraries/HedgepieLibraryBsc.sol";

interface IStrategy {
    function deposit(uint256) external;

    function depositBNB() external payable;

    function withdraw(uint256) external;

    function withdrawBNB(uint256) external;

    function withdrawAll() external;

    function withdrawAllBNB() external;

    function getPricePerFullShare() external view returns (uint256);
}

contract BeefyVaultAdapterBsc is BaseAdapter {
    using SafeERC20 for IERC20;

    /**
     * @notice Initializer
     * @param _strategy  address of strategy
     * @param _stakingToken  address of staking token
     * @param _router  address of router for LP
     * @param _swapRouter  address of swap router
     * @param _name  adatper name
     * @param _authority HedgepieAuthority address
     */
    function initialize(
        address _strategy,
        address _stakingToken,
        address _router,
        address _swapRouter,
        string memory _name,
        address _authority
    ) external initializer {
        require(_stakingToken != address(0), "Invalid staking token");
        require(_strategy != address(0), "Invalid strategy address");

        __BaseAdapter__init(_authority);

        strategy = _strategy;
        stakingToken = _stakingToken;
        repayToken = _strategy;
        router = _router;
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

        // 1. get stakingToken
        bool isBNB = stakingToken == HedgepieLibraryBsc.WBNB;
        if (router == address(0)) {
            amountOut = isBNB
                ? msg.value
                : HedgepieLibraryBsc.swapOnRouter(msg.value, address(this), stakingToken, swapRouter);
        } else {
            amountOut = HedgepieLibraryBsc.getLP(IYBNFT.AdapterParam(0, address(this)), stakingToken, msg.value);
        }

        // 2. deposit to vault
        uint256 repayAmt = IERC20(repayToken).balanceOf(address(this));
        if (isBNB) {
            IStrategy(strategy).depositBNB{value: amountOut}();
        } else {
            IERC20(stakingToken).safeApprove(strategy, 0);
            IERC20(stakingToken).safeApprove(strategy, amountOut);
            IStrategy(strategy).deposit(amountOut);
        }

        unchecked {
            repayAmt = IERC20(repayToken).balanceOf(address(this)) - repayAmt;
            require(repayAmt != 0, "Failed to deposit");
        }

        // 3. update user info
        userInfo.amount += repayAmt;
        userInfo.invested += amountOut;
    }

    /**
     * @notice Withdraw from strategy
     * @param _tokenId YBNFT token id
     * @param _amount amount of repayToken to withdraw
     */
    /// #if_succeeds {:msg "withdraw failed"}  userAdapterInfos[_tokenId].userShare1 == mAdapter.accTokenPerShare1 && userAdapterInfos[_tokenId].rewardDebt1 == 0;
    function withdraw(
        uint256 _tokenId,
        uint256 _amount
    ) external payable override onlyInvestor returns (uint256 amountOut) {
        if (_amount == 0) return 0;

        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId];

        // 1. withdraw from vault
        bool isBNB = stakingToken == HedgepieLibraryBsc.WBNB;
        uint256 tokenAmt = isBNB ? address(this).balance : IERC20(stakingToken).balanceOf(address(this));

        if (isBNB) IStrategy(strategy).withdrawBNB(_amount);
        else IStrategy(strategy).withdraw(_amount);

        unchecked {
            tokenAmt = (isBNB ? address(this).balance : IERC20(stakingToken).balanceOf(address(this))) - tokenAmt;
        }

        // 2. swap withdrawn lp to bnb
        if (router == address(0)) {
            amountOut = isBNB
                ? tokenAmt
                : HedgepieLibraryBsc.swapForBnb(tokenAmt, address(this), stakingToken, swapRouter);
        } else {
            amountOut = HedgepieLibraryBsc.withdrawLP(IYBNFT.AdapterParam(0, address(this)), stakingToken, tokenAmt);
        }

        // 3. update userInfo
        unchecked {
            userInfo.amount -= _amount;

            if (tokenAmt >= userInfo.invested) userInfo.invested = 0;
            else userInfo.invested -= tokenAmt;
        }

        // 4. send withdrawn bnb to investor
        if (amountOut != 0) _chargeFeeAndSendToInvestor(_tokenId, amountOut, 0);
    }

    /**
     * @notice Claim the pending reward
     * @param _tokenId YBNFT token id
     */
    /// #if_succeeds {:msg "withdraw failed"}  userAdapterInfos[_tokenId].userShare1 == mAdapter.accTokenPerShare1 && userAdapterInfos[_tokenId].rewardDebt1 == 0;
    function claim(uint256 _tokenId) external payable override onlyInvestor returns (uint256 amountOut) {
        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId];

        // 1. check if reward is generated
        uint256 wantAmt = ((userInfo.amount * IStrategy(strategy).getPricePerFullShare()) / 1e18);
        uint256 wantShare = ((wantAmt > userInfo.invested ? wantAmt - userInfo.invested : 0) * 1e18) /
            IStrategy(strategy).getPricePerFullShare();

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
     * @notice Return the pending reward by BNB
     * @param _tokenId YBNFT token id
     */
    function pendingReward(uint256 _tokenId) external view override returns (uint256 reward, uint256 withdrawable) {
        UserAdapterInfo memory userInfo = userAdapterInfos[_tokenId];

        // 1. calc want amount
        uint256 wantAmt = ((userInfo.amount * IStrategy(strategy).getPricePerFullShare()) / 1e18);

        if (wantAmt <= userInfo.invested) return (userInfo.rewardDebt1, userInfo.rewardDebt1);

        // 2. calc reward
        wantAmt -= userInfo.invested;

        if (router == address(0)) {
            if (stakingToken == HedgepieLibraryBsc.WBNB) reward = wantAmt;
            else {
                address[] memory paths = IPathFinder(authority.pathFinder()).getPaths(
                    swapRouter,
                    stakingToken,
                    HedgepieLibraryBsc.WBNB
                );

                reward = IPancakeRouter(swapRouter).getAmountsOut(wantAmt, paths)[paths.length - 1];
            }
        } else {
            address token0 = IPancakePair(stakingToken).token0();
            address token1 = IPancakePair(stakingToken).token1();

            (uint112 reserve0, uint112 reserve1, ) = IPancakePair(stakingToken).getReserves();

            uint256 amount0 = (reserve0 * wantAmt) / IPancakePair(stakingToken).totalSupply();
            uint256 amount1 = (reserve1 * wantAmt) / IPancakePair(stakingToken).totalSupply();

            if (token0 == HedgepieLibraryBsc.WBNB) reward = amount0;
            else {
                address[] memory path0 = IPathFinder(authority.pathFinder()).getPaths(
                    swapRouter,
                    token0,
                    HedgepieLibraryBsc.WBNB
                );

                reward = IPancakeRouter(swapRouter).getAmountsOut(amount0, path0)[path0.length - 1];
            }

            if (token1 == HedgepieLibraryBsc.WBNB) reward += amount1;
            else {
                address[] memory path1 = IPathFinder(authority.pathFinder()).getPaths(
                    swapRouter,
                    token1,
                    HedgepieLibraryBsc.WBNB
                );

                reward += IPancakeRouter(swapRouter).getAmountsOut(amount1, path1)[path1.length - 1];
            }
        }

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
        bool isBNB = stakingToken == HedgepieLibraryBsc.WBNB;
        amountOut = isBNB ? address(this).balance : IERC20(stakingToken).balanceOf(address(this));

        if (isBNB) IStrategy(strategy).withdrawAllBNB();
        else IStrategy(strategy).withdrawAll();

        unchecked {
            amountOut = (isBNB ? address(this).balance : IERC20(stakingToken).balanceOf(address(this))) - amountOut;
        }

        // 2. calc reward
        uint256 rewardPercent = 0;
        if (amountOut > userInfo.invested) {
            unchecked {
                rewardPercent = ((amountOut - userInfo.invested) * 1e12) / amountOut;
            }
        }

        // 3. swap withdrawn lp to bnb
        if (router == address(0)) {
            if (!isBNB) amountOut = HedgepieLibraryBsc.swapForBnb(amountOut, address(this), stakingToken, swapRouter);
        } else {
            amountOut = HedgepieLibraryBsc.withdrawLP(IYBNFT.AdapterParam(0, address(this)), stakingToken, amountOut);
        }

        // 4. remove userInfo and stake pendingReward to rewardDebt1
        uint256 reward = (amountOut * rewardPercent) / 1e12;
        userInfo.amount = 0;
        userInfo.invested = 0;
        userInfo.rewardDebt1 += reward;

        // 5. send withdrawn bnb to investor
        if (amountOut != 0) _chargeFeeAndSendToInvestor(_tokenId, amountOut - reward, 0);
    }

    /**
     * @notice Update funds
     * @param _tokenId YBNFT token id
     */
    /// #if_succeeds {:msg "updateFunds failed"}  userAdapterInfos[_tokenId].userShare1 == mAdapter.accTokenPerShare1;
    function updateFunds(uint256 _tokenId) external payable override onlyInvestor returns (uint256 amountOut) {
        if (msg.value == 0) return 0;

        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId];

        // 1. get stakingToken
        bool isBNB = stakingToken == HedgepieLibraryBsc.WBNB;
        if (router == address(0)) {
            amountOut = isBNB
                ? msg.value
                : HedgepieLibraryBsc.swapOnRouter(msg.value, address(this), stakingToken, swapRouter);
        } else {
            amountOut = HedgepieLibraryBsc.getLP(IYBNFT.AdapterParam(0, address(this)), stakingToken, msg.value);
        }

        // 2. deposit to vault
        uint256 repayAmt = IERC20(repayToken).balanceOf(address(this));
        if (isBNB) {
            IStrategy(strategy).depositBNB{value: amountOut}();
        } else {
            IERC20(stakingToken).safeApprove(strategy, 0);
            IERC20(stakingToken).safeApprove(strategy, amountOut);
            IStrategy(strategy).deposit(amountOut);
        }

        unchecked {
            repayAmt = IERC20(repayToken).balanceOf(address(this)) - repayAmt;
            require(repayAmt != 0, "Failed to update funds");
        }

        // 3. update user info
        userInfo.amount = repayAmt;
        userInfo.invested = amountOut;
    }
}
