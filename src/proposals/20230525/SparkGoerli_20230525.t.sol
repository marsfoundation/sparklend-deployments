// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import 'forge-std/Test.sol';
import {SparkTestBase, InterestStrategyValues, ReserveConfig} from '../../SparkTestBase.sol';
import {TestWithExecutor} from 'aave-helpers/GovHelpers.sol';
import {SparkGoerli_20230525} from './SparkGoerli_20230525.sol';
import {IPool} from "aave-v3-core/contracts/interfaces/IPool.sol";
import {IPoolAddressesProvider} from "aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol";
import {IACLManager} from "aave-v3-core/contracts/interfaces/IACLManager.sol";
import {IDefaultInterestRateStrategy} from "aave-v3-core/contracts/interfaces/IDefaultInterestRateStrategy.sol";

contract SparkGoerli_20230525Test is SparkTestBase, TestWithExecutor {
    uint256 internal constant RAY = 1e27;
    SparkGoerli_20230525 public payload;

    address internal constant PAUSE_PROXY = 0x5DCdbD3cCF9B09EAAD03bc5f50fA2B3d3ACA0121;
    address internal constant EXECUTOR = 0x4e847915D8a9f2Ab0cDf2FC2FD0A30428F25665d;

    IPool internal constant POOL = IPool(0x26ca51Af4506DE7a6f0785D20CD776081a05fF6d);
    IPoolAddressesProvider internal constant POOL_ADDRESS_PROVIDER = IPoolAddressesProvider(0x026a5B6114431d8F3eF2fA0E1B2EDdDccA9c540E);
    IACLManager internal constant ACL_MANAGER = IACLManager(0xb137E7d16564c81ae2b0C8ee6B55De81dd46ECe5);

    address internal constant RETH = 0x62BC478FFC429161115A6E4090f819CE5C50A5d9;

    address public constant DAI = 0x11fE4B6AE13d2a6055C8D9cF65c55bac32B5d844;
    address public constant DAI_INTEREST_RATE_STRATEGY = 0x70659BcA22A2a8BB324A526a8BB919185d3ecEBC;
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
            symbol: 'rETH',
            underlying: RETH,
            aToken: address(0), // Mock, as they don't get validated, because of the "dynamic" deployment on proposal execution
            variableDebtToken: address(0), // Mock, as they don't get validated, because of the "dynamic" deployment on proposal execution
            stableDebtToken: address(0), // Mock, as they don't get validated, because of the "dynamic" deployment on proposal execution
            decimals: 18,
            ltv: 68_50,
            liquidationThreshold: 79_50,
            liquidationBonus: 10700,
            liquidationProtocolFee: 1000,
            reserveFactor: 1500,
            usageAsCollateralEnabled: true,
            borrowingEnabled: true,
            interestRateStrategy: _findReserveConfigBySymbol(allConfigs, 'rETH').interestRateStrategy,
            stableBorrowRateEnabled: false,
            isActive: true,
            isFrozen: false,
            isSiloed: false,
            isBorrowableInIsolation: false,
            isFlashloanable: true,
            supplyCap: 20_000,
            borrowCap: 2_400,
            debtCeiling: 0,
            eModeCategory: 1
        });

        _validateReserveConfig(reth, allConfigs);

        _validateInterestRateStrategy(
            reth.interestRateStrategy,
            reth.interestRateStrategy,
            InterestStrategyValues({
                addressesProvider: address(POOL_ADDRESS_PROVIDER),
                optimalUsageRatio: 45 * (RAY / 100),
                optimalStableToTotalDebtRatio: 0,
                baseStableBorrowRate: 7 * (RAY / 100),      // Equal to variableRateSlope1 as we don't use stable rates
                stableRateSlope1: 0,
                stableRateSlope2: 0,
                baseVariableBorrowRate: 0,
                variableRateSlope1: 7 * (RAY / 100),
                variableRateSlope2: 300 * (RAY / 100)
            })
        );

        _validateAssetSourceOnOracle(
            POOL_ADDRESS_PROVIDER,
            RETH,
            payload.RETH_PRICE_FEED()
        );

        // DAI Interest Rate Strategy

        _validateDaiInterestRateStrategy(
            _findReserveConfigBySymbol(allConfigs, 'DAI').interestRateStrategy,
            DAI_INTEREST_RATE_STRATEGY,
            DaiInterestStrategyValues({
                vat: MCD_VAT,
                pot: MCD_POT,
                ilk: SPARK_ILK,
                baseRateConversion: RAY,
                borrowSpread: 0,
                supplySpread: 0,
                maxRate: 75 * (RAY / 100),
                performanceBonus: 0
            })
        );

        createConfigurationSnapshot(
            'post-Spark-Goerli-rETH-Listing',
            POOL
        );
    }
}