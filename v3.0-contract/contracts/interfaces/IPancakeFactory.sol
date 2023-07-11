// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

interface IPancakeFactory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}
