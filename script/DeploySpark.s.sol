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
    string name;

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
        name = vm.envOr("INSTANCE_ID", string("primary"));
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

        ScriptTools.exportContract(name, "admin", admin);
        ScriptTools.exportContract(name, "deployer", deployer);
        ScriptTools.exportContract(name, "poolAddressesProviderRegistry", address(registry));
        ScriptTools.exportContract(name, "poolAddressesProvider", address(poolAddressesProvider));
        ScriptTools.exportContract(name, "protocolDataProvider", address(protocolDataProvider));
        ScriptTools.exportContract(name, "poolConfigurator", address(poolConfigurator));
        ScriptTools.exportContract(name, "poolConfiguratorImpl", address(_poolConfigurator));
        ScriptTools.exportContract(name, "pool", address(pool));
        ScriptTools.exportContract(name, "poolImpl", address(_pool));
        ScriptTools.exportContract(name, "aclManager", address(aclManager));
        ScriptTools.exportContract(name, "aaveOracle", address(aaveOracle));
        ScriptTools.exportContract(name, "aTokenImpl", address(aTokenImpl));
        ScriptTools.exportContract(name, "stableDebtTokenImpl", address(stableDebtTokenImpl));
        ScriptTools.exportContract(name, "variableDebtTokenImpl", address(variableDebtTokenImpl));
        ScriptTools.exportContract(name, "treasury", address(treasury));
        ScriptTools.exportContract(name, "treasuryImpl", address(treasuryImpl));
        ScriptTools.exportContract(name, "treasuryController", address(treasuryController));
        ScriptTools.exportContract(name, "incentives", address(incentives));
        ScriptTools.exportContract(name, "incentivesImpl", address(rewardsController));
        ScriptTools.exportContract(name, "emissionManager", address(emissionManager));
        ScriptTools.exportContract(name, "uiPoolDataProvider", address(uiPoolDataProvider));
        ScriptTools.exportContract(name, "uiIncentiveDataProvider", address(uiIncentiveDataProvider));
        ScriptTools.exportContract(name, "wethGateway", address(wethGateway));
        ScriptTools.exportContract(name, "walletBalanceProvider", address(walletBalanceProvider));
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
