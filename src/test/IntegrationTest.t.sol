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
        dss = MCD.loadFromChainlog(config.readAddress("chainlog"));

        admin = config.readAddress("admin");
        deployer = deployedContracts.readAddress("deployer");

        //hub = D3MHubLike(dss.chainlog.getAddress("DIRECT_HUB"));
        weth = IERC20(dss.chainlog.getAddress("ETH"));
        wsteth = IERC20(dss.chainlog.getAddress("WSTETH"));
        wbtc = IERC20(dss.chainlog.getAddress("WBTC"));
        dai = IERC20(dss.chainlog.getAddress("MCD_DAI"));
        usdc = IERC20(dss.chainlog.getAddress("USDC"));
        sdai = IERC20(0xD8134205b0328F5676aaeFb3B2a0DC15f4029d8C);

        poolAddressesProviderRegistry = PoolAddressesProviderRegistry(deployedContracts.readAddress("poolAddressesProviderRegistry"));
        poolAddressesProvider = PoolAddressesProvider(deployedContracts.readAddress("poolAddressesProvider"));
        protocolDataProvider = AaveProtocolDataProvider(deployedContracts.readAddress("protocolDataProvider"));
        poolConfigurator = PoolConfigurator(deployedContracts.readAddress("poolConfigurator"));
        pool = Pool(deployedContracts.readAddress("pool"));
        aclManager = ACLManager(deployedContracts.readAddress("aclManager"));
        aaveOracle = AaveOracle(deployedContracts.readAddress("aaveOracle"));

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
        if (block.chainid == 1) assertEq(reserves[1], address(sdai));
        assertEq(reserves[2], address(usdc));
        if (block.chainid == 1) assertEq(reserves[3], address(weth));
        if (block.chainid == 1) assertEq(reserves[4], address(wsteth));
        if (block.chainid == 1) assertEq(reserves[5], address(wbtc));
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
