// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "../SparkDeployBase.t.sol";

// A forked mainnet on Tenderly to test
contract SparkDeploy_ExampleFork is SparkDeployBase {

    function setupFork() internal override {
        vm.createSelectFork("https://rpc.tenderly.co/fork/a05f0dea-a373-4caf-8cd9-fde3cbb6fcf1", 17456647);
    }

    function getInstanceId() internal override pure returns (string memory) {
        return "example";
    }

}
