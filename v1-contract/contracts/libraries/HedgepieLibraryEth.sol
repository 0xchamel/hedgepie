// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

import "../interfaces/IYBNFT.sol";
import "../interfaces/IAdapterEth.sol";
import "../interfaces/IPancakePair.sol";
import "../interfaces/IPancakeRouter.sol";

import "../HedgepieInvestorEth.sol";
import "../adapters/BaseAdapterEth.sol";

library HedgepieLibraryEth {
    function swapOnRouter(
        uint256 _amountIn,
        address _adapter,
        address _outToken,
        address _router,
        address weth
    ) public returns (uint256 amountOut) {
        address[] memory path = IAdapterEth(_adapter).getPaths(weth, _outToken);
        uint256 beforeBalance = IBEP20(_outToken).balanceOf(address(this));

        IPancakeRouter(_router)
            .swapExactETHForTokensSupportingFeeOnTransferTokens{
            value: _amountIn
        }(0, path, address(this), block.timestamp + 2 hours);

        uint256 afterBalance = IBEP20(_outToken).balanceOf(address(this));
        amountOut = afterBalance - beforeBalance;
    }

    function swapforEth(
        uint256 _amountIn,
        address _adapter,
        address _inToken,
        address _router,
        address _weth
    ) public returns (uint256 amountOut) {
        if (_inToken == _weth) {
            IWrap(_weth).withdraw(_amountIn);
            amountOut = _amountIn;
        } else {
            address[] memory path = IAdapterEth(_adapter).getPaths(
                _inToken,
                _weth
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
        BaseAdapterEth.AdapterInfo memory adapterInfo = IAdapterEth(
            _adapterAddr
        ).adapterInfos(_tokenId);
        BaseAdapterEth.UserAdapterInfo memory userInfo = IAdapterEth(
            _adapterAddr
        ).userAdapterInfos(_account, _tokenId);

        if (
            IAdapterEth(_adapterAddr).rewardToken() != address(0) &&
            adapterInfo.totalStaked != 0 &&
            adapterInfo.accTokenPerShare != 0
        ) {
            reward =
                ((adapterInfo.accTokenPerShare - userInfo.userShares) *
                    userInfo.amount) /
                1e12;
        }

        if (
            IAdapterEth(_adapterAddr).rewardToken1() != address(0) &&
            adapterInfo.totalStaked != 0 &&
            adapterInfo.accTokenPerShare1 != 0
        ) {
            reward1 =
                ((adapterInfo.accTokenPerShare1 - userInfo.userShares1) *
                    userInfo.amount) /
                1e12;
        }
    }

    function getLP(
        IYBNFT.Adapter memory _adapter,
        address weth,
        uint256 _amountIn
    ) public returns (uint256 amountOut) {
        address[2] memory tokens;
        tokens[0] = IPancakePair(_adapter.token).token0();
        tokens[1] = IPancakePair(_adapter.token).token1();
        address _router = IAdapterEth(_adapter.addr).router();

        uint256[2] memory tokenAmount;
        unchecked {
            tokenAmount[0] = _amountIn / 2;
            tokenAmount[1] = _amountIn - tokenAmount[0];
        }

        if (tokens[0] != weth) {
            tokenAmount[0] = swapOnRouter(
                tokenAmount[0],
                _adapter.addr,
                tokens[0],
                _router,
                weth
            );
            IBEP20(tokens[0]).approve(_router, tokenAmount[0]);
        }

        if (tokens[1] != weth) {
            tokenAmount[1] = swapOnRouter(
                tokenAmount[1],
                _adapter.addr,
                tokens[1],
                _router,
                weth
            );
            IBEP20(tokens[1]).approve(_router, tokenAmount[1]);
        }

        if (tokenAmount[0] != 0 && tokenAmount[1] != 0) {
            if (tokens[0] == weth || tokens[1] == weth) {
                (, , amountOut) = IPancakeRouter(_router).addLiquidityETH{
                    value: tokens[0] == weth ? tokenAmount[0] : tokenAmount[1]
                }(
                    tokens[0] == weth ? tokens[1] : tokens[0],
                    tokens[0] == weth ? tokenAmount[1] : tokenAmount[0],
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
        address weth,
        uint256 _amountIn
    ) public returns (uint256 amountOut) {
        address[2] memory tokens;
        tokens[0] = IPancakePair(_adapter.token).token0();
        tokens[1] = IPancakePair(_adapter.token).token1();

        address _router = IAdapterEth(_adapter.addr).router();

        IBEP20(_adapter.token).approve(_router, _amountIn);

        if (tokens[0] == weth || tokens[1] == weth) {
            address tokenAddr = tokens[0] == weth ? tokens[1] : tokens[0];
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
            amountOut += swapforEth(
                amountToken,
                _adapter.addr,
                tokenAddr,
                IAdapterEth(_adapter.addr).swapRouter(),
                weth
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

            amountOut += swapforEth(
                amountA,
                _adapter.addr,
                tokens[0],
                IAdapterEth(_adapter.addr).swapRouter(),
                weth
            );
            amountOut += swapforEth(
                amountB,
                _adapter.addr,
                tokens[1],
                IAdapterEth(_adapter.addr).swapRouter(),
                weth
            );
        }
    }
}
