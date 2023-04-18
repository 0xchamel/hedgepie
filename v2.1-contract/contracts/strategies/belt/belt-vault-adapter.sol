// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../../libraries/HedgepieLibraryBsc.sol";

interface IStrategy {
    function deposit(uint256) external payable;

    function deposit(uint256, uint256) external;

    function withdraw(uint256, uint256) external;

    function withdrawBNB(uint256, uint256) external;

    function balance() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function getPricePerFullShare() external view returns (uint256);
}

contract BeltVaultAdapterBsc is BaseAdapter {
    using SafeERC20 for IERC20;

    /**
     * @notice Construct
     * @param _strategy  address of strategy
     * @param _stakingToken  address of staking token
     * @param _repayToken  address of reward token
     * @param _swapRouter  address of swap router
     * @param _wbnb  address of wbnb
     * @param _name  adatper name
     */
    constructor(
        address _strategy,
        address _stakingToken,
        address _repayToken,
        address _swapRouter,
        address _wbnb,
        string memory _name,
        address _hedgepieAuthority
    ) BaseAdapter(_hedgepieAuthority) {
        require(_repayToken != address(0), "Invalid reward token");
        require(_stakingToken != address(0), "Invalid staking token");
        require(_strategy != address(0), "Invalid strategy address");

        stakingToken = _stakingToken;
        repayToken = _repayToken;
        strategy = _strategy;
        swapRouter = _swapRouter;
        wbnb = _wbnb;
        name = _name;
    }

    /**
     * @notice Deposit with Bnb
     * @param _tokenId YBNFT token id
     */
    function deposit(uint256 _tokenId) external payable override onlyInvestor returns (uint256 amountOut) {
        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId];

        // 1. get stakingToken
        if (stakingToken != wbnb)
            amountOut = HedgepieLibraryBsc.swapOnRouter(msg.value, address(this), stakingToken, swapRouter);

        // 2. deposit to vault
        uint256 repayAmt = IERC20(repayToken).balanceOf(address(this));

        if (stakingToken == wbnb) {
            IStrategy(strategy).deposit{value: msg.value}(0);
        } else {
            IERC20(stakingToken).safeApprove(strategy, 0);
            IERC20(stakingToken).safeApprove(strategy, amountOut);
            IStrategy(strategy).deposit(amountOut, 0);
        }
        repayAmt = IERC20(repayToken).balanceOf(address(this)) - repayAmt;

        require(repayAmt != 0, "Failed to deposit");

        // 3. update user info
        userInfo.amount += repayAmt;
        userInfo.invested += amountOut;

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

        bool isBNB = stakingToken == wbnb;

        // 1. withdraw from Vault
        uint256 lpOut = isBNB ? address(this).balance : IERC20(stakingToken).balanceOf(address(this));
        if (isBNB) {
            IStrategy(strategy).withdrawBNB(_amount, 0);
        } else {
            IStrategy(strategy).withdraw(_amount, 0);
        }
        lpOut = (isBNB ? address(this).balance : IERC20(stakingToken).balanceOf(address(this))) - lpOut;

        // 2. swap withdrawn lp to bnb
        if (!isBNB) amountOut = HedgepieLibraryBsc.swapForBnb(lpOut, address(this), stakingToken, swapRouter);

        // 3. update userInfo
        userInfo.amount -= _amount;

        if (lpOut >= userInfo.invested) userInfo.invested = 0;
        else userInfo.invested -= lpOut;

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
    function claim(uint256 _tokenId) external payable override onlyInvestor returns (uint256 amountOut) {
        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId];

        bool isBNB = stakingToken == wbnb;

        // 1. check if reward is generated
        uint256 wantAmt = ((userInfo.amount * IStrategy(strategy).getPricePerFullShare()) / 1e18);
        uint256 wantShare = ((wantAmt > userInfo.invested ? wantAmt - userInfo.invested : 0) * 1e18) /
            IStrategy(strategy).getPricePerFullShare();

        // 2. if reward is not generated
        if (wantAmt <= userInfo.invested) {
            if (userInfo.rewardDebt1 == 0) return 0;

            amountOut = userInfo.rewardDebt1;
            userInfo.rewardDebt1 = 0;

            // send reward in bnb
            _sendToInvestor(_tokenId, amountOut, amountOut);
            return amountOut;
        }

        // 3. withdraw reward from vault
        wantAmt -= userInfo.invested;
        uint256 lpOut = isBNB ? address(this).balance : IERC20(stakingToken).balanceOf(address(this));
        IStrategy(strategy).withdraw(wantShare, 0);
        lpOut = (isBNB ? address(this).balance : IERC20(stakingToken).balanceOf(address(this))) - lpOut;

        // 4. swap reward to bnb
        if (!isBNB) amountOut = HedgepieLibraryBsc.swapForBnb(lpOut, address(this), stakingToken, swapRouter);

        // 5. update user info
        userInfo.amount -= wantShare;
        userInfo.rewardDebt1 = 0;

        // 6. send reward in bnb to investor
        if (amountOut != 0) {
            _sendToInvestor(_tokenId, amountOut, amountOut);
        }
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
            if (stakingToken == wbnb) reward += wantAmt;
            else {
                address[] memory paths = IPathFinder(authority.pathFinder()).getPaths(swapRouter, stakingToken, wbnb);
                reward += IPancakeRouter(swapRouter).getAmountsOut(wantAmt, paths)[paths.length - 1];
            }
        }

        return (reward + userInfo.rewardDebt1, reward + userInfo.rewardDebt1);
    }

    /**
     * @notice Remove funds
     * @param _tokenId YBNFT token id
     */
    function removeFunds(uint256 _tokenId) external payable override onlyInvestor returns (uint256 amountOut) {
        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId];
        if (userInfo.amount == 0) return 0;

        bool isBNB = stakingToken == wbnb;

        // 1. withdraw all from Vault
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
    function updateFunds(uint256 _tokenId) external payable override onlyInvestor returns (uint256 amountOut) {
        if (msg.value == 0) return 0;

        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId];

        // 1. get stakingToken
        if (stakingToken != wbnb) {
            amountOut = HedgepieLibraryBsc.swapOnRouter(msg.value, address(this), stakingToken, swapRouter);
        }

        // 2. deposit to vault
        uint256 repayAmt = IERC20(repayToken).balanceOf(address(this));

        if (stakingToken == wbnb) {
            IStrategy(strategy).deposit{value: msg.value}(0);
        } else {
            IERC20(stakingToken).safeApprove(strategy, 0);
            IERC20(stakingToken).safeApprove(strategy, amountOut);
            IStrategy(strategy).deposit(amountOut, 0);
        }
        repayAmt = IERC20(repayToken).balanceOf(address(this)) - repayAmt;

        require(repayAmt != 0, "Failed to update funds");

        // 3. update user info
        userInfo.amount = repayAmt;
        userInfo.invested = amountOut;

        return msg.value;
    }
}
