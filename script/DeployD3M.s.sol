// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.10;

import "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {IERC20Detailed} from 'aave-v3-core/contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol';
import {Strings} from 'aave-v3-core/contracts/dependencies/openzeppelin/contracts/Strings.sol';
import {IERC20} from 'aave-v3-core/contracts/dependencies/openzeppelin/contracts/IERC20.sol';

contract DeployD3M is Script {

    using stdJson for string;

    string config;

    function readInput(string memory input) internal view returns (string memory) {
        string memory root = vm.projectRoot();
        string memory chainInputFolder = string(string.concat(bytes("/script/input/"), bytes(vm.toString(block.chainid)), bytes("/")));
        return vm.readFile(string(string.concat(bytes(root), bytes(chainInputFolder), string.concat(bytes(input), bytes(".json")))));
    }

    function run() external {
        config = readInput("config");

        vm.startBroadcast();
        address admin = msg.sender;

        
        vm.stopBroadcast();

        console.log(string(abi.encodePacked("LENDING_POOL_ADDRESS_PROVIDER=", Strings.toHexString(uint256(uint160(address(poolAddressesProvider))), 20))));
    }

}
