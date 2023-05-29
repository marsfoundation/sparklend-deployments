// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import 'forge-std/Test.sol';

import { TestWithExecutor } from 'aave-helpers/GovHelpers.sol';

import { IPool }                        from "aave-v3-core/contracts/interfaces/IPool.sol";
import { IPoolAddressesProvider }       from "aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol";
import { IACLManager }                  from "aave-v3-core/contracts/interfaces/IACLManager.sol";
import { IDefaultInterestRateStrategy } from "aave-v3-core/contracts/interfaces/IDefaultInterestRateStrategy.sol";

import { SparkTestBase, InterestStrategyValues, ReserveConfig } from '../../SparkTestBase.sol';

import { DaiInterestRateStrategy } from "../../DaiInterestRateStrategy.sol";

import { SparkEthereum_20230525 } from './SparkEthereum_20230525.sol';

contract SparkEthereum_20230525Test is SparkTestBase, TestWithExecutor {

    uint256 internal constant RAY = 1e27;
    SparkEthereum_20230525 public payload;

    address internal constant PAUSE_PROXY = 0xBE8E3e3618f7474F8cB1d074A26afFef007E98FB;
    address internal constant EXECUTOR    = 0x3300f198988e4C9C63F75dF86De36421f06af8c4;

    IPool                  internal constant POOL                  = IPool(0xC13e21B648A5Ee794902342038FF3aDAB66BE987);
    IPoolAddressesProvider internal constant POOL_ADDRESS_PROVIDER = IPoolAddressesProvider(0x02C3eA4e34C0cBd694D2adFa2c690EECbC1793eE);
    IACLManager            internal constant ACL_MANAGER           = IACLManager(0xdA135Cd78A086025BcdC87B038a1C462032b510C);

    address internal constant RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;

    address public constant DAI                        = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant DAI_INTEREST_RATE_STRATEGY = 0x9f9782880dd952F067Cad97B8503b0A3ac0fb21d;
    address public constant MCD_VAT                    = 0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B;
    address public constant MCD_POT                    = 0x197E90f9FAD81970bA7976f33CbD77088E5D7cf7;

    bytes32 public constant SPARK_ILK = 0x4449524543542d535041524b2d44414900000000000000000000000000000000;

    function setUp() public {
        vm.createSelectFork(getChain('mainnet').rpcUrl, 17365302);

        // This needs to be done in Maker spell, but grant the subdao proxy admin access on the pool
        vm.prank(PAUSE_PROXY);
        ACL_MANAGER.addPoolAdmin(EXECUTOR);

        _selectPayloadExecutor(EXECUTOR);

        payload = new SparkEthereum_20230525();
    }

    function testSpellExecution() public {
        createConfigurationSnapshot('pre-Spark-Ethereum-rETH-Listing', POOL);

        _executePayload(address(payload));

        ReserveConfig[] memory allConfigs = _getReservesConfigs(POOL);

        // rETH

        ReserveConfig memory reth = ReserveConfig({
            symbol:                  'rETH',
            underlying:               RETH,
            aToken:                   address(0),  // Mock, as they don't get validated, because of the "dynamic" deployment on proposal execution
            variableDebtToken:        address(0),  // Mock, as they don't get validated, because of the "dynamic" deployment on proposal execution
            stableDebtToken:          address(0),  // Mock, as they don't get validated, because of the "dynamic" deployment on proposal execution
            decimals:                 18,
            ltv:                      68_50,
            liquidationThreshold:     79_50,
            liquidationBonus:         107_00,
            liquidationProtocolFee:   10_00,
            reserveFactor:            15_00,
            usageAsCollateralEnabled: true,
            borrowingEnabled:         true,
            interestRateStrategy:     _findReserveConfigBySymbol(allConfigs, 'rETH').interestRateStrategy,
            stableBorrowRateEnabled:  false,
            isActive:                 true,
            isFrozen:                 false,
            isSiloed:                 false,
            isBorrowableInIsolation:  false,
            isFlashloanable:          true,
            supplyCap:                20_000,
            borrowCap:                2_400,
            debtCeiling:              0,
            eModeCategory:            1
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

        _validateAssetSourceOnOracle(POOL_ADDRESS_PROVIDER,RETH, payload.RETH_PRICE_FEED());

        // DAI Interest Rate Strategy

        _validateDaiInterestRateStrategy(
            _findReserveConfigBySymbol(allConfigs, 'DAI').interestRateStrategy,
            DAI_INTEREST_RATE_STRATEGY,
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

        createConfigurationSnapshot('post-Spark-Ethereum-rETH-Listing', POOL);

        diffReports(
            'pre-Spark-Ethereum-rETH-Listing',
            'post-Spark-Ethereum-rETH-Listing'
        );
    }
}
