// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "../../../SparkDeployPoolImplementationBase.t.sol";

contract SparkDeploy_20230711_GoerliPrimary_PoolImplementationV302Test is SparkDeployPoolImplementationBaseTest {
    
    constructor() {
        rpcUrl      = getChain("goerli").rpcUrl;
        //forkBlock   = 9211177;
        instanceId  = "primary";
        revisionNum = 2;
    }

}
