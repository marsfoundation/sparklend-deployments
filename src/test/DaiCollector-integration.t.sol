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
import {IAToken} from '@aave/core-v3/contracts/interfaces/IAToken.sol';
import {DataTypes} from '@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol';

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
    DaiCollector daiTreasury;
    ICollector treasury;

    DaiCollector implementation;

    function setUp() public {
        config = ScriptTools.readInput("config");
        deployedContracts = ScriptTools.readOutput("spark");
        dss = MCD.loadFromChainlog(config.readAddress(".chainlog"));

        admin = config.readAddress(".admin");

        pool = Pool(deployedContracts.readAddress(".pool"));
        daiTreasury = DaiCollector(deployedContracts.readAddress(".daiTreasury"));
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

        dss.dai.approve(address(pool), type(uint256).max);

        // Over-issue DAI liabilities to the daiTreasury
        uint256 assets = getTotalAssets(address(dss.dai));
        uint256 liabilities = getTotalLiabilities(address(dss.dai));
        if (assets >= liabilities) {
            // Force the assets to become less than the liabilities
            uint256 performanceBonus = 100_000_000 * WAD;
            dss.dai.setBalance(address(this), performanceBonus * 4);
            pool.supply(address(dss.dai), performanceBonus * 4, address(this), 0);
            pool.borrow(address(dss.dai), performanceBonus * 2, 2, 0, address(this));  // Supply rate should now be above 0% (we are over-allocating)

            // Warp so we gaurantee there is new interest
            vm.warp(block.timestamp + 365 days);
            forceUpdateIndicies(address(dss.dai));

            assets = getTotalAssets(address(dss.dai));
            liabilities = getTotalLiabilities(address(dss.dai));
            assertLe(assets, liabilities, "assets should be less than or equal to liabilities");
        }
        
        daiTreasury.push();

        assets = getTotalAssets(address(dss.dai)) + 1;  // In case of rounding error we +1
        liabilities = getTotalLiabilities(address(dss.dai));
        assertGe(assets, liabilities, "assets should be greater than or equal to liabilities");
    }

    function getTotalAssets(address asset) internal view returns (uint256) {
        // Assets = DAI Liquidity + Total Debt
        DataTypes.ReserveData memory data = pool.getReserveData(asset);
        return dss.dai.balanceOf(data.aTokenAddress) + IERC20(data.variableDebtTokenAddress).totalSupply() + IERC20(data.stableDebtTokenAddress).totalSupply();
    }

    function getTotalLiabilities(address asset) internal view returns (uint256) {
        // Liabilities = spDAI Supply + Amount Accrued to Treasury
        DataTypes.ReserveData memory data = pool.getReserveData(asset);
        return _divup((IAToken(data.aTokenAddress).scaledTotalSupply() + uint256(data.accruedToTreasury)) * data.liquidityIndex, RAY);
    }

    function forceUpdateIndicies(address asset) internal {
        // Do the flashloan trick to force update indicies
        pool.flashLoanSimple(address(this), asset, 1, "", 0);
    }

    function executeOperation(
        address,
        uint256,
        uint256,
        address,
        bytes calldata
    ) external pure returns (bool) {
        // Flashloan callback just immediately returns
        return true;
    }

    function _divup(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            z = x != 0 ? ((x - 1) / y) + 1 : 0;
        }
    }

}
