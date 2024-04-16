// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {ScriptTools} from "dss-test/ScriptTools.sol";

import {PoolAddressesProvider} from "sparklend-v1-core/contracts/protocol/configuration/PoolAddressesProvider.sol";
import {Pool} from "sparklend-v1-core/contracts/protocol/pool/Pool.sol";

abstract contract SparkDeployPoolImplementationBaseTest is Test {

    using stdJson for string;

    // Configuration
    // Override this in the inheriting contract
    string  instanceId = "primary";
    string  rpcUrl;
    uint256 forkBlock;
    uint256 revisionNum;

    string deployedContracts;
    string upgradeContracts;

    PoolAddressesProvider poolAddressesProvider;
    Pool poolImpl;

    function setUp() public {
        if (forkBlock > 0) vm.createSelectFork(rpcUrl, forkBlock);
        else vm.createSelectFork(rpcUrl);
        vm.setEnv("FOUNDRY_ROOT_CHAINID", vm.toString(block.chainid));

        deployedContracts = ScriptTools.readOutput(instanceId);
        upgradeContracts  = ScriptTools.readOutput(string(abi.encodePacked(instanceId, "-pool")));

        poolAddressesProvider = PoolAddressesProvider(deployedContracts.readAddress(".poolAddressesProvider"));
        poolImpl              = Pool(upgradeContracts.readAddress(".poolImpl"));
    }

    function test_poolImpl() public {
        assertEq(address(poolImpl.ADDRESSES_PROVIDER()), address(poolAddressesProvider));
        assertEq(poolImpl.POOL_REVISION(),               revisionNum);

        vm.expectRevert("Contract instance has already been initialized");
        poolImpl.initialize(poolAddressesProvider);
    }

}
