// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "../../../SparkDeployPoolImplementationBase.t.sol";

contract SparkDeploy_20240408_GnosisPrimary_PoolImplementationTest is SparkDeployPoolImplementationBaseTest {
    
    constructor() {
        rpcUrl      = getChain("gnosis_chain").rpcUrl;
        forkBlock   = 33350836;  // April 9, 2024
        instanceId  = "primary";
        revisionNum = 3;
    }

}
