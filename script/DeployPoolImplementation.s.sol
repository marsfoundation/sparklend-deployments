// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

import "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {ScriptTools} from "dss-test/ScriptTools.sol";

import {IPoolAddressesProvider} from "aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol";
import {Pool} from "aave-v3-core/contracts/protocol/pool/Pool.sol";

contract DeployPoolImplementation is Script {

    using stdJson for string;
    using ScriptTools for string;

    string deployedContracts;
    string instanceId;

    IPoolAddressesProvider poolAddressesProvider;
    Pool poolImpl;

    function run() external {
        //vm.createSelectFork(vm.envString("ETH_RPC_URL"));     // Multi-chain not supported in Foundry yet (use CLI arg for now)
        instanceId = vm.envOr("INSTANCE_ID", string("primary"));
        vm.setEnv("FOUNDRY_ROOT_CHAINID", vm.toString(block.chainid));
        
        deployedContracts = ScriptTools.readOutput(instanceId);

        vm.startBroadcast();
        poolAddressesProvider = IPoolAddressesProvider(deployedContracts.readAddress(".poolAddressesProvider"));
        poolImpl = new Pool(poolAddressesProvider);
        poolImpl.initialize(poolAddressesProvider);
        vm.stopBroadcast();

        ScriptTools.exportContract(string(abi.encodePacked(instanceId, "-pool")), "poolImpl", address(poolImpl));
    }

}
