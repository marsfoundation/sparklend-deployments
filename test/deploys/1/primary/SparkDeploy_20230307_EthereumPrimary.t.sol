// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "../../../SparkDeployBase.t.sol";

contract SparkDeploy_20230307_EthereumPrimaryTest is SparkDeployBaseTest {
    
    constructor() {
        rpcUrl     = getChain("mainnet").rpcUrl;
        forkBlock  = 16776533;
        instanceId = "primary";

        initialReserveCount = 6;
    }

}
