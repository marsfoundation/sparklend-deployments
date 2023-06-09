// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.10;

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

import {DaiInterestRateStrategy} from "../src/DaiInterestRateStrategy.sol";

struct ReserveConfig {
    // Needs to be in alphabetical order to parse correctly
    bool borrow;
    uint256 borrowCap;
    uint256 decimals;
    uint256 eModeCategory;
    uint256 irBaseVariableBorrowRate;
    uint256 irOptimalUsageRatio;
    uint256 irVariableRateSlope1;
    uint256 irVariableRateSlope2;
    uint256 liquidationBonus;
    uint256 liquidationProtocolFee;
    uint256 liquidationThreshold;
    uint256 ltv;
    string name;
    address oracle;
    uint256 oracleMockPrice;
    uint256 reserveFactor;
    uint256 supplyCap;
    address token;
}

struct EModeConfig {
    // Needs to be in alphabetical order to parse correctly
    uint256 categoryId;
    string label;
    uint256 liquidationBonus;
    uint256 liquidationThreshold;
    uint256 ltv;
    address oracle;
}

contract DeploySpark is Script {

    string constant NAME = "spark";

    using stdJson for string;
    using ScriptTools for string;

    uint256 constant RAY = 10 ** 27;

    string config;
    DssInstance dss;

    address admin;
    address deployer;

    PoolAddressesProviderRegistry registry;
    PoolAddressesProvider poolAddressesProvider;
    AaveProtocolDataProvider protocolDataProvider;
    PoolConfigurator poolConfigurator;
    Pool pool;
    ACLManager aclManager;
    AaveOracle aaveOracle;

    AToken aTokenImpl;
    StableDebtToken stableDebtTokenImpl;
    VariableDebtToken variableDebtTokenImpl;

    Collector treasury;
    address treasuryImpl;
    CollectorController treasuryController;
    RewardsController incentives;
    EmissionManager emissionManager;
    Collector collectorImpl;

    address weth;
    address wethOracle;
    UiPoolDataProviderV3 uiPoolDataProvider;
    UiIncentiveDataProviderV3 uiIncentiveDataProvider;
    WrappedTokenGatewayV3 wethGateway;
    WalletBalanceProvider walletBalanceProvider;

    ConfiguratorInputTypes.InitReserveInput[] reserves;
    address[] assets;
    address[] assetOracleSources;
    DataTypes.ReserveData reserveData;

    function run() external {
        //vm.createSelectFork(vm.envString("ETH_RPC_URL"));     // Multi-chain not supported in Foundry yet (use CLI arg for now)
        vm.setEnv("FOUNDRY_ROOT_CHAINID", vm.toString(block.chainid));

        config = ScriptTools.loadConfig("config");
        dss = MCD.loadFromChainlog(config.readAddress(".chainlog"));

        admin = config.readAddress(".admin");
        deployer = msg.sender;

        vm.startBroadcast();
        registry = new PoolAddressesProviderRegistry(deployer);
        poolAddressesProvider = new PoolAddressesProvider(config.readString(".marketId"), deployer);
        poolAddressesProvider.setACLAdmin(deployer);
        protocolDataProvider = new AaveProtocolDataProvider(poolAddressesProvider);
        PoolConfigurator _poolConfigurator = new PoolConfigurator();
        _poolConfigurator.initialize(poolAddressesProvider);
        Pool _pool = new Pool(poolAddressesProvider);
        _pool.initialize(poolAddressesProvider);
        aclManager = new ACLManager(poolAddressesProvider);
        aclManager.addPoolAdmin(deployer);
        registry.registerAddressesProvider(address(poolAddressesProvider), 1);

        poolAddressesProvider.setPoolDataProvider(address(protocolDataProvider));
        poolAddressesProvider.setPoolImpl(address(_pool));
        pool = Pool(poolAddressesProvider.getPool());
        poolAddressesProvider.setPoolConfiguratorImpl(address(_poolConfigurator));
        poolConfigurator = PoolConfigurator(poolAddressesProvider.getPoolConfigurator());
        poolAddressesProvider.setACLManager(address(aclManager));

        aTokenImpl = new AToken(pool);
        aTokenImpl.initialize(pool, address(0), address(0), IAaveIncentivesController(address(0)), 0, "SPTOKEN_IMPL", "SPTOKEN_IMPL", "");
        stableDebtTokenImpl = new StableDebtToken(pool);
        stableDebtTokenImpl.initialize(pool, address(0), IAaveIncentivesController(address(0)), 0, "STABLE_DEBT_TOKEN_IMPL", "STABLE_DEBT_TOKEN_IMPL", "");
        variableDebtTokenImpl = new VariableDebtToken(pool);
        variableDebtTokenImpl.initialize(pool, address(0), IAaveIncentivesController(address(0)), 0, "VARIABLE_DEBT_TOKEN_IMPL", "VARIABLE_DEBT_TOKEN_IMPL", "");

        treasuryController = new CollectorController(admin);
        collectorImpl = new Collector();
        collectorImpl.initialize(address(0));
        (treasury, treasuryImpl) = createCollector(admin);

        InitializableAdminUpgradeabilityProxy incentivesProxy = new InitializableAdminUpgradeabilityProxy();
        incentives = RewardsController(address(incentivesProxy));
        emissionManager = new EmissionManager(deployer);
        RewardsController rewardsController = new RewardsController(address(emissionManager));
        rewardsController.initialize(address(0));
        incentivesProxy.initialize(
            address(rewardsController),
            admin,
            abi.encodeWithSignature("initialize(address)", address(emissionManager))
        );
        emissionManager.setRewardsController(address(incentives));

        // Init reserves
        ReserveConfig[] memory reserveConfigs = parseReserves();
        for (uint256 i = 0; i < reserveConfigs.length; i++) {
            ReserveConfig memory cfg = reserveConfigs[i];

            if (cfg.name.eq("WETH")) {
                weth = cfg.token;
                wethOracle = cfg.oracle;
            }

            require(IERC20Detailed(address(cfg.token)).symbol().eq(cfg.name), "Token name doesn't match symbol");

            reserves.push(makeReserve(
                IERC20Detailed(address(cfg.token)),
                cfg.name.eq("DAI") ?
                    IReserveInterestRateStrategy(new DaiInterestRateStrategy(
                        address(dss.vat),
                        address(dss.pot),
                        config.readString(".ilk").stringToBytes32(),
                        RAY,
                        0,
                        0,
                        75 * RAY / 100,  // 75%
                        0
                    )) :
                    IReserveInterestRateStrategy(new DefaultReserveInterestRateStrategy(
                        poolAddressesProvider,
                        cfg.irOptimalUsageRatio * 1e23,
                        cfg.irBaseVariableBorrowRate * 1e23,
                        cfg.irVariableRateSlope1 * 1e23,
                        cfg.irVariableRateSlope2 * 1e23,
                        0,
                        0,
                        0,
                        0,
                        0
                    ))
            ));
            assets.push(address(cfg.token));
            assetOracleSources.push(address(cfg.oracle));
        }
        poolConfigurator.initReserves(reserves);
        poolConfigurator.updateFlashloanPremiumTotal(0);    // Flash loans are free

        IEACAggregatorProxy proxy = IEACAggregatorProxy(wethOracle);
        uiPoolDataProvider = new UiPoolDataProviderV3(proxy, proxy);
        uiIncentiveDataProvider = new UiIncentiveDataProviderV3();
        wethGateway = new WrappedTokenGatewayV3(weth, admin, IPool(address(pool)));
        walletBalanceProvider = new WalletBalanceProvider();

        // Setup oracles
        aaveOracle = new AaveOracle(
            poolAddressesProvider,
            assets,
            assetOracleSources,
            address(0),
            address(0),     // USD
            1e8
        );
        poolAddressesProvider.setPriceOracle(address(aaveOracle));

        // Setup e-mode categories
        setupEModeCategories();

        // Setup reserves
        for (uint256 i = 0; i < reserveConfigs.length; i++) {
            ReserveConfig memory cfg = reserveConfigs[i];

            poolConfigurator.setReserveBorrowing(address(cfg.token), cfg.borrow);
            poolConfigurator.configureReserveAsCollateral({
                asset: address(cfg.token), 
                ltv: cfg.ltv,
                liquidationThreshold: cfg.liquidationThreshold,
                liquidationBonus: cfg.liquidationBonus
            });
            poolConfigurator.setReserveFactor(address(cfg.token), cfg.reserveFactor);
            poolConfigurator.setAssetEModeCategory(address(cfg.token), uint8(cfg.eModeCategory));
            poolConfigurator.setReserveFlashLoaning(address(cfg.token), true);
            if (cfg.supplyCap != 0) poolConfigurator.setSupplyCap(address(cfg.token), cfg.supplyCap);
            if (cfg.borrowCap != 0) poolConfigurator.setBorrowCap(address(cfg.token), cfg.borrowCap);
            if (cfg.liquidationProtocolFee != 0) poolConfigurator.setLiquidationProtocolFee(address(cfg.token), cfg.liquidationProtocolFee);
        }

        // Change all ownership to admin
        aclManager.addEmergencyAdmin(admin);
        aclManager.addPoolAdmin(admin);
        aclManager.removePoolAdmin(deployer);
        aclManager.grantRole(aclManager.DEFAULT_ADMIN_ROLE(), admin);
        aclManager.revokeRole(aclManager.DEFAULT_ADMIN_ROLE(), deployer);
        poolAddressesProvider.setACLAdmin(admin);
        poolAddressesProvider.transferOwnership(admin);
        registry.transferOwnership(admin);
        emissionManager.transferOwnership(admin);

        vm.stopBroadcast();

        ScriptTools.exportContract(NAME, "admin", admin);
        ScriptTools.exportContract(NAME, "deployer", deployer);
        ScriptTools.exportContract(NAME, "poolAddressesProviderRegistry", address(registry));
        ScriptTools.exportContract(NAME, "poolAddressesProvider", address(poolAddressesProvider));
        ScriptTools.exportContract(NAME, "protocolDataProvider", address(protocolDataProvider));
        ScriptTools.exportContract(NAME, "poolConfigurator", address(poolConfigurator));
        ScriptTools.exportContract(NAME, "poolConfiguratorImpl", address(_poolConfigurator));
        ScriptTools.exportContract(NAME, "pool", address(pool));
        ScriptTools.exportContract(NAME, "poolImpl", address(_pool));
        ScriptTools.exportContract(NAME, "aclManager", address(aclManager));
        ScriptTools.exportContract(NAME, "aaveOracle", address(aaveOracle));
        ScriptTools.exportContract(NAME, "aTokenImpl", address(aTokenImpl));
        ScriptTools.exportContract(NAME, "stableDebtTokenImpl", address(stableDebtTokenImpl));
        ScriptTools.exportContract(NAME, "variableDebtTokenImpl", address(variableDebtTokenImpl));
        ScriptTools.exportContract(NAME, "treasury", address(treasury));
        ScriptTools.exportContract(NAME, "treasuryImpl", address(treasuryImpl));
        ScriptTools.exportContract(NAME, "treasuryController", address(treasuryController));
        ScriptTools.exportContract(NAME, "incentives", address(incentives));
        ScriptTools.exportContract(NAME, "incentivesImpl", address(rewardsController));
        ScriptTools.exportContract(NAME, "emissionManager", address(emissionManager));
        ScriptTools.exportContract(NAME, "uiPoolDataProvider", address(uiPoolDataProvider));
        ScriptTools.exportContract(NAME, "uiIncentiveDataProvider", address(uiIncentiveDataProvider));
        ScriptTools.exportContract(NAME, "wethGateway", address(wethGateway));
        ScriptTools.exportContract(NAME, "walletBalanceProvider", address(walletBalanceProvider));
        for (uint256 i = 0; i < assets.length; i++) {
            reserveData = pool.getReserveData(assets[i]);
            ScriptTools.exportContract(NAME, string(abi.encodePacked(reserveConfigs[i].name, "_token")), reserveConfigs[i].token);
            ScriptTools.exportContract(NAME, string(abi.encodePacked(reserveConfigs[i].name, "_oracle")), reserveConfigs[i].oracle);
            ScriptTools.exportContract(NAME, string(abi.encodePacked(reserveConfigs[i].name, "_aToken")), address(reserveData.aTokenAddress));
            ScriptTools.exportContract(NAME, string(abi.encodePacked(reserveConfigs[i].name, "_stableDebtToken")), address(reserveData.stableDebtTokenAddress));
            ScriptTools.exportContract(NAME, string(abi.encodePacked(reserveConfigs[i].name, "_variableDebtToken")), address(reserveData.variableDebtTokenAddress));
            ScriptTools.exportContract(NAME, string(abi.encodePacked(reserveConfigs[i].name, "_interestRateStrategy")), address(reserveData.interestRateStrategyAddress));
        }
    }

    function parseReserves() internal view returns (ReserveConfig[] memory) {
        return abi.decode(vm.parseJson(config, ".reserves"), (ReserveConfig[]));
    }

    function setupEModeCategories() internal {
        EModeConfig[] memory emodes = abi.decode(vm.parseJson(config, ".emodeCategories"), (EModeConfig[]));
        for (uint256 i = 0; i < emodes.length; i++) {
            EModeConfig memory emode = emodes[i];
            poolConfigurator.setEModeCategory({
                categoryId: uint8(emode.categoryId),
                ltv: uint16(emode.ltv),
                liquidationThreshold: uint16(emode.liquidationThreshold),
                liquidationBonus: uint16(emode.liquidationBonus),
                oracle: emode.oracle,
                label: emode.label
            });
        }
    }

    function makeReserve(
        IERC20Detailed token,
        IReserveInterestRateStrategy strategy
    ) internal view returns (ConfiguratorInputTypes.InitReserveInput memory) {
        ConfiguratorInputTypes.InitReserveInput memory input;
        input.aTokenImpl = address(aTokenImpl);
        input.stableDebtTokenImpl = address(stableDebtTokenImpl);
        input.variableDebtTokenImpl = address(variableDebtTokenImpl);
        input.underlyingAssetDecimals = token.decimals();
        input.interestRateStrategyAddress = address(strategy);
        input.underlyingAsset = address(token);
        input.treasury = address(treasury);
        input.incentivesController = address(0);
        input.aTokenName = string(string.concat("Spark ", bytes(token.symbol())));
        input.aTokenSymbol = string(string.concat("sp", bytes(token.symbol())));
        input.variableDebtTokenName = string(string.concat("Spark Variable Debt ", bytes(token.symbol())));
        input.variableDebtTokenSymbol = string(string.concat("variableDebt", bytes(token.symbol())));
        input.stableDebtTokenName = string(string.concat("Spark Stable Debt ", bytes(token.symbol())));
        input.stableDebtTokenSymbol = string(string.concat("stableDebt", bytes(token.symbol())));
        input.params = "";
        return input;
    }

    function createCollector(address admin) internal returns (Collector collector, address impl) {
        InitializableAdminUpgradeabilityProxy proxy = new InitializableAdminUpgradeabilityProxy();
        collector = Collector(address(proxy));
        impl = address(collectorImpl);
        proxy.initialize(
            address(collectorImpl),
            admin,
            abi.encodeWithSignature("initialize(address)", address(treasuryController))
        );
    }

}
