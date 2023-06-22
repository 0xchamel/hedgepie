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
        bool isEnabled; // adapter contract status
    }

    // list of adapters
    AdapterInfo[] public adapterList;

    // existing status of adapters
    mapping(address => bool) public adapterActive;

    /// @dev events
    event AdapterAdded(address indexed adapter);
    event AdapterActivated(address indexed strategy);
    event AdapterDeactivated(address indexed strategy);

    /**
     * @notice Construct
     * @param _hedgepieAuthority HedgepieAuthority address
     */
    constructor(address _hedgepieAuthority) HedgepieAccessControlled(IHedgepieAuthority(_hedgepieAuthority)) {}

    /// @dev modifier for active adapters
    modifier onlyActiveAdapter(address _adapter) {
        require(adapterActive[_adapter], "Error: Adapter is not active");
        _;
    }

    /**
     * @notice Get a list of active adapters
     */
    function getAdapterList() external view returns (AdapterInfo[] memory activeAdapters) {
        activeAdapters = new AdapterInfo[](adapterList.length);

        uint256 adaterCnt;
        for (uint256 i; i < adapterList.length; ++i) {
            if (!adapterList[i].isEnabled) continue;

            activeAdapters[adaterCnt] = adapterList[i];
            ++adaterCnt;
        }
    }

    /**
     * @notice Get a list of deactivated adapters
     */
    function getDeactiveList() external view returns (AdapterInfo[] memory deactiveAdapters) {
        deactiveAdapters = new AdapterInfo[](adapterList.length);

        uint256 adaterCnt;
        for (uint256 i; i < adapterList.length; ++i) {
            if (adapterList[i].isEnabled) continue;

            deactiveAdapters[adaterCnt] = adapterList[i];
            ++adaterCnt;
        }
    }

    /**
     * @notice Get adapter infor
     * @param _adapterAddr address of adapter that need to get information
     */
    function getAdapterInfo(
        address _adapterAddr
    ) external view returns (address adapterAddr, string memory name, address stakingToken, bool isEnabled) {
        for (uint256 i; i < adapterList.length; i++) {
            if (adapterList[i].addr == _adapterAddr && adapterList[i].isEnabled) {
                adapterAddr = adapterList[i].addr;
                name = adapterList[i].name;
                stakingToken = adapterList[i].stakingToken;
                isEnabled = adapterList[i].isEnabled;

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
    function addAdapters(address[] calldata _adapters) external onlyAdapterManager {
        for (uint256 i = 0; i < _adapters.length; i++) {
            require(!adapterActive[_adapters[i]], "Already added");
            require(_adapters[i] != address(0), "Invalid adapter address");

            adapterList.push(
                AdapterInfo({
                    addr: _adapters[i],
                    name: IAdapter(_adapters[i]).name(),
                    stakingToken: IAdapter(_adapters[i]).stakingToken(),
                    isEnabled: true
                })
            );
            adapterActive[_adapters[i]] = true;

            emit AdapterAdded(_adapters[i]);
        }
    }

    /**
     * @notice Remove adapter
     * @param _adapterId  array of adapter id
     * @param _isEnabled  array of adapter activeness
     */
    /// #if_succeeds {:msg "setAdapters failed"} _isEnabled.length > 0 ? (adapterList[_adapterId[_isEnabled.length - 1]]._isEnabled == _isEnabled[_isEnabled.length - 1]) : true;
    function setAdapters(uint256[] calldata _adapterId, bool[] calldata _isEnabled) external onlyAdapterManager {
        require(_adapterId.length == _isEnabled.length, "Invalid array length");

        for (uint256 i = 0; i < _adapterId.length; i++) {
            require(_adapterId[i] < adapterList.length, "Invalid adapter address");

            if (adapterList[_adapterId[i]].isEnabled != _isEnabled[i]) {
                adapterList[_adapterId[i]].isEnabled = _isEnabled[i];

                if (_isEnabled[i]) emit AdapterActivated(adapterList[_adapterId[i]].addr);
                else emit AdapterDeactivated(adapterList[_adapterId[i]].addr);
            }
        }
    }
}
