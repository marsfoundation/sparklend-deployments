// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {ScriptTools} from "dss-test/ScriptTools.sol";

import {PoolAddressesProvider} from "aave-v3-core/contracts/protocol/configuration/PoolAddressesProvider.sol";
import {Pool} from "aave-v3-core/contracts/protocol/pool/Pool.sol";

abstract contract SparkDeployPoolImplementationBaseTest is Test {

    using stdJson for string;

    // Configuration
    // Override this in the inheriting contract
    string  instanceId = "primary";
    string  rpcUrl;
    uint256 forkBlock;

    string config;
    string deployedContracts;
    string upgradeContracts;

    PoolAddressesProvider poolAddressesProvider;
    Pool poolImpl;

    function setUp() public {
        if (forkBlock > 0) vm.createSelectFork(rpcUrl, forkBlock);
        else vm.createSelectFork(rpcUrl);
        vm.setEnv("FOUNDRY_ROOT_CHAINID", vm.toString(block.chainid));

        config            = ScriptTools.readInput(instanceId);
        deployedContracts = ScriptTools.readOutput(instanceId);
        upgradeContracts  = ScriptTools.readOutput(string(abi.encodePacked(instanceId, "-pool")));

        poolAddressesProvider = PoolAddressesProvider(deployedContracts.readAddress(".poolAddressesProvider"));
        poolImpl              = Pool(upgradeContracts.readAddress(".poolImpl"));
    }

    function _getBytecodeMetadataLength(address a) internal view returns (uint256 length) {
        // The Solidity compiler encodes the metadata length in the last two bytes of the contract bytecode.
        assembly {
            let ptr  := mload(0x40)
            let size := extcodesize(a)
            if iszero(lt(size, 2)) {
                extcodecopy(a, ptr, sub(size, 2), 2)
                length := mload(ptr)
                length := shr(240, length)
                length := add(length, 2)  // the two bytes used to specify the length are not counted in the length
            }
            // We'll return zero if the bytecode is shorter than two bytes.
        }
    }

    function test_poolImpl() public {
        assertEq(address(poolImpl.ADDRESSES_PROVIDER()), address(poolAddressesProvider));

        vm.expectRevert("Contract instance has already been initialized");
        poolImpl.initialize(poolAddressesProvider);
    }

    function test_poolImpl_bytecode_match() public {
        if (!vm.envOr("BYTECODE_CHECK", false)) return;

        address expected = address(new Pool(poolAddressesProvider));
        address actual   = address(poolImpl);
        uint256 expectedBytecodeSize;
        uint256 actualBytecodeSize;
        assembly {
            expectedBytecodeSize := extcodesize(expected)
            actualBytecodeSize   := extcodesize(actual)
        }

        uint256 metadataLength = _getBytecodeMetadataLength(expected);
        assertTrue(metadataLength <= expectedBytecodeSize);
        expectedBytecodeSize -= metadataLength;

        metadataLength = _getBytecodeMetadataLength(actual);
        assertTrue(metadataLength <= actualBytecodeSize);
        actualBytecodeSize -= metadataLength;

        assertEq(actualBytecodeSize, expectedBytecodeSize);
        uint256 size = actualBytecodeSize;
        uint256 expectedHash;
        uint256 actualHash;
        assembly {
            let ptr := mload(0x40)

            extcodecopy(expected, ptr, 0, size)
            expectedHash := keccak256(ptr, size)

            extcodecopy(actual, ptr, 0, size)
            actualHash := keccak256(ptr, size)
        }
        assertEq(actualHash, expectedHash);
    }

}
