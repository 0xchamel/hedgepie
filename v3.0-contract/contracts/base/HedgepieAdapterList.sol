// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

import "../interfaces/IAdapter.sol";
import "../interfaces/IHedgepieAuthority.sol";

import "./HedgepieAccessControlled.sol";

contract HedgepieAdapterList is HedgepieAccessControlled {
    struct AdapterInfo {
        address addr; // adapter address
        string name; // adapter name
        address stakingToken; // staking token of adapter
        bool status; // adapter contract status true: active, false: inactive
    }

    // list of adapters
    AdapterInfo[] public adapterList;

    // existing status of adapters
    mapping(address => bool) public adapterActive;

    // lock status of adapters
    mapping(address => bool) public locked;

    /// @dev events
    event AdapterAdded(address indexed adapter);
    event AdapterActivated(address indexed strategy);
    event AdapterDeactivated(address indexed strategy);
    event AdapterLocked(address indexed adapter);
    event AdapterUnlocked(address indexed adapter);

    /**
     * @notice initialize
     * @param _hedgepieAuthority HedgepieAuthority address
     */
    function initialize(address _hedgepieAuthority) external initializer {
        __HedgepieAccessControlled_init(IHedgepieAuthority(_hedgepieAuthority));
    }

    /// @dev modifier for active adapters
    modifier onlyActiveAdapter(address _adapter) {
        require(adapterActive[_adapter], "Error: Adapter is not active");
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
    function getAdapterInfo(
        address _adapterAddr
    ) external view returns (address adapterAddr, string memory name, address stakingToken, bool status) {
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
    function getAdapterStrat(
        address _adapter
    ) external view onlyActiveAdapter(_adapter) returns (address adapterStrat) {
        adapterStrat = IAdapter(_adapter).strategy();
    }

    // ===== AdapterManager functions =====
    /**
     * @notice Add adapters
     * @param _adapters  array of adapter address
     */
    /// #if_succeeds {:msg "addAdapters failed"} _adapters.length > 0 ? (adapterList.length == old(adapterList.length) + _adapters.length && adapterActive[_adapters[_adapters.length - 1]] == true) : true;
    function addAdapters(address[] memory _adapters) external onlyAdapterManager {
        for (uint256 i = 0; i < _adapters.length; i++) {
            require(!adapterActive[_adapters[i]], "Already added");
            require(_adapters[i] != address(0), "Invalid adapter address");

            adapterList.push(
                AdapterInfo({
                    addr: _adapters[i],
                    name: IAdapter(_adapters[i]).name(),
                    stakingToken: IAdapter(_adapters[i]).stakingToken(),
                    status: true
                })
            );
            adapterActive[_adapters[i]] = true;

            emit AdapterAdded(_adapters[i]);
        }
    }

    /**
     * @notice Remove adapter
     * @param _adapterId  array of adapter id
     * @param _status  array of adapter status
     */
    /// #if_succeeds {:msg "setAdapters failed"} _status.length > 0 ? (adapterList[_adapterId[_status.length - 1]].status == _status[_status.length - 1]) : true;
    function setAdapters(uint256[] memory _adapterId, bool[] memory _status) external onlyAdapterManager {
        require(_adapterId.length == _status.length, "Invalid array length");

        for (uint256 i = 0; i < _adapterId.length; i++) {
            require(_adapterId[i] < adapterList.length, "Invalid adapter address");

            if (adapterList[_adapterId[i]].status != _status[i]) {
                adapterList[_adapterId[i]].status = _status[i];

                if (_status[i]) emit AdapterActivated(adapterList[_adapterId[i]].addr);
                else emit AdapterDeactivated(adapterList[_adapterId[i]].addr);
            }
        }
    }

    /**
     * @notice Set locked status to adapter
     * @param _adapterId  array of adapter id
     * @param _status  locked status
     */
    /// #if_succeeds {:msg "setAdapters failed"} _status.length > 0 ? (adapterList[_adapterId[_status.length - 1]].status == _status[_status.length - 1]) : true;
    function setLocked(uint256[] memory _adapterId, bool[] memory _status) external onlyAdapterManager {
        require(_adapterId.length == _status.length, "Invalid array length");

        for (uint256 i = 0; i < _adapterId.length; i++) {
            require(_adapterId[i] < adapterList.length, "Invalid adapter address");

            locked[adapterList[_adapterId[i]].addr] = _status[i];

            if (_status[i]) emit AdapterLocked(adapterList[_adapterId[i]].addr);
            else emit AdapterUnlocked(adapterList[_adapterId[i]].addr);
        }
    }
}
