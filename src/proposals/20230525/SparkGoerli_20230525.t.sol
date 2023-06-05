// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import 'forge-std/Test.sol';

import { TestWithExecutor } from 'aave-helpers/GovHelpers.sol';

import {
    InitializableAdminUpgradeabilityProxy
} from 'aave-v3-core/contracts/dependencies/openzeppelin/upgradeability/InitializableAdminUpgradeabilityProxy.sol';

import { IAaveOracle }                  from "aave-v3-core/contracts/interfaces/IAaveOracle.sol";
import { IACLManager }                  from "aave-v3-core/contracts/interfaces/IACLManager.sol";
import { IDefaultInterestRateStrategy } from "aave-v3-core/contracts/interfaces/IDefaultInterestRateStrategy.sol";
import { IPoolAddressesProvider }       from "aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol";
import { IPool }                        from "aave-v3-core/contracts/interfaces/IPool.sol";

import { ReserveConfiguration } from "aave-v3-core/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import { DataTypes }            from "aave-v3-core/contracts/protocol/libraries/types/DataTypes.sol";

import { DefaultReserveInterestRateStrategy } from "aave-v3-core/contracts/protocol/pool/DefaultReserveInterestRateStrategy.sol";

import { DaiInterestRateStrategy }                              from '../../DaiInterestRateStrategy.sol';
import { SparkTestBase, InterestStrategyValues, ReserveConfig } from '../../SparkTestBase.sol';

import { SparkGoerli_20230525 } from './SparkGoerli_20230525.sol';

