// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import 'forge-std/Test.sol';
import {ProtocolV3_0_1TestBase, InterestStrategyValues, ReserveConfig} from 'aave-helpers/ProtocolV3TestBase.sol';
import {TestWithExecutor} from 'aave-helpers/GovHelpers.sol';
import {SparkEthereum_20230525} from './SparkEthereum_20230525.sol';
import {IPool} from "aave-v3-core/contracts/interfaces/IPool.sol";
import {IPoolAddressesProvider} from "aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol";
import {IDefaultInterestRateStrategy} from "aave-v3-core/contracts/interfaces/IDefaultInterestRateStrategy.sol";
import {DaiInterestRateStrategy} from "../../DaiInterestRateStrategy.sol";

contract SparkEthereum_20230525Test is ProtocolV3_0_1TestBase, TestWithExecutor {
    uint256 internal constant RAY = 1e27;
    SparkEthereum_20230525 public payload;

    address internal constant MCD_PAUSE_PROXY = 0xBE8E3e3618f7474F8cB1d074A26afFef007E98FB;

    IPool internal constant POOL = IPool(0xC13e21B648A5Ee794902342038FF3aDAB66BE987);
    IPoolAddressesProvider internal constant POOL_ADDRESS_PROVIDER = IPoolAddressesProvider(0x02C3eA4e34C0cBd694D2adFa2c690EECbC1793eE);

    address internal constant RETH = 0x553303d460EE0afB37EdFf9bE42922D8FF63220e;
    address internal constant RETH_PRICE_FEED = 0x553303d460EE0afB37EdFf9bE42922D8FF63220e;

    function setUp() public {
        vm.createSelectFork(getChain('mainnet').rpcUrl, 17336776);
        _selectPayloadExecutor(MCD_PAUSE_PROXY);

        payload = new SparkEthereum_20230525();
    }

    function testPoolActivation() public {
        createConfigurationSnapshot(
            'pre-Spark-Ethereum-rETH-Listing',
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
                baseStableBorrowRate: 0,
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

        createConfigurationSnapshot(
            'post-Spark-Ethereum-rETH-Listing',
            POOL
        );

        diffReports(
            'pre-Spark-Ethereum-rETH-Listing',
            'post-Spark-Ethereum-rETH-Listing'
        );
    }

    function _writeStrategyConfig(string memory strategiesKey, address _strategy) internal override returns (string memory content) {
        try IDefaultInterestRateStrategy(_strategy).getBaseStableBorrowRate() {
            // Default IRS
            content = super._writeStrategyConfig(strategiesKey, _strategy);
        } catch {
            // DAI IRS
            string memory key = vm.toString(_strategy);
            DaiInterestRateStrategy strategy = DaiInterestRateStrategy(
                _strategy
            );
            string memory object = vm.serializeString(
                key,
                'test',
                '123'
            );
            content = vm.serializeString(strategiesKey, key, object);
        }
    }
}