// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "../../../SparkDeployPoolImplementationBase.t.sol";

contract SparkDeploy_20240110_EthereumPrimary_PoolImplementationV302Jan10PatchTest is SparkDeployPoolImplementationBaseTest {
    
    constructor() {
        rpcUrl      = getChain("mainnet").rpcUrl;
        forkBlock   = 18980488;
        instanceId  = "primary";
        revisionNum = 3;
    }

}
