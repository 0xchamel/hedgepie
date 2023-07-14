// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../../interfaces/IVaultStrategy.sol";
import "../../libraries/HedgepieLibraryBsc.sol";

interface IStrategy {
    function pendingAUTO(uint256 pid, address user) external view returns (uint256);

    function userInfo(uint256 pid, address user) external view returns (uint256, uint256);

    function deposit(uint256 pid, uint256 shares) external;

    function withdraw(uint256 pid, uint256 shares) external;
}

contract AutoVaultAdapterBsc is BaseAdapter {
    using SafeERC20 for IERC20;

    // index ==> address vStrategy address of vault
    mapping(uint256 => address) public vStrategy;

    /**
     * @notice Initializer
     * @param _pid pool id of strategy
     * @param _strategy  address of strategy
     * @param _vStrategy  address of vault strategy
     * @param _stakingToken  address of staking token
     * @param _router  address of DEX router
     * @param _swapRouter  address of swap router
     * @param _name  adatper name
     * @param _authority HedgepieAuthority address
     */
    function initialize(
        uint256 _pid,
        address _strategy,
        address _vStrategy,
        address _stakingToken,
        address _router,
        address _swapRouter,
        string memory _name,
        address _authority
    ) external initializer {
        require(_stakingToken != address(0), "Invalid staking token");
        require(_strategy != address(0), "Invalid strategy address");
        require(_vStrategy != address(0), "Invalid vStrategy address");

        __BaseAdapter__init(_authority);

        adapterDetails.push(
            AdapterDetail({
                pid: _pid,
                stakingToken: _stakingToken,
                rewardToken1: address(0),
                rewardToken2: address(0),
                repayToken: address(0),
                strategy: _strategy,
                router: _router,
                swapRouter: _swapRouter,
                name: _name
            })
        );

        vStrategy[0] = _vStrategy;
    }

    /**
     * @notice Deposit with Bnb
     * @param _tokenId YBNFT token id
     * @param _index index of strategies
     */
    /// #if_succeeds {:msg "deposit failed"}  userAdapterInfos[_tokenId][_index].userShare1 == mAdapter.accTokenPerShare1 && mAdapter.totalStaked > old(mAdapter.totalStaked);
    function deposit(
        uint256 _tokenId,
        uint256 _index
    ) external payable override onlyInvestor returns (uint256 amountOut) {
        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId][_index];
        AdapterDetail memory aDetail = adapterDetails[_index];

        // 1. get LP
        amountOut = HedgepieLibraryBsc.getLP(
            aDetail,
            IYBNFT.AdapterParam(0, address(this), _index),
            aDetail.stakingToken,
            msg.value
        );

        // 2. deposit to vault
        (uint256 beforeShare, ) = IStrategy(aDetail.strategy).userInfo(aDetail.pid, address(this));
        IERC20(aDetail.stakingToken).safeApprove(aDetail.strategy, 0);
        IERC20(aDetail.stakingToken).safeApprove(aDetail.strategy, amountOut);
        IStrategy(aDetail.strategy).deposit(aDetail.pid, amountOut);
        (uint256 afterShare, ) = IStrategy(aDetail.strategy).userInfo(aDetail.pid, address(this));
        require(afterShare > beforeShare, "Failed to deposit");

        // 3. update user info
        userInfo.amount += afterShare - beforeShare;
        userInfo.invested += amountOut;
    }

    /**
     * @notice Withdraw from strategy
     * @param _tokenId YBNFT token id
     * @param _amount amount of staking token to withdraw
     */
    /// #if_succeeds {:msg "withdraw failed"}  userAdapterInfos[_tokenId][_index].userShare1 == mAdapter.accTokenPerShare1 && userAdapterInfos[_tokenId][_index].rewardDebt1 == 0;
    function withdraw(
        uint256 _tokenId,
        uint256 _index,
        uint256 _amount
    ) external payable override onlyInvestor returns (uint256 amountOut) {
        if (_amount == 0) return 0;

        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId][_index];
        AdapterDetail memory aDetail = adapterDetails[_index];

        // 1. withdraw from Vault
        uint256 vAmount = (_amount * IVaultStrategy(vStrategy[_index]).wantLockedTotal()) /
            IVaultStrategy(vStrategy[_index]).sharesTotal();
        uint256 lpOut = IERC20(aDetail.stakingToken).balanceOf(address(this));
        IStrategy(aDetail.strategy).withdraw(aDetail.pid, vAmount);
        lpOut = IERC20(aDetail.stakingToken).balanceOf(address(this)) - lpOut;

        // 2. swap withdrawn lp to bnb
        amountOut = HedgepieLibraryBsc.withdrawLP(
            aDetail,
            IYBNFT.AdapterParam(0, address(this), _index),
            aDetail.stakingToken,
            lpOut
        );

        // 3. update userInfo
        userInfo.amount -= _amount;
        if (lpOut >= userInfo.invested) userInfo.invested = 0;
        else userInfo.invested -= lpOut;

        // 4. send withdrawn bnb to investor
        if (amountOut != 0) _chargeFeeAndSendToInvestor(_tokenId, amountOut, 0);
    }

    /**
     * @notice Claim the pending reward
     * @param _tokenId YBNFT token id
     * @param _index index of strategies
     */
    /// #if_succeeds {:msg "claim failed"}  userAdapterInfos[_tokenId][_index].userShare1 == mAdapter.accTokenPerShare1 && userAdapterInfos[_tokenId][_index].rewardDebt1 == 0;
    function claim(
        uint256 _tokenId,
        uint256 _index
    ) external payable override onlyInvestor returns (uint256 amountOut) {
        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId][_index];
        AdapterDetail memory aDetail = adapterDetails[_index];

        // 1. check if reward is generated
        uint256 vAmount = (userInfo.amount * IVaultStrategy(vStrategy[_index]).wantLockedTotal()) /
            IVaultStrategy(vStrategy[_index]).sharesTotal();

        // 2. if reward is not generated
        if (vAmount <= userInfo.invested) {
            if (userInfo.rewardDebt1 == 0) return 0;

            amountOut = userInfo.rewardDebt1;
            userInfo.rewardDebt1 = 0;

            // 3. charge fee and send BNB to investor
            _chargeFeeAndSendToInvestor(_tokenId, amountOut, amountOut);
            return amountOut;
        }

        // 3. withdraw reward from vault
        vAmount -= userInfo.invested;
        (uint256 beforeShare, ) = IStrategy(aDetail.strategy).userInfo(aDetail.pid, address(this));
        uint256 lpOut = IERC20(aDetail.stakingToken).balanceOf(address(this));
        IStrategy(aDetail.strategy).withdraw(aDetail.pid, vAmount);
        lpOut = IERC20(aDetail.stakingToken).balanceOf(address(this)) - lpOut;
        (uint256 afterShare, ) = IStrategy(aDetail.strategy).userInfo(aDetail.pid, address(this));

        // 4. swap reward to bnb
        amountOut =
            HedgepieLibraryBsc.withdrawLP(
                aDetail,
                IYBNFT.AdapterParam(0, address(this), _index),
                aDetail.stakingToken,
                lpOut
            ) +
            userInfo.rewardDebt1;

        // 5. update user info
        userInfo.amount -= beforeShare - afterShare;
        userInfo.rewardDebt1 = 0;

        // 6. charge fee and send BNB to investor
        if (amountOut != 0) _chargeFeeAndSendToInvestor(_tokenId, amountOut, amountOut);
    }

    /**
     * @notice Return the pending reward by BNB
     * @param _tokenId YBNFT token id
     * @param _index index of strategies
     */
    function pendingReward(
        uint256 _tokenId,
        uint256 _index
    ) external view override returns (uint256 reward, uint256 withdrawable) {
        UserAdapterInfo memory userInfo = userAdapterInfos[_tokenId][_index];
        AdapterDetail memory aDetail = adapterDetails[_index];

        // 1. calc want amount
        uint256 vAmount = (userInfo.amount * IVaultStrategy(vStrategy[_index]).wantLockedTotal()) /
            IVaultStrategy(vStrategy[_index]).sharesTotal();

        if (vAmount <= userInfo.invested) return (userInfo.rewardDebt1, userInfo.rewardDebt1);

        // 2. calc reward
        vAmount -= userInfo.invested;

        address token0 = IPancakePair(aDetail.stakingToken).token0();
        address token1 = IPancakePair(aDetail.stakingToken).token1();
        (uint112 reserve0, uint112 reserve1, ) = IPancakePair(aDetail.stakingToken).getReserves();

        uint256 amount0 = (reserve0 * vAmount) / IPancakePair(aDetail.stakingToken).totalSupply();
        uint256 amount1 = (reserve1 * vAmount) / IPancakePair(aDetail.stakingToken).totalSupply();

        if (amount0 != 0) {
            if (token0 == HedgepieLibraryBsc.WBNB) reward += amount0;
            else {
                address[] memory paths = IPathFinder(authority.pathFinder()).getPaths(
                    aDetail.swapRouter,
                    token0,
                    HedgepieLibraryBsc.WBNB
                );

                reward += IPancakeRouter(aDetail.swapRouter).getAmountsOut(amount0, paths)[paths.length - 1];
            }
        }

        if (amount1 != 0) {
            if (token1 == HedgepieLibraryBsc.WBNB) reward += amount1;
            else {
                address[] memory paths = IPathFinder(authority.pathFinder()).getPaths(
                    aDetail.swapRouter,
                    token1,
                    HedgepieLibraryBsc.WBNB
                );
                reward += IPancakeRouter(aDetail.swapRouter).getAmountsOut(amount1, paths)[paths.length - 1];
            }
        }

        reward += userInfo.rewardDebt1;
        withdrawable = reward;
    }

    /**
     * @notice Remove funds
     * @param _tokenId YBNFT token id
     * @param _index index of strategies
     */
    /// #if_succeeds {:msg "removeFunds failed"}  userAdapterInfos[_tokenId][_index].userShare1 == mAdapter.accTokenPerShare1 && userAdapterInfos[_tokenId][_index].amount == 0;
    function removeFunds(
        uint256 _tokenId,
        uint256 _index
    ) external payable override onlyInvestor returns (uint256 amountOut) {
        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId][_index];
        AdapterDetail memory aDetail = adapterDetails[_index];

        if (userInfo.amount == 0) return 0;

        // 1. withdraw all from Vault
        amountOut = IERC20(aDetail.stakingToken).balanceOf(address(this));
        uint256 vAmount = (userInfo.amount * IVaultStrategy(vStrategy[_index]).wantLockedTotal()) /
            IVaultStrategy(vStrategy[_index]).sharesTotal();
        IStrategy(aDetail.strategy).withdraw(aDetail.pid, vAmount);
        amountOut = IERC20(aDetail.stakingToken).balanceOf(address(this)) - amountOut;

        // 2. calc reward
        uint256 rewardPercent = 0;
        if (amountOut > userInfo.invested) {
            rewardPercent = ((amountOut - userInfo.invested) * 1e12) / amountOut;
        }

        // 3. swap withdrawn lp to bnb
        if (aDetail.router == address(0)) {
            amountOut = HedgepieLibraryBsc.swapForBnb(
                amountOut,
                address(this),
                aDetail.stakingToken,
                aDetail.swapRouter
            );
        } else {
            amountOut = HedgepieLibraryBsc.withdrawLP(
                aDetail,
                IYBNFT.AdapterParam(0, address(this), _index),
                aDetail.stakingToken,
                amountOut
            );
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
     * @param _index index of strategies
     */
    /// #if_succeeds {:msg "updateFunds failed"}  userAdapterInfos[_tokenId][_index].userShare1 == mAdapter.accTokenPerShare1;
    function updateFunds(
        uint256 _tokenId,
        uint256 _index
    ) external payable override onlyInvestor returns (uint256 amountOut) {
        if (msg.value == 0) return 0;

        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId][_index];
        AdapterDetail memory aDetail = adapterDetails[_index];

        // 1. get LP
        amountOut = HedgepieLibraryBsc.getLP(
            aDetail,
            IYBNFT.AdapterParam(0, address(this), _index),
            aDetail.stakingToken,
            msg.value
        );

        // 2. deposit to vault
        (uint256 beforeShare, ) = IStrategy(aDetail.strategy).userInfo(aDetail.pid, address(this));
        IERC20(aDetail.stakingToken).safeApprove(aDetail.strategy, 0);
        IERC20(aDetail.stakingToken).safeApprove(aDetail.strategy, amountOut);
        IStrategy(aDetail.strategy).deposit(aDetail.pid, amountOut);
        (uint256 afterShare, ) = IStrategy(aDetail.strategy).userInfo(aDetail.pid, address(this));
        require(afterShare > beforeShare, "Failed to update funds");

        // 3. update user info
        userInfo.amount = afterShare - beforeShare;
        userInfo.invested = amountOut;
    }

    /**
     * @notice Set vStrategy
     * @param _index index of strategies
     * @param _vStrategy address of vStrategy
     */
    function setvStrategy(uint256 _index, address _vStrategy) external onlyAdapterManager {
        vStrategy[_index] = _vStrategy;
    }
}
