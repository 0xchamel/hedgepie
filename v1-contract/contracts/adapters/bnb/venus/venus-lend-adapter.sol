// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./interface/VBep20Interface.sol";

import "../../../libraries/HedgepieLibraryBsc.sol";
import "../../../interfaces/IHedgepieInvestorBsc.sol";
import "../../../interfaces/IHedgepieAdapterInfoBsc.sol";

interface IStrategy {
    function mint(uint256 amount) external returns (uint256);

    function redeem(uint256 amount) external returns (uint256);

    function comptroller() external view returns (address);
}

interface IVenusLens {
    function pendingVenus(address, address) external view returns(uint256);
}

contract VenusLendAdapterBsc is BaseAdapterBsc {
    IVenusLens immutable venusLens;

    address private comptroller;

    uint256 private pendingVenus;

    /**
     * @notice Construct
     * @param _strategy  address of strategy
     * @param _venusLens  address of venus lens
     * @param _stakingToken  address of staking token
     * @param _repayToken  address of repay token
     * @param _swapRouter  address of swap router
     * @param _wbnb  address of wbnb
     * @param _name  adatper name
     */
    constructor(
        address _strategy,
        address _venusLens,
        address _stakingToken,
        address _repayToken,
        address _swapRouter,
        address _wbnb,
        string memory _name
    ) {
        require(
            VBep20Interface(_strategy).isVToken(),
            "Error: Invalid vToken address"
        );
        require(
            VBep20Interface(_strategy).underlying() != address(0),
            "Error: Invalid underlying address"
        );

        strategy = _strategy;
        venusLens = IVenusLens(_venusLens);
        comptroller = IStrategy(strategy).comptroller();
        stakingToken = _stakingToken;
        repayToken = _repayToken;
        swapRouter = _swapRouter;
        wbnb = _wbnb;
        name = _name;
    }

    /**
     * @notice Return pendingVenus
     */
    function _pendingVenus() private view returns(uint256) {
        return venusLens.pendingVenus(address(this), comptroller);
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

        amountOut = HedgepieLibraryBsc.swapOnRouter(
            _amountIn,
            address(this),
            stakingToken,
            swapRouter,
            wbnb
        );

        uint256 repayAmt = IBEP20(repayToken).balanceOf(address(this));
        IBEP20(stakingToken).approve(strategy, amountOut);
        require(
            IStrategy(strategy).mint(amountOut) == 0,
            "Error: Venus internal error"
        );
        repayAmt = IBEP20(repayToken).balanceOf(address(this)) - repayAmt;

        {
            uint256 newPending = _pendingVenus();
            unchecked {
                if(newPending > pendingVenus) {
                    mAdapter.accTokenPerShare +=
                        ((newPending - pendingVenus) * 1e12) /
                        mAdapter.totalStaked;

                    pendingVenus = newPending;
                }

                if (userInfo.amount != 0) {
                    userInfo.rewardDebt +=
                        (userInfo.amount *
                            (mAdapter.accTokenPerShare - userInfo.userShares)) /
                        1e12;
                }

                mAdapter.totalStaked += amountOut;

                userInfo.amount += amountOut;
                userInfo.invested += _amountIn;
                userInfo.userShares1 += repayAmt;
                userInfo.userShares = mAdapter.accTokenPerShare;
            }
        }

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
        AdapterInfo storage adapterInfo = adapterInfos[_tokenId];
        UserAdapterInfo storage userInfo = userAdapterInfos[_account][_tokenId];

        uint256 repayAmt;

        amountOut = IBEP20(stakingToken).balanceOf(address(this));
        repayAmt = IBEP20(repayToken).balanceOf(address(this));

        IBEP20(repayToken).approve(strategy, userInfo.userShares1);
        require(
            IStrategy(strategy).redeem(userInfo.userShares1) == 0,
            "Error: Venus internal error"
        );

        repayAmt = repayAmt - IBEP20(repayToken).balanceOf(address(this));
        amountOut = IBEP20(stakingToken).balanceOf(address(this)) - amountOut;

        require(repayAmt == userInfo.userShares1, "Error: Redeem failed");

        amountOut = HedgepieLibraryBsc.swapforBnb(
            amountOut,
            address(this),
            stakingToken,
            swapRouter,
            wbnb
        );

        (uint256 reward, ) = HedgepieLibraryBsc.getRewards(
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
                swapRouter,
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
            adapterInfo.totalStaked -= userInfo.amount;
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
     * @notice Return the pending reward by Bnb
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

        uint256 updatedAccTokenPerShare = mAdapter.accTokenPerShare +
            (((_pendingVenus() - pendingVenus) * 1e12) /
                mAdapter.totalStaked);

        uint256 tokenRewards = ((updatedAccTokenPerShare -
            userInfo.userShares) * userInfo.amount) /
            1e12 +
            userInfo.rewardDebt;

        if (tokenRewards != 0) {
            address[] memory paths = getPaths(stakingToken, wbnb);
            reward = stakingToken == wbnb
                ? tokenRewards
                : IPancakeRouter(swapRouter).getAmountsOut(
                    tokenRewards,
                    paths
                )[paths.length - 1];
        }
    }

    receive() external payable {}
}
