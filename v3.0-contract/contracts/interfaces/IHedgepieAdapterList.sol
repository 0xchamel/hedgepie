// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

interface IHedgepieAdapterList {
    function getAdapterStrat(address _adapter) external view returns (address adapterStrat);

    function getAdapterInfo(
        address _adapter,
        uint256 _index
    ) external view returns (address, string memory, uint256, address, bool, uint8);

    function investor() external view returns (address);

    function adapterActive(address _adapter) external view returns (bool);

    function locked(address _adapter, uint256 _index) external view returns (bool);
}
