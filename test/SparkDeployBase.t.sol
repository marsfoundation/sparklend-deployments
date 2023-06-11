// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
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

abstract contract SparkDeployBaseTest is Test {

    using stdJson for string;

    // Configuration
    // Override this in the inheriting contract
    string  instanceId = "primary";
    string  rpcUrl;
    uint256 forkBlock;
    uint256 initialReserveCount;

    string config;
    string deployedContracts;

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
    EmissionManager emissionManager;
    RewardsController incentives;
    RewardsController incentivesImpl;
    UiPoolDataProviderV3 uiPoolDataProvider;
    UiIncentiveDataProviderV3 uiIncentiveDataProvider;
    WrappedTokenGatewayV3 wethGateway;
    WalletBalanceProvider walletBalanceProvider;

    function setUp() public {
        if (forkBlock > 0) vm.createSelectFork(rpcUrl, forkBlock);
        else vm.createSelectFork(rpcUrl);
        vm.setEnv("FOUNDRY_ROOT_CHAINID", vm.toString(block.chainid));

        config            = ScriptTools.readInput("config");
        deployedContracts = ScriptTools.readOutput(instanceId);

        admin    = config.readAddress(".admin");
        deployer = deployedContracts.readAddress(".deployer");

        poolAddressesProviderRegistry = PoolAddressesProviderRegistry(deployedContracts.readAddress(".poolAddressesProviderRegistry"));
        poolAddressesProvider         = PoolAddressesProvider(deployedContracts.readAddress(".poolAddressesProvider"));
        protocolDataProvider          = AaveProtocolDataProvider(deployedContracts.readAddress(".protocolDataProvider"));
        poolConfigurator              = PoolConfigurator(deployedContracts.readAddress(".poolConfigurator"));
        poolConfiguratorImpl          = PoolConfigurator(deployedContracts.readAddress(".poolConfiguratorImpl"));
        pool                          = Pool(deployedContracts.readAddress(".pool"));
        poolImpl                      = Pool(deployedContracts.readAddress(".poolImpl"));

        aclManager = ACLManager(deployedContracts.readAddress(".aclManager"));
        aaveOracle = AaveOracle(deployedContracts.readAddress(".aaveOracle"));

        aTokenImpl            = AToken(deployedContracts.readAddress(".aTokenImpl"));
        variableDebtTokenImpl = VariableDebtToken(deployedContracts.readAddress(".variableDebtTokenImpl"));
        stableDebtTokenImpl   = StableDebtToken(deployedContracts.readAddress(".stableDebtTokenImpl"));

        treasuryController = CollectorController(deployedContracts.readAddress(".treasuryController"));
        treasury           = Collector(deployedContracts.readAddress(".treasury"));
        treasuryImpl       = Collector(deployedContracts.readAddress(".treasuryImpl"));

        emissionManager = EmissionManager(deployedContracts.readAddress(".emissionManager"));
        incentives      = RewardsController(deployedContracts.readAddress(".incentives"));
        incentivesImpl  = RewardsController(deployedContracts.readAddress(".incentivesImpl"));

        uiPoolDataProvider      = UiPoolDataProviderV3(deployedContracts.readAddress(".uiPoolDataProvider"));
        uiIncentiveDataProvider = UiIncentiveDataProviderV3(deployedContracts.readAddress(".uiIncentiveDataProvider"));
        wethGateway             = WrappedTokenGatewayV3(payable(deployedContracts.readAddress(".wethGateway")));
        walletBalanceProvider   = WalletBalanceProvider(payable(deployedContracts.readAddress(".walletBalanceProvider")));
    }

    function test_spark_deploy_poolAddressesProviderRegistry() public {
        address[] memory providersList = poolAddressesProviderRegistry.getAddressesProvidersList();

        assertEq(poolAddressesProviderRegistry.owner(), admin);
        assertEq(providersList.length,                  1);
        assertEq(providersList[0],                      address(poolAddressesProvider));

        assertEq(poolAddressesProviderRegistry.getAddressesProviderAddressById(1),  address(poolAddressesProvider));

        assertEq(poolAddressesProviderRegistry.getAddressesProviderIdByAddress(address(poolAddressesProvider)), 1);
    }

    function test_spark_deploy_poolAddressesProvider() public {
        assertEq(poolAddressesProvider.owner(),                  admin);
        assertEq(poolAddressesProvider.getMarketId(),            "Spark Protocol");
        assertEq(poolAddressesProvider.getPool(),                address(pool));
        assertEq(poolAddressesProvider.getPoolConfigurator(),    address(poolConfigurator));
        assertEq(poolAddressesProvider.getPriceOracle(),         address(aaveOracle));
        assertEq(poolAddressesProvider.getACLManager(),          address(aclManager));
        assertEq(poolAddressesProvider.getACLAdmin(),            admin);
        assertEq(poolAddressesProvider.getPriceOracleSentinel(), address(0));
        assertEq(poolAddressesProvider.getPoolDataProvider(),    address(protocolDataProvider));
    }

    function test_spark_deploy_aclManager() public {
        // NOTE: Also verify that no other address than the admin address has any role (verify with events)
        assertEq(address(aclManager.ADDRESSES_PROVIDER()), address(poolAddressesProvider));

        bytes32 defaultAdmin = aclManager.DEFAULT_ADMIN_ROLE();

        assertEq(aclManager.getRoleAdmin(aclManager.POOL_ADMIN_ROLE()),      defaultAdmin);
        assertEq(aclManager.getRoleAdmin(aclManager.EMERGENCY_ADMIN_ROLE()), defaultAdmin);

        assertTrue( aclManager.hasRole(defaultAdmin, admin));
        assertTrue(!aclManager.hasRole(defaultAdmin, deployer));

        assertTrue( aclManager.hasRole(aclManager.POOL_ADMIN_ROLE(), admin));
        assertTrue(!aclManager.hasRole(aclManager.POOL_ADMIN_ROLE(), deployer));

        if (block.chainid == 1) assertTrue(aclManager.hasRole(aclManager.EMERGENCY_ADMIN_ROLE(), admin));     // FIXME missing on GOERLI

        assertEq(aclManager.getRoleAdmin(aclManager.RISK_ADMIN_ROLE()),          defaultAdmin);
        assertEq(aclManager.getRoleAdmin(aclManager.FLASH_BORROWER_ROLE()),      defaultAdmin);
        assertEq(aclManager.getRoleAdmin(aclManager.BRIDGE_ROLE()),              defaultAdmin);
        assertEq(aclManager.getRoleAdmin(aclManager.ASSET_LISTING_ADMIN_ROLE()), defaultAdmin);
    }

    function test_spark_deploy_protocolDataProvider() public {
        assertEq(address(protocolDataProvider.ADDRESSES_PROVIDER()), address(poolAddressesProvider));
    }

    function test_spark_deploy_poolConfigurator() public {
        assertEq(poolConfigurator.CONFIGURATOR_REVISION(), 1);
        assertImplementation(address(poolAddressesProvider), address(poolConfigurator), address(poolConfiguratorImpl));
    }

    function test_spark_deploy_pool() public {
        assertEq(address(pool.ADDRESSES_PROVIDER()), address(poolAddressesProvider));

        assertEq(pool.POOL_REVISION(),                       1);
        assertEq(pool.MAX_STABLE_RATE_BORROW_SIZE_PERCENT(), 0.25e4);
        assertEq(pool.BRIDGE_PROTOCOL_FEE(),                 0);
        assertEq(pool.FLASHLOAN_PREMIUM_TOTAL(),             0);
        assertEq(pool.FLASHLOAN_PREMIUM_TO_PROTOCOL(),       0);
        assertEq(pool.MAX_NUMBER_RESERVES(),                 128);

        assertImplementation(address(poolAddressesProvider), address(pool), address(poolImpl));

        address[] memory reserves = pool.getReservesList();
        assertEq(reserves.length, initialReserveCount);
    }

    function test_spark_deploy_tokenImpls() public {
        assertEq(address(aTokenImpl.POOL()),            address(pool));
        assertEq(address(variableDebtTokenImpl.POOL()), address(pool));
        assertEq(address(stableDebtTokenImpl.POOL()),   address(pool));
    }

    function test_spark_deploy_treasury() public {
        assertEq(address(treasuryController.owner()), admin);
        assertEq(treasury.REVISION(), 1);
        assertEq(treasury.getFundsAdmin(), address(treasuryController));
        assertImplementation(admin, address(treasury), address(treasuryImpl));
    }

    function test_spark_deploy_incentives() public {
        assertEq(address(emissionManager.owner()), admin);
        assertEq(address(emissionManager.getRewardsController()), address(incentives));
        assertEq(incentives.REVISION(), 1);
        assertEq(incentives.EMISSION_MANAGER(), address(emissionManager));
        assertImplementation(admin, address(incentives), address(incentivesImpl));
    }

    function test_spark_deploy_misc_contracts() public {
        address nativeToken = config.readAddress(".nativeToken");
        address nativeTokenOracle = config.readAddress(".nativeTokenOracle");
        assertEq(address(uiPoolDataProvider.networkBaseTokenPriceInUsdProxyAggregator()), nativeTokenOracle);
        assertEq(address(uiPoolDataProvider.marketReferenceCurrencyPriceInUsdProxyAggregator()), nativeTokenOracle);
        assertEq(wethGateway.owner(), admin);
        assertEq(wethGateway.getWETHAddress(), nativeToken);
    }

    function test_spark_deploy_oracles() public {
        assertEq(address(aaveOracle.ADDRESSES_PROVIDER()), address(poolAddressesProvider));
        assertEq(aaveOracle.BASE_CURRENCY(), address(0));
        assertEq(aaveOracle.BASE_CURRENCY_UNIT(), 10 ** 8);
        assertEq(aaveOracle.getFallbackOracle(), address(0));
    }

    function test_implementation_contracts_initialized() public {
        vm.expectRevert("Contract instance has already been initialized");
        poolConfiguratorImpl.initialize(poolAddressesProvider);
        vm.expectRevert("Contract instance has already been initialized");
        poolImpl.initialize(poolAddressesProvider);
        vm.expectRevert("Contract instance has already been initialized");
        treasuryImpl.initialize(address(0));
        vm.expectRevert("Contract instance has already been initialized");
        incentivesImpl.initialize(address(0));
        vm.expectRevert("Contract instance has already been initialized");
        aTokenImpl.initialize(pool, address(0), address(0), IAaveIncentivesController(address(0)), 0, "SPTOKEN_IMPL", "SPTOKEN_IMPL", "");
        vm.expectRevert("Contract instance has already been initialized");
        stableDebtTokenImpl.initialize(pool, address(0), IAaveIncentivesController(address(0)), 0, "STABLE_DEBT_TOKEN_IMPL", "STABLE_DEBT_TOKEN_IMPL", "");
        vm.expectRevert("Contract instance has already been initialized");
        variableDebtTokenImpl.initialize(pool, address(0), IAaveIncentivesController(address(0)), 0, "VARIABLE_DEBT_TOKEN_IMPL", "VARIABLE_DEBT_TOKEN_IMPL", "");
    }

    function assertImplementation(address _admin, address proxy, address implementation) internal {
        vm.prank(_admin); assertEq(InitializableAdminUpgradeabilityProxy(payable(proxy)).implementation(), implementation);
    }

}
