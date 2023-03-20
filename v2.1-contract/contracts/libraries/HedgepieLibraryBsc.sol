// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

import "../interfaces/IYBNFT.sol";
import "../interfaces/IAdapter.sol";
import "../interfaces/IPancakePair.sol";
import "../interfaces/IPancakeRouter.sol";
import "../interfaces/IOffchainOracle.sol";
import "../base/BaseAdapter.sol";

library HedgepieLibraryBsc {
    address constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address constant USDT = 0x55d398326f99059fF775485246999027B3197955;
    address constant ORACLE = 0xfbD61B037C325b959c0F6A7e69D8f37770C2c550;

    function swapOnRouter(
        uint256 _amountIn,
        address _adapter,
        address _outToken,
        address _router,
        address _wbnb
    ) public returns (uint256 amountOut) {
        address[] memory path = IAdapter(_adapter).getPaths(_wbnb, _outToken);
        uint256 beforeBalance = IBEP20(_outToken).balanceOf(address(this));

        IPancakeRouter(_router)
            .swapExactETHForTokensSupportingFeeOnTransferTokens{
            value: _amountIn
        }(0, path, address(this), block.timestamp + 2 hours);

        uint256 afterBalance = IBEP20(_outToken).balanceOf(address(this));
        amountOut = afterBalance - beforeBalance;
    }

    function swapForBnb(
        uint256 _amountIn,
        address _adapter,
        address _inToken,
        address _router,
        address _wbnb
    ) public returns (uint256 amountOut) {
        if (_inToken == _wbnb) {
            IWrap(_wbnb).withdraw(_amountIn);
            amountOut = _amountIn;
        } else {
            address[] memory path = IAdapter(_adapter).getPaths(
                _inToken,
                _wbnb
            );
            uint256 beforeBalance = address(this).balance;

            IBEP20(_inToken).approve(_router, _amountIn);

            IPancakeRouter(_router)
                .swapExactTokensForETHSupportingFeeOnTransferTokens(
                    _amountIn,
                    0,
                    path,
                    address(this),
                    block.timestamp + 2 hours
                );

            uint256 afterBalance = address(this).balance;
            amountOut = afterBalance - beforeBalance;
        }
    }

    function getRewards(
        uint256 _tokenId,
        address _adapterAddr,
        address _account
    ) public view returns (uint256 reward, uint256 reward1) {
        BaseAdapter.AdapterInfo memory adapterInfo = IAdapter(_adapterAddr)
            .adapterInfos(_tokenId);
        BaseAdapter.UserAdapterInfo memory userInfo = IAdapter(_adapterAddr)
            .userAdapterInfos(_account, _tokenId);

        if (
            IAdapter(_adapterAddr).rewardToken() != address(0) &&
            adapterInfo.totalStaked != 0 &&
            adapterInfo.accTokenPerShare != 0
        ) {
            reward =
                ((adapterInfo.accTokenPerShare - userInfo.userShares) *
                    userInfo.amount) /
                1e12;
        }

        if (
            IAdapter(_adapterAddr).rewardToken1() != address(0) &&
            adapterInfo.totalStaked != 0 &&
            adapterInfo.accTokenPerShare1 != 0
        ) {
            reward1 =
                ((adapterInfo.accTokenPerShare1 - userInfo.userShares1) *
                    userInfo.amount) /
                1e12;
        }
    }

    function getMRewards(
        uint256 _tokenId,
        address _adapterAddr,
        address _account
    ) public view returns (uint256 reward, uint256 reward1) {
        BaseAdapter.AdapterInfo memory adapterInfo = IAdapter(_adapterAddr)
            .mAdapter();
        BaseAdapter.UserAdapterInfo memory userInfo = IAdapter(_adapterAddr)
            .userAdapterInfos(_account, _tokenId);

        if (
            IAdapter(_adapterAddr).rewardToken() != address(0) &&
            adapterInfo.totalStaked != 0 &&
            adapterInfo.accTokenPerShare != 0
        ) {
            reward =
                (IAdapter(_adapterAddr).getfBNBAmount(_tokenId, _account) *
                    (adapterInfo.accTokenPerShare - userInfo.userShares)) /
                1e12 +
                userInfo.rewardDebt;
        }

        if (
            IAdapter(_adapterAddr).rewardToken1() != address(0) &&
            adapterInfo.totalStaked != 0 &&
            adapterInfo.accTokenPerShare1 != 0
        ) {
            reward1 =
                (IAdapter(_adapterAddr).getfBNBAmount(_tokenId, _account) *
                    (adapterInfo.accTokenPerShare1 - userInfo.userShares1)) /
                1e12 +
                userInfo.rewardDebt1;
        }
    }

    function getLP(
        IYBNFT.Adapter memory _adapter,
        address wbnb,
        uint256 _amountIn
    ) public returns (uint256 amountOut) {
        address[2] memory tokens;
        tokens[0] = IPancakePair(_adapter.token).token0();
        tokens[1] = IPancakePair(_adapter.token).token1();
        address _router = IAdapter(_adapter.addr).router();

        uint256[2] memory tokenAmount;
        unchecked {
            tokenAmount[0] = _amountIn / 2;
            tokenAmount[1] = _amountIn - tokenAmount[0];
        }

        if (tokens[0] != wbnb) {
            tokenAmount[0] = swapOnRouter(
                tokenAmount[0],
                _adapter.addr,
                tokens[0],
                _router,
                wbnb
            );
            IBEP20(tokens[0]).approve(_router, tokenAmount[0]);
        }

        if (tokens[1] != wbnb) {
            tokenAmount[1] = swapOnRouter(
                tokenAmount[1],
                _adapter.addr,
                tokens[1],
                _router,
                wbnb
            );
            IBEP20(tokens[1]).approve(_router, tokenAmount[1]);
        }

        if (tokenAmount[0] != 0 && tokenAmount[1] != 0) {
            if (tokens[0] == wbnb || tokens[1] == wbnb) {
                (, , amountOut) = IPancakeRouter(_router).addLiquidityETH{
                    value: tokens[0] == wbnb ? tokenAmount[0] : tokenAmount[1]
                }(
                    tokens[0] == wbnb ? tokens[1] : tokens[0],
                    tokens[0] == wbnb ? tokenAmount[1] : tokenAmount[0],
                    0,
                    0,
                    address(this),
                    block.timestamp + 2 hours
                );
            } else {
                (, , amountOut) = IPancakeRouter(_router).addLiquidity(
                    tokens[0],
                    tokens[1],
                    tokenAmount[0],
                    tokenAmount[1],
                    0,
                    0,
                    address(this),
                    block.timestamp + 2 hours
                );
            }
        }
    }

    function withdrawLP(
        IYBNFT.Adapter memory _adapter,
        address wbnb,
        uint256 _amountIn
    ) public returns (uint256 amountOut) {
        address[2] memory tokens;
        tokens[0] = IPancakePair(_adapter.token).token0();
        tokens[1] = IPancakePair(_adapter.token).token1();

        address _router = IAdapter(_adapter.addr).router();
        address swapRouter = IAdapter(_adapter.addr).swapRouter();

        IBEP20(_adapter.token).approve(_router, _amountIn);

        if (tokens[0] == wbnb || tokens[1] == wbnb) {
            address tokenAddr = tokens[0] == wbnb ? tokens[1] : tokens[0];
            (uint256 amountToken, uint256 amountETH) = IPancakeRouter(_router)
                .removeLiquidityETH(
                    tokenAddr,
                    _amountIn,
                    0,
                    0,
                    address(this),
                    block.timestamp + 2 hours
                );

            amountOut = amountETH;
            amountOut += swapForBnb(
                amountToken,
                _adapter.addr,
                tokenAddr,
                swapRouter,
                wbnb
            );
        } else {
            (uint256 amountA, uint256 amountB) = IPancakeRouter(_router)
                .removeLiquidity(
                    tokens[0],
                    tokens[1],
                    _amountIn,
                    0,
                    0,
                    address(this),
                    block.timestamp + 2 hours
                );

            amountOut += swapForBnb(
                amountA,
                _adapter.addr,
                tokens[0],
                swapRouter,
                wbnb
            );
            amountOut += swapForBnb(
                amountB,
                _adapter.addr,
                tokens[1],
                swapRouter,
                wbnb
            );
        }
    }

    function getBNBPrice() public view returns (uint256) {
        return IOffchainOracle(ORACLE).getRate(WBNB, USDT, false);
    }
}
