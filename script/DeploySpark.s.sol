// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

import "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {ScriptTools} from "dss-test/ScriptTools.sol";

import {InitializableAdminUpgradeabilityProxy} from 'aave-v3-core/contracts/dependencies/openzeppelin/upgradeability/InitializableAdminUpgradeabilityProxy.sol';

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

import {IAaveIncentivesController} from "aave-v3-core/contracts/interfaces/IAaveIncentivesController.sol";

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

contract DeploySpark is Script {

    string constant NAME = "spark";

    using stdJson for string;
    using ScriptTools for string;

    uint256 constant RAY = 10 ** 27;

    string config;

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

    UiPoolDataProviderV3 uiPoolDataProvider;
    UiIncentiveDataProviderV3 uiIncentiveDataProvider;
    WrappedTokenGatewayV3 wethGateway;
    WalletBalanceProvider walletBalanceProvider;

    function run() external {
        //vm.createSelectFork(vm.envString("ETH_RPC_URL"));     // Multi-chain not supported in Foundry yet (use CLI arg for now)
        vm.setEnv("FOUNDRY_ROOT_CHAINID", vm.toString(block.chainid));

        config = ScriptTools.loadConfig("config");

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
        poolConfigurator.updateFlashloanPremiumTotal(0);    // Flash loans are free

        IEACAggregatorProxy proxy = IEACAggregatorProxy(config.readAddress(".nativeTokenOracle"));
        uiPoolDataProvider = new UiPoolDataProviderV3(proxy, proxy);
        uiIncentiveDataProvider = new UiIncentiveDataProviderV3();
        wethGateway = new WrappedTokenGatewayV3(config.readAddress(".nativeToken"), admin, IPool(address(pool)));
        walletBalanceProvider = new WalletBalanceProvider();

        // Setup oracles
        address[] memory assets;
        address[] memory oracles;
        aaveOracle = new AaveOracle(
            poolAddressesProvider,
            assets,
            oracles,
            address(0),
            address(0),     // USD
            1e8
        );
        poolAddressesProvider.setPriceOracle(address(aaveOracle));

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
    }

    function createCollector(address _admin) internal returns (Collector collector, address impl) {
        InitializableAdminUpgradeabilityProxy proxy = new InitializableAdminUpgradeabilityProxy();
        collector = Collector(address(proxy));
        impl = address(collectorImpl);
        proxy.initialize(
            address(collectorImpl),
            _admin,
            abi.encodeWithSignature("initialize(address)", address(treasuryController))
        );
    }

}
