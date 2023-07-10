// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "../SparkDeployPoolImplementationBase.t.sol";

contract SparkDeployPoolImplementation_GoerliPrimaryV302Test is SparkDeployPoolImplementationBaseTest {
    
    constructor() {
        rpcUrl     = getChain("goerli").rpcUrl;
        forkBlock  = 9211177;
        instanceId = "primary";
    }

}
