// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "../../../SparkDeployPoolImplementationBase.t.sol";

contract SparkDeploy_20240110_GnosisPrimary_PoolImplementationV302Jan10PatchTest is SparkDeployPoolImplementationBaseTest {
    
    constructor() {
        rpcUrl      = getChain("gnosis_chain").rpcUrl;
        forkBlock   = 31885915;
        instanceId  = "primary";
        revisionNum = 2;
    }

}
