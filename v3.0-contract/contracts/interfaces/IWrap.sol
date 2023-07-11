// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

interface IWrap {
    // get wrapper token
    function deposit(uint256 amount) external;

    // get native token
    function withdraw(uint256 share) external;

    function deposit() external payable;
}
