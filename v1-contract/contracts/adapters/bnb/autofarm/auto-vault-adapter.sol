// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../../../interfaces/IVaultStrategy.sol";
import "../../../interfaces/IHedgepieInvestorBsc.sol";
import "../../../interfaces/IHedgepieAdapterInfoBsc.sol";
import "../../../libraries/HedgepieLibraryBsc.sol";

interface IStrategy {
    function pendingAUTO(uint256 pid, address user)
        external
        view
        returns (uint256);

    function userInfo(uint256 pid, address user)
        external
        view
        returns (uint256, uint256);

    function deposit(uint256 pid, uint256 shares) external;

    function withdraw(uint256 pid, uint256 shares) external;
}

contract AutoVaultAdapterBsc is BaseAdapterBsc {
    // vStrategy address of vault
    address public vStrategy;

    /**
     * @notice Construct
     * @param _pid pool id of strategy
     * @param _strategy  address of strategy
     * @param _vStrategy  address of vault strategy
     * @param _stakingToken  address of staking token
     * @param _router  address of DEX router
     * @param _swapRouter  address of swap router
     * @param _wbnb  address of wbnb
     * @param _name  adatper name
     */
    constructor(
        uint256 _pid,
        address _strategy,
        address _vStrategy,
        address _stakingToken,
        address _router,
        address _swapRouter,
        address _wbnb,
        string memory _name
    ) {
        pid = _pid;
        strategy = _strategy;
        vStrategy = _vStrategy;
        stakingToken = _stakingToken;
        router = _router;
        swapRouter = _swapRouter;
        wbnb = _wbnb;
        name = _name;
    }

    /**
     * @notice Deposit with Bnb
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

        // get LP
        amountOut = HedgepieLibraryBsc.getLP(
            IYBNFT.Adapter(0, stakingToken, address(this)),
            wbnb,
            _amountIn
        );

        // deposit
        (uint256 beforeShare, ) = IStrategy(strategy).userInfo(
            pid,
            address(this)
        );
        IBEP20(stakingToken).approve(strategy, amountOut);
        IStrategy(strategy).deposit(pid, amountOut);
        (uint256 afterShare, ) = IStrategy(strategy).userInfo(
            pid,
            address(this)
        );

        userInfo.invested += _amountIn;

        // Update adapterInfo contract
        address adapterInfoBnbAddr = IHedgepieInvestorBsc(investor)
            .adapterInfo();
        IHedgepieAdapterInfoBsc(adapterInfoBnbAddr).updateTVLInfo(
            _tokenId,
            _amountIn,
            true
        );
        IHedgepieAdapterInfoBsc(adapterInfoBnbAddr).updateTradedInfo(
            _tokenId,
            _amountIn,
            true
        );
        IHedgepieAdapterInfoBsc(adapterInfoBnbAddr).updateParticipantInfo(
            _tokenId,
            _account,
            true
        );

        _amountIn = (_amountIn * HedgepieLibraryBsc.getBNBPrice()) / 1e18;
        mAdapter.totalStaked += afterShare - beforeShare;
        mAdapter.invested += _amountIn;
        adapterInvested[_tokenId] += _amountIn;

        return _amountIn;
    }

    /**
     * @notice Withdraw the deposited Bnb
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

        // withdraw from Vault
        uint256 vAmount = (getMUserAmount(_tokenId, _account) *
            IVaultStrategy(vStrategy).wantLockedTotal()) /
            IVaultStrategy(vStrategy).sharesTotal();
        uint256 lpOut = IBEP20(stakingToken).balanceOf(address(this));
        IStrategy(strategy).withdraw(pid, vAmount);

        unchecked {
            lpOut = IBEP20(stakingToken).balanceOf(address(this)) - lpOut;
        }

        amountOut = HedgepieLibraryBsc.withdrawLP(
            IYBNFT.Adapter(0, stakingToken, address(this)),
            wbnb,
            lpOut
        );

        address adapterInfoBnbAddr = IHedgepieInvestorBsc(investor)
            .adapterInfo();

        uint256 reward;
        if (amountOut > userInfo.invested) {
            reward = amountOut - userInfo.invested;

            IHedgepieAdapterInfoBsc(adapterInfoBnbAddr).updateProfitInfo(
                _tokenId,
                reward,
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
            mAdapter.totalStaked -= getMUserAmount(_tokenId, _account);
            mAdapter.invested -= getfBNBAmount(_tokenId, _account);
            adapterInvested[_tokenId] -= getfBNBAmount(_tokenId, _account);
        }

        delete userAdapterInfos[_account][_tokenId];

        if (amountOut != 0) {
            bool success;
            if (reward != 0) {
                reward =
                    (reward *
                        IYBNFT(IHedgepieInvestorBsc(investor).ybnft())
                            .performanceFee(_tokenId)) /
                    1e4;
                (success, ) = payable(IHedgepieInvestorBsc(investor).treasury())
                    .call{value: reward}("");
                require(success, "Failed to send bnb to Treasury");
            }

            (success, ) = payable(_account).call{value: amountOut - reward}("");
            require(success, "Failed to send bnb");
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
        returns (uint256 reward, uint256)
    {
        UserAdapterInfo memory userInfo = userAdapterInfos[_account][_tokenId];

        uint256 vAmount = (getMUserAmount(_tokenId, _account) *
            IVaultStrategy(vStrategy).wantLockedTotal()) /
            IVaultStrategy(vStrategy).sharesTotal();

        address token0 = IPancakePair(stakingToken).token0();
        address token1 = IPancakePair(stakingToken).token1();
        (uint112 reserve0, uint112 reserve1, ) = IPancakePair(stakingToken)
            .getReserves();

        uint256 amount0 = (reserve0 * vAmount) /
            IPancakePair(stakingToken).totalSupply();
        uint256 amount1 = (reserve1 * vAmount) /
            IPancakePair(stakingToken).totalSupply();

        if (token0 == wbnb) reward += amount0;
        else
            reward += amount0 == 0
                ? 0
                : IPancakeRouter(swapRouter).getAmountsOut(
                    amount0,
                    getPaths(token0, wbnb)
                )[getPaths(token0, wbnb).length - 1];

        if (token1 == wbnb) reward += amount1;
        else
            reward += amount1 == 0
                ? 0
                : IPancakeRouter(swapRouter).getAmountsOut(
                    amount1,
                    getPaths(token1, wbnb)
                )[getPaths(token1, wbnb).length - 1];

        if (reward <= userInfo.invested) return (0, 0);
        return (reward - userInfo.invested, 0);
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
        // get shares amount to withdraw
        uint256 shareAmt = (mAdapter.totalStaked * adapterInvested[_tokenId]) /
            mAdapter.invested;

        // withdraw from Vault
        amountOut = IBEP20(stakingToken).balanceOf(address(this));
        uint256 vAmount = (shareAmt *
            IVaultStrategy(vStrategy).wantLockedTotal()) /
            IVaultStrategy(vStrategy).sharesTotal();
        IStrategy(strategy).withdraw(pid, vAmount);
        amountOut = IBEP20(stakingToken).balanceOf(address(this)) - amountOut;

        // swap withdrawn lp to bnb
        if (router == address(0)) {
            amountOut = HedgepieLibraryBsc.swapforBnb(
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
        mAdapter.totalStaked -= shareAmt;

        // Update adapterInfo contract
        address adapterInfoBnbAddr = IHedgepieInvestorBsc(investor)
            .adapterInfo();
        IHedgepieAdapterInfoBsc(adapterInfoBnbAddr).updateTVLInfo(
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

        // get LP
        amountOut = HedgepieLibraryBsc.getLP(
            IYBNFT.Adapter(0, stakingToken, address(this)),
            wbnb,
            _amountIn
        );

        // deposit
        (uint256 beforeShare, ) = IStrategy(strategy).userInfo(
            pid,
            address(this)
        );
        IBEP20(stakingToken).approve(strategy, amountOut);
        IStrategy(strategy).deposit(pid, amountOut);
        (uint256 afterShare, ) = IStrategy(strategy).userInfo(
            pid,
            address(this)
        );
        // Update adapterInfo contract
        address adapterInfoBnbAddr = IHedgepieInvestorBsc(investor)
            .adapterInfo();
        IHedgepieAdapterInfoBsc(adapterInfoBnbAddr).updateTVLInfo(
            _tokenId,
            _amountIn,
            true
        );

        _amountIn = (_amountIn * HedgepieLibraryBsc.getBNBPrice()) / 1e18;
        mAdapter.totalStaked += afterShare - beforeShare;
        mAdapter.invested += _amountIn;
        adapterInvested[_tokenId] += _amountIn;

        return _amountIn;
    }

    receive() external payable {}
}
