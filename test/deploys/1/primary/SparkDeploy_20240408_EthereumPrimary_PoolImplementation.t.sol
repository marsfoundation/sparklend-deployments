// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "../../../SparkDeployPoolImplementationBase.t.sol";

contract SparkDeploy_20240408_EthereumPrimary_PoolImplementationTest is SparkDeployPoolImplementationBaseTest {
    
    constructor() {
        rpcUrl      = getChain("mainnet").rpcUrl;
        forkBlock   = 19609506;
        instanceId  = "primary";
        revisionNum = 4;
    }

}
