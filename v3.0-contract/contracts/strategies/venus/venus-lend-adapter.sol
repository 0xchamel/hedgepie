// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../../interfaces/IVBep20.sol";

import "../../libraries/HedgepieLibraryBsc.sol";

interface IStrategy {
    function mint() external payable;

    function mint(uint256 amount) external returns (uint256);

    function redeem(uint256 amount) external returns (uint256);

    function comptroller() external view returns (address);
}

interface IVenusLens {
    function pendingVenus(address, address) external view returns (uint256);
}

contract VenusLendAdapterBsc is BaseAdapter {
    // venus lends address
    IVenusLens public venusLens;

    // venus comptroller address
    address private comptroller;

    /**
     * @notice Initializer
     * @param _strategy  address of strategy
     * @param _venusLens  address of venus lens
     * @param _stakingToken  address of staking token
     * @param _repayToken  address of repay token
     * @param _swapRouter  address of swap router
     * @param _name  adatper name
     * @param _authority  hedgepieAuthority address
     */
    function initialize(
        address _strategy,
        address _venusLens,
        address _stakingToken,
        address _repayToken,
        address _swapRouter,
        string memory _name,
        address _authority
    ) external initializer {
        require(IVBep20(_strategy).isVToken(), "Error: Invalid vToken address");
        // require(IVBep20(_strategy).underlying() != address(0), "Error: Invalid underlying address");

        __BaseAdapter__init(_authority);

        venusLens = IVenusLens(_venusLens);
        comptroller = IStrategy(_strategy).comptroller();

        adapterDetails.push(
            AdapterDetail({
                pid: 0,
                stakingToken: _stakingToken,
                rewardToken1: IComptroller(comptroller).getXVSAddress(),
                rewardToken2: _stakingToken,
                repayToken: _repayToken,
                strategy: _strategy,
                router: address(0),
                swapRouter: _swapRouter,
                name: _name
            })
        );
    }

    /**
     * @notice Return pendingVenus
     */
    function _pendingVenus() private view returns (uint256) {
        return venusLens.pendingVenus(address(this), comptroller);
    }

    /**
     * @notice Deposit with BNB
     * @param _tokenId YBNFT token id
     * @param _index index of strategies
     */
    function deposit(
        uint256 _tokenId,
        uint256 _index
    ) external payable override onlyInvestor returns (uint256 amountOut) {
        uint256 _amountIn = msg.value;
        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId][_index];
        AdapterDetail memory aDetail = adapterDetails[_index];

        // 1. get staking token
        bool isBNB = aDetail.stakingToken == HedgepieLibraryBsc.WBNB;
        amountOut = isBNB
            ? msg.value
            : HedgepieLibraryBsc.swapOnRouter(_amountIn, address(this), aDetail.stakingToken, aDetail.swapRouter);

        uint256 repayAmt = IERC20(aDetail.repayToken).balanceOf(address(this));

        if (isBNB) {
            IStrategy(aDetail.strategy).mint{value: amountOut}();
        } else {
            IERC20(aDetail.stakingToken).approve(aDetail.strategy, amountOut);
            require(IStrategy(aDetail.strategy).mint(amountOut) == 0, "Error: Venus internal error");
        }

        unchecked {
            repayAmt = IERC20(aDetail.repayToken).balanceOf(address(this)) - repayAmt;

            // 2. update mAdapter & userInfo
            mAdapters[_index].totalStaked += repayAmt;

            userInfo.amount += repayAmt;
            userInfo.invested += amountOut;
        }
    }

    /**
     * @notice Withdraw the deposited Bnb
     * @param _tokenId YBNFT token id
     * @param _index index of strategies
     * @param _amount staking token amount to withdraw
     */
    function withdraw(
        uint256 _tokenId,
        uint256 _index,
        uint256 _amount
    ) external payable override onlyInvestor returns (uint256 amountOut) {
        if (_amount == 0) return 0;

        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId][_index];
        AdapterDetail memory aDetail = adapterDetails[_index];

        // validation of _amount parameter
        require(_amount <= userInfo.amount, "Not enough balance to withdraw");

        // 1. calc reward and withdraw from adapter
        bool isBNB = aDetail.stakingToken == HedgepieLibraryBsc.WBNB;
        uint256 tokenAmt = isBNB ? address(this).balance : IERC20(aDetail.stakingToken).balanceOf(address(this));
        uint256 repayAmt = IERC20(aDetail.repayToken).balanceOf(address(this));
        IERC20(aDetail.repayToken).approve(aDetail.strategy, _amount);
        require(IStrategy(aDetail.strategy).redeem(_amount) == 0, "Error: Venus internal error");

        unchecked {
            repayAmt = repayAmt - IERC20(aDetail.repayToken).balanceOf(address(this));
            tokenAmt =
                (isBNB ? address(this).balance : IERC20(aDetail.stakingToken).balanceOf(address(this))) -
                tokenAmt;
            require(repayAmt == _amount, "Error: Redeem failed");
        }

        // 2. swap withdrawn staking tokens to bnb
        amountOut = isBNB
            ? tokenAmt
            : HedgepieLibraryBsc.swapForBnb(tokenAmt, address(this), aDetail.stakingToken, aDetail.swapRouter);

        // 3. update mAdapter & user Info
        unchecked {
            mAdapters[_index].totalStaked -= _amount;
            userInfo.amount -= _amount;
            if (tokenAmt >= userInfo.invested) userInfo.invested = 0;
            else userInfo.invested -= tokenAmt;
            userInfo.rewardDebt1 = 0;
        }

        // 4. charge fee and send BNB to investor
        if (amountOut != 0) _chargeFeeAndSendToInvestor(_tokenId, amountOut, 0);
    }

    /**
     * @notice Return the pending reward by Bnb
     * @param _tokenId YBNFT token id
     * @param _index index of strategies
     */
    function pendingReward(
        uint256 _tokenId,
        uint256 _index
    ) external view override returns (uint256 reward, uint256 withdrawable) {
        UserAdapterInfo memory userInfo = userAdapterInfos[_tokenId][_index];
        AdapterDetail memory aDetail = adapterDetails[_index];

        uint256 exchangeRate = IVToken(aDetail.repayToken).exchangeRateStored();

        // 1. calc updatedAccTokenPerShares
        uint256 updatedAccTokenPerShare1 = mAdapters[_index].accTokenPerShare1;
        uint256 updatedAccTokenPerShare2 = mAdapters[_index].accTokenPerShare2;

        if (mAdapters[_index].totalStaked != 0) {
            updatedAccTokenPerShare1 += ((_pendingVenus() * 1e12) / mAdapters[_index].totalStaked);

            if ((userInfo.amount * exchangeRate) / 1e18 > userInfo.invested) {
                updatedAccTokenPerShare2 +=
                    (((userInfo.amount * exchangeRate) / 1e18 - userInfo.invested) * 1e12) /
                    mAdapters[_index].totalStaked;
            }
        }

        // 2. calc rewards from updatedAccTokenPerShare
        uint256 tokenRewards1 = ((updatedAccTokenPerShare1 - userInfo.userShare1) * userInfo.amount) /
            1e12 +
            userInfo.rewardDebt1;

        uint256 tokenRewards2 = ((updatedAccTokenPerShare2 - userInfo.userShare2) * userInfo.amount) /
            1e12 +
            userInfo.rewardDebt2;

        // 3. calc pending reward in bnb
        if (tokenRewards1 != 0) {
            if (aDetail.rewardToken1 == HedgepieLibraryBsc.WBNB) reward = tokenRewards1;
            else {
                address[] memory paths1 = IPathFinder(authority.pathFinder()).getPaths(
                    aDetail.swapRouter,
                    aDetail.rewardToken1,
                    HedgepieLibraryBsc.WBNB
                );
                reward = IPancakeRouter(aDetail.swapRouter).getAmountsOut(tokenRewards1, paths1)[paths1.length - 1];
            }
        }
        if (tokenRewards2 != 0) {
            if (aDetail.rewardToken2 == HedgepieLibraryBsc.WBNB) reward += tokenRewards2;
            else {
                address[] memory paths2 = IPathFinder(authority.pathFinder()).getPaths(
                    aDetail.swapRouter,
                    aDetail.stakingToken,
                    HedgepieLibraryBsc.WBNB
                );
                reward += IPancakeRouter(aDetail.swapRouter).getAmountsOut(tokenRewards2, paths2)[paths2.length - 1];
            }
        }

        withdrawable = reward;
    }

    /**
     * @notice Claim the pending reward
     * @param _tokenId YBNFT token id
     * @param _index index of strategies
     */
    function claim(
        uint256 _tokenId,
        uint256 _index
    ) external payable override onlyInvestor returns (uint256 amountOut) {
        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId][_index];
        AdapterDetail memory aDetail = adapterDetails[_index];

        // 1. check if reward is generated
        _calcReward(_tokenId, _index, IVToken(aDetail.repayToken).exchangeRateCurrent());

        // 2. get reward amount
        (uint256 reward1, uint256 reward2) = HedgepieLibraryBsc.getMRewards(
            _tokenId,
            _index,
            adapterDetails[_index],
            address(this)
        );

        // 3. update user info
        userInfo.userShare1 = mAdapters[_index].accTokenPerShare1;
        userInfo.userShare2 = mAdapters[_index].accTokenPerShare2;
        userInfo.rewardDebt1 = 0;
        userInfo.rewardDebt2 = 0;

        // 4. swap reward to bnb and send to investor
        if (reward1 != 0) {
            amountOut = aDetail.rewardToken1 == HedgepieLibraryBsc.WBNB
                ? reward1
                : HedgepieLibraryBsc.swapForBnb(reward1, address(this), aDetail.rewardToken1, aDetail.swapRouter);
        }

        if (reward2 != 0) {
            amountOut += aDetail.rewardToken2 == HedgepieLibraryBsc.WBNB
                ? reward2
                : HedgepieLibraryBsc.swapForBnb(reward2, address(this), aDetail.rewardToken2, aDetail.swapRouter);
        }

        // 5. charge fee and send BNB to investor
        if (amountOut != 0) _chargeFeeAndSendToInvestor(_tokenId, amountOut, amountOut);
    }

    /**
     * @notice calculate XVS & supply rewards
     * @param _tokenId YBNFT token id
     * @param _index index of strategies
     * @param _exchangeRate exchangeRate from venus
     */
    function _calcReward(uint256 _tokenId, uint256 _index, uint256 _exchangeRate) internal {
        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId][_index];
        AdapterDetail memory aDetail = adapterDetails[_index];

        // check if reward is generated & updated accTokenPerShare values
        uint256 rewardAmt1 = IERC20(aDetail.rewardToken1).balanceOf(address(this));
        IComptroller(comptroller).claimVenus(address(this));
        rewardAmt1 = IERC20(aDetail.rewardToken1).balanceOf(address(this)) - rewardAmt1;
        if (rewardAmt1 != 0 && mAdapters[_index].totalStaked != 0) {
            mAdapters[_index].accTokenPerShare1 += (rewardAmt1 * 1e12) / mAdapters[_index].totalStaked;
        }

        if ((userInfo.amount * _exchangeRate) / 1e18 > userInfo.invested) {
            bool isBNB = aDetail.rewardToken2 == HedgepieLibraryBsc.WBNB;
            uint256 rewardAmt2 = isBNB ? address(this).balance : IERC20(aDetail.rewardToken2).balanceOf(address(this));
            uint256 withdrawAmt = (((userInfo.amount * _exchangeRate) / 1e18 - userInfo.invested) * 1e18) /
                _exchangeRate;
            require(IStrategy(aDetail.strategy).redeem(withdrawAmt) == 0, "Error: Venus internal error");
            rewardAmt2 =
                (isBNB ? address(this).balance : IERC20(aDetail.rewardToken2).balanceOf(address(this))) -
                rewardAmt2;

            if (rewardAmt2 != 0 && mAdapters[_index].totalStaked != 0) {
                mAdapters[_index].accTokenPerShare2 += (rewardAmt2 * 1e12) / mAdapters[_index].totalStaked;
            }

            userInfo.amount -= withdrawAmt;
            mAdapters[_index].totalStaked -= withdrawAmt;
        }
    }

    /**
     * @notice Remove funds
     * @param _tokenId YBNFT token id
     * @param _index index of strategies
     */
    function removeFunds(
        uint256 _tokenId,
        uint256 _index
    ) external payable override onlyInvestor returns (uint256 amountOut) {
        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId][_index];
        AdapterDetail memory aDetail = adapterDetails[_index];

        if (userInfo.amount == 0) return 0;

        // 1. update reward infor after withdraw all staking tokens
        _calcReward(_tokenId, _index, IVToken(aDetail.repayToken).exchangeRateCurrent());

        bool isBNB = aDetail.stakingToken == HedgepieLibraryBsc.WBNB;
        amountOut = isBNB ? address(this).balance : IERC20(aDetail.stakingToken).balanceOf(address(this));
        require(IStrategy(aDetail.strategy).redeem(userInfo.amount) == 0, "Error: Venus internal error");
        amountOut = (isBNB ? address(this).balance : IERC20(aDetail.stakingToken).balanceOf(address(this))) - amountOut;
        require(amountOut != 0, "Failed to remove funds");

        // 2. update user rewardDebt value
        if (userInfo.amount != 0) {
            userInfo.rewardDebt1 +=
                (userInfo.amount * (mAdapters[_index].accTokenPerShare1 - userInfo.userShare1)) /
                1e12;
            userInfo.rewardDebt2 +=
                (userInfo.amount * (mAdapters[_index].accTokenPerShare2 - userInfo.userShare2)) /
                1e12;
        }

        // 4. swap withdrawn lp to bnb
        if (!isBNB)
            amountOut = HedgepieLibraryBsc.swapForBnb(
                amountOut,
                address(this),
                aDetail.stakingToken,
                aDetail.swapRouter
            );

        // 5. update invested information for token id
        mAdapters[_index].totalStaked -= userInfo.amount;
        userInfo.amount = 0;
        userInfo.invested = 0;
        userInfo.userShare1 = mAdapters[_index].accTokenPerShare1;
        userInfo.userShare2 = mAdapters[_index].accTokenPerShare2;

        // 6. send to investor
        if (amountOut != 0) _chargeFeeAndSendToInvestor(_tokenId, amountOut, 0);
    }

    /**
     * @notice Update funds
     * @param _tokenId YBNFT token id
     * @param _index index of strategies
     */
    /// #if_succeeds {:msg "updateFunds failed"}  userAdapterInfos[_tokenId][_index].userShare1 == mAdapters[_index].accTokenPerShare1;
    function updateFunds(
        uint256 _tokenId,
        uint256 _index
    ) external payable override onlyInvestor returns (uint256 amountOut) {
        if (msg.value == 0) return 0;

        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId][_index];
        AdapterDetail memory aDetail = adapterDetails[_index];

        // 1. swap bnb to staking token
        bool isBNB = aDetail.stakingToken == HedgepieLibraryBsc.WBNB;
        amountOut = isBNB
            ? msg.value
            : HedgepieLibraryBsc.swapOnRouter(msg.value, address(this), aDetail.stakingToken, aDetail.swapRouter);

        // 2. get reward amount after deposit
        _calcReward(_tokenId, _index, IVToken(aDetail.repayToken).exchangeRateCurrent());

        // 3. supply staking token
        uint256 repayAmt = IERC20(aDetail.repayToken).balanceOf(address(this));
        if (isBNB) {
            IStrategy(aDetail.strategy).mint{value: amountOut}();
        } else {
            IERC20(aDetail.stakingToken).approve(aDetail.strategy, amountOut);
            require(IStrategy(aDetail.strategy).mint(amountOut) == 0, "Error: Venus internal error");
        }

        unchecked {
            repayAmt = IERC20(aDetail.repayToken).balanceOf(address(this)) - repayAmt;

            // 4. update mAdapter & userInfo
            mAdapters[_index].totalStaked += repayAmt;

            userInfo.amount = repayAmt;
            userInfo.invested = amountOut;
            userInfo.userShare1 = mAdapters[_index].accTokenPerShare1;
            userInfo.userShare2 = mAdapters[_index].accTokenPerShare2;
        }
    }
}
