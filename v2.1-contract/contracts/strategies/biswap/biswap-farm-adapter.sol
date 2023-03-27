// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../../libraries/HedgepieLibraryBsc.sol";
import "../../interfaces/IHedgepieInvestor.sol";

interface IStrategy {
    function pendingBSW(uint256 _pid, address _user)
        external
        view
        returns (uint256);

    function deposit(uint256 pid, uint256 amount) external;

    function withdraw(uint256 pid, uint256 amount) external;

    function enterStaking(uint256 amount) external;

    function leaveStaking(uint256 amount) external;
}

contract BiSwapFarmLPAdapterBsc is BaseAdapter {
    /**
     * @notice Construct
     * @param _strategy  address of strategy
     * @param _stakingToken  address of staking token
     * @param _rewardToken  address of reward token
     * @param _router  address of biswap
     * @param _swapRouter  address of swap router
     * @param _wbnb  wbnb address
     * @param _name  adatper name
     * @param _hedgepieAuthority  hedgepieAuthority address
     */
    constructor(
        uint256 _pid,
        address _strategy,
        address _stakingToken,
        address _rewardToken,
        address _router,
        address _swapRouter,
        address _wbnb,
        string memory _name,
        address _hedgepieAuthority
    ) BaseAdapter(_hedgepieAuthority) {
        pid = _pid;
        stakingToken = _stakingToken;
        rewardToken = _rewardToken;
        strategy = _strategy;
        router = _router;
        swapRouter = _swapRouter;
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
        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId];

        uint256 rewardAmt = IERC20(rewardToken).balanceOf(address(this));

        if (router == address(0)) {
            amountOut = HedgepieLibraryBsc.swapOnRouter(
                msg.value,
                address(this),
                stakingToken,
                swapRouter,
                wbnb
            );
        } else {
            amountOut = HedgepieLibraryBsc.getLP(
                IYBNFT.Adapter(0, stakingToken, address(this)),
                wbnb,
                msg.value
            );
        }

        IERC20(stakingToken).approve(strategy, amountOut);
        if (pid == 0) IStrategy(strategy).enterStaking(amountOut);
        else IStrategy(strategy).deposit(pid, amountOut);

        unchecked {
            rewardAmt =
                IERC20(rewardToken).balanceOf(address(this)) -
                rewardAmt;

            // update accTokenPerShare if reward is generated
            if (rewardAmt != 0 && mAdapter.totalStaked != 0) {
                mAdapter.accTokenPerShare1 +=
                    (rewardAmt * 1e12) /
                    mAdapter.totalStaked;
            }

            // update user's rewardDebt value when user staked several times
            if (userInfo.amount != 0) {
                userInfo.rewardDebt1 +=
                    (userInfo.amount *
                        (mAdapter.accTokenPerShare1 - userInfo.userShare1)) /
                    1e12;
            }

            // update mAdapter & userInfo
            userInfo.amount += amountOut;
            userInfo.userShare1 = mAdapter.accTokenPerShare1;
            mAdapter.totalStaked += amountOut;

            amountOut = msg.value;
        }
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
        if (_amount == 0) return 0;

        UserAdapterInfo storage userInfo = userAdapterInfos[_tokenId];

        // validation of _amount parameter
        require(_amount <= userInfo.amount, "Not enough balance to withdraw");

        amountOut = IERC20(stakingToken).balanceOf(address(this));
        uint256 rewardAmt = IERC20(rewardToken).balanceOf(address(this));

        // remove stakingToken
        if (pid == 0) IStrategy(strategy).leaveStaking(userInfo.amount);
        else IStrategy(strategy).withdraw(pid, userInfo.amount);

        unchecked {
            if (rewardToken == stakingToken) {
                
            }
        }

        rewardAmt0 = pid == 0
            ? IERC20(rewardToken).balanceOf(address(this)) -
                rewardAmt0 -
                userInfo.amount
            : IERC20(rewardToken).balanceOf(address(this)) - rewardAmt0;
        amountOut = pid == 0
            ? IERC20(stakingToken).balanceOf(address(this)) -
                amountOut -
                rewardAmt0
            : IERC20(stakingToken).balanceOf(address(this)) - amountOut;

        if (
            rewardAmt0 != 0 &&
            rewardToken != address(0) &&
            mAdapter.totalStaked != 0
        ) {
            mAdapter.accTokenPerShare +=
                (rewardAmt0 * 1e12) /
                mAdapter.totalStaked;
        }

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

        mAdapter.totalStaked -= userInfo.amount;
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
        uint256 rewardAmt0 = IERC20(rewardToken).balanceOf(address(this));
        if (pid == 0) IStrategy(strategy).leaveStaking(0);
        else IStrategy(strategy).withdraw(pid, 0);
        rewardAmt0 = IERC20(rewardToken).balanceOf(address(this)) - rewardAmt0;
        if (
            rewardAmt0 != 0 &&
            rewardToken != address(0) &&
            mAdapter.totalStaked != 0
        ) {
            mAdapter.accTokenPerShare +=
                (rewardAmt0 * 1e12) /
                mAdapter.totalStaked;
        }

        (uint256 reward, ) = HedgepieLibraryBsc.getMRewards(
            _tokenId,
            address(this),
            _account
        );

        userInfo.userShares = mAdapter.accTokenPerShare;
        userInfo.rewardDebt = 0;

        if (reward != 0 && rewardToken != address(0)) {
            amountOut = HedgepieLibraryBsc.swapforBnb(
                reward,
                address(this),
                rewardToken,
                swapRouter,
                wbnb
            );
        }

        if (amountOut != 0) {
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
            ((IStrategy(strategy).pendingBSW(pid, address(this)) * 1e12) /
                mAdapter.totalStaked);

        uint256 tokenRewards = ((updatedAccTokenPerShare -
            userInfo.userShares) * userInfo.amount) /
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

    receive() external payable {}
}
