// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.10;

import "dss-test/DssTest.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {IERC20Detailed} from 'aave-v3-core/contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol';
import {IERC20} from 'aave-v3-core/contracts/dependencies/openzeppelin/contracts/IERC20.sol';
import {InitializableImmutableAdminUpgradeabilityProxy} from 'aave-v3-core/contracts/protocol/libraries/aave-upgradeability/InitializableImmutableAdminUpgradeabilityProxy.sol';
import {WadRayMath} from 'aave-v3-core/contracts/protocol/libraries/math/WadRayMath.sol';
import {PoolAddressesProvider} from "aave-v3-core/contracts/protocol/configuration/PoolAddressesProvider.sol";
import {Pool} from "aave-v3-core/contracts/protocol/pool/Pool.sol";
import {IAToken} from "aave-v3-core/contracts/interfaces/IAToken.sol";
import {IAaveIncentivesController} from "aave-v3-core/contracts/interfaces/IAaveIncentivesController.sol";
import {DataTypes} from "aave-v3-core/contracts/protocol/libraries/types/DataTypes.sol";
import {ReserveConfiguration} from "aave-v3-core/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {ICollector} from "aave-v3-periphery/treasury/interfaces/ICollector.sol";

import {VariableInterestToken} from "../VariableInterestToken.sol";
import {FixedRatesManager} from "../FixedRatesManager.sol";

contract FixedRatesIntegrationTest is DssTest {

    using stdJson for string;
    using MCD for *;
    using GodMode for *;
    using WadRayMath for uint256;

    uint256 constant ERROR_ONE_BPS = WAD / BPS;

    string config;
    DssInstance dss;

    PoolAddressesProvider poolAddressesProvider;
    Pool pool;
    IERC20 dai;
    IAToken aToken;
    address treasurySource;
    address treasuryDestination;
    
    VariableInterestToken vToken;
    FixedRatesManager mgr;

    uint256 loanSize;

    function setUp() public {
        config = ScriptTools.readInput("config");
        dss = MCD.loadFromChainlog(config.readAddress(".chainlog"));

        dai = IERC20(dss.chainlog.getAddress("MCD_DAI"));

        poolAddressesProvider = PoolAddressesProvider(ScriptTools.importContract("LENDING_POOL_ADDRESS_PROVIDER"));
        pool = Pool(poolAddressesProvider.getPool());
        aToken = getAToken(address(dai));
        treasurySource = aToken.RESERVE_TREASURY_ADDRESS();
        treasuryDestination = TEST_ADDRESS;

        vToken = VariableInterestToken(initProxy(
            address(123),
            address(new VariableInterestToken(pool)),
            abi.encodeWithSelector(
                VariableInterestToken.initialize.selector,
                address(pool),
                computeCreateAddress(address(this), 3),
                aToken,
                IAaveIncentivesController(address(0)),
                18,
                "DAI Variable Interest Token",
                "vDAI",
                ""
            )
        ));
        mgr = new FixedRatesManager(
            pool,
            vToken,
            address(this),
            treasurySource,
            treasuryDestination
        );
        assertEq(vToken.MANAGER_ADDRESS(), address(mgr), "bad manager address");

        // Borrow 100k of DAI
        loanSize = 100_000 ether;
        uint256 collateral = loanSize * 2;
        address(dai).setBalance(address(this), collateral);
        dai.approve(address(pool), type(uint256).max);
        pool.supply(address(dai), collateral, address(this), 0);
        pool.borrow(address(dai), loanSize, 2, 0, address(this));
        address[] memory assets = new address[](1);
        assets[0] = address(dai);
        pool.mintToTreasury(assets);

        vm.startPrank(ICollector(treasurySource).getFundsAdmin());
        ICollector(treasurySource).approve(aToken, address(mgr), type(uint256).max);
        ICollector(treasurySource).transfer(aToken, treasuryDestination, aToken.balanceOf(treasurySource));
        vm.stopPrank();
    }

    function getLTV(address asset) internal view returns (uint256) {
        DataTypes.ReserveData memory data = pool.getReserveData(asset);
        return ReserveConfiguration.getLtv(data.configuration);
    }

    function getAToken(address asset) internal view returns (IAToken) {
        DataTypes.ReserveData memory data = pool.getReserveData(asset);
        return IAToken(data.aTokenAddress);
    }

    function initProxy(address owner, address impl, bytes memory initData) internal returns (address) {
        InitializableImmutableAdminUpgradeabilityProxy proxy = new InitializableImmutableAdminUpgradeabilityProxy(owner);
        proxy.initialize(impl, initData);
        return address(proxy);
    }

    function initProxy(InitializableImmutableAdminUpgradeabilityProxy proxy, address impl, bytes memory initData) internal returns (address) {
        proxy.initialize(impl, initData);
        return address(proxy);
    }

    function test_interest_accumulates() public {
        uint256 aTokensDestinationInitial = aToken.balanceOf(treasuryDestination);
        assertEq(aToken.balanceOf(address(vToken)), 0, "vToken should have no aToken to start");
        assertEq(aToken.balanceOf(treasurySource), 0, "treasurySource should have no aTokens to start");
        uint256 ratio = loanSize.wadDiv(aToken.totalSupply() - dai.balanceOf(address(aToken)));
        
        mgr.mint(address(this), loanSize);

        assertEq(aToken.balanceOf(address(vToken)), 0, "vToken should still have no aToken after minting");
        assertEq(aToken.balanceOf(treasurySource), 0, "treasurySource should have no aTokens after minting");
        assertEq(vToken.balanceOf(address(this)), loanSize, "we should have the loanSize in vTokens after minting");

        // Accumulate some interest
        vm.warp(block.timestamp + 365 days);
        _triggerIndexUpdate();
        address[] memory assets = new address[](1);
        assets[0] = address(dai);
        pool.mintToTreasury(assets);
        uint256 delta = aToken.balanceOf(treasurySource);
        uint256 myInterest = delta.wadMul(ratio);

        assertEq(aToken.balanceOf(address(vToken)), 0, "vToken should still have no aToken after collecting interest permissionlessly");
        assertEq(aToken.balanceOf(treasuryDestination), aTokensDestinationInitial, "treasury destination aTokens should be unchanged");
        assertApproxEqRel(vToken.balanceOf(address(this)), loanSize + myInterest, ERROR_ONE_BPS, "my vTokens should have increased by my interest");

        mgr.mint(address(this), 0); // Trigger the interest to be transferred to the vToken and any remainder into the treasury

        assertApproxEqRel(aToken.balanceOf(address(vToken)), myInterest, ERROR_ONE_BPS, "aToken balance of vToken should be my interest");
        assertApproxEqRel(aToken.balanceOf(treasuryDestination), aTokensDestinationInitial + delta - myInterest, ERROR_ONE_BPS, "aToken balance of treasury destination be the remainder");
        assertEq(aToken.balanceOf(treasurySource), 0, "treasurySource should have no aTokens after minting");
    }

    function _triggerIndexUpdate() private {
        pool.flashLoanSimple(address(this), address(dai), 1, "", 0);
    }
    function executeOperation(
        address,
        uint256,
        uint256,
        address,
        bytes calldata
    ) external pure returns (bool) {
        return true;
    }

}
