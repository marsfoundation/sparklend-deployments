// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.10;

import "dss-test/DssTest.sol";
import {stdJson} from "forge-std/StdJson.sol";

import "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import { MCD, DssInstance } from "dss-test/MCD.sol";
import {ScriptTools} from "dss-test/ScriptTools.sol";

import {IERC20Detailed} from 'aave-v3-core/contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol';
import {Strings} from 'aave-v3-core/contracts/dependencies/openzeppelin/contracts/Strings.sol';
import {IERC20} from 'aave-v3-core/contracts/dependencies/openzeppelin/contracts/IERC20.sol';
import {InitializableAdminUpgradeabilityProxy} from 'aave-v3-core/contracts/dependencies/openzeppelin/upgradeability/InitializableAdminUpgradeabilityProxy.sol';
import {AggregatorInterface} from 'aave-v3-core/contracts/dependencies/chainlink/AggregatorInterface.sol';

import {PoolAddressesProviderRegistry} from "aave-v3-core/contracts/protocol/configuration/PoolAddressesProviderRegistry.sol";
import {PoolAddressesProvider} from "aave-v3-core/contracts/protocol/configuration/PoolAddressesProvider.sol";
import {AaveProtocolDataProvider} from "aave-v3-core/contracts/misc/AaveProtocolDataProvider.sol";
import {PoolConfigurator} from "aave-v3-core/contracts/protocol/pool/PoolConfigurator.sol";
import {Pool} from "aave-v3-core/contracts/protocol/pool/Pool.sol";
import {ACLManager} from "aave-v3-core/contracts/protocol/configuration/ACLManager.sol";
import {AaveOracle} from 'aave-v3-core/contracts/misc/AaveOracle.sol';

import {AToken} from "aave-v3-core/contracts/protocol/tokenization/AToken.sol";
import {StableDebtToken} from "aave-v3-core/contracts/protocol/tokenization/StableDebtToken.sol";
import {VariableDebtToken} from "aave-v3-core/contracts/protocol/tokenization/VariableDebtToken.sol";

import {ConfiguratorInputTypes} from "aave-v3-core/contracts/protocol/libraries/types/ConfiguratorInputTypes.sol";
import {DataTypes} from "aave-v3-core/contracts/protocol/libraries/types/DataTypes.sol";
import {IReserveInterestRateStrategy} from "aave-v3-core/contracts/interfaces/IReserveInterestRateStrategy.sol";
import {IAaveIncentivesController} from "aave-v3-core/contracts/interfaces/IAaveIncentivesController.sol";
import {DefaultReserveInterestRateStrategy} from "aave-v3-core/contracts/protocol/pool/DefaultReserveInterestRateStrategy.sol";

import {Collector} from "aave-v3-periphery/treasury/Collector.sol";
import {CollectorController} from "aave-v3-periphery/treasury/CollectorController.sol";
import {RewardsController} from "aave-v3-periphery/rewards/RewardsController.sol";
import {EmissionManager} from "aave-v3-periphery/rewards/EmissionManager.sol";

import {UiPoolDataProviderV3} from "aave-v3-periphery/misc/UiPoolDataProviderV3.sol";
import {UiIncentiveDataProviderV3} from "aave-v3-periphery/misc/UiIncentiveDataProviderV3.sol";
import {WrappedTokenGatewayV3} from "aave-v3-periphery/misc/WrappedTokenGatewayV3.sol";
import {IPool} from "aave-v3-core/contracts/interfaces/IPool.sol";
import {WalletBalanceProvider} from "aave-v3-periphery/misc/WalletBalanceProvider.sol";
import {IEACAggregatorProxy} from "aave-v3-periphery/misc/interfaces/IEACAggregatorProxy.sol";

import {MintableERC20} from "aave-v3-core/contracts/mocks/tokens/MintableERC20.sol";
import {WETH9Mocked} from "aave-v3-core/contracts/mocks/tokens/WETH9Mocked.sol";
import {MockAggregator} from "aave-v3-core/contracts/mocks/oracle/CLAggregators/MockAggregator.sol";

import {DaiInterestRateStrategy} from "../src/DaiInterestRateStrategy.sol";
import {SavingsDaiOracle} from "../src/SavingsDaiOracle.sol";

import {ReserveConfiguration} from "aave-v3-core/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";

interface stETHLike {
    function getTotalShares() external view returns (uint256);
}

