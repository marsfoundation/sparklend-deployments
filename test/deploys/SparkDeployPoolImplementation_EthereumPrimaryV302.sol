// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "../SparkDeployPoolImplementationBase.t.sol";

contract SparkDeployPoolImplementation_EthereumPrimaryV302Test is SparkDeployPoolImplementationBaseTest {
    constructor() {
        rpcUrl     = getChain("mainnet").rpcUrl;
        forkBlock  = 17570286;
        instanceId = "primary";
    }

}
