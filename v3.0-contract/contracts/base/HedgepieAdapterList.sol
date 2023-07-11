// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

import "../interfaces/IAdapter.sol";
import "../interfaces/IHedgepieAuthority.sol";

import "./HedgepieAccessControlled.sol";

contract HedgepieAdapterList is HedgepieAccessControlled {
    enum AdapterStatus {
        ACTIVE,
        INACTIVE,
        LOCKED
    }

    struct AdapterInfo {
        string[] names; // adapter names
        address[] strategies; // strategy addresses
        uint256[] pids; // pool ids of stratgy
        bool[] types; // types of pid or strategy adapter
        AdapterStatus[] status; // 0: active, 1: inactive, 2: locked
    }

    // list of adapter addresses
    address[] public list;

    // mapping for adapter info
    mapping(address => AdapterInfo) public infos;

    // existing status of adapters
    mapping(address => bool) public added;

    // lock status of adapters
    mapping(address => bool) public locked;

    /// @dev events
    event AdapterAdded(address indexed adapter);
    event AdapterActivated(address indexed strategy);
    event AdapterDeactivated(address indexed strategy);
    event AdapterLocked(address indexed adapter, uint256 index);
    event AdapterUnlocked(address indexed adapter, uint256 index);

    /**
     * @notice initialize
     * @param _hedgepieAuthority HedgepieAuthority address
     */
    function initialize(address _hedgepieAuthority) external initializer {
        __HedgepieAccessControlled_init(IHedgepieAuthority(_hedgepieAuthority));
    }

    /// @dev modifier for active adapters
    modifier onlyActiveAdapter(address _adapter) {
        require(added[_adapter], "Error: Adapter is not active");
        _;
    }

    /**
     * @notice Get a list of adapters
     */
    function getAdapterList() external view returns (address[] memory) {
        return list;
    }

    /**
     * @notice Get adapter infor
     * @param _adapterAddr adapter address
     */
    function getAdapterInfo(
        address _adapterAddr
    ) external view onlyActiveAdapter(_adapterAddr) returns (AdapterInfo memory) {
        return infos[_adapterAddr];
    }

    /**
     * @notice Get strategy address of adapter contract
     * @param _adapterAddr  adapter address
     */
    function getAdapterStrat(
        address _adapterAddr
    ) external view onlyActiveAdapter(_adapterAddr) returns (address[] strategies) {
        return infos[_adapterAddr].strategies;
    }

    // ===== AdapterManager functions =====
    /**
     * @notice Add adapters
     * @param _adapters  array of adapter address
     */
    /// #if_succeeds {:msg "addAdapters failed"} _adapters.length > 0 ? (adapterList.length == old(adapterList.length) + _adapters.length && adapterActive[_adapters[_adapters.length - 1]] == true) : true;
    function addAdapters(address[] memory _adapters) external onlyAdapterManager {
        for (uint256 i = 0; i < _adapters.length; i++) {
            require(!added[_adapters[i]], "Already added");
            require(_adapters[i] != address(0), "Invalid adapter address");

            list.push(_adapters[i]);
            added[_adapters[i]] = true;

            emit AdapterAdded(_adapters[i]);
        }
    }

    /**
     * @notice Add information for adapter
     * @param _adapter  array of adapter address
     * @param _names  array of adapter name
     * @param _strategies  array of adapter strategy
     * @param _pids  array of adapter pool id
     * @param _types  array of adapter type
     * @param _status  array of adapter status
     */
    function addInfo(
        address _adapter,
        string[] memory _names,
        address[] memory _strategies,
        uint256[] _pids,
        bool[] memory _types,
        AdapterStatus[] memory _status
    ) external onlyActiveAdapter(_adapter) onlyAdapterManager {
        require(
            _names.length == _strategies.length &&
                _strategies.length == _pids.length &&
                _pids.length == _types.length &&
                _types.length == _status.length,
            "Invalid array length"
        );

        for (uint i; i < _names.length; ) {
            infos[_adapter].names.push(_names[i]);
            infos[_adapter].strategies.push(_strategies[i]);
            infos[_adapter].pids.push(_pids[i]);
            infos[_adapter].types.push(_types[i]);
            infos[_adapter].status.push(_status[i]);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Remove adapter
     * @param _adapter address of adapter
     * @param _index index of AdapterInfo
     * @param _name  adapter name
     * @param _strategy  adapter strategy
     * @param _pid  pool id
     * @param _type  adapter type
     * @param _status  adapter status
     */
    /// #if_succeeds {:msg "setAdapters failed"} _status.length > 0 ? (adapterList[_adapterId[_status.length - 1]].status == _status[_status.length - 1]) : true;
    function setAdapters(
        address _adapter,
        uint256 _index,
        string memory _name,
        address _strategy,
        uint256 _pid,
        bool _type,
        AdapterStatus memory _status
    ) external onlyActiveAdapter(_adapter) onlyAdapterManager {
        require(_index < infos[_adapter].names.length, "Invalid array length");

        infos[_adapter].names[_index] = _name;
        infos[_adapter].strategies[_index] = _strategy;
        infos[_adapter].pids[_index] = _pid;
        infos[_adapter].types[_index] = _type;
        infos[_adapter].status[_index] = _status;
    }

    /**
     * @notice Set locked status to adapter
     * @param _adapter address of adapter
     * @param _index index of AdapterInfo
     * @param _locked  locked status
     */
    /// #if_succeeds {:msg "setAdapters failed"} _status.length > 0 ? (adapterList[_adapterId[_status.length - 1]].status == _status[_status.length - 1]) : true;
    function setLocked(
        address _adapter,
        uint256 _index,
        AdapterStatus memory _locked
    ) external onlyActiveAdapter(_adapter) onlyAdapterManager {
        require(_index < infos[_adapter].names.length, "Invalid array length");

        infos[_adapter].status[_index] = _locked;

        if (_locked == AdapterStatus.LOCKED) emit AdapterLocked(_adapter, _index);
        else emit AdapterLocked(_adapter, _index);
    }
}
