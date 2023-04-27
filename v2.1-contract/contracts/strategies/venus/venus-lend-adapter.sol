// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../../interfaces/IVBep20.sol";

import "../../libraries/HedgepieLibraryBsc.sol";

interface IStrategy {
    function mint(uint256 amount) external returns (uint256);

    function redeem(uint256 amount) external returns (uint256);

    function comptroller() external view returns (address);
}

interface IVenusLens {
    function pendingVenus(address, address) external view returns (uint256);
}

contract VenusLendAdapterBsc is BaseAdapter {
    // venus lends address
    IVenusLens immutable venusLens;

    // venus comptroller address
    address private comptroller;

    /**
     * @notice Construct
     * @param _strategy  address of strategy
     * @param _venusLens  address of venus lens
     * @param _stakingToken  address of staking token
     * @param _repayToken  address of repay token
     * @param _swapRouter  address of swap router
     * @param _name  adatper name
     * @param _authority  hedgepieAuthority address
     */
    constructor(
        address _strategy,
        address _venusLens,
        address _stakingToken,
        address _repayToken,
        address _swapRouter,
        string memory _name,
        address _authority
    ) BaseAdapter(_authority) {
        require(IVBep20(_strategy).isVToken(), "Error: Invalid vToken address");
        require(IVBep20(_strategy).underlying() != address(0), "Error: Invalid underlying address");

        strategy = _strategy;
        venusLens = IVenusLens(_venusLens);
        comptroller = IStrategy(strategy).comptroller();
        stakingToken = _stakingToken;
        repayToken = _repayToken;
        rewardToken1 = IComptroller(comptroller).getXVSAddress();
        rewardToken2 = _stakingToken;
        swapRouter = _swapRouter;
        name = _name;
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
     */
    function deposit(uint256 _tokenId) external payable override onlyInvestor returns (uint256 amountOut) {
        uint256 _amountIn = msg.value;
        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId];

        // 1. get staking token
        amountOut = HedgepieLibraryBsc.swapOnRouter(_amountIn, address(this), stakingToken, swapRouter);

        uint256 repayAmt = IERC20(repayToken).balanceOf(address(this));
        IERC20(stakingToken).approve(strategy, amountOut);
        require(IStrategy(strategy).mint(amountOut) == 0, "Error: Venus internal error");
        repayAmt = IERC20(repayToken).balanceOf(address(this)) - repayAmt;

        unchecked {
            // 2. update mAdapter & userInfo
            mAdapter.totalStaked += repayAmt;

            userInfo.amount += repayAmt;
            userInfo.invested += amountOut;
        }

        return _amountIn;
    }

    /**
     * @notice Withdraw the deposited Bnb
     * @param _tokenId YBNFT token id
     * @param _amount staking token amount to withdraw
     */
    function withdraw(
        uint256 _tokenId,
        uint256 _amount
    ) external payable override onlyInvestor returns (uint256 amountOut) {
        if (_amount == 0) return 0;

        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId];

        // validation of _amount parameter
        require(_amount <= userInfo.amount, "Not enough balance to withdraw");

        // 1. calc reward and withdraw from adapter
        amountOut = IERC20(stakingToken).balanceOf(address(this));
        uint256 repayAmt = IERC20(repayToken).balanceOf(address(this));
        IERC20(repayToken).approve(strategy, _amount);
        require(IStrategy(strategy).redeem(_amount) == 0, "Error: Venus internal error");
        repayAmt = repayAmt - IERC20(repayToken).balanceOf(address(this));
        amountOut = IERC20(stakingToken).balanceOf(address(this)) - amountOut;
        require(repayAmt == _amount, "Error: Redeem failed");

        // 2. swap withdrawn staking tokens to bnb
        if (router == address(0)) {
            amountOut = HedgepieLibraryBsc.swapForBnb(amountOut, address(this), stakingToken, swapRouter);
        } else {
            amountOut = HedgepieLibraryBsc.withdrawLP(IYBNFT.AdapterParam(0, address(this)), stakingToken, amountOut);
        }

        // 3. update mAdapter & user Info
        mAdapter.totalStaked -= _amount;
        userInfo.amount -= _amount;
        userInfo.invested -= amountOut;
        userInfo.rewardDebt1 = 0;

        // 4. charge fee and send BNB to investor
        if (amountOut != 0) _chargeFeeAndSendToInvestor(_tokenId, amountOut, 0);
    }

    /**
     * @notice Return the pending reward by Bnb
     * @param _tokenId YBNFT token id
     */
    function pendingReward(uint256 _tokenId) external view override returns (uint256 reward, uint256 withdrawable) {
        UserAdapterInfo memory userInfo = userAdapterInfos[_tokenId];

        uint256 exchangeRate = IVToken(repayToken).exchangeRateStored();

        // 1. calc updatedAccTokenPerShares
        uint256 updatedAccTokenPerShare1 = mAdapter.accTokenPerShare1;
        uint256 updatedAccTokenPerShare2 = mAdapter.accTokenPerShare2;

        if (mAdapter.totalStaked != 0) {
            updatedAccTokenPerShare1 += ((_pendingVenus() * 1e12) / mAdapter.totalStaked);

            if ((userInfo.amount * exchangeRate) / 1e18 > userInfo.invested) {
                updatedAccTokenPerShare2 +=
                    (((userInfo.amount * exchangeRate) / 1e18 - userInfo.invested) * 1e12) /
                    mAdapter.totalStaked;
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
            address[] memory paths1 = IPathFinder(authority.pathFinder()).getPaths(
                swapRouter,
                rewardToken1,
                HedgepieLibraryBsc.WBNB
            );
            reward = stakingToken == HedgepieLibraryBsc.WBNB
                ? tokenRewards1
                : IPancakeRouter(swapRouter).getAmountsOut(tokenRewards1, paths1)[paths1.length - 1];
        }
        if (tokenRewards2 != 0) {
            address[] memory paths2 = IPathFinder(authority.pathFinder()).getPaths(
                swapRouter,
                stakingToken,
                HedgepieLibraryBsc.WBNB
            );
            reward += stakingToken == HedgepieLibraryBsc.WBNB
                ? tokenRewards2
                : IPancakeRouter(swapRouter).getAmountsOut(tokenRewards2, paths2)[paths2.length - 1];
        }

        withdrawable = reward;
    }

    /**
     * @notice Claim the pending reward
     * @param _tokenId YBNFT token id
     */
    function claim(uint256 _tokenId) external payable override onlyInvestor returns (uint256 amountOut) {
        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId];

        // 1. check if reward is generated
        _calcReward(_tokenId, IVToken(repayToken).exchangeRateCurrent());

        // 2. get reward amount
        (uint256 reward1, uint256 reward2) = HedgepieLibraryBsc.getMRewards(_tokenId, address(this));

        // 3. update user info
        userInfo.userShare1 = mAdapter.accTokenPerShare1;
        userInfo.userShare2 = mAdapter.accTokenPerShare2;
        userInfo.rewardDebt1 = 0;
        userInfo.rewardDebt2 = 0;

        // 4. swap reward to bnb and send to investor
        if (reward1 != 0) {
            amountOut = HedgepieLibraryBsc.swapForBnb(reward1, address(this), rewardToken1, swapRouter);
            if (reward2 != 0)
                amountOut += HedgepieLibraryBsc.swapForBnb(reward2, address(this), rewardToken2, swapRouter);

            // 5. charge fee and send BNB to investor
            _chargeFeeAndSendToInvestor(_tokenId, amountOut, amountOut);
        }
    }

    /**
     * @notice calculate XVS & supply rewards
     * @param _tokenId YBNFT token id
     * @param _exchangeRate exchangeRate from venus
     */
    function _calcReward(uint256 _tokenId, uint256 _exchangeRate) internal {
        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId];

        // check if reward is generated & updated accTokenPerShare values
        uint256 rewardAmt1 = IERC20(rewardToken1).balanceOf(address(this));
        IComptroller(comptroller).claimVenus(address(this));
        rewardAmt1 = IERC20(rewardToken1).balanceOf(address(this)) - rewardAmt1;
        if (rewardAmt1 != 0 && mAdapter.totalStaked != 0) {
            mAdapter.accTokenPerShare1 += (rewardAmt1 * 1e12) / mAdapter.totalStaked;
        }

        if ((userInfo.amount * _exchangeRate) / 1e18 > userInfo.invested) {
            uint256 rewardAmt2 = IERC20(rewardToken2).balanceOf(address(this));
            uint256 withdrawAmt = (((userInfo.amount * _exchangeRate) / 1e18 - userInfo.invested) * 1e18) /
                _exchangeRate;
            require(IStrategy(strategy).redeem(withdrawAmt) == 0, "Error: Venus internal error");
            rewardAmt2 = IERC20(rewardToken2).balanceOf(address(this)) - rewardAmt2;

            if (rewardAmt2 != 0 && mAdapter.totalStaked != 0) {
                mAdapter.accTokenPerShare2 += (rewardAmt2 * 1e12) / mAdapter.totalStaked;
            }

            userInfo.amount -= withdrawAmt;
            mAdapter.totalStaked -= withdrawAmt;
        }
    }

    /**
     * @notice Remove funds
     * @param _tokenId YBNFT token id
     */
    function removeFunds(uint256 _tokenId) external payable override onlyInvestor returns (uint256 amountOut) {
        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId];
        if (userInfo.amount == 0) return 0;

        // 1. update reward infor after withdraw all staking tokens
        _calcReward(_tokenId, IVToken(repayToken).exchangeRateCurrent());

        amountOut = IERC20(stakingToken).balanceOf(address(this));
        require(IStrategy(strategy).redeem(userInfo.amount) == 0, "Error: Venus internal error");
        amountOut = IERC20(stakingToken).balanceOf(address(this)) - amountOut;
        require(amountOut != 0, "Failed to remove funds");

        // 2. update user rewardDebt value
        if (userInfo.amount != 0) {
            userInfo.rewardDebt1 += (userInfo.amount * (mAdapter.accTokenPerShare1 - userInfo.userShare1)) / 1e12;
            userInfo.rewardDebt2 += (userInfo.amount * (mAdapter.accTokenPerShare2 - userInfo.userShare2)) / 1e12;
        }

        // 4. swap withdrawn lp to bnb
        if (router == address(0)) {
            amountOut = HedgepieLibraryBsc.swapForBnb(amountOut, address(this), stakingToken, swapRouter);
        } else {
            amountOut = HedgepieLibraryBsc.withdrawLP(IYBNFT.AdapterParam(0, address(this)), stakingToken, amountOut);
        }

        // 5. update invested information for token id
        mAdapter.totalStaked -= userInfo.amount;
        userInfo.amount = 0;
        userInfo.invested = 0;
        userInfo.userShare1 = mAdapter.accTokenPerShare1;
        userInfo.userShare2 = mAdapter.accTokenPerShare2;

        // 6. send to investor
        (bool success, ) = payable(authority.hInvestor()).call{value: amountOut}("");
        require(success, "Failed to send bnb to investor");
    }

    /**
     * @notice Update funds
     * @param _tokenId YBNFT token id
     */
    /// #if_succeeds {:msg "updateFunds failed"}  userAdapterInfos[_tokenId].userShare1 == mAdapter.accTokenPerShare1;
    function updateFunds(uint256 _tokenId) external payable override onlyInvestor returns (uint256 amountOut) {
        if (msg.value == 0) return 0;

        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId];

        // 1. swap bnb to staking token
        if (router == address(0)) {
            amountOut = HedgepieLibraryBsc.swapOnRouter(msg.value, address(this), stakingToken, swapRouter);
        } else {
            amountOut = HedgepieLibraryBsc.getLP(IYBNFT.AdapterParam(0, address(this)), stakingToken, msg.value);
        }

        // 2. get reward amount after deposit
        _calcReward(_tokenId, IVToken(repayToken).exchangeRateCurrent());

        // 3. supply staking token
        uint256 repayAmt = IERC20(repayToken).balanceOf(address(this));
        IERC20(stakingToken).approve(strategy, amountOut);
        require(IStrategy(strategy).mint(amountOut) == 0, "Error: Venus internal error");
        repayAmt = IERC20(repayToken).balanceOf(address(this)) - repayAmt;

        unchecked {
            // 4. update mAdapter & userInfo
            mAdapter.totalStaked += repayAmt;

            userInfo.amount = repayAmt;
            userInfo.invested = amountOut;
            userInfo.userShare1 = mAdapter.accTokenPerShare1;
            userInfo.userShare2 = mAdapter.accTokenPerShare2;
        }

        return msg.value;
    }
}
