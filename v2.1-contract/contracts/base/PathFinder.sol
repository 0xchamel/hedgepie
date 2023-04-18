// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

import "./HedgepieAccessControlled.sol";
import "../interfaces/IHedgepieAuthority.sol";
import "../interfaces/IPancakeFactory.sol";
import "../interfaces/IPancakeRouter.sol";

contract PathFinder is HedgepieAccessControlled {
    // router information
    mapping(address => bool) public routers;

    // router => inToken => outToken => path
    mapping(address => mapping(address => mapping(address => address[]))) public paths;

    /// @dev events
    event RouterAdded(address indexed router, bool status);
    event RouterRemoved(address indexed router, bool status);

    /**
     * @notice Construct
     * @param _hedgepieAuthority HedgepieAuthority address
     */
    constructor(address _hedgepieAuthority) HedgepieAccessControlled(IHedgepieAuthority(_hedgepieAuthority)) {}

    /**
     * @notice Set swap router
     * @param _router swap router address
     * @param _status router status flag
     */
    function setRouter(address _router, bool _status) external onlyPathManager {
        require(_router != address(0), "Invalid router address");
        routers[_router] = _status;

        if (_status) emit RouterAdded(_router, _status);
        else emit RouterRemoved(_router, _status);
    }

    /**
     * @notice Get path
     * @param _router router address
     * @param _inToken token address of inToken
     * @param _outToken token address of outToken
     */
    function getPaths(address _router, address _inToken, address _outToken) public view returns (address[] memory) {
        require(paths[_router][_inToken][_outToken].length > 1, "Path not existing");

        return paths[_router][_inToken][_outToken];
    }

    /**
     * @notice Set path from inToken to outToken
     * @param _router swap router address
     * @param _inToken token address of inToken
     * @param _outToken token address of outToken
     * @param _path swapping path
     */
    function setPath(
        address _router,
        address _inToken,
        address _outToken,
        address[] memory _path
    ) external onlyPathManager {
        require(routers[_router], "Router not registered");
        require(_path.length > 1, "Invalid path length");
        require(_inToken == _path[0], "Invalid inToken address");
        require(_outToken == _path[_path.length - 1], "Invalid inToken address");

        IPancakeFactory factory = IPancakeFactory(IPancakeRouter(_router).factory());
        address[] storage cPath = paths[_router][_inToken][_outToken];

        uint8 i;
        for (i; i < _path.length; i++) {
            // check if new path is valid
            if (i < _path.length - 1) require(factory.getPair(_path[i], _path[i + 1]) != address(0), "Invalid path");

            // update current path if new path is valid
            if (i < cPath.length) cPath[i] = _path[i];
            else cPath.push(_path[i]);
        }

        // remove deprecated path token info after new path is updated
        if (cPath.length > _path.length) {
            for (i = 0; i < cPath.length - _path.length; i++) cPath.pop();
        }
    }
}
