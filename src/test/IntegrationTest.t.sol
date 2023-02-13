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

import {DaiInterestRateStrategy} from "../DaiInterestRateStrategy.sol";
import {SavingsDaiOracle} from "../SavingsDaiOracle.sol";

import {ReserveConfiguration} from "aave-v3-core/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";

interface stETHLike {
    function getTotalShares() external view returns (uint256);
}

interface D3MHubLike {
    function exec(bytes32) external;
}

contract User {

    Pool public pool;

    constructor(Pool _pool) {
        pool = _pool;
    }

    function supply(IERC20 asset, uint256 amount) external {
        asset.approve(address(pool), amount);
        pool.supply(address(asset), amount, address(this), 0);
    }

    function borrow(IERC20 asset, uint256 amount) external {
        pool.borrow(address(asset), amount, 2, 0, address(this));
    }

    function setEMode(uint8 categoryId) external {
        pool.setUserEMode(categoryId);
    }

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
    Pool pool;
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

    User[] users;
    address[] assets;

    D3MHubLike hub;
    IERC20 weth;
    IERC20 wsteth;
    IERC20 wbtc;
    IERC20 dai;
    IERC20 usdc;
    IERC20 sdai;

    function setUp() public {
        config = ScriptTools.readInput("config");
        deployedContracts = ScriptTools.readOutput("spark");
        dss = MCD.loadFromChainlog(config.readAddress(".chainlog"));

        admin = config.readAddress(".admin");
        deployer = deployedContracts.readAddress(".deployer");

        //hub = D3MHubLike(dss.chainlog.getAddress("DIRECT_HUB"));
        if (block.chainid == 1) {
            // Mainnet
            weth = IERC20(dss.chainlog.getAddress("ETH"));
            wsteth = IERC20(dss.chainlog.getAddress("WSTETH"));
            wbtc = IERC20(dss.chainlog.getAddress("WBTC"));
            dai = IERC20(dss.chainlog.getAddress("MCD_DAI"));
            usdc = IERC20(dss.chainlog.getAddress("USDC"));
            sdai = IERC20(0xD8134205b0328F5676aaeFb3B2a0DC15f4029d8C);
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
        pool = Pool(deployedContracts.readAddress(".pool"));
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

        users.push(new User(pool));
        users.push(new User(pool));
        users.push(new User(pool));

        // Mint $100k worth of tokens for each user
        uint256 valuePerAsset = 100_000;
        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            uint256 numTokens = valuePerAsset * (10 ** IERC20Detailed(asset).decimals()) * aaveOracle.BASE_CURRENCY_UNIT() / aaveOracle.getAssetPrice(asset);
            for (uint256 o = 0; o < users.length; o++) {
                asset.setBalance(address(users[o]), numTokens);
            }

            // Have the third user seed all pools
            users[2].supply(IERC20(asset), numTokens);
        }
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
    }

    function test_spark_deploy_pool() public {
        assertEq(pool.POOL_REVISION(), 1);
        assertEq(address(pool.ADDRESSES_PROVIDER()), address(poolAddressesProvider));
        assertEq(pool.MAX_STABLE_RATE_BORROW_SIZE_PERCENT(), 0.25e4);
        assertEq(pool.BRIDGE_PROTOCOL_FEE(), 0);
        assertEq(pool.FLASHLOAN_PREMIUM_TOTAL(), 0);
        assertEq(pool.FLASHLOAN_PREMIUM_TO_PROTOCOL(), 0);
        assertEq(pool.MAX_NUMBER_RESERVES(), 128);
        address[] memory reserves = pool.getReservesList();
        assertEq(reserves.length, 6);
        assertEq(reserves[0], address(dai));
        assertEq(reserves[1], address(sdai));
        assertEq(reserves[2], address(usdc));
        assertEq(reserves[3], address(weth));
        assertEq(reserves[4], address(wsteth));
        assertEq(reserves[5], address(wbtc));
        {
            DataTypes.ReserveData memory data = pool.getReserveData(address(dai));
            assertEq(data.aTokenAddress, deployedContracts.readAddress(".DAI_aToken"));
            assertEq(data.stableDebtTokenAddress, deployedContracts.readAddress(".DAI_stableDebtToken"));
            assertEq(data.variableDebtTokenAddress, deployedContracts.readAddress(".DAI_variableDebtToken"));
            assertEq(data.interestRateStrategyAddress, deployedContracts.readAddress(".DAI_interestRateStrategy"));
            DataTypes.ReserveConfigurationMap memory cfg = data.configuration;
            assertEq(cfg.getLtv(), 7400);
            assertEq(cfg.getLiquidationThreshold(), 7600);
            assertEq(cfg.getLiquidationBonus(), 10450);
            assertEq(cfg.getDecimals(), 18);
            assertEq(cfg.getActive(), false);
            assertEq(cfg.getFrozen(), false);
            assertEq(cfg.getPaused(), false);
            assertEq(cfg.getBorrowableInIsolation(), false);
            assertEq(cfg.getSiloedBorrowing(), false);
            assertEq(cfg.getBorrowingEnabled(), true);
            assertEq(cfg.getStableRateBorrowingEnabled(), false);
            assertEq(cfg.getReserveFactor(), 10000);
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
            assertEq(data.stableDebtTokenAddress, deployedContracts.readAddress(".sDAI_stableDebtToken"));
            assertEq(data.variableDebtTokenAddress, deployedContracts.readAddress(".sDAI_variableDebtToken"));
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
            assertEq(data.stableDebtTokenAddress, deployedContracts.readAddress(".USDC_stableDebtToken"));
            assertEq(data.variableDebtTokenAddress, deployedContracts.readAddress(".USDC_variableDebtToken"));
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
            assertEq(data.stableDebtTokenAddress, deployedContracts.readAddress(".WETH_stableDebtToken"));
            assertEq(data.variableDebtTokenAddress, deployedContracts.readAddress(".WETH_variableDebtToken"));
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
            assertEq(st.getBaseStableBorrowRate(), 0);
            assertEq(st.getBaseVariableBorrowRate(), 100 * RAY / 10000);
            assertEq(st.getMaxVariableBorrowRate(), 8480 * RAY / 10000);
        }
        {
            DataTypes.ReserveData memory data = pool.getReserveData(address(wsteth));
            assertEq(data.aTokenAddress, deployedContracts.readAddress(".wstETH_aToken"));
            assertEq(data.stableDebtTokenAddress, deployedContracts.readAddress(".wstETH_stableDebtToken"));
            assertEq(data.variableDebtTokenAddress, deployedContracts.readAddress(".wstETH_variableDebtToken"));
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
            assertEq(st.getBaseStableBorrowRate(), 0);
            assertEq(st.getBaseVariableBorrowRate(), 25 * RAY / 10000);
            assertEq(st.getMaxVariableBorrowRate(), 8475 * RAY / 10000);
        }
        {
            DataTypes.ReserveData memory data = pool.getReserveData(address(wbtc));
            assertEq(data.aTokenAddress, deployedContracts.readAddress(".WBTC_aToken"));
            assertEq(data.stableDebtTokenAddress, deployedContracts.readAddress(".WBTC_stableDebtToken"));
            assertEq(data.variableDebtTokenAddress, deployedContracts.readAddress(".WBTC_variableDebtToken"));
            assertEq(data.interestRateStrategyAddress, deployedContracts.readAddress(".WBTC_interestRateStrategy"));
            DataTypes.ReserveConfigurationMap memory cfg = data.configuration;
            assertEq(cfg.getLtv(), 7000);
            assertEq(cfg.getLiquidationThreshold(), 7500);
            assertEq(cfg.getLiquidationBonus(), 10625);
            assertEq(cfg.getDecimals(), 8);
            assertEq(cfg.getActive(), true);
            assertEq(cfg.getFrozen(), false);
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
            assertEq(st.getBaseStableBorrowRate(), 0);
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
        vm.prank(admin);
        assertEq(InitializableAdminUpgradeabilityProxy(payable(address(treasury))).implementation(), address(treasuryImpl));
        vm.prank(admin);
        assertEq(InitializableAdminUpgradeabilityProxy(payable(address(daiTreasury))).implementation(), address(daiTreasuryImpl));
        assertEq(address(treasuryImpl), address(daiTreasuryImpl));
    }

    function test_spark_deploy_incentives() public {
        assertEq(address(emissionManager.owner()), admin);
        assertEq(incentives.REVISION(), 1);
        assertEq(incentives.EMISSION_MANAGER(), address(emissionManager));
        vm.prank(admin);
        assertEq(InitializableAdminUpgradeabilityProxy(payable(address(incentives))).implementation(), address(incentivesImpl));
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
        assertEq(aaveOracle.getSourceOfAsset(address(sdai)), deployedContracts.readAddress(".sDAI_oracle"));
        assertEq(SavingsDaiOracle(aaveOracle.getSourceOfAsset(address(sdai))).POT_ADDRESS(), address(dss.pot));
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

    /*function test_d3m() public {
        IERC20 adai = getAToken(address(dai));
        uint256 prevAmount = dai.balanceOf(address(adai));

        hub.exec("DIRECT-SPARK-DAI");

        assertEq(dai.balanceOf(address(adai)), prevAmount + 300_000_000 * 10 ** 18);
    }

    function test_borrow() public {
        User user = users[0];
        IERC20 supplyAsset = weth;
        IERC20 borrowAsset = dai;
        uint256 collateralAmount = supplyAsset.balanceOf(address(user));

        user.supply(supplyAsset, collateralAmount);
        user.borrow(borrowAsset, collateralAmount * getLTV(address(borrowAsset)) / 1e4 * aaveOracle.getAssetPrice(address(supplyAsset)) / aaveOracle.getAssetPrice(address(borrowAsset)));
    }

    function test_emode() public {
        User user = users[0];
        user.setEMode(1);
        user.supply(wsteth, 10 ether);
        user.borrow(weth, 8.5 ether);   // Should be able to borrow up to 85%
    }

    function _divup(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            z = x != 0 ? ((x - 1) / y) + 1 : 0;
        }
    }*/

}
