// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

import "./IWrap.sol";
import "../base/BaseAdapter.sol";

interface IAdapter {
    function stakingToken() external view returns (address);

    function repayToken() external view returns (address);

    function strategy() external view returns (address);

    function name() external view returns (string memory);

    function rewardToken1() external view returns (address);

    function rewardToken2() external view returns (address);

    function router() external view returns (address);

    function swapRouter() external view returns (address);

    function authority() external view returns (address);

    function userAdapterInfos(
        uint256 _tokenId,
        uint256 _index
    ) external view returns (BaseAdapter.UserAdapterInfo memory);

    function mAdapters(uint256 _index) external view returns (BaseAdapter.AdapterInfo memory);

    function adapterDetails(uint256 _index) external view returns (BaseAdapter.AdapterDetail memory);

    /**
     * @notice deposit to strategy
     * @param _tokenId YBNFT token id
     * @param _index index of strategies
     */
    function deposit(uint256 _tokenId, uint256 _index) external payable returns (uint256 amountOut);

    /**
     * @notice withdraw from strategy
     * @param _tokenId YBNFT token id
     * @param _index index of strategies
     * @param _amount amount of staking tokens to withdraw
     */
    function withdraw(uint256 _tokenId, uint256 _index, uint256 _amount) external payable returns (uint256 amountOut);

    /**
     * @notice claim reward from strategy
     * @param _tokenId YBNFT token id
     * @param _index index of strategies
     */
    function claim(uint256 _tokenId, uint256 _index) external payable returns (uint256 amountOut);

    /**
     * @notice Get pending token reward
     * @param _tokenId YBNFT token id
     * @param _index index of strategies
     */
    function pendingReward(
        uint256 _tokenId,
        uint256 _index
    ) external view returns (uint256 amountOut, uint256 withdrawable);

    /**
     * @notice Remove funds
     * @param _tokenId YBNFT token id
     * @param _index index of strategies
     */
    function removeFunds(uint256 _tokenId, uint256 _index) external payable returns (uint256 amount);

    /**
     * @notice Update funds
     * @param _tokenId YBNFT token id
     * @param _index index of strategies
     */
    function updateFunds(uint256 _tokenId, uint256 _index) external payable returns (uint256 amount);

    /**
     * @notice get user staked amount
     * @param _index index of strategies
     */
    function getUserAmount(uint256 _tokenId, uint256 _index) external view returns (uint256 amount);
}
