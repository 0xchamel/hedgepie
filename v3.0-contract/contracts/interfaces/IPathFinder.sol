// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

interface IPathFinder {
    /**
     * @notice Get Path
     * @param _router swap router address
     * @param _inToken input token address
     * @param _outToken output token address
     */
    function getPaths(address _router, address _inToken, address _outToken) external view returns (address[] memory);
}
