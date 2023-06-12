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

    using stdJson for string;
    using ScriptTools for string;

    uint256 constant RAY = 10 ** 27;

    string config;
    string instanceId;

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

    Pool poolImpl;

    InitializableAdminUpgradeabilityProxy incentivesProxy;
    RewardsController rewardsController;
    IEACAggregatorProxy proxy;

    function run() external {
        //vm.createSelectFork(vm.envString("ETH_RPC_URL"));     // Multi-chain not supported in Foundry yet (use CLI arg for now)
        instanceId = vm.envOr("INSTANCE_ID", string("primary"));
        vm.setEnv("FOUNDRY_ROOT_CHAINID", vm.toString(block.chainid));

        config = ScriptTools.loadConfig("config");

        admin    = config.readAddress(".admin");
        deployer = msg.sender;

        vm.startBroadcast();

        // 1. Deploy and configure registry and addresses provider

        registry              = new PoolAddressesProviderRegistry(deployer);
        poolAddressesProvider = new PoolAddressesProvider(config.readString(".marketId"), deployer);

        poolAddressesProvider.setACLAdmin(deployer);

        // 2. Deploy and data provider and pool configurator

        protocolDataProvider = new AaveProtocolDataProvider(poolAddressesProvider);
        poolConfigurator     = new PoolConfigurator();

        poolConfigurator.initialize(poolAddressesProvider);

        // 3. Deploy pool implementation and initialize

        poolImpl = new Pool(poolAddressesProvider);
        poolImpl.initialize(poolAddressesProvider);

        // 4. Deploy and configure ACL manager

        aclManager = new ACLManager(poolAddressesProvider);
        aclManager.addPoolAdmin(deployer);

        // 5. Additional configuration for registry and pool address provider

        registry.registerAddressesProvider(address(poolAddressesProvider), 1);

        poolAddressesProvider.setPoolDataProvider(address(protocolDataProvider));
        poolAddressesProvider.setPoolImpl(address(poolImpl));

        // 6. Get pool instance

        pool = Pool(poolAddressesProvider.getPool());

        // 7. Set the Pool Configurator implementation and ACL manager and get the pool configurator instance

        poolAddressesProvider.setPoolConfiguratorImpl(address(poolConfigurator));
        poolConfigurator = PoolConfigurator(poolAddressesProvider.getPoolConfigurator());
        poolAddressesProvider.setACLManager(address(aclManager));

        // 8. Deploy and initialize aToken instance

        aTokenImpl = new AToken(pool);
        aTokenImpl.initialize(pool, address(0), address(0), IAaveIncentivesController(address(0)), 0, "SPTOKEN_IMPL", "SPTOKEN_IMPL", "");

        // 9. Deploy and initialize stableDebtToken instance

        stableDebtTokenImpl = new StableDebtToken(pool);
        stableDebtTokenImpl.initialize(pool, address(0), IAaveIncentivesController(address(0)), 0, "STABLE_DEBT_TOKEN_IMPL", "STABLE_DEBT_TOKEN_IMPL", "");

        // 9. Deploy and initialize variableDebtToken instance

        variableDebtTokenImpl = new VariableDebtToken(pool);
        variableDebtTokenImpl.initialize(pool, address(0), IAaveIncentivesController(address(0)), 0, "VARIABLE_DEBT_TOKEN_IMPL", "VARIABLE_DEBT_TOKEN_IMPL", "");

        // 10. Deploy Collector, CollectorController and treasury contracts.

        treasuryController = new CollectorController(admin);
        collectorImpl      = new Collector();

        collectorImpl.initialize(address(0));

        (treasury, treasuryImpl) = createCollector(admin);

        // 11. Deploy initialize and configure rewards contracts

        incentivesProxy   = new InitializableAdminUpgradeabilityProxy();
        incentives        = RewardsController(address(incentivesProxy));
        emissionManager   = new EmissionManager(deployer);
        rewardsController = new RewardsController(address(emissionManager));

        rewardsController.initialize(address(0));
        incentivesProxy.initialize(
            address(rewardsController),
            admin,
            abi.encodeWithSignature("initialize(address)", address(emissionManager))
        );
        emissionManager.setRewardsController(address(incentives));
        poolConfigurator.updateFlashloanPremiumTotal(0);    // Flash loans are free

        // 12. Deploy data provider contracts.

        proxy                   = IEACAggregatorProxy(config.readAddress(".nativeTokenOracle"));
        uiPoolDataProvider      = new UiPoolDataProviderV3(proxy, proxy);
        uiIncentiveDataProvider = new UiIncentiveDataProviderV3();
        wethGateway             = new WrappedTokenGatewayV3(config.readAddress(".nativeToken"), admin, IPool(address(pool)));
        walletBalanceProvider   = new WalletBalanceProvider();

        // 13. Set up oracle

        address[] memory assets;
        address[] memory oracles;
        aaveOracle = new AaveOracle(
            poolAddressesProvider,
            assets,
            oracles,
            address(0),
            address(0),  // USD
            1e8
        );
        poolAddressesProvider.setPriceOracle(address(aaveOracle));

        // 14. Transfer all ownership from deployer to admin

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

        ScriptTools.exportContract(instanceId, "aTokenImpl",      address(aTokenImpl));
        ScriptTools.exportContract(instanceId, "aaveOracle",      address(aaveOracle));
        ScriptTools.exportContract(instanceId, "aclManager",      address(aclManager));
        ScriptTools.exportContract(instanceId, "admin",           address(admin));
        ScriptTools.exportContract(instanceId, "deployer",        address(deployer));
        ScriptTools.exportContract(instanceId, "emissionManager", address(emissionManager));
        ScriptTools.exportContract(instanceId, "incentives",      address(incentives));
        ScriptTools.exportContract(instanceId, "incentivesImpl",  address(rewardsController));
        ScriptTools.exportContract(instanceId, "pool",            address(pool));

        ScriptTools.exportContract(instanceId, "poolAddressesProvider",         address(poolAddressesProvider));
        ScriptTools.exportContract(instanceId, "poolAddressesProviderRegistry", address(registry));

        ScriptTools.exportContract(instanceId, "poolConfigurator",        address(poolConfigurator));
        ScriptTools.exportContract(instanceId, "poolConfiguratorImpl",    address(poolConfigurator));
        ScriptTools.exportContract(instanceId, "poolImpl",                address(pool));
        ScriptTools.exportContract(instanceId, "protocolDataProvider",    address(protocolDataProvider));
        ScriptTools.exportContract(instanceId, "stableDebtTokenImpl",     address(stableDebtTokenImpl));
        ScriptTools.exportContract(instanceId, "treasury",                address(treasury));
        ScriptTools.exportContract(instanceId, "treasuryController",      address(treasuryController));
        ScriptTools.exportContract(instanceId, "treasuryImpl",            address(treasuryImpl));
        ScriptTools.exportContract(instanceId, "uiIncentiveDataProvider", address(uiIncentiveDataProvider));
        ScriptTools.exportContract(instanceId, "uiPoolDataProvider",      address(uiPoolDataProvider));
        ScriptTools.exportContract(instanceId, "variableDebtTokenImpl",   address(variableDebtTokenImpl));
        ScriptTools.exportContract(instanceId, "walletBalanceProvider",   address(walletBalanceProvider));
        ScriptTools.exportContract(instanceId, "wethGateway",             address(wethGateway));
    }

    function createCollector(address _admin) internal returns (Collector collector, address impl) {
        InitializableAdminUpgradeabilityProxy collectorProxy = new InitializableAdminUpgradeabilityProxy();
        collector = Collector(address(collectorProxy));
        impl = address(collectorImpl);
        collectorProxy.initialize(
            address(collectorImpl),
            _admin,
            abi.encodeWithSignature("initialize(address)", address(treasuryController))
        );
    }

}
