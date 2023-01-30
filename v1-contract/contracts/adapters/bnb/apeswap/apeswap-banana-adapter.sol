// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../../../libraries/HedgepieLibraryBsc.sol";
import "../../../interfaces/IHedgepieInvestorBsc.sol";
import "../../../interfaces/IHedgepieAdapterInfoBsc.sol";

interface IStrategy {
    function enterStaking(uint256) external;

    function leaveStaking(uint256) external;

    function pendingCake(uint256 _pid, address _user)
        external
        view
        returns (uint256);
}

contract ApeswapBananaAdapter is BaseAdapterBsc {
    /**
     * @notice Construct
     * @param _strategy  address of strategy
     * @param _stakingToken  address of staking token
     * @param _repayToken  address of repay token
     * @param _name  adatper name
     */
    constructor(
        address _strategy,
        address _stakingToken,
        address _repayToken,
        address _router,
        address _wbnb,
        string memory _name
    ) {
        stakingToken = _stakingToken;
        rewardToken = _stakingToken;
        repayToken = _repayToken;
        strategy = _strategy;
        router = _router;
        wbnb = _wbnb;
        name = _name;
    }

    /**
     * @notice Deposit with BNB
     * @param _tokenId YBNFT token id
     * @param _account user wallet address
     */
    function deposit(uint256 _tokenId, address _account)
        external
        payable
        override
        onlyInvestor
        returns (uint256 amountOut)
    {
        uint256 _amountIn = msg.value;

        UserAdapterInfo storage userInfo = userAdapterInfos[_account][_tokenId];

        // get token
        amountOut = HedgepieLibraryBsc.swapOnRouter(
            _amountIn,
            address(this),
            stakingToken,
            router,
            wbnb
        );

        // deposit
        uint256 shareAmt = IBEP20(rewardToken).balanceOf(address(this));

        IBEP20(stakingToken).approve(strategy, amountOut);
        IStrategy(strategy).enterStaking(amountOut);

        unchecked {
            shareAmt =
                IBEP20(rewardToken).balanceOf(address(this)) +
                amountOut -
                shareAmt;

            if (shareAmt != 0 && mAdapter.totalStaked != 0) {
                mAdapter.accTokenPerShare +=
                    (shareAmt * 1e12) /
                    mAdapter.totalStaked;
            }
            mAdapter.totalStaked += amountOut;

            if (userInfo.amount != 0) {
                userInfo.rewardDebt +=
                    (userInfo.amount *
                        (mAdapter.accTokenPerShare - userInfo.userShares)) /
                    1e12;
            }

            userInfo.userShares = mAdapter.accTokenPerShare;
            userInfo.amount += amountOut;
            userInfo.invested += _amountIn;
        }

        // Update adapterInfo contract
        address adapterInfoBscAddr = IHedgepieInvestorBsc(investor)
            .adapterInfo();
        IHedgepieAdapterInfoBsc(adapterInfoBscAddr).updateTVLInfo(
            _tokenId,
            _amountIn,
            true
        );
        IHedgepieAdapterInfoBsc(adapterInfoBscAddr).updateTradedInfo(
            _tokenId,
            _amountIn,
            true
        );
        IHedgepieAdapterInfoBsc(adapterInfoBscAddr).updateParticipantInfo(
            _tokenId,
            _account,
            true
        );
    }

    /**
     * @notice Withdraw the deposited BNB
     * @param _tokenId YBNFT token id
     * @param _account user wallet address
     */
    function withdraw(uint256 _tokenId, address _account)
        external
        payable
        override
        onlyInvestor
        returns (uint256 amountOut)
    {
        UserAdapterInfo memory userInfo = userAdapterInfos[_account][_tokenId];

        uint256 rewardAmt = IBEP20(rewardToken).balanceOf(address(this));

        // withdraw
        IStrategy(strategy).leaveStaking(userInfo.amount);

        unchecked {
            rewardAmt =
                IBEP20(rewardToken).balanceOf(address(this)) -
                userInfo.amount -
                rewardAmt;
        }

        if (
            rewardAmt != 0 &&
            rewardToken != address(0) &&
            mAdapter.totalStaked != 0
        ) {
            mAdapter.accTokenPerShare +=
                (rewardAmt * 1e12) /
                mAdapter.totalStaked;
        }

        amountOut = HedgepieLibraryBsc.swapforBnb(
            userInfo.amount,
            address(this),
            stakingToken,
            router,
            wbnb
        );

        (uint256 reward, ) = HedgepieLibraryBsc.getMRewards(
            _tokenId,
            address(this),
            _account
        );

        uint256 rewardBnb;
        if (reward != 0) {
            rewardBnb = HedgepieLibraryBsc.swapforBnb(
                reward,
                address(this),
                rewardToken,
                router,
                wbnb
            );
        }

        address adapterInfoBnbAddr = IHedgepieInvestorBsc(investor)
            .adapterInfo();

        if (rewardBnb != 0) {
            amountOut += rewardBnb;
            IHedgepieAdapterInfoBsc(adapterInfoBnbAddr).updateProfitInfo(
                _tokenId,
                rewardBnb,
                true
            );
        }

        // Update adapterInfo contract
        IHedgepieAdapterInfoBsc(adapterInfoBnbAddr).updateTVLInfo(
            _tokenId,
            userInfo.invested,
            false
        );
        IHedgepieAdapterInfoBsc(adapterInfoBnbAddr).updateTradedInfo(
            _tokenId,
            userInfo.invested,
            true
        );
        IHedgepieAdapterInfoBsc(adapterInfoBnbAddr).updateParticipantInfo(
            _tokenId,
            _account,
            false
        );

        unchecked {
            mAdapter.totalStaked -= userInfo.amount;
        }

        delete userAdapterInfos[_account][_tokenId];

        if (amountOut != 0) {
            bool success;
            if (rewardBnb != 0) {
                rewardBnb =
                    (rewardBnb *
                        IYBNFT(IHedgepieInvestorBsc(investor).ybnft())
                            .performanceFee(_tokenId)) /
                    1e4;
                (success, ) = payable(IHedgepieInvestorBsc(investor).treasury())
                    .call{value: rewardBnb}("");
                require(success, "Failed to send bnb to Treasury");
            }

            (success, ) = payable(_account).call{value: amountOut - rewardBnb}(
                ""
            );
            require(success, "Failed to send bnb");
        }
    }

    /**
     * @notice Claim the pending reward
     * @param _tokenId YBNFT token id
     * @param _account user wallet address
     */
    function claim(uint256 _tokenId, address _account)
        external
        payable
        override
        onlyInvestor
        returns (uint256 amountOut)
    {
        UserAdapterInfo storage userInfo = userAdapterInfos[_account][_tokenId];

        // claim rewards
        uint256 rewardAmt = IBEP20(rewardToken).balanceOf(address(this));
        IStrategy(strategy).leaveStaking(0);
        rewardAmt = IBEP20(rewardToken).balanceOf(address(this)) - rewardAmt;

        if (
            rewardAmt != 0 &&
            rewardToken != address(0) &&
            mAdapter.totalStaked != 0
        ) {
            mAdapter.accTokenPerShare +=
                (rewardAmt * 1e12) /
                mAdapter.totalStaked;
        }

        (uint256 reward, ) = HedgepieLibraryBsc.getMRewards(
            _tokenId,
            address(this),
            _account
        );

        userInfo.userShares = mAdapter.accTokenPerShare;
        userInfo.userShares1 = mAdapter.accTokenPerShare1;

        if (reward != 0 && rewardToken != address(0)) {
            amountOut = HedgepieLibraryBsc.swapforBnb(
                reward,
                address(this),
                rewardToken,
                router,
                wbnb
            );

            uint256 taxAmount = (amountOut *
                IYBNFT(IHedgepieInvestorBsc(investor).ybnft()).performanceFee(
                    _tokenId
                )) / 1e4;
            (bool success, ) = payable(
                IHedgepieInvestorBsc(investor).treasury()
            ).call{value: taxAmount}("");
            require(success, "Failed to send bnb to Treasury");

            (success, ) = payable(_account).call{value: amountOut - taxAmount}(
                ""
            );
            require(success, "Failed to send bnb");

            IHedgepieAdapterInfoBsc(
                IHedgepieInvestorBsc(investor).adapterInfo()
            ).updateProfitInfo(_tokenId, amountOut, true);
        }
    }

    /**
     * @notice Return the pending reward by BNB
     * @param _tokenId YBNFT token id
     * @param _account user wallet address
     */
    function pendingReward(uint256 _tokenId, address _account)
        external
        view
        override
        returns (uint256 reward)
    {
        UserAdapterInfo memory userInfo = userAdapterInfos[_account][_tokenId];

        uint256 updatedAccTokenPerShare = mAdapter.accTokenPerShare +
            ((IStrategy(strategy).pendingCake(0, address(this)) * 1e12) /
                mAdapter.totalStaked);

        uint256 tokenRewards = ((updatedAccTokenPerShare -
            userInfo.userShares) * userInfo.amount) / 1e12;

        if (tokenRewards != 0)
            reward = stakingToken == wbnb
                ? tokenRewards
                : IPancakeRouter(router).getAmountsOut(
                    tokenRewards,
                    getPaths(stakingToken, wbnb)
                )[1];
    }

    receive() external payable {}
}