contract IntegrationTest is DssTest {

    using stdJson for string;
    using MCD for *;
    using GodMode for *;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    string config;
    string deployedContracts;
    DssInstance dss;

    address admin;
    address deployer;

    PoolAddressesProviderRegistry poolAddressesProviderRegistry;
    PoolAddressesProvider poolAddressesProvider;
    AaveProtocolDataProvider protocolDataProvider;
    PoolConfigurator poolConfigurator;
    PoolConfigurator poolConfiguratorImpl;
    Pool pool;
    Pool poolImpl;
    ACLManager aclManager;
    AaveOracle aaveOracle;
    AToken aTokenImpl;
    VariableDebtToken variableDebtTokenImpl;
    StableDebtToken stableDebtTokenImpl;
    CollectorController treasuryController;
    Collector treasury;
    Collector treasuryImpl;
    Collector daiTreasury;
    Collector daiTreasuryImpl;
    EmissionManager emissionManager;
    RewardsController incentives;
    RewardsController incentivesImpl;
    UiPoolDataProviderV3 uiPoolDataProvider;
    UiIncentiveDataProviderV3 uiIncentiveDataProvider;
    WrappedTokenGatewayV3 wethGateway;
    WalletBalanceProvider walletBalanceProvider;

    address[] assets;

    IERC20 weth;
    IERC20 wsteth;
    IERC20 wbtc;
    IERC20 dai;
    IERC20 usdc;
    IERC20 sdai;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        vm.setEnv("FOUNDRY_ROOT_CHAINID", vm.toString(block.chainid));

        config = ScriptTools.readInput("config");
        deployedContracts = ScriptTools.readOutput("spark");
        dss = MCD.loadFromChainlog(config.readAddress(".chainlog"));

        admin = config.readAddress(".admin");
        deployer = deployedContracts.readAddress(".deployer");

        if (block.chainid == 1) {
            // Mainnet
            weth = IERC20(dss.chainlog.getAddress("ETH"));
            wsteth = IERC20(dss.chainlog.getAddress("WSTETH"));
            wbtc = IERC20(dss.chainlog.getAddress("WBTC"));
            dai = IERC20(dss.chainlog.getAddress("MCD_DAI"));
            usdc = IERC20(dss.chainlog.getAddress("USDC"));
            sdai = IERC20(0x83F20F44975D03b1b09e64809B757c47f942BEeA);
            // reth =
        } else {
            // Goerli
            weth = IERC20(deployedContracts.readAddress(".WETH_token"));
            wsteth = IERC20(deployedContracts.readAddress(".wstETH_token"));
            wbtc = IERC20(deployedContracts.readAddress(".WBTC_token"));
            dai = IERC20(dss.chainlog.getAddress("MCD_DAI"));
            usdc = IERC20(dss.chainlog.getAddress("USDC"));
            sdai = IERC20(0xD8134205b0328F5676aaeFb3B2a0DC15f4029d8C);
        }

        poolAddressesProviderRegistry = PoolAddressesProviderRegistry(deployedContracts.readAddress(".poolAddressesProviderRegistry"));
        poolAddressesProvider = PoolAddressesProvider(deployedContracts.readAddress(".poolAddressesProvider"));
        protocolDataProvider = AaveProtocolDataProvider(deployedContracts.readAddress(".protocolDataProvider"));
        poolConfigurator = PoolConfigurator(deployedContracts.readAddress(".poolConfigurator"));
        poolConfiguratorImpl = PoolConfigurator(deployedContracts.readAddress(".poolConfiguratorImpl"));
        pool = Pool(deployedContracts.readAddress(".pool"));
        poolImpl = Pool(deployedContracts.readAddress(".poolImpl"));
        aclManager = ACLManager(deployedContracts.readAddress(".aclManager"));
        aaveOracle = AaveOracle(deployedContracts.readAddress(".aaveOracle"));

        aTokenImpl = AToken(deployedContracts.readAddress(".aTokenImpl"));
        variableDebtTokenImpl = VariableDebtToken(deployedContracts.readAddress(".variableDebtTokenImpl"));
        stableDebtTokenImpl = StableDebtToken(deployedContracts.readAddress(".stableDebtTokenImpl"));

        treasuryController = CollectorController(deployedContracts.readAddress(".treasuryController"));
        treasury = Collector(deployedContracts.readAddress(".treasury"));
        treasuryImpl = Collector(deployedContracts.readAddress(".treasuryImpl"));
        daiTreasury = Collector(deployedContracts.readAddress(".daiTreasury"));
        daiTreasuryImpl = Collector(deployedContracts.readAddress(".daiTreasuryImpl"));

        emissionManager = EmissionManager(deployedContracts.readAddress(".emissionManager"));
        incentives = RewardsController(deployedContracts.readAddress(".incentives"));
        incentivesImpl = RewardsController(deployedContracts.readAddress(".incentivesImpl"));

        uiPoolDataProvider = UiPoolDataProviderV3(deployedContracts.readAddress(".uiPoolDataProvider"));
        uiIncentiveDataProvider = UiIncentiveDataProviderV3(deployedContracts.readAddress(".uiIncentiveDataProvider"));
        wethGateway = WrappedTokenGatewayV3(payable(deployedContracts.readAddress(".wethGateway")));
        walletBalanceProvider = WalletBalanceProvider(payable(deployedContracts.readAddress(".walletBalanceProvider")));

        assets = pool.getReservesList();
    }

    function getLTV(address asset) internal view returns (uint256) {
        DataTypes.ReserveData memory data = pool.getReserveData(asset);
        return ReserveConfiguration.getLtv(data.configuration);
    }

    function getAToken(address asset) internal view returns (IERC20) {
        DataTypes.ReserveData memory data = pool.getReserveData(asset);
        return IERC20(data.aTokenAddress);
    }

    function test_spark_deploy_poolAddressesProviderRegistry() public {
        assertEq(poolAddressesProviderRegistry.owner(), admin);
        address[] memory providersList = poolAddressesProviderRegistry.getAddressesProvidersList();
        assertEq(providersList.length, 1);
        assertEq(providersList[0], address(poolAddressesProvider));
        assertEq(poolAddressesProviderRegistry.getAddressesProviderAddressById(1),  address(poolAddressesProvider));
        assertEq(poolAddressesProviderRegistry.getAddressesProviderIdByAddress(address(poolAddressesProvider)), 1);
    }

    function test_spark_deploy_poolAddressesProvider() public {
        assertEq(poolAddressesProvider.owner(), admin);
        assertEq(poolAddressesProvider.getMarketId(), "Spark Protocol");
        assertEq(poolAddressesProvider.getPool(), address(pool));
        assertEq(poolAddressesProvider.getPoolConfigurator(), address(poolConfigurator));
        assertEq(poolAddressesProvider.getPriceOracle(), address(aaveOracle));
        assertEq(poolAddressesProvider.getACLManager(), address(aclManager));
        assertEq(poolAddressesProvider.getACLAdmin(), admin);
        assertEq(poolAddressesProvider.getPriceOracleSentinel(), address(0));
        assertEq(poolAddressesProvider.getPoolDataProvider(), address(protocolDataProvider));
    }

    function test_spark_deploy_aclManager() public {
        // NOTE: Also verify that no other address than the admin address has any role (verify with events)
        assertEq(address(aclManager.ADDRESSES_PROVIDER()), address(poolAddressesProvider));
        assertTrue(aclManager.hasRole(aclManager.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(!aclManager.hasRole(aclManager.DEFAULT_ADMIN_ROLE(), deployer));
        assertEq(aclManager.getRoleAdmin(aclManager.POOL_ADMIN_ROLE()), aclManager.DEFAULT_ADMIN_ROLE());
        assertTrue(aclManager.hasRole(aclManager.POOL_ADMIN_ROLE(), admin));
        assertTrue(!aclManager.hasRole(aclManager.POOL_ADMIN_ROLE(), deployer));
        assertEq(aclManager.getRoleAdmin(aclManager.EMERGENCY_ADMIN_ROLE()), aclManager.DEFAULT_ADMIN_ROLE());
        if (block.chainid == 1) assertTrue(aclManager.hasRole(aclManager.EMERGENCY_ADMIN_ROLE(), admin));     // FIXME missing on GOERLI
        assertEq(aclManager.getRoleAdmin(aclManager.RISK_ADMIN_ROLE()), aclManager.DEFAULT_ADMIN_ROLE());
        assertEq(aclManager.getRoleAdmin(aclManager.FLASH_BORROWER_ROLE()), aclManager.DEFAULT_ADMIN_ROLE());
        assertEq(aclManager.getRoleAdmin(aclManager.BRIDGE_ROLE()), aclManager.DEFAULT_ADMIN_ROLE());
        assertEq(aclManager.getRoleAdmin(aclManager.ASSET_LISTING_ADMIN_ROLE()), aclManager.DEFAULT_ADMIN_ROLE());
    }

    function test_spark_deploy_protocolDataProvider() public {
        assertEq(address(protocolDataProvider.ADDRESSES_PROVIDER()), address(poolAddressesProvider));
    }

    function test_spark_deploy_poolConfigurator() public {
        assertEq(poolConfigurator.CONFIGURATOR_REVISION(), 1);
        assertImplementation(address(poolAddressesProvider), address(poolConfigurator), address(poolConfiguratorImpl));
    }

    function assertImplementation(address _admin, address proxy, address implementation) internal {
        vm.prank(_admin);
        assertEq(InitializableAdminUpgradeabilityProxy(payable(proxy)).implementation(), implementation);
    }

    function test_spark_deploy_pool() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), 17414000);

        assertEq(pool.POOL_REVISION(), 1);
        assertEq(address(pool.ADDRESSES_PROVIDER()), address(poolAddressesProvider));
        assertEq(pool.MAX_STABLE_RATE_BORROW_SIZE_PERCENT(), 0.25e4);
        assertEq(pool.BRIDGE_PROTOCOL_FEE(), 0);
        assertEq(pool.FLASHLOAN_PREMIUM_TOTAL(), 0);
        assertEq(pool.FLASHLOAN_PREMIUM_TO_PROTOCOL(), 0);
        assertEq(pool.MAX_NUMBER_RESERVES(), 128);
        assertImplementation(address(poolAddressesProvider), address(pool), address(poolImpl));
        address[] memory reserves = pool.getReservesList();
        assertEq(reserves.length, 7);
        assertEq(reserves[0], address(dai));
        assertEq(reserves[1], address(sdai));
        assertEq(reserves[2], address(usdc));
        assertEq(reserves[3], address(weth));
        assertEq(reserves[4], address(wsteth));
        assertEq(reserves[5], address(wbtc));
        {
            DataTypes.ReserveData memory data = pool.getReserveData(address(dai));
            assertEq(data.aTokenAddress, deployedContracts.readAddress(".DAI_aToken"));
            assertImplementation(address(poolConfigurator), address(data.aTokenAddress), address(aTokenImpl));
            assertEq(data.stableDebtTokenAddress, deployedContracts.readAddress(".DAI_stableDebtToken"));
            assertImplementation(address(poolConfigurator), address(data.stableDebtTokenAddress), address(stableDebtTokenImpl));
            assertEq(data.variableDebtTokenAddress, deployedContracts.readAddress(".DAI_variableDebtToken"));
            assertImplementation(address(poolConfigurator), address(data.variableDebtTokenAddress), address(variableDebtTokenImpl));
            assertEq(data.interestRateStrategyAddress, deployedContracts.readAddress(".DAI_interestRateStrategy"));
            DataTypes.ReserveConfigurationMap memory cfg = data.configuration;
            assertEq(cfg.getLtv(), 7400);
            assertEq(cfg.getLiquidationThreshold(), 7600);
            assertEq(cfg.getLiquidationBonus(), 10450);
            assertEq(cfg.getDecimals(), 18);
            assertEq(cfg.getActive(), true);
            assertEq(cfg.getFrozen(), false);
            assertEq(cfg.getPaused(), false);
            assertEq(cfg.getBorrowableInIsolation(), true);
            assertEq(cfg.getSiloedBorrowing(), false);
            assertEq(cfg.getBorrowingEnabled(), true);
            assertEq(cfg.getStableRateBorrowingEnabled(), false);
            assertEq(cfg.getReserveFactor(), 0);
            assertEq(cfg.getBorrowCap(), 0);
            assertEq(cfg.getSupplyCap(), 0);
            assertEq(cfg.getDebtCeiling(), 0);
            assertEq(cfg.getLiquidationProtocolFee(), 2000);
            assertEq(cfg.getUnbackedMintCap(), 0);
            assertEq(cfg.getEModeCategory(), 0);
            assertEq(cfg.getFlashLoanEnabled(), true);
        }
        {
            DataTypes.ReserveData memory data = pool.getReserveData(address(sdai));
            assertEq(data.aTokenAddress, deployedContracts.readAddress(".sDAI_aToken"));
            assertImplementation(address(poolConfigurator), address(data.aTokenAddress), address(aTokenImpl));
            assertEq(data.stableDebtTokenAddress, deployedContracts.readAddress(".sDAI_stableDebtToken"));
            assertImplementation(address(poolConfigurator), address(data.stableDebtTokenAddress), address(stableDebtTokenImpl));
            assertEq(data.variableDebtTokenAddress, deployedContracts.readAddress(".sDAI_variableDebtToken"));
            assertImplementation(address(poolConfigurator), address(data.variableDebtTokenAddress), address(variableDebtTokenImpl));
            assertEq(data.interestRateStrategyAddress, deployedContracts.readAddress(".sDAI_interestRateStrategy"));
            DataTypes.ReserveConfigurationMap memory cfg = data.configuration;
            assertEq(cfg.getLtv(), 7400);
            assertEq(cfg.getLiquidationThreshold(), 7600);
            assertEq(cfg.getLiquidationBonus(), 10450);
            assertEq(cfg.getDecimals(), 18);
            assertEq(cfg.getActive(), true);
            assertEq(cfg.getFrozen(), false);
            assertEq(cfg.getPaused(), false);
            assertEq(cfg.getBorrowableInIsolation(), false);
            assertEq(cfg.getSiloedBorrowing(), false);
            assertEq(cfg.getBorrowingEnabled(), false);
            assertEq(cfg.getStableRateBorrowingEnabled(), false);
            assertEq(cfg.getReserveFactor(), 1000);
            assertEq(cfg.getBorrowCap(), 0);
            assertEq(cfg.getSupplyCap(), 0);
            assertEq(cfg.getDebtCeiling(), 0);
            assertEq(cfg.getLiquidationProtocolFee(), 2000);
            assertEq(cfg.getUnbackedMintCap(), 0);
            assertEq(cfg.getEModeCategory(), 0);
            assertEq(cfg.getFlashLoanEnabled(), true);

            // Interest strategy
            DefaultReserveInterestRateStrategy st = DefaultReserveInterestRateStrategy(data.interestRateStrategyAddress);
            assertEq(st.OPTIMAL_USAGE_RATIO(), RAY);
            assertEq(st.OPTIMAL_STABLE_TO_TOTAL_DEBT_RATIO(), 0);
            assertEq(st.MAX_EXCESS_USAGE_RATIO(), 0);
            assertEq(st.MAX_EXCESS_STABLE_TO_TOTAL_DEBT_RATIO(), RAY);
            assertEq(address(st.ADDRESSES_PROVIDER()), address(poolAddressesProvider));
            assertEq(st.getVariableRateSlope1(), 0);
            assertEq(st.getVariableRateSlope2(), 0);
            assertEq(st.getStableRateSlope1(), 0);
            assertEq(st.getStableRateSlope2(), 0);
            assertEq(st.getStableRateExcessOffset(), 0);
            assertEq(st.getBaseStableBorrowRate(), 0);
            assertEq(st.getBaseVariableBorrowRate(), 1 * RAY / 100);
            assertEq(st.getMaxVariableBorrowRate(), 1 * RAY / 100);
        }
        {
            DataTypes.ReserveData memory data = pool.getReserveData(address(usdc));
            assertEq(data.aTokenAddress, deployedContracts.readAddress(".USDC_aToken"));
            assertImplementation(address(poolConfigurator), address(data.aTokenAddress), address(aTokenImpl));
            assertEq(data.stableDebtTokenAddress, deployedContracts.readAddress(".USDC_stableDebtToken"));
            assertImplementation(address(poolConfigurator), address(data.stableDebtTokenAddress), address(stableDebtTokenImpl));
            assertEq(data.variableDebtTokenAddress, deployedContracts.readAddress(".USDC_variableDebtToken"));
            assertImplementation(address(poolConfigurator), address(data.variableDebtTokenAddress), address(variableDebtTokenImpl));
            assertEq(data.interestRateStrategyAddress, deployedContracts.readAddress(".USDC_interestRateStrategy"));
            DataTypes.ReserveConfigurationMap memory cfg = data.configuration;
            assertEq(cfg.getLtv(), 0);
            assertEq(cfg.getLiquidationThreshold(), 0);
            assertEq(cfg.getLiquidationBonus(), 0);
            assertEq(cfg.getDecimals(), 6);
            assertEq(cfg.getActive(), true);
            assertEq(cfg.getFrozen(), false);
            assertEq(cfg.getPaused(), false);
            assertEq(cfg.getBorrowableInIsolation(), false);
            assertEq(cfg.getSiloedBorrowing(), false);
            assertEq(cfg.getBorrowingEnabled(), false);
            assertEq(cfg.getStableRateBorrowingEnabled(), false);
            assertEq(cfg.getReserveFactor(), 1000);
            assertEq(cfg.getBorrowCap(), 0);
            assertEq(cfg.getSupplyCap(), 0);
            assertEq(cfg.getDebtCeiling(), 0);
            assertEq(cfg.getLiquidationProtocolFee(), 0);
            assertEq(cfg.getUnbackedMintCap(), 0);
            assertEq(cfg.getEModeCategory(), 0);
            assertEq(cfg.getFlashLoanEnabled(), true);

            // Interest strategy
            DefaultReserveInterestRateStrategy st = DefaultReserveInterestRateStrategy(data.interestRateStrategyAddress);
            assertEq(st.OPTIMAL_USAGE_RATIO(), RAY);
            assertEq(st.OPTIMAL_STABLE_TO_TOTAL_DEBT_RATIO(), 0);
            assertEq(st.MAX_EXCESS_USAGE_RATIO(), 0);
            assertEq(st.MAX_EXCESS_STABLE_TO_TOTAL_DEBT_RATIO(), RAY);
            assertEq(address(st.ADDRESSES_PROVIDER()), address(poolAddressesProvider));
            assertEq(st.getVariableRateSlope1(), 0);
            assertEq(st.getVariableRateSlope2(), 0);
            assertEq(st.getStableRateSlope1(), 0);
            assertEq(st.getStableRateSlope2(), 0);
            assertEq(st.getStableRateExcessOffset(), 0);
            assertEq(st.getBaseStableBorrowRate(), 0);
            assertEq(st.getBaseVariableBorrowRate(), 1 * RAY / 100);
            assertEq(st.getMaxVariableBorrowRate(), 1 * RAY / 100);
        }
        {
            DataTypes.ReserveData memory data = pool.getReserveData(address(weth));
            assertEq(data.aTokenAddress, deployedContracts.readAddress(".WETH_aToken"));
            assertImplementation(address(poolConfigurator), address(data.aTokenAddress), address(aTokenImpl));
            assertEq(data.stableDebtTokenAddress, deployedContracts.readAddress(".WETH_stableDebtToken"));
            assertImplementation(address(poolConfigurator), address(data.stableDebtTokenAddress), address(stableDebtTokenImpl));
            assertEq(data.variableDebtTokenAddress, deployedContracts.readAddress(".WETH_variableDebtToken"));
            assertImplementation(address(poolConfigurator), address(data.variableDebtTokenAddress), address(variableDebtTokenImpl));
            assertEq(data.interestRateStrategyAddress, deployedContracts.readAddress(".WETH_interestRateStrategy"));
            DataTypes.ReserveConfigurationMap memory cfg = data.configuration;
            assertEq(cfg.getLtv(), 8000);
            assertEq(cfg.getLiquidationThreshold(), 8250);
            assertEq(cfg.getLiquidationBonus(), 10500);
            assertEq(cfg.getDecimals(), 18);
            assertEq(cfg.getActive(), true);
            assertEq(cfg.getFrozen(), false);
            assertEq(cfg.getPaused(), false);
            assertEq(cfg.getBorrowableInIsolation(), false);
            assertEq(cfg.getSiloedBorrowing(), false);
            assertEq(cfg.getBorrowingEnabled(), true);
            assertEq(cfg.getStableRateBorrowingEnabled(), false);
            assertEq(cfg.getReserveFactor(), 1500);
            assertEq(cfg.getBorrowCap(), 1400000);
            assertEq(cfg.getSupplyCap(), 0);
            assertEq(cfg.getDebtCeiling(), 0);
            assertEq(cfg.getLiquidationProtocolFee(), 1000);
            assertEq(cfg.getUnbackedMintCap(), 0);
            assertEq(cfg.getEModeCategory(), 1);
            assertEq(cfg.getFlashLoanEnabled(), true);

            // Interest strategy
            DefaultReserveInterestRateStrategy st = DefaultReserveInterestRateStrategy(data.interestRateStrategyAddress);
            assertEq(st.OPTIMAL_USAGE_RATIO(), 80 * RAY / 100);
            assertEq(st.OPTIMAL_STABLE_TO_TOTAL_DEBT_RATIO(), 0);
            assertEq(st.MAX_EXCESS_USAGE_RATIO(), 20 * RAY / 100);
            assertEq(st.MAX_EXCESS_STABLE_TO_TOTAL_DEBT_RATIO(), RAY);
            assertEq(address(st.ADDRESSES_PROVIDER()), address(poolAddressesProvider));
            assertEq(st.getVariableRateSlope1(), 380 * RAY / 10000);
            assertEq(st.getVariableRateSlope2(), 8000 * RAY / 10000);
            assertEq(st.getStableRateSlope1(), 0);
            assertEq(st.getStableRateSlope2(), 0);
            assertEq(st.getStableRateExcessOffset(), 0);
            assertEq(st.getBaseStableBorrowRate(), 380 * RAY / 10000);
            assertEq(st.getBaseVariableBorrowRate(), 100 * RAY / 10000);
            assertEq(st.getMaxVariableBorrowRate(), 8480 * RAY / 10000);
        }
        {
            DataTypes.ReserveData memory data = pool.getReserveData(address(wsteth));
            assertEq(data.aTokenAddress, deployedContracts.readAddress(".wstETH_aToken"));
            assertImplementation(address(poolConfigurator), address(data.aTokenAddress), address(aTokenImpl));
            assertEq(data.stableDebtTokenAddress, deployedContracts.readAddress(".wstETH_stableDebtToken"));
            assertImplementation(address(poolConfigurator), address(data.stableDebtTokenAddress), address(stableDebtTokenImpl));
            assertEq(data.variableDebtTokenAddress, deployedContracts.readAddress(".wstETH_variableDebtToken"));
            assertImplementation(address(poolConfigurator), address(data.variableDebtTokenAddress), address(variableDebtTokenImpl));
            assertEq(data.interestRateStrategyAddress, deployedContracts.readAddress(".wstETH_interestRateStrategy"));
            DataTypes.ReserveConfigurationMap memory cfg = data.configuration;
            assertEq(cfg.getLtv(), 6850);
            assertEq(cfg.getLiquidationThreshold(), 7950);
            assertEq(cfg.getLiquidationBonus(), 10700);
            assertEq(cfg.getDecimals(), 18);
            assertEq(cfg.getActive(), true);
            assertEq(cfg.getFrozen(), false);
            assertEq(cfg.getPaused(), false);
            assertEq(cfg.getBorrowableInIsolation(), false);
            assertEq(cfg.getSiloedBorrowing(), false);
            assertEq(cfg.getBorrowingEnabled(), true);
            assertEq(cfg.getStableRateBorrowingEnabled(), false);
            assertEq(cfg.getReserveFactor(), 1500);
            assertEq(cfg.getBorrowCap(), 3000);
            assertEq(cfg.getSupplyCap(), 200000);
            assertEq(cfg.getDebtCeiling(), 0);
            assertEq(cfg.getLiquidationProtocolFee(), 1000);
            assertEq(cfg.getUnbackedMintCap(), 0);
            assertEq(cfg.getEModeCategory(), 1);
            assertEq(cfg.getFlashLoanEnabled(), true);

            // Interest strategy
            DefaultReserveInterestRateStrategy st = DefaultReserveInterestRateStrategy(data.interestRateStrategyAddress);
            assertEq(st.OPTIMAL_USAGE_RATIO(), 45 * RAY / 100);
            assertEq(st.OPTIMAL_STABLE_TO_TOTAL_DEBT_RATIO(), 0);
            assertEq(st.MAX_EXCESS_USAGE_RATIO(), 55 * RAY / 100);
            assertEq(st.MAX_EXCESS_STABLE_TO_TOTAL_DEBT_RATIO(), RAY);
            assertEq(address(st.ADDRESSES_PROVIDER()), address(poolAddressesProvider));
            assertEq(st.getVariableRateSlope1(), 450 * RAY / 10000);
            assertEq(st.getVariableRateSlope2(), 8000 * RAY / 10000);
            assertEq(st.getStableRateSlope1(), 0);
            assertEq(st.getStableRateSlope2(), 0);
            assertEq(st.getStableRateExcessOffset(), 0);
            assertEq(st.getBaseStableBorrowRate(), 450 * RAY / 10000);
            assertEq(st.getBaseVariableBorrowRate(), 25 * RAY / 10000);
            assertEq(st.getMaxVariableBorrowRate(), 8475 * RAY / 10000);
        }
        {
            DataTypes.ReserveData memory data = pool.getReserveData(address(wbtc));
            assertEq(data.aTokenAddress, deployedContracts.readAddress(".WBTC_aToken"));
            assertImplementation(address(poolConfigurator), address(data.aTokenAddress), address(aTokenImpl));
            assertEq(data.stableDebtTokenAddress, deployedContracts.readAddress(".WBTC_stableDebtToken"));
            assertImplementation(address(poolConfigurator), address(data.stableDebtTokenAddress), address(stableDebtTokenImpl));
            assertEq(data.variableDebtTokenAddress, deployedContracts.readAddress(".WBTC_variableDebtToken"));
            assertImplementation(address(poolConfigurator), address(data.variableDebtTokenAddress), address(variableDebtTokenImpl));
            assertEq(data.interestRateStrategyAddress, deployedContracts.readAddress(".WBTC_interestRateStrategy"));
            DataTypes.ReserveConfigurationMap memory cfg = data.configuration;
            assertEq(cfg.getLtv(), 7000);
            assertEq(cfg.getLiquidationThreshold(), 7500);
            assertEq(cfg.getLiquidationBonus(), 10625);
            assertEq(cfg.getDecimals(), 8);
            assertEq(cfg.getActive(), true);
            assertEq(cfg.getFrozen(), true);
            assertEq(cfg.getPaused(), false);
            assertEq(cfg.getBorrowableInIsolation(), false);
            assertEq(cfg.getSiloedBorrowing(), false);
            assertEq(cfg.getBorrowingEnabled(), true);
            assertEq(cfg.getStableRateBorrowingEnabled(), false);
            assertEq(cfg.getReserveFactor(), 2000);
            assertEq(cfg.getBorrowCap(), 500);
            assertEq(cfg.getSupplyCap(), 1000);
            assertEq(cfg.getDebtCeiling(), 0);
            assertEq(cfg.getLiquidationProtocolFee(), 1000);
            assertEq(cfg.getUnbackedMintCap(), 0);
            assertEq(cfg.getEModeCategory(), 0);
            assertEq(cfg.getFlashLoanEnabled(), true);

            // Interest strategy
            DefaultReserveInterestRateStrategy st = DefaultReserveInterestRateStrategy(data.interestRateStrategyAddress);
            assertEq(st.OPTIMAL_USAGE_RATIO(), 65 * RAY / 100);
            assertEq(st.OPTIMAL_STABLE_TO_TOTAL_DEBT_RATIO(), 0);
            assertEq(st.MAX_EXCESS_USAGE_RATIO(), 35 * RAY / 100);
            assertEq(st.MAX_EXCESS_STABLE_TO_TOTAL_DEBT_RATIO(), RAY);
            assertEq(address(st.ADDRESSES_PROVIDER()), address(poolAddressesProvider));
            assertEq(st.getVariableRateSlope1(), 800 * RAY / 10000);
            assertEq(st.getVariableRateSlope2(), 30000 * RAY / 10000);
            assertEq(st.getStableRateSlope1(), 0);
            assertEq(st.getStableRateSlope2(), 0);
            assertEq(st.getStableRateExcessOffset(), 0);
            assertEq(st.getBaseStableBorrowRate(), 800 * RAY / 10000);
            assertEq(st.getBaseVariableBorrowRate(), 0);
            assertEq(st.getMaxVariableBorrowRate(), 30800 * RAY / 10000);
        }
        // Efficiency Mode Categories
        {
            DataTypes.EModeCategory memory cat = pool.getEModeCategoryData(1);
            assertEq(cat.ltv, 9000);
            assertEq(cat.liquidationThreshold, 9300);
            assertEq(cat.liquidationBonus, 10100);
            assertEq(cat.priceSource, address(0));
            assertEq(cat.label, "ETH");
        }
    }

    function test_spark_deploy_tokenImpls() public {
        assertEq(address(aTokenImpl.POOL()), address(pool));
        assertEq(address(variableDebtTokenImpl.POOL()), address(pool));
        assertEq(address(stableDebtTokenImpl.POOL()), address(pool));
    }

    function test_spark_deploy_treasury() public {
        assertEq(address(treasuryController.owner()), admin);
        assertEq(treasury.REVISION(), 1);
        assertEq(daiTreasury.REVISION(), 1);
        assertEq(treasury.getFundsAdmin(), address(treasuryController));
        assertEq(daiTreasury.getFundsAdmin(), address(treasuryController));
        assertImplementation(admin, address(treasury), address(treasuryImpl));
        assertImplementation(admin, address(daiTreasury), address(daiTreasuryImpl));
        assertEq(address(treasuryImpl), address(daiTreasuryImpl));

        // Test that funds can be extracted
        GodMode.setBalance(address(dai), address(treasury), 1000 ether);
        vm.prank(admin);
        treasuryController.transfer(address(treasury), dai, address(this), 1000 ether);
        assertEq(dai.balanceOf(address(this)), 1000 ether);
        GodMode.setBalance(address(dai), address(daiTreasury), 1000 ether);
        vm.prank(admin);
        treasuryController.transfer(address(daiTreasury), dai, address(this), 1000 ether);
        assertEq(dai.balanceOf(address(this)), 2000 ether);
    }

    function test_spark_deploy_incentives() public {
        assertEq(address(emissionManager.owner()), admin);
        if (block.chainid == 1) assertEq(address(emissionManager.getRewardsController()), address(incentives));     // FIXME missing on GOERLI
        assertEq(incentives.REVISION(), 1);
        assertEq(incentives.EMISSION_MANAGER(), address(emissionManager));
        assertImplementation(admin, address(incentives), address(incentivesImpl));
    }

    function test_spark_deploy_misc_contracts() public {
        assertEq(address(uiPoolDataProvider.networkBaseTokenPriceInUsdProxyAggregator()), deployedContracts.readAddress(".WETH_oracle"));
        assertEq(address(uiPoolDataProvider.marketReferenceCurrencyPriceInUsdProxyAggregator()), deployedContracts.readAddress(".WETH_oracle"));
        assertEq(wethGateway.owner(), admin);
        assertEq(wethGateway.getWETHAddress(), address(weth));
    }

    function test_spark_deploy_oracles() public {
        assertEq(address(aaveOracle.ADDRESSES_PROVIDER()), address(poolAddressesProvider));
        assertEq(aaveOracle.BASE_CURRENCY(), address(0));
        assertEq(aaveOracle.BASE_CURRENCY_UNIT(), 10 ** 8);
        assertEq(aaveOracle.getFallbackOracle(), address(0));

        assertEq(aaveOracle.getSourceOfAsset(address(dai)), deployedContracts.readAddress(".DAI_oracle"));
        assertEq(SavingsDaiOracle(aaveOracle.getSourceOfAsset(address(sdai))).POT_ADDRESS(), address(dss.pot));
        assertEq(SavingsDaiOracle(aaveOracle.getSourceOfAsset(address(sdai))).DAI_PRICE_FEED_ADDRESS(), deployedContracts.readAddress(".DAI_oracle"));
        assertEq(aaveOracle.getSourceOfAsset(address(usdc)), deployedContracts.readAddress(".USDC_oracle"));
        assertEq(aaveOracle.getSourceOfAsset(address(weth)), deployedContracts.readAddress(".WETH_oracle"));
        assertEq(aaveOracle.getSourceOfAsset(address(wsteth)), deployedContracts.readAddress(".wstETH_oracle"));
        assertEq(aaveOracle.getSourceOfAsset(address(wbtc)), deployedContracts.readAddress(".WBTC_oracle"));

        // Some basic sanity checks - but should double check manually
        assertGe(aaveOracle.getAssetPrice(address(dai)), 99000000);
        assertLe(aaveOracle.getAssetPrice(address(dai)), 101000000);
        assertGe(aaveOracle.getAssetPrice(address(sdai)), 100000000);
        assertLe(aaveOracle.getAssetPrice(address(sdai)), 105000000);
        assertGe(aaveOracle.getAssetPrice(address(usdc)), 99000000);
        assertLe(aaveOracle.getAssetPrice(address(usdc)), 101000000);
        assertGe(aaveOracle.getAssetPrice(address(weth)), 500 * 10 ** 8);
        assertLe(aaveOracle.getAssetPrice(address(weth)), 5000 * 10 ** 8);
        assertGe(aaveOracle.getAssetPrice(address(wsteth)), 500 * 10 ** 8);
        assertLe(aaveOracle.getAssetPrice(address(wsteth)), 5000 * 10 ** 8);
        assertGe(aaveOracle.getAssetPrice(address(wbtc)), 10000 * 10 ** 8);
        assertLe(aaveOracle.getAssetPrice(address(wbtc)), 100000 * 10 ** 8);
    }

    function test_implementation_contracts_initialized() public {
        vm.expectRevert("Contract instance has already been initialized");
        poolConfiguratorImpl.initialize(poolAddressesProvider);
        vm.expectRevert("Contract instance has already been initialized");
        poolImpl.initialize(poolAddressesProvider);
        vm.expectRevert("Contract instance has already been initialized");
        treasuryImpl.initialize(address(0));
        vm.expectRevert("Contract instance has already been initialized");
        daiTreasuryImpl.initialize(address(0));
        vm.expectRevert("Contract instance has already been initialized");
        incentivesImpl.initialize(address(0));
        vm.expectRevert("Contract instance has already been initialized");
        aTokenImpl.initialize(pool, address(0), address(0), IAaveIncentivesController(address(0)), 0, "SPTOKEN_IMPL", "SPTOKEN_IMPL", "");
        vm.expectRevert("Contract instance has already been initialized");
        stableDebtTokenImpl.initialize(pool, address(0), IAaveIncentivesController(address(0)), 0, "STABLE_DEBT_TOKEN_IMPL", "STABLE_DEBT_TOKEN_IMPL", "");
        vm.expectRevert("Contract instance has already been initialized");
        variableDebtTokenImpl.initialize(pool, address(0), IAaveIncentivesController(address(0)), 0, "VARIABLE_DEBT_TOKEN_IMPL", "VARIABLE_DEBT_TOKEN_IMPL", "");
    }

}
