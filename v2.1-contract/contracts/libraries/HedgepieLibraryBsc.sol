// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/IAdapter.sol";
import "../interfaces/IPancakePair.sol";
import "../interfaces/IPancakeRouter.sol";
import "../interfaces/IOffchainOracle.sol";

import "../base/BaseAdapter.sol";

library HedgepieLibraryBsc {
    using SafeERC20 for IERC20;

    address private constant _WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address private constant _USDT = 0x55d398326f99059fF775485246999027B3197955;
    address private constant _ORACLE =
        0xfbD61B037C325b959c0F6A7e69D8f37770C2c550;

    /**
     * @notice Swap tokens
     * @param _amountIn  amount of inputToken
     * @param _adapter  address of adapter
     * @param _outToken  address of targetToken
     * @param _router  address of swap router
     */
    function swapOnRouter(
        uint256 _amountIn,
        address _adapter,
        address _outToken,
        address _router
    ) public returns (uint256 amountOut) {
        address[] memory path = IPathFinder(
            IHedgepieAuthority(IAdapter(_adapter).authority()).pathFinder()
        ).getPaths(_router, _WBNB, _outToken);
        uint256 beforeBalance = IERC20(_outToken).balanceOf(address(this));

        IPancakeRouter(_router)
            .swapExactETHForTokensSupportingFeeOnTransferTokens{
            value: _amountIn
        }(0, path, address(this), block.timestamp + 2 hours);

        uint256 afterBalance = IERC20(_outToken).balanceOf(address(this));
        amountOut = afterBalance - beforeBalance;
    }

    /**
     * @notice Swap tokens and receive BNB
     * @param _amountIn  amount of swap token
     * @param _adapter  address of adapter
     * @param _inToken  address of swap token
     * @param _router  address of swap router
     */
    function swapForBnb(
        uint256 _amountIn,
        address _adapter,
        address _inToken,
        address _router
    ) public returns (uint256 amountOut) {
        if (_inToken == _WBNB) {
            IWrap(_WBNB).withdraw(_amountIn);
            amountOut = _amountIn;
        } else {
            address[] memory path = IPathFinder(
                IHedgepieAuthority(IAdapter(_adapter).authority()).pathFinder()
            ).getPaths(_router, _inToken, _WBNB);
            uint256 beforeBalance = address(this).balance;

            IERC20(_inToken).safeApprove(_router, 0);
            IERC20(_inToken).safeApprove(_router, _amountIn);

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

    /**
     * @notice Get user's reward amount in adapter
     * @param _tokenId  tokenID
     * @param _adapterAddr  address of adapter
     */
    function getMRewards(
        uint256 _tokenId,
        address _adapterAddr
    ) public view returns (uint256 reward, uint256 reward1) {
        BaseAdapter.AdapterInfo memory adapterInfo = IAdapter(_adapterAddr)
            .mAdapter();
        BaseAdapter.UserAdapterInfo memory userInfo = IAdapter(_adapterAddr)
            .userAdapterInfos(_tokenId);

        if (
            IAdapter(_adapterAddr).rewardToken() != address(0) &&
            adapterInfo.totalStaked != 0 &&
            adapterInfo.accTokenPerShare1 != 0
        ) {
            reward =
                (userInfo.amount *
                    (adapterInfo.accTokenPerShare1 - userInfo.userShare1)) /
                1e12 +
                userInfo.rewardDebt1;
        }

        if (
            IAdapter(_adapterAddr).rewardToken1() != address(0) &&
            adapterInfo.totalStaked != 0 &&
            adapterInfo.accTokenPerShare2 != 0
        ) {
            reward1 =
                (userInfo.amount *
                    (adapterInfo.accTokenPerShare2 - userInfo.userShare2)) /
                1e12 +
                userInfo.rewardDebt2;
        }
    }

    /**
     * @notice Get LP by add liquidity
     * @param _adapter  AdapterInfo
     * @param _stakingToken  address of staking token
     * @param _amountIn  amount of BNB
     */
    function getLP(
        IYBNFT.AdapterParam memory _adapter,
        address _stakingToken,
        uint256 _amountIn
    ) public returns (uint256 amountOut) {
        address[2] memory tokens;
        tokens[0] = IPancakePair(_stakingToken).token0();
        tokens[1] = IPancakePair(_stakingToken).token1();
        address _router = IAdapter(_adapter.addr).router();

        uint256[2] memory tokenAmount;
        unchecked {
            tokenAmount[0] = _amountIn / 2;
            tokenAmount[1] = _amountIn - tokenAmount[0];
        }

        if (tokens[0] != _WBNB) {
            tokenAmount[0] = swapOnRouter(
                tokenAmount[0],
                _adapter.addr,
                tokens[0],
                _router
            );
            IERC20(tokens[0]).safeApprove(_router, 0);
            IERC20(tokens[0]).safeApprove(_router, tokenAmount[0]);
        }

        if (tokens[1] != _WBNB) {
            tokenAmount[1] = swapOnRouter(
                tokenAmount[1],
                _adapter.addr,
                tokens[1],
                _router
            );
            IERC20(tokens[1]).safeApprove(_router, 0);
            IERC20(tokens[1]).safeApprove(_router, tokenAmount[1]);
        }

        if (tokenAmount[0] != 0 && tokenAmount[1] != 0) {
            if (tokens[0] == _WBNB || tokens[1] == _WBNB) {
                (, , amountOut) = IPancakeRouter(_router).addLiquidityETH{
                    value: tokens[0] == _WBNB ? tokenAmount[0] : tokenAmount[1]
                }(
                    tokens[0] == _WBNB ? tokens[1] : tokens[0],
                    tokens[0] == _WBNB ? tokenAmount[1] : tokenAmount[0],
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

    /**
     * @notice Withdraw LP from pool
     * @param _adapter  AdapterInfo
     * @param _stakingToken  address of staking token
     * @param _amountIn  amount of LP
     */
    function withdrawLP(
        IYBNFT.AdapterParam memory _adapter,
        address _stakingToken,
        uint256 _amountIn
    ) public returns (uint256 amountOut) {
        address[2] memory tokens;
        tokens[0] = IPancakePair(_stakingToken).token0();
        tokens[1] = IPancakePair(_stakingToken).token1();

        address _router = IAdapter(_adapter.addr).router();
        address swapRouter = IAdapter(_adapter.addr).swapRouter();

        IERC20(_stakingToken).safeApprove(_router, 0);
        IERC20(_stakingToken).safeApprove(_router, _amountIn);

        if (tokens[0] == _WBNB || tokens[1] == _WBNB) {
            address tokenAddr = tokens[0] == _WBNB ? tokens[1] : tokens[0];
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
                swapRouter
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
                swapRouter
            );
            amountOut += swapForBnb(
                amountB,
                _adapter.addr,
                tokens[1],
                swapRouter
            );
        }
    }

    /**
     * @notice Get BNB Price from oracle
     */
    function getBNBPrice() public view returns (uint256) {
        return IOffchainOracle(_ORACLE).getRate(_WBNB, _USDT, false);
    }
}