contract SparkGoerli_20230525Test is SparkTestBase, TestWithExecutor {

    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    uint256 public constant WAD  = 1e18;
    uint256 public constant RAY  = 1e27;
    uint256 public constant RBPS = RAY / 10000;

    SparkGoerli_20230525 public payload;

    address public constant PAUSE_PROXY = 0x5DCdbD3cCF9B09EAAD03bc5f50fA2B3d3ACA0121;
    address public constant EXECUTOR    = 0x4e847915D8a9f2Ab0cDf2FC2FD0A30428F25665d;

    IAaveOracle            public constant ORACLE                = IAaveOracle(0x5Cd822d9a4421be687930498ec4B498EB972ad29);
    IACLManager            public constant ACL_MANAGER           = IACLManager(0xb137E7d16564c81ae2b0C8ee6B55De81dd46ECe5);
    IPool                  public constant POOL                  = IPool(0x26ca51Af4506DE7a6f0785D20CD776081a05fF6d);
    IPoolAddressesProvider public constant POOL_ADDRESS_PROVIDER = IPoolAddressesProvider(0x026a5B6114431d8F3eF2fA0E1B2EDdDccA9c540E);

    address public constant A_TOKEN_IMPL                   = 0x35542cbc5730d5e39CF79dDBd8976ac984ca109b;
    address public constant NEW_DAI_INTEREST_RATE_STRATEGY = 0x70659BcA22A2a8BB324A526a8BB919185d3ecEBC;
    address public constant OLD_DAI_INTEREST_RATE_STRATEGY = 0x491acea4126E48e9A354b64869AE16b2f27BE333;
    address public constant POOL_CONFIGURATOR              = 0xe0C7ec61cC47e7c02b9B24F03f75C7BC406CCA98;
    address public constant STABLE_DEBT_TOKEN_IMPL         = 0x571501be53711c372cE69De51865dD34B87698D5;
    address public constant VARIABLE_DEBT_TOKEN_IMPL       = 0xb9E6DBFa4De19CCed908BcbFe1d015190678AB5f;
    address public constant RETH_PRICE_FEED                = 0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e;

    address public constant DAI    = 0x11fE4B6AE13d2a6055C8D9cF65c55bac32B5d844;
    address public constant SDAI   = 0xD8134205b0328F5676aaeFb3B2a0DC15f4029d8C;
    address public constant USDC   = 0x6Fb5ef893d44F4f88026430d82d4ef269543cB23;
    address public constant WETH   = 0x7D5afF7ab67b431cDFA6A94d50d3124cC4AB2611;
    address public constant WSTETH = 0x6E4F1e8d4c5E5E6e2781FD814EE0744cc16Eb352;
    address public constant WBTC   = 0x91277b74a9d1Cc30fA0ff4927C287fe55E307D78;
    address public constant GNO    = 0x86Bc432064d7F933184909975a384C7E4c9d0977;
    address public constant RETH   = 0x62BC478FFC429161115A6E4090f819CE5C50A5d9;

    address public constant MCD_VAT = 0xB966002DDAa2Baf48369f5015329750019736031;
    address public constant MCD_POT = 0x50672F0a14B40051B65958818a7AcA3D54Bd81Af;

    bytes32 public constant SPARK_ILK = 0x4449524543542d535041524b2d44414900000000000000000000000000000000;

    function setUp() public {
        vm.createSelectFork(getChain('goerli').rpcUrl, 9085778);

        // This needs to be done in Maker spell, but grant the subdao proxy admin access on the pool
        vm.prank(PAUSE_PROXY); ACL_MANAGER.addPoolAdmin(EXECUTOR);

        _selectPayloadExecutor(EXECUTOR);

        payload = new SparkGoerli_20230525();
    }

    function testSpellExecution() public {
        createConfigurationSnapshot(
            'pre-Spark-Goerli-rETH-Listing',
            POOL
        );

        _executePayload(address(payload));

        ReserveConfig[] memory allConfigs = _getReservesConfigs(POOL);

        // rETH

        ReserveConfig memory reth = ReserveConfig({
            symbol:                  'rETH',
            underlying:               RETH,
            aToken:                   address(0), // Mock, as they don't get validated, because of the "dynamic" deployment on proposal execution
            variableDebtToken:        address(0), // Mock, as they don't get validated, because of the "dynamic" deployment on proposal execution
            stableDebtToken:          address(0), // Mock, as they don't get validated, because of the "dynamic" deployment on proposal execution
            decimals:                 18,
            ltv:                      68_50,
            liquidationThreshold:     79_50,
            liquidationBonus:         10700,
            liquidationProtocolFee:   1000,
            reserveFactor:            1500,
            usageAsCollateralEnabled: true,
            borrowingEnabled:         true,
            interestRateStrategy:    _findReserveConfigBySymbol(allConfigs, 'rETH').interestRateStrategy,
            stableBorrowRateEnabled: false,
            isActive:                true,
            isFrozen:                false,
            isSiloed:                false,
            isBorrowableInIsolation: false,
            isFlashloanable:         true,
            supplyCap:               20_000,
            borrowCap:               2_400,
            debtCeiling:             0,
            eModeCategory:           1
        });

        _validateReserveConfig(reth, allConfigs);

        _validateInterestRateStrategy(
            reth.interestRateStrategy,
            reth.interestRateStrategy,
            InterestStrategyValues({
                addressesProvider:             address(POOL_ADDRESS_PROVIDER),
                optimalUsageRatio:             45 * (RAY / 100),
                optimalStableToTotalDebtRatio: 0,
                baseStableBorrowRate:          7 * (RAY / 100),      // Equal to variableRateSlope1 as we don't use stable rates
                stableRateSlope1:              0,
                stableRateSlope2:              0,
                baseVariableBorrowRate:        0,
                variableRateSlope1:            7 * (RAY / 100),
                variableRateSlope2:            300 * (RAY / 100)
            })
        );

        _validateAssetSourceOnOracle(POOL_ADDRESS_PROVIDER, RETH, payload.RETH_PRICE_FEED());

        // DAI Interest Rate Strategy

        _validateDaiInterestRateStrategy(
            _findReserveConfigBySymbol(allConfigs, 'DAI').interestRateStrategy,
            NEW_DAI_INTEREST_RATE_STRATEGY,
            DaiInterestStrategyValues({
                vat:                MCD_VAT,
                pot:                MCD_POT,
                ilk:                SPARK_ILK,
                baseRateConversion: RAY,
                borrowSpread:       0,
                supplySpread:       0,
                maxRate:            75 * (RAY / 100),
                performanceBonus:   0
            })
        );

        createConfigurationSnapshot(
            'post-Spark-Goerli-rETH-Listing',
            POOL
        );
    }

    function testSpellExecution_manual() public {

        /*********************/
        /*** Reserves List ***/
        /*********************/

        address[] memory reserves = POOL.getReservesList();

        assertEq(reserves.length, 7);

        assertEq(reserves[0], DAI);
        assertEq(reserves[1], SDAI);
        assertEq(reserves[2], USDC);
        assertEq(reserves[3], WETH);
        assertEq(reserves[4], WSTETH);
        assertEq(reserves[5], WBTC);
        assertEq(reserves[6], GNO);

        /**********************************************************/
        /*** RETH Onboarding - Reserve Configuration and Oracle ***/
        /**********************************************************/

        DataTypes.ReserveData memory data = POOL.getReserveData(RETH);

        assertEq(data.aTokenAddress,               address(0));
        assertEq(data.stableDebtTokenAddress,      address(0));
        assertEq(data.variableDebtTokenAddress,    address(0));
        assertEq(data.interestRateStrategyAddress, address(0));  // No assertions possible on strategy since it's not deployed

        assertEq(data.liquidityIndex,            0);
        assertEq(data.currentLiquidityRate,      0);
        assertEq(data.variableBorrowIndex,       0);
        assertEq(data.currentVariableBorrowRate, 0);
        assertEq(data.currentStableBorrowRate,   0);
        assertEq(data.lastUpdateTimestamp,       0);
        assertEq(data.id,                        0);
        assertEq(data.accruedToTreasury,         0);
        assertEq(data.unbacked,                  0);
        assertEq(data.isolationModeTotalDebt,    0);

        DataTypes.ReserveConfigurationMap memory cfg = data.configuration;

        assertEq(cfg.data, 0);  // Entire map is empty

        assertEq(ORACLE.getSourceOfAsset(RETH), address(0));

        /*****************************/
        /*** DAI Interest Strategy ***/
        /*****************************/

        data = POOL.getReserveData(DAI);

        assertEq(data.interestRateStrategyAddress, OLD_DAI_INTEREST_RATE_STRATEGY);

        DaiInterestRateStrategy daiStrategy = DaiInterestRateStrategy(data.interestRateStrategyAddress);

        assertEq(daiStrategy.vat(), MCD_VAT);
        assertEq(daiStrategy.pot(), MCD_POT);
        assertEq(daiStrategy.ilk(), SPARK_ILK);

        assertEq(daiStrategy.baseRateConversion(), RAY * 10 / 9);
        assertEq(daiStrategy.borrowSpread(),       0);
        assertEq(daiStrategy.supplySpread(),       0);
        assertEq(daiStrategy.maxRate(),            75_00 * RBPS);
        assertEq(daiStrategy.performanceBonus(),   0);

        daiStrategy.recompute();

        assertEq(daiStrategy.getBaseRate(), 0.011055923171930957297759999e27);  // ~1.11%

        ( uint256 supplyRate,, uint256 borrowRate ) = daiStrategy.calculateInterestRates(DataTypes.CalculateInterestRatesParams(
            0,
            0,
            0,
            0,
            1_000_000_000 * WAD,
            0,
            0,
            DAI,
            address(0)
        ));

        assertEq(supplyRate, 0.011053159583008550868558601e27); // ~1.11%
        assertEq(borrowRate, 0.011055923171930957297759999e27); // ~1.11% (slightly higher)

        /***********************/
        /*** Execute Payload ***/
        /***********************/

        _executePayload(address(payload));

        /*********************/
        /*** Reserves List ***/
        /*********************/

        reserves = POOL.getReservesList();

        assertEq(reserves.length, 8);

        assertEq(reserves[0], DAI);
        assertEq(reserves[1], SDAI);
        assertEq(reserves[2], USDC);
        assertEq(reserves[3], WETH);
        assertEq(reserves[4], WSTETH);
        assertEq(reserves[5], WBTC);
        assertEq(reserves[6], GNO);
        assertEq(reserves[7], RETH);

        /**********************************************************/
        /*** RETH Onboarding - Reserve Configuration and Oracle ***/
        /**********************************************************/

        data = POOL.getReserveData(RETH);

        assertImplementation(POOL_CONFIGURATOR, data.aTokenAddress,            A_TOKEN_IMPL);
        assertImplementation(POOL_CONFIGURATOR, data.stableDebtTokenAddress,   STABLE_DEBT_TOKEN_IMPL);
        assertImplementation(POOL_CONFIGURATOR, data.variableDebtTokenAddress, VARIABLE_DEBT_TOKEN_IMPL);

        cfg = data.configuration;

        assertEq(cfg.getLtv(),                  68_50);
        assertEq(cfg.getLiquidationThreshold(), 79_50);
        assertEq(cfg.getLiquidationBonus(),     107_00);
        assertEq(cfg.getDecimals(),             18);

        assertEq(cfg.getActive(), true);
        assertEq(cfg.getFrozen(), false);
        assertEq(cfg.getPaused(), false);

        assertEq(cfg.getBorrowableInIsolation(),      false);
        assertEq(cfg.getSiloedBorrowing(),            false);
        assertEq(cfg.getBorrowingEnabled(),           true);
        assertEq(cfg.getStableRateBorrowingEnabled(), false);

        assertEq(cfg.getReserveFactor(),          15_00);
        assertEq(cfg.getBorrowCap(),              2_400);
        assertEq(cfg.getSupplyCap(),              20_000);
        assertEq(cfg.getDebtCeiling(),            0);
        assertEq(cfg.getLiquidationProtocolFee(), 10_00);
        assertEq(cfg.getUnbackedMintCap(),        0);
        assertEq(cfg.getEModeCategory(),          1);
        assertEq(cfg.getFlashLoanEnabled(),       true);

        assertEq(ORACLE.getSourceOfAsset(RETH), RETH_PRICE_FEED);

        /*******************************************/
        /*** RETH Onboarding - Interest Strategy ***/
        /*******************************************/

        DefaultReserveInterestRateStrategy st = DefaultReserveInterestRateStrategy(data.interestRateStrategyAddress);

        assertEq(address(st.ADDRESSES_PROVIDER()), address(POOL_ADDRESS_PROVIDER));

        assertEq(st.OPTIMAL_USAGE_RATIO(),                   45 * RAY / 100);
        assertEq(st.OPTIMAL_STABLE_TO_TOTAL_DEBT_RATIO(),    0);
        assertEq(st.MAX_EXCESS_USAGE_RATIO(),                55 * RAY / 100);
        assertEq(st.MAX_EXCESS_STABLE_TO_TOTAL_DEBT_RATIO(), RAY);

        assertEq(st.getVariableRateSlope1(),     7   * RAY / 100);
        assertEq(st.getVariableRateSlope2(),     300 * RAY / 100);
        assertEq(st.getStableRateSlope1(),       0);
        assertEq(st.getStableRateSlope2(),       0);
        assertEq(st.getStableRateExcessOffset(), 0);
        assertEq(st.getBaseStableBorrowRate(),   7 * RAY / 100);
        assertEq(st.getBaseVariableBorrowRate(), 0);
        assertEq(st.getMaxVariableBorrowRate(),  307 * RAY / 100);

        /*****************************/
        /*** DAI Interest Strategy ***/
        /*****************************/

        data = POOL.getReserveData(DAI);

        assertEq(data.interestRateStrategyAddress, NEW_DAI_INTEREST_RATE_STRATEGY);

        daiStrategy = DaiInterestRateStrategy(data.interestRateStrategyAddress);

        assertEq(daiStrategy.vat(), MCD_VAT);
        assertEq(daiStrategy.pot(), MCD_POT);
        assertEq(daiStrategy.ilk(), SPARK_ILK);

        assertEq(daiStrategy.baseRateConversion(), RAY);
        assertEq(daiStrategy.borrowSpread(),       0);
        assertEq(daiStrategy.supplySpread(),       0);
        assertEq(daiStrategy.maxRate(),            75_00 * RBPS);
        assertEq(daiStrategy.performanceBonus(),   0);

        daiStrategy.recompute();

        assertEq(daiStrategy.getBaseRate(), 0.009950330854737861567984000e27);  // ~0.99%

        ( supplyRate,, borrowRate ) = daiStrategy.calculateInterestRates(DataTypes.CalculateInterestRatesParams(
            0,
            0,
            0,
            0,
            1_000_000_000 * WAD,
            0,
            0,
            DAI,
            address(0)
        ));

        assertEq(supplyRate, 0.009947843624707695781702742e27); // ~0.99% (slightly lower)
        assertEq(borrowRate, 0.009950330854737861567984000e27); // ~0.99% (slightly higher)
    }

    function assertImplementation(address admin, address proxy, address implementation) internal {
        vm.prank(admin);
        assertEq(InitializableAdminUpgradeabilityProxy(payable(proxy)).implementation(), implementation);
    }

}
