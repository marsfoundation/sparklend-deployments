// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface Potlike {
    function drip() external;
    function file(bytes32 what, uint data) external;
}
