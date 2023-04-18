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

    // LP pool id - should be 0 when stakingToken is not LP
    uint256 public pid;

    // staking token
    address public stakingToken;

    // first reward token
    address public rewardToken1;

    // second reward token - optional
    address public rewardToken2;

    // repay token which we will receive after deposit - optional
    address public repayToken;

    // strategy where we deposit staking token
    address public strategy;

    // router address for LP token
    address public router;

    // swap router address for ERC20 token swap
    address public swapRouter;

    // wbnb address
    address public wbnb;

    // adapter name
    string public name;

    // adapter info having totalStaked and 1st, 2nd share info
    AdapterInfo public mAdapter;

    // adapter info for each nft
    // nft id => UserAdapterInfo
    mapping(uint256 => UserAdapterInfo) public userAdapterInfos;

    /** @notice Constructor
     * @param _hedgepieAuthority  address of authority
     */
    constructor(address _hedgepieAuthority) HedgepieAccessControlled(IHedgepieAuthority(_hedgepieAuthority)) {}

    /** @notice get user staked amount */
    function getUserAmount(uint256 _tokenId) external view returns (uint256 amount) {
        return userAdapterInfos[_tokenId].amount;
    }

    /**
     * @notice deposit to strategy
     * @param _tokenId YBNFT token id
     */
    function deposit(uint256 _tokenId) external payable virtual returns (uint256 amountOut) {}

    /**
     * @notice withdraw from strategy
     * @param _tokenId YBNFT token id
     * @param _amount amount of staking tokens to withdraw
     */
    function withdraw(uint256 _tokenId, uint256 _amount) external payable virtual returns (uint256 amountOut) {}

    /**
     * @notice claim reward from strategy
     * @param _tokenId YBNFT token id
     */
    function claim(uint256 _tokenId) external payable virtual returns (uint256 amountOut) {}

    /**
     * @notice Remove funds
     * @param _tokenId YBNFT token id
     */
    function removeFunds(uint256 _tokenId) external payable virtual returns (uint256 amountOut) {}

    /**
     * @notice Update funds
     * @param _tokenId YBNFT token id
     */
    function updateFunds(uint256 _tokenId) external payable virtual returns (uint256 amountOut) {}

    /**
     * @notice Get pending token reward
     * @param _tokenId YBNFT token id
     */
    function pendingReward(uint256 _tokenId) external view virtual returns (uint256 reward, uint256 withdrawable) {}

    /**
     * @notice Charge Fee and send BNB to investor
     * @param _tokenId YBNFT token id
     */
    function _chargeFeeAndSendToInvestor(uint256 _tokenId, uint256 _amount, uint256 _reward) internal {
        bool success;
        if (_reward != 0) {
            _reward = (_reward * IYBNFT(authority.hYBNFT()).performanceFee(_tokenId)) / 1e4;
            (success, ) = payable(IHedgepieInvestor(authority.hInvestor()).treasury()).call{value: _reward}("");
            require(success, "Failed to send bnb to Treasury");
        }

        (success, ) = payable(msg.sender).call{value: _amount - _reward}("");
        require(success, "Failed to send bnb");
    }

    receive() external payable {}
}
