// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "../SparkDeployBase.t.sol";

contract SparkDeploy_GoerliPrimaryTest is SparkDeployBaseTest {
    constructor() {
        rpcUrl     = getChain("goerli").rpcUrl;
        forkBlock  = 8612863;
        instanceId = "primary";

        initialReserveCount = 6;
    }

}
