// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

import "../interfaces/IAdapter.sol";
import "../interfaces/IHedgepieAuthority.sol";

import "./HedgepieAccessControlled.sol";

contract HedgepieAdapterList is HedgepieAccessControlled {
    struct AdapterInfo {
        address addr;
        string name;
        address stakingToken;
        bool status;
    }

    // list of adapters
    AdapterInfo[] public adapterList;

    // existing status of adapters
    mapping(address => bool) public adapterExist;

    /// @dev events
    event AdapterAdded(address indexed adapter);
    event AdapterActivated(address indexed strategy);
    event AdapterDeactivated(address indexed strategy);

    /**
     * @notice Construct
     * @param _hedgepieAuthority HedgepieAuthority address
     */
    constructor(address _hedgepieAuthority)
        HedgepieAccessControlled(IHedgepieAuthority(_hedgepieAuthority))
    {}

    /// @dev modifier for active adapters
    modifier onlyActiveAdapter(address _adapter) {
        require(adapterExist[_adapter], "Error: Adapter is not active");
        _;
    }

    /**
     * @notice Get a list of adapters
     */
    function getAdapterList() external view returns (AdapterInfo[] memory) {
        return adapterList;
    }

    /**
     * @notice Get adapter infor
     * @param _adapterAddr address of adapter that need to get information
     */
    function getAdapterInfo(address _adapterAddr)
        external
        view
        returns (
            address adapterAddr,
            string memory name,
            address stakingToken,
            bool status
        )
    {
        for (uint256 i; i < adapterList.length; i++) {
            if (adapterList[i].addr == _adapterAddr && adapterList[i].status) {
                adapterAddr = adapterList[i].addr;
                name = adapterList[i].name;
                stakingToken = adapterList[i].stakingToken;
                status = adapterList[i].status;

                break;
            }
        }
    }

    /**
     * @notice Get strategy address of adapter contract
     * @param _adapter  adapter address
     */
    function getAdapterStrat(address _adapter)
        external
        view
        onlyActiveAdapter(_adapter)
        returns (address adapterStrat)
    {
        adapterStrat = IAdapter(_adapter).strategy();
    }

    // ===== AdapterManager functions =====
    /**
     * @notice Add adapter
     * @param _adapter  adapter address
     */
    /// #if_succeeds {:msg "Adapter not set correctly"} adapterList.length == old(adapterInfo.length) + 1;
    function addAdapter(address _adapter) external onlyAdapterManager {
        require(!adapterExist[_adapter], "Already added");
        require(_adapter != address(0), "Invalid adapter address");

        adapterList.push(
            AdapterInfo({
                addr: _adapter,
                name: IAdapter(_adapter).name(),
                stakingToken: IAdapter(_adapter).stakingToken(),
                status: true
            })
        );
        adapterExist[_adapter] = true;

        emit AdapterAdded(_adapter);
    }

    /**
     * @notice Remove adapter
     * @param _adapterId  adapter id
     * @param _status  adapter status
     */
    /// #if_succeeds {:msg "Status not updated"} adapterList[_adapterId].status == _status;
    function setAdapter(uint256 _adapterId, bool _status)
        external
        onlyAdapterManager
    {
        require(_adapterId < adapterList.length, "Invalid adapter address");
        adapterList[_adapterId].status = _status;

        if (_status) emit AdapterActivated(adapterList[_adapterId].addr);
        else emit AdapterDeactivated(adapterList[_adapterId].addr);
    }
}
