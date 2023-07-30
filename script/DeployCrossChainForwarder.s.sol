// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

import "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {ScriptTools} from "dss-test/ScriptTools.sol";

import { CrosschainForwarderOptimism } from "../src/crosschainforwarders/CrosschainForwarderOptimism.sol";
import { CrosschainForwarderArbitrum } from "../src/crosschainforwarders/CrosschainForwarderArbitrum.sol";

contract DeployCrossChainForwarder is Script {

    using stdJson for string;
    using ScriptTools for string;

    string instanceId;
    string config;
    string forwarderType;

    address forwarder;

    function run() external {
        //vm.createSelectFork(vm.envString("ETH_RPC_URL"));     // Multi-chain not supported in Foundry yet (use CLI arg for now)
        vm.setEnv("FOUNDRY_ROOT_CHAINID", vm.toString(block.chainid));

        instanceId = vm.envString("FOUNDRY_SCRIPT_CONFIG");
        config = ScriptTools.loadConfig(instanceId);
        forwarderType = config.readString(".type");

        vm.startBroadcast();
        
        if (forwarderType.eq("optimism")) {
            forwarder = address(new CrosschainForwarderOptimism(
                config.readAddress(".executor")
            ));
        } else if (forwarderType.eq("arbitrum")) {
            forwarder = address(new CrosschainForwarderArbitrum(
                config.readAddress(".executor")
            ));
        } else {
            revert("Unknown forwarder type");
        }
        
        vm.stopBroadcast();

        ScriptTools.exportContract(instanceId, "forwarder", address(forwarder));
    }

}
