// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "../SparkDeployBase.t.sol";

// THIS IS AN EXAMPLE
abstract contract SparkDeploy_EthereumMain is SparkDeployBase {

    function setupFork() internal override {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
    }

    function getMarketId() internal override pure returns (string memory) {
        return "test";
    }

}
