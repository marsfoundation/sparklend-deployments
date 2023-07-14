// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "../../../SparkDeployBase.t.sol";

contract SparkDeploy_20230714_GnosisPrimaryTest is SparkDeployBaseTest {
    constructor() {
        rpcUrl     = getChain("gnosis_chain").rpcUrl;
        forkBlock  = 28941997;
        instanceId = "primary";
    }

}
