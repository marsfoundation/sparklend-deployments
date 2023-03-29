// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.10;

import "dss-test/DssTest.sol";
import {stdJson} from "forge-std/StdJson.sol";

import "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import { MCD, DssInstance } from "dss-test/MCD.sol";
import {ScriptTools} from "dss-test/ScriptTools.sol";

import {IERC20} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20.sol';
import {ICollector} from 'aave-v3-periphery/treasury/interfaces/ICollector.sol';
import {Pool} from "aave-v3-core/contracts/protocol/pool/Pool.sol";
import {InitializableAdminUpgradeabilityProxy} from 'aave-v3-core/contracts/dependencies/openzeppelin/upgradeability/InitializableAdminUpgradeabilityProxy.sol';

import {AToken} from "aave-v3-core/contracts/protocol/tokenization/AToken.sol";
import {StableDebtToken} from "aave-v3-core/contracts/protocol/tokenization/StableDebtToken.sol";
import {VariableDebtToken} from "aave-v3-core/contracts/protocol/tokenization/VariableDebtToken.sol";

import {DaiCollector} from "../DaiCollector.sol";

contract DaiCollectorIntegrationTest is DssTest {

    using stdJson for string;
    using MCD for *;
    using GodMode for *;

    string config;
    string deployedContracts;
    DssInstance dss;

    address admin;

    Pool pool;
    ICollector daiTreasury;
    ICollector treasury;

    DaiCollector implementation;

    function setUp() public {
        config = ScriptTools.readInput("config");
        deployedContracts = ScriptTools.readOutput("spark");
        dss = MCD.loadFromChainlog(config.readAddress(".chainlog"));

        admin = config.readAddress(".admin");

        pool = Pool(deployedContracts.readAddress(".pool"));
        daiTreasury = ICollector(deployedContracts.readAddress(".daiTreasury"));
        treasury = ICollector(deployedContracts.readAddress(".treasury"));

        implementation = new DaiCollector(
            pool,
            IERC20(address(dss.dai)),
            address(treasury)
        );
    }

    function test_constructor() public {
        assertEq(implementation.REVISION(), 2);
        assertEq(address(implementation.pool()), address(pool));
        assertEq(address(implementation.dai()), address(dss.dai));
        assertEq(implementation.targetCollector(), address(treasury));
    }

    function doUpgrade() internal {
        vm.prank(admin); InitializableAdminUpgradeabilityProxy(payable(address(daiTreasury))).upgradeTo(address(implementation));
    }

    function test_upgrade() public {
        assertEq(daiTreasury.REVISION(), 1);
        doUpgrade();
        assertEq(daiTreasury.REVISION(), 2);
    }

    function test_push() public {
        doUpgrade();
    }

}
