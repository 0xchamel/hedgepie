// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../interfaces/IYBNFT.sol";
import "../interfaces/IPathFinder.sol";
import "../interfaces/IHedgepieInvestor.sol";
import "../interfaces/IHedgepieAuthority.sol";

import "./HedgepieAccessControlled.sol";

abstract contract BaseAdapter is HedgepieAccessControlled {
    struct UserAdapterInfo {
        uint256 amount; // Staking token amount
        uint256 userShare1; // First rewardTokens' share
        uint256 userShare2; // Second rewardTokens' share
        uint256 rewardDebt1; // Reward Debt for first reward token
        uint256 rewardDebt2; // Reward Debt for second reward token
        uint256 invested; // invested lp token amount
    }

    struct AdapterInfo {
        uint256 accTokenPerShare1; // Accumulated per share for first reward token
        uint256 accTokenPerShare2; // Accumulated per share for second reward token
        uint256 totalStaked; // Total staked staking token
    }

    struct AdapterDetail {
        // LP pool id - should be 0 when stakingToken is not LP
        uint256 pid;
        // staking token
        address stakingToken;
        // first reward token
        address rewardToken1;
        // second reward token - optional
        address rewardToken2;
        // repay token which we will receive after deposit - optional
        address repayToken;
        // strategy where we deposit staking token
        address strategy;
        // router address for LP token
        address router;
        // swap router address for ERC20 token swap
        address swapRouter;
        // adapter name
        string name;
    }

    // Adapter Detail array
    AdapterDetail[] public adapterDetails;

    // mAdapter informations
    // index => mAdapter
    mapping(uint256 => AdapterInfo) public mAdapters;

    // adapter info for each nft
    // nft id => index => UserAdapterInfo
    mapping(uint256 => mapping(uint256 => UserAdapterInfo)) public userAdapterInfos;

    /**
     * @notice initialize
     * @param _hedgepieAuthority HedgepieAuthority address
     */
    function __BaseAdapter__init(address _hedgepieAuthority) internal onlyInitializing {
        __HedgepieAccessControlled_init(IHedgepieAuthority(_hedgepieAuthority));
    }

    /** @notice get user staked amount */
    function getUserAmount(uint256 _tokenId, uint256 _index) external view returns (uint256 amount) {
        return userAdapterInfos[_tokenId][_index].amount;
    }

    /**
     * @notice deposit to strategy
     * @param _tokenId YBNFT token id
     * @param _index index of strategies
     */
    function deposit(uint256 _tokenId, uint256 _index) external payable virtual returns (uint256 amountOut) {}

    /**
     * @notice withdraw from strategy
     * @param _tokenId YBNFT token id
     * @param _index index of strategies
     * @param _amount amount of staking tokens to withdraw
     */
    function withdraw(
        uint256 _tokenId,
        uint256 _index,
        uint256 _amount
    ) external payable virtual returns (uint256 amountOut) {}

    /**
     * @notice claim reward from strategy
     * @param _tokenId YBNFT token id
     * @param _index index of strategies
     */
    function claim(uint256 _tokenId, uint256 _index) external payable virtual returns (uint256 amountOut) {}

    /**
     * @notice Remove funds
     * @param _tokenId YBNFT token id
     * @param _index index of strategies
     */
    function removeFunds(uint256 _tokenId, uint256 _index) external payable virtual returns (uint256 amountOut) {}

    /**
     * @notice Update funds
     * @param _tokenId YBNFT token id
     * @param _index index of strategies
     */
    function updateFunds(uint256 _tokenId, uint256 _index) external payable virtual returns (uint256 amountOut) {}

    /**
     * @notice Get pending token reward
     * @param _tokenId YBNFT token id
     * @param _index index of strategies
     */
    function pendingReward(
        uint256 _tokenId,
        uint256 _index
    ) external view virtual returns (uint256 reward, uint256 withdrawable) {}

    /**
     * @notice Charge Fee and send BNB to investor
     * @param _tokenId YBNFT token id
     */
    function _chargeFeeAndSendToInvestor(uint256 _tokenId, uint256 _amount, uint256 _reward) internal {
        bool success;
        if (_reward != 0) {
            _reward = (_reward * IYBNFT(authority.hYBNFT()).performanceFee(_tokenId)) / 1e4;

            // 20% to treasury
            (success, ) = payable(IHedgepieInvestor(authority.hInvestor()).treasury()).call{value: _reward / 5}("");
            require(success, "Failed to send bnb to Treasury");

            // 80% to fund manager
            (success, ) = payable(IYBNFT(authority.hYBNFT()).ownerOf(_tokenId)).call{value: _reward - _reward / 5}("");
            require(success, "Failed to send bnb to Treasury");
        }

        (success, ) = payable(msg.sender).call{value: _amount - _reward}("");
        require(success, "Failed to send bnb");
    }

    /**
     * @notice Add adapter detail
     * @param _detail AdapterDetail parameter
     */
    function addAdapterDetail(AdapterDetail memory _detail) external onlyAdapterManager {
        adapterDetails.push(_detail);
    }

    /**
     * @notice Set adapter detail
     * @param _detail AdapterDetail parameter
     */
    function setAdapterDetail(uint256 _index, AdapterDetail memory _detail) external onlyAdapterManager {
        require(_index < adapterDetails.length, "Invalid index number");
        adapterDetails[_index] = _detail;
    }

    receive() external payable {}
}
