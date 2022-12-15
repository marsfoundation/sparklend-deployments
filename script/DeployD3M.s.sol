// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.10;

import "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {IERC20Detailed} from 'aave-v3-core/contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol';
import {Strings} from 'aave-v3-core/contracts/dependencies/openzeppelin/contracts/Strings.sol';
import {IERC20} from 'aave-v3-core/contracts/dependencies/openzeppelin/contracts/IERC20.sol';

import {D3MHub} from 'dss-direct-deposit/D3MHub.sol';
import {D3MAavePlan} from 'dss-direct-deposit/plans/D3MAavePlan.sol';
import {D3MAavePool} from 'dss-direct-deposit/pools/D3MAavePool.sol';

contract DeployD3M is Script {

    using stdJson for string;

    string config;

    address lendingPool;
    D3MHub hub;
    bytes32 ilk;

    D3MAavePlan plan;
    D3MAavePool pool;

    // TODO these should not be hard coded
    IERC20 dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    function readInput(string memory input) internal view returns (string memory) {
        string memory root = vm.projectRoot();
        string memory chainInputFolder = string(string.concat(bytes("/script/input/"), bytes(vm.toString(block.chainid)), bytes("/")));
        return vm.readFile(string(string.concat(bytes(root), bytes(chainInputFolder), string.concat(bytes(input), bytes(".json")))));
    }

    function stringToBytes32(string memory source) public pure returns (bytes32 result) {
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
            return 0x0;
        }

        assembly {
            result := mload(add(source, 32))
        }
    }

    function run() external {
        config = readInput("config");

        lendingPool = vm.envAddress("LENDING_POOL");
        hub = D3MHub(config.readAddress(".d3m.hub"));
        ilk = stringToBytes32(config.readString(".d3m.ilk"));

        vm.startBroadcast();
        address admin = msg.sender;

        plan = new D3MAavePlan(address(dai), lendingPool);
        if (plan.wards(admin) != 1) {
            plan.rely(admin);
            plan.deny(msg.sender);
        }
        pool = new D3MAavePool(ilk, address(hub), address(dai), lendingPool);
        if (plan.wards(admin) != 1) {
            plan.rely(admin);
            plan.deny(msg.sender);
        }
        vm.stopBroadcast();

        console.log(string(abi.encodePacked("D3M_PLAN=", Strings.toHexString(uint256(uint160(address(plan))), 20))));
        console.log(string(abi.encodePacked("D3M_POOL=", Strings.toHexString(uint256(uint160(address(pool))), 20))));
    }

}
