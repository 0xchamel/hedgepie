// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../../libraries/HedgepieLibraryBsc.sol";

interface IStrategy {
    function deposit(uint256, uint256) external;

    function depositBNB(uint256) external payable;

    function withdraw(uint256, uint256) external;

    function withdrawBNB(uint256, uint256) external;

    function getPricePerFullShare() external view returns (uint256);
}

contract BeltVaultAdapterBsc is BaseAdapter {
    using SafeERC20 for IERC20;

    /**
     * @notice Constructor
     * @param _strategy  address of strategy
     * @param _stakingToken  address of staking token
     * @param _repayToken  address of reward token
     * @param _swapRouter  address of swap router
     * @param _label  adatper label
     */
    constructor(
        address _strategy,
        address _stakingToken,
        address _repayToken,
        address _swapRouter,
        string memory _label,
        address _authority
    ) BaseAdapter(_authority) {
        require(_repayToken != address(0), "Invalid reward token");
        require(_stakingToken != address(0), "Invalid staking token");
        require(_strategy != address(0), "Invalid strategy address");

        stakingToken = _stakingToken;
        repayToken = _repayToken;
        strategy = _strategy;
        swapRouter = _swapRouter;
        label = _label;
    }

    /**
     * @notice Deposit with Bnb
     * @param _tokenId YBNFT token id
     */
    /// #if_succeeds {:msg "deposit failed"}  userAdapterInfos[_tokenId].userShare1 == mAdapter.accTokenPerShare1 && mAdapter.totalStaked > old(mAdapter.totalStaked);
    function deposit(uint256 _tokenId) external payable override onlyInvestor returns (uint256 amountOut) {
        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId];

        // 1. get stakingToken
        bool isBNB = stakingToken == HedgepieLibraryBsc.WBNB;
        amountOut = isBNB ? msg.value : amountOut = HedgepieLibraryBsc.swapOnRouter(
            msg.value,
            address(this),
            stakingToken,
            swapRouter
        );

        // 2. deposit to vault
        uint256 repayAmt = IERC20(repayToken).balanceOf(address(this));

        if (isBNB) {
            IStrategy(strategy).depositBNB{value: amountOut}(0);
        } else {
            IERC20(stakingToken).safeApprove(strategy, 0);
            IERC20(stakingToken).safeApprove(strategy, amountOut);
            IStrategy(strategy).deposit(amountOut, 0);
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
     * @param _amount amount of staking token to withdraw
     */
    /// #if_succeeds {:msg "withdraw failed"}  userAdapterInfos[_tokenId].userShare1 == mAdapter.accTokenPerShare1 && userAdapterInfos[_tokenId].rewardDebt1 == 0;
    function withdraw(
        uint256 _tokenId,
        uint256 _amount
    ) external payable override onlyInvestor returns (uint256 amountOut) {
        if (_amount == 0) return 0;

        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId];

        // 1. withdraw from Vault
        bool isBNB = stakingToken == HedgepieLibraryBsc.WBNB;
        uint256 tokenAmt = isBNB ? address(this).balance : IERC20(stakingToken).balanceOf(address(this));
        if (isBNB) {
            IStrategy(strategy).withdrawBNB(_amount, 0);
        } else {
            IStrategy(strategy).withdraw(_amount, 0);
        }
        tokenAmt = (isBNB ? address(this).balance : IERC20(stakingToken).balanceOf(address(this))) - tokenAmt;

        // 2. swap withdrawn lp to bnb
        amountOut = isBNB ? tokenAmt : HedgepieLibraryBsc.swapForBnb(tokenAmt, address(this), stakingToken, swapRouter);

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
    /// #if_succeeds {:msg "claim failed"}  userAdapterInfos[_tokenId].userShare1 == mAdapter.accTokenPerShare1 && userAdapterInfos[_tokenId].rewardDebt1 == 0;
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
        bool isBNB = stakingToken == HedgepieLibraryBsc.WBNB;
        amountOut = isBNB ? address(this).balance : IERC20(stakingToken).balanceOf(address(this));

        if (isBNB) IStrategy(strategy).withdrawBNB(wantShare, 0);
        else IStrategy(strategy).withdraw(wantShare, 0);

        amountOut = (isBNB ? address(this).balance : IERC20(stakingToken).balanceOf(address(this))) - amountOut;

        // 4. swap reward to bnb
        if (!isBNB) amountOut = HedgepieLibraryBsc.swapForBnb(amountOut, address(this), stakingToken, swapRouter);

        amountOut += userInfo.rewardDebt1;

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
    function pendingReward(uint256 _tokenId) external view override returns (uint256 reward, uint256) {
        UserAdapterInfo memory userInfo = userAdapterInfos[_tokenId];

        // 1. calc want amount
        uint256 wantAmt = ((userInfo.amount * IStrategy(strategy).getPricePerFullShare()) / 1e18);

        if (wantAmt <= userInfo.invested) return (userInfo.rewardDebt1, userInfo.rewardDebt1);
        wantAmt -= userInfo.invested;

        // 2. calc reward
        if (wantAmt != 0) {
            if (stakingToken == HedgepieLibraryBsc.WBNB) reward = wantAmt;
            else {
                address[] memory paths = IPathFinder(authority.pathFinder()).getPaths(
                    swapRouter,
                    stakingToken,
                    HedgepieLibraryBsc.WBNB
                );
                reward = IPancakeRouter(swapRouter).getAmountsOut(wantAmt, paths)[paths.length - 1];
            }
        }

        return (reward + userInfo.rewardDebt1, reward + userInfo.rewardDebt1);
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
        if (isBNB) {
            IStrategy(strategy).withdrawBNB(userInfo.amount, 0);
        } else {
            IStrategy(strategy).withdraw(userInfo.amount, 0);
        }
        amountOut = (isBNB ? address(this).balance : IERC20(stakingToken).balanceOf(address(this))) - amountOut;

        // 2. calc reward
        uint256 rewardPercent = 0;
        if (amountOut > userInfo.invested) {
            unchecked {
                rewardPercent = ((amountOut - userInfo.invested) * 1e12) / amountOut;
            }
        }

        // 3. swap withdrawn lp to bnb
        if (!isBNB) amountOut = HedgepieLibraryBsc.swapForBnb(amountOut, address(this), stakingToken, swapRouter);

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
        amountOut = isBNB
            ? msg.value
            : HedgepieLibraryBsc.swapOnRouter(msg.value, address(this), stakingToken, swapRouter);

        // 2. deposit to vault
        uint256 repayAmt = IERC20(repayToken).balanceOf(address(this));

        if (isBNB) {
            IStrategy(strategy).depositBNB{value: amountOut}(0);
        } else {
            IERC20(stakingToken).safeApprove(strategy, 0);
            IERC20(stakingToken).safeApprove(strategy, amountOut);
            IStrategy(strategy).deposit(amountOut, 0);
        }

        unchecked {
            repayAmt = IERC20(repayToken).balanceOf(address(this)) - repayAmt;
            require(repayAmt != 0, "Failed to update funds");

            // 3. update user info
            userInfo.amount = repayAmt;
            userInfo.invested = amountOut;
        }
    }
}
