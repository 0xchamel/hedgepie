// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../../libraries/HedgepieLibraryBsc.sol";
import "../../interfaces/IHedgepieInvestor.sol";
import "../../interfaces/IHedgepieAdapterInfo.sol";

interface IStrategy {
    function pendingCake(uint256 _pid, address _user)
        external
        view
        returns (uint256);

    function deposit(uint256 pid, uint256 shares) external;

    function withdraw(uint256 pid, uint256 shares) external;
}

contract PancakeSwapFarmLPAdapterBsc is BaseAdapterBsc {
    /**
     * @notice Construct
     * @param _strategy  address of strategy
     * @param _stakingToken  address of staking token
     * @param _rewardToken  address of reward token
     * @param _name  adatper name
     */
    constructor(
        uint256 _pid,
        address _strategy,
        address _stakingToken,
        address _rewardToken,
        address _router,
        address _wbnb,
        string memory _name
    ) {
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
    function deposit(uint256 _tokenId)
        external
        payable
        override
        onlyInvestor
        returns (uint256 amountOut)
    {
        uint256 _amountIn = msg.value;

        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId];

        // swap to staking token
        amountOut = HedgepieLibraryBsc.swapOnRouter(
            _amountIn,
            address(this),
            stakingToken,
            router,
            wbnb
        );

        // calc rewardToken amount
        uint256 rewardAmt0;
        rewardAmt0 = IBEP20(rewardToken).balanceOf(address(this));
        IBEP20(stakingToken).approve(strategy, amountOut);
        IStrategy(strategy).deposit(pid, amountOut);
        rewardAmt0 = IBEP20(rewardToken).balanceOf(address(this)) - rewardAmt0;

        // update accTokenPerShare if reward is generated
        if (
            rewardAmt0 != 0 &&
            rewardToken != address(0) &&
            mAdapter.totalStaked != 0
        ) {
            mAdapter.accTokenPerShare +=
                (rewardAmt0 * 1e12) /
                mAdapter.totalStaked;
        }

        // update user's rewardDebt value when user staked several times
        if (userInfo.amount != 0) {
            userInfo.rewardDebt +=
                (userInfo.amount *
                    (mAdapter.accTokenPerShare - userInfo.userShares)) /
                1e12;
        }

        // update user's share values
        userInfo.amount += amountOut;
        userInfo.userShares = mAdapter.accTokenPerShare;

        // Update adapterInfo contract
        address adapterInfoBnbAddr = IHedgepieInvestor(investor).adapterInfo();
        IHedgepieAdapterInfo(adapterInfoBnbAddr).updateTVLInfo(
            _tokenId,
            _amountIn,
            true
        );
        IHedgepieAdapterInfo(adapterInfoBnbAddr).updateTradedInfo(
            _tokenId,
            _amountIn,
            true
        );
        IHedgepieAdapterInfo(adapterInfoBnbAddr).updateParticipantInfo(
            _tokenId,
            _account,
            true
        );

        mAdapter.totalStaked += amountOut;
        mAdapter.invested += _amountIn;

        return _amountIn;
    }

    /**
     * @notice Withdraw the deposited Bnb
     * @param _tokenId YBNFT token id
     * @param _amount amount of staking token to withdraw
     */
    function withdraw(uint256 _tokenId, uint256 _amount)
        external
        payable
        override
        onlyInvestor
        returns (uint256 amountOut)
    {
        UserAdapterInfo storage userInfo = userAdapterInfos[_account][_tokenId];
        require(_amount <= userInfo.amount, "Not enough balance to withdraw");

        // calc reward and withdrawn amount
        uint256 rewardAmt0 = IBEP20(rewardToken).balanceOf(address(this));
        amountOut = IBEP20(stakingToken).balanceOf(address(this));
        IStrategy(strategy).withdraw(pid, _amount);
        rewardAmt0 = IBEP20(rewardToken).balanceOf(address(this)) - rewardAmt0;
        amountOut = IBEP20(stakingToken).balanceOf(address(this)) - amountOut;
        require(_amount == amountOut, "Failed to withdraw");

        // update accTokenPerShare if reward is generated
        if (rewardAmt0 != 0 && rewardToken != address(0)) {
            mAdapter.accTokenPerShare +=
                (rewardAmt0 * 1e12) /
                mAdapter.totalStaked;
        }

        if (router == address(0)) {
            amountOut = HedgepieLibraryBsc.swapForBnb(
                amountOut,
                address(this),
                stakingToken,
                swapRouter,
                wbnb
            );
        } else {
            amountOut = HedgepieLibraryBsc.withdrawLP(
                IYBNFT.Adapter(0, stakingToken, address(this)),
                wbnb,
                amountOut
            );
        }

        (uint256 reward, ) = HedgepieLibraryBsc.getMRewards(
            _tokenId,
            address(this),
            _account
        );

        uint256 rewardBnb;
        if (reward != 0) {
            rewardBnb = HedgepieLibraryBsc.swapForBnb(
                reward,
                address(this),
                rewardToken,
                swapRouter,
                wbnb
            );
        }

        address adapterInfoBnbAddr = IHedgepieInvestor(investor).adapterInfo();
        if (rewardBnb != 0) {
            amountOut += rewardBnb;
            IHedgepieAdapterInfo(adapterInfoBnbAddr).updateProfitInfo(
                _tokenId,
                rewardBnb,
                true
            );
        }

        // Update adapterInfo contract
        IHedgepieAdapterInfo(adapterInfoBnbAddr).updateTVLInfo(
            _tokenId,
            rewardBnb != 0 ? amountOut - rewardBnb : amountOut,
            false
        );
        IHedgepieAdapterInfo(adapterInfoBnbAddr).updateTradedInfo(
            _tokenId,
            userInfo.invested,
            true
        );
        IHedgepieAdapterInfo(adapterInfoBnbAddr).updateParticipantInfo(
            _tokenId,
            _account,
            false
        );

        mAdapter.totalStaked -= getMUserAmount(_tokenId, _account);
        mAdapter.invested -= getfBNBAmount(_tokenId, _account);
        adapterInvested[_tokenId] -= getfBNBAmount(_tokenId, _account);
        delete userAdapterInfos[_account][_tokenId];

        if (amountOut != 0) {
            bool success;
            if (rewardBnb != 0) {
                rewardBnb =
                    (rewardBnb *
                        IYBNFT(IHedgepieInvestor(investor).ybnft())
                            .performanceFee(_tokenId)) /
                    1e4;
                (success, ) = payable(IHedgepieInvestor(investor).treasury())
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
        uint256 rewardAmt0 = IBEP20(rewardToken).balanceOf(address(this));
        IStrategy(strategy).withdraw(pid, 0);
        rewardAmt0 = IBEP20(rewardToken).balanceOf(address(this)) - rewardAmt0;
        if (rewardAmt0 != 0 && rewardToken != address(0)) {
            mAdapter.accTokenPerShare +=
                (rewardAmt0 * 1e12) /
                mAdapter.invested;
        }

        (uint256 reward, ) = HedgepieLibraryBsc.getMRewards(
            _tokenId,
            address(this),
            _account
        );

        userInfo.userShares = mAdapter.accTokenPerShare;
        userInfo.rewardDebt = 0;

        if (reward != 0 && rewardToken != address(0)) {
            amountOut = HedgepieLibraryBsc.swapForBnb(
                reward,
                address(this),
                rewardToken,
                swapRouter,
                wbnb
            );

            uint256 taxAmount = (amountOut *
                IYBNFT(IHedgepieInvestor(investor).ybnft()).performanceFee(
                    _tokenId
                )) / 1e4;
            (bool success, ) = payable(IHedgepieInvestor(investor).treasury())
                .call{value: taxAmount}("");
            require(success, "Failed to send bnb to Treasury");

            (success, ) = payable(_account).call{value: amountOut - taxAmount}(
                ""
            );
            require(success, "Failed to send bnb");

            IHedgepieAdapterInfo(IHedgepieInvestor(investor).adapterInfo())
                .updateProfitInfo(_tokenId, amountOut, true);
        }
    }

    /**
     * @notice Return the pending reward by Bnb
     * @param _tokenId YBNFT token id
     * @param _account user wallet address
     */
    function pendingReward(uint256 _tokenId, address _account)
        external
        view
        override
        returns (uint256 reward, uint256 withdrawable)
    {
        UserAdapterInfo memory userInfo = userAdapterInfos[_account][_tokenId];

        uint256 updatedAccTokenPerShare = mAdapter.accTokenPerShare +
            ((IStrategy(strategy).pendingCake(pid, address(this)) * 1e12) /
                mAdapter.invested);

        uint256 tokenRewards = ((updatedAccTokenPerShare -
            userInfo.userShares) * getfBNBAmount(_tokenId, _account)) /
            1e12 +
            userInfo.rewardDebt;

        if (tokenRewards != 0) {
            reward = rewardToken == wbnb
                ? tokenRewards
                : IPancakeRouter(swapRouter).getAmountsOut(
                    tokenRewards,
                    getPaths(rewardToken, wbnb)
                )[getPaths(rewardToken, wbnb).length - 1];
            withdrawable = reward;
        }
    }

    /**
     * @notice Remove funds
     * @param _tokenId YBNFT token id
     */
    function removeFunds(uint256 _tokenId)
        external
        payable
        override
        onlyInvestor
        returns (uint256 amountOut)
    {
        if (adapterInvested[_tokenId] == 0) return 0;

        // get lp amount to withdraw
        uint256 lpAmt = (mAdapter.totalStaked * adapterInvested[_tokenId]) /
            mAdapter.invested;

        // update reward infor
        uint256 rewardAmt0 = IBEP20(rewardToken).balanceOf(address(this));
        amountOut = IBEP20(stakingToken).balanceOf(address(this));
        IStrategy(strategy).withdraw(pid, lpAmt);
        amountOut = IBEP20(stakingToken).balanceOf(address(this)) - amountOut;
        rewardAmt0 = IBEP20(rewardToken).balanceOf(address(this)) - rewardAmt0;
        if (rewardAmt0 != 0 && rewardToken != address(0)) {
            mAdapter.accTokenPerShare +=
                (rewardAmt0 * 1e12) /
                mAdapter.invested;
        }

        // swap withdrawn lp to bnb
        if (router == address(0)) {
            amountOut = HedgepieLibraryBsc.swapForBnb(
                amountOut,
                address(this),
                stakingToken,
                swapRouter,
                wbnb
            );
        } else {
            amountOut = HedgepieLibraryBsc.withdrawLP(
                IYBNFT.Adapter(0, stakingToken, address(this)),
                wbnb,
                amountOut
            );
        }

        // update invested information for token id
        mAdapter.invested -= adapterInvested[_tokenId];
        mAdapter.totalStaked -= lpAmt;

        // Update adapterInfo contract
        address adapterInfoBnbAddr = IHedgepieInvestor(investor).adapterInfo();
        IHedgepieAdapterInfo(adapterInfoBnbAddr).updateTVLInfo(
            _tokenId,
            amountOut,
            false
        );

        delete adapterInvested[_tokenId];

        // send to investor
        (bool success, ) = payable(investor).call{value: amountOut}("");
        require(success, "Failed to send bnb to investor");
    }

    /**
     * @notice Update funds
     * @param _tokenId YBNFT token id
     */
    function updateFunds(uint256 _tokenId)
        external
        payable
        override
        onlyInvestor
        returns (uint256 amountOut)
    {
        uint256 _amountIn = msg.value;

        if (router == address(0)) {
            amountOut = HedgepieLibraryBsc.swapOnRouter(
                _amountIn,
                address(this),
                stakingToken,
                swapRouter,
                wbnb
            );
        } else {
            amountOut = HedgepieLibraryBsc.getLP(
                IYBNFT.Adapter(0, stakingToken, address(this)),
                wbnb,
                _amountIn
            );
        }
        uint256 rewardAmt0;

        rewardAmt0 = IBEP20(rewardToken).balanceOf(address(this));
        IBEP20(stakingToken).approve(strategy, amountOut);
        IStrategy(strategy).deposit(pid, amountOut);
        rewardAmt0 = IBEP20(rewardToken).balanceOf(address(this)) - rewardAmt0;
        if (
            rewardAmt0 != 0 &&
            rewardToken != address(0) &&
            mAdapter.invested != 0
        ) {
            mAdapter.accTokenPerShare +=
                (rewardAmt0 * 1e12) /
                mAdapter.invested;
        }

        // Update adapterInfo contract
        address adapterInfoBnbAddr = IHedgepieInvestor(investor).adapterInfo();
        IHedgepieAdapterInfo(adapterInfoBnbAddr).updateTVLInfo(
            _tokenId,
            _amountIn,
            true
        );

        _amountIn = (_amountIn * HedgepieLibraryBsc.getBNBPrice()) / 1e18;
        mAdapter.totalStaked += amountOut;
        mAdapter.invested += _amountIn;
        adapterInvested[_tokenId] += _amountIn;

        return _amountIn;
    }

    receive() external payable {}
}
