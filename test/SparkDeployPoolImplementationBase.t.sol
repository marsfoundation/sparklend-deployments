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

    function test_poolImpl() public {
        assertEq(address(poolImpl.ADDRESSES_PROVIDER()), address(poolAddressesProvider));

        vm.expectRevert("Contract instance has already been initialized");
        poolImpl.initialize(poolAddressesProvider);
    }

    function test_poolImpl_bytecode_match() public {
        if (!vm.envOr("BYTECODE_CHECK", false)) return;

        /*_compareBytecode(
            address(poolImpl),
            address(new Pool(poolAddressesProvider)),
            "poolImpl"
        );*/
        _checkLibrary("BorrowLogic");
        _checkLibrary("BridgeLogic");
        _checkLibrary("EModeLogic");
        // FIXME - below here all seems to be broken
        //_checkLibrary("FlashLoanLogic");
        //_checkLibrary("LiquidationLogic");
        //_checkLibrary("PoolLogic");
        //_checkLibrary("SupplyLogic");
    }

    function _checkLibrary(string memory libName) internal {
        _compareBytecodeLibrary(
            address(upgradeContracts.readAddress(string(abi.encodePacked(".", libName)))),
            deployCode(string(abi.encodePacked(libName, ".sol"))),
            libName
        );
    }

    function _compareBytecodeLibrary(address actual, address expected, string memory err) internal {
        bytes memory actualCode = actual.code;
        bytes memory expectedCode = expected.code;
        bytes20 actualB = bytes20(actual);

        // Libraries insert their own address into the runtime code -- correct for this
        for (uint256 i = 0; i < 20; i++) {
            expectedCode[i + 1] = actualB[i];
        }

        assertEq(actualCode.length, expectedCode.length, err);

        // TODO - verify it is okay to ignore these last two words
        uint256 l = actualCode.length;
        uint256 ms = l - 64;
        uint256 me = ms + 64;
        for (uint256 i = 0; i < actualCode.length; i++) {
            if (i >= ms && i < me) continue; // skip the metadata
            assertEq(actualCode[i], expectedCode[i], err);
        }
    }

    function _compareBytecode(address actual, address expected, string memory err) internal {
        uint256 expectedBytecodeSize;
        uint256 actualBytecodeSize;
        assembly {
            expectedBytecodeSize := extcodesize(expected)
            actualBytecodeSize   := extcodesize(actual)
        }

        uint256 metadataLength = _getBytecodeMetadataLength(expected);
        assertTrue(metadataLength <= expectedBytecodeSize, err);
        expectedBytecodeSize -= metadataLength;

        metadataLength = _getBytecodeMetadataLength(actual);
        assertTrue(metadataLength <= actualBytecodeSize, err);
        actualBytecodeSize -= metadataLength;

        assertEq(actualBytecodeSize, expectedBytecodeSize, err);
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
        assertEq(actualHash, expectedHash, err);
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

}
