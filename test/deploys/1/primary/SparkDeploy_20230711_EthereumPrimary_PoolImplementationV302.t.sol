// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "../../../SparkDeployPoolImplementationBase.t.sol";

contract SparkDeploy_20230711_EthereumPrimary_PoolImplementationV302Test is SparkDeployPoolImplementationBaseTest {
    
    constructor() {
        rpcUrl      = getChain("mainnet").rpcUrl;
        forkBlock   = 17689592;
        instanceId  = "primary";
        revisionNum = 2;
    }

}
