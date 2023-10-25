// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

contract RateSourceMock {

    uint256 public rate;

    constructor(uint256 _rate) {
        rate = _rate;
    }

    function setRate(uint256 _rate) external {
        rate = _rate;
    }

    function getAPR() external view returns (uint256) {
        return rate;
    }

}