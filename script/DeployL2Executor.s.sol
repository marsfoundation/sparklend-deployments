// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

import "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {ScriptTools} from "dss-test/ScriptTools.sol";

import { OptimismBridgeExecutor } from "governance-crosschain-bridges/contracts/bridges/OptimismBridgeExecutor.sol";
import { ArbitrumBridgeExecutor } from "governance-crosschain-bridges/contracts/bridges/ArbitrumBridgeExecutor.sol";

contract DeployL2Executor is Script {

    using stdJson for string;
    using ScriptTools for string;

    string config;
    string executorType;

    address executor;

    function run() external {
        //vm.createSelectFork(vm.envString("ETH_RPC_URL"));     // Multi-chain not supported in Foundry yet (use CLI arg for now)
        vm.setEnv("FOUNDRY_ROOT_CHAINID", vm.toString(block.chainid));

        config = ScriptTools.loadConfig("executor");
        executorType = config.readString(".type");

        vm.startBroadcast();
        
        if (executorType.eq("optimism")) {
            executor = address(new OptimismBridgeExecutor(
                config.readAddress(".crossDomainMessenger"),
                config.readAddress(".hostAdmin"),
                config.readUint(".delay"),
                config.readUint(".gracePeriod"),
                config.readUint(".minimumDelay"),
                config.readUint(".maximumDelay"),
                config.readAddress(".guardian")
            ));
        } else if (executorType.eq("arbitrum")) {
            executor = address(new ArbitrumBridgeExecutor(
                config.readAddress(".hostAdmin"),
                config.readUint(".delay"),
                config.readUint(".gracePeriod"),
                config.readUint(".minimumDelay"),
                config.readUint(".maximumDelay"),
                config.readAddress(".guardian")
            ));
        } else {
            revert("Unknown executor type");
        }
        
        vm.stopBroadcast();

        ScriptTools.exportContract("executor", "executor", address(executor));
    }

}
