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

import {Faucet} from "../src/testnet/Faucet.sol";
import {DaiInterestRateStrategy} from "../src/DaiInterestRateStrategy.sol";

struct ReserveConfig {
    string name;
    address token;
    uint256 decimals;
    uint256 borrowEnabled;
    uint256 irOptimalUsageRatio;
    uint256 irBaseVariableBorrowRate;
    uint256 irVariableRateSlope1;
    uint256 irVariableRateSlope2;
    address oracle;
    uint256 oracleMockPrice;
    uint256 ltv;
    uint256 liquidationThreshold;
    uint256 liquidationBonus;
    uint256 reserveFactor;
    uint256 eModeCategory;
    uint256 supplyCap;
    uint256 borrowCap;
}

struct EModeConfig {
    uint256 categoryId;
    uint256 ltv;
    uint256 liquidationThreshold;
    uint256 liquidationBonus;
    address oracle;
    string label;
}

contract DeployAave is Script {

    using stdJson for string;
    using ScriptTools for string;

    uint256 constant WAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;

    string config;
    DssInstance dss;

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
    Collector daiTreasury;
    CollectorController treasuryController;
    RewardsController incentives;
    EmissionManager emissionManager;

    address weth;
    address wethOracle;
    address savingsDai;
    UiPoolDataProviderV3 uiPoolDataProvider;
    UiIncentiveDataProviderV3 uiIncentiveDataProvider;
    WrappedTokenGatewayV3 wethGateway;
    WalletBalanceProvider walletBalanceProvider;
    Faucet faucet;

    ConfiguratorInputTypes.InitReserveInput[] reserves;
    address[] assets;
    address[] assetOracleSources;

    function parseReserves() internal view returns (ReserveConfig[] memory) {
        // JSON parsing is a bit janky and I don't know why, so I'm doing this more manually
        bytes[] memory a = config.readBytesArray(".reserves");
        ReserveConfig[] memory _reserves = new ReserveConfig[](a.length);
        for (uint256 i = 0; i < a.length; i++) {
            string memory base = string(string.concat(bytes(".reserves["), bytes(Strings.toString(i)), "]"));
            _reserves[i] = ReserveConfig({
                name: config.readString(string(string.concat(bytes(base), bytes(".name")))),
                token: config.readAddress(string(string.concat(bytes(base), bytes(".token")))),
                decimals: config.readUint(string(string.concat(bytes(base), bytes(".decimals")))),
                borrowEnabled: config.readUint(string(string.concat(bytes(base), bytes(".borrow")))),
                irOptimalUsageRatio: config.readUint(string(string.concat(bytes(base), bytes(".irOptimalUsageRatio")))),
                irBaseVariableBorrowRate: config.readUint(string(string.concat(bytes(base), bytes(".irBaseVariableBorrowRate")))),
                irVariableRateSlope1: config.readUint(string(string.concat(bytes(base), bytes(".irVariableRateSlope1")))),
                irVariableRateSlope2: config.readUint(string(string.concat(bytes(base), bytes(".irVariableRateSlope2")))),
                oracle: config.readAddress(string(string.concat(bytes(base), bytes(".oracle")))),
                oracleMockPrice: config.readUint(string(string.concat(bytes(base), bytes(".oracleMockPrice")))),
                ltv: config.readUint(string(string.concat(bytes(base), bytes(".ltv")))),
                liquidationThreshold: config.readUint(string(string.concat(bytes(base), bytes(".liquidationThreshold")))),
                liquidationBonus: config.readUint(string(string.concat(bytes(base), bytes(".liquidationBonus")))),
                reserveFactor: config.readUint(string(string.concat(bytes(base), bytes(".reserveFactor")))),
                eModeCategory: config.readUint(string(string.concat(bytes(base), bytes(".eModeCategory")))),
                supplyCap: config.readUint(string(string.concat(bytes(base), bytes(".supplyCap")))),
                borrowCap: config.readUint(string(string.concat(bytes(base), bytes(".borrowCap"))))
            });
        }
        return _reserves;
    }

    function setupEModeCategories() internal {
        // JSON parsing is a bit janky and I don't know why, so I'm doing this more manually
        bytes[] memory a = config.readBytesArray(".emodeCategories");
        for (uint256 i = 0; i < a.length; i++) {
            string memory base = string(string.concat(bytes(".emodeCategories["), bytes(Strings.toString(i)), "]"));
            poolConfigurator.setEModeCategory({
                categoryId: uint8(config.readUint(string(string.concat(bytes(base), bytes(".categoryId"))))),
                ltv: uint16(config.readUint(string(string.concat(bytes(base), bytes(".ltv"))))),
                liquidationThreshold: uint16(config.readUint(string(string.concat(bytes(base), bytes(".liquidationThreshold"))))),
                liquidationBonus: uint16(config.readUint(string(string.concat(bytes(base), bytes(".liquidationBonus"))))),
                oracle: config.readAddress(string(string.concat(bytes(base), bytes(".oracle")))),
                label: config.readString(string(string.concat(bytes(base), bytes(".label"))))
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
        input.treasury = token.symbol().eq("DAI") ? address(daiTreasury) : address(treasury);
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

    function createCollector(address admin) internal returns (Collector collector) {
        InitializableAdminUpgradeabilityProxy proxy = new InitializableAdminUpgradeabilityProxy();
        collector = Collector(address(proxy));
        Collector collectorImpl = new Collector();
        proxy.initialize(
            address(collectorImpl),
            admin,
            abi.encodeWithSignature("initialize(address)", address(treasuryController))
        );
    }

    function run() external {
        config = ScriptTools.loadConfig("config");
        dss = MCD.loadFromChainlog(config.readAddress(".chainlog"));

        address admin = config.readAddress(".admin", "AAVE_ADMIN");

        vm.startBroadcast();
        registry = new PoolAddressesProviderRegistry(admin);
        poolAddressesProvider = new PoolAddressesProvider(config.readString(".marketId"), admin);
        poolAddressesProvider.setACLAdmin(admin);
        protocolDataProvider = new AaveProtocolDataProvider(poolAddressesProvider);
        PoolConfigurator _poolConfigurator = new PoolConfigurator();
        Pool _pool = new Pool(poolAddressesProvider);
        aclManager = new ACLManager(poolAddressesProvider);
        aclManager.addPoolAdmin(admin);
        registry.registerAddressesProvider(address(poolAddressesProvider), 1);

        poolAddressesProvider.setPoolDataProvider(address(protocolDataProvider));
        poolAddressesProvider.setPoolImpl(address(_pool));
        pool = Pool(poolAddressesProvider.getPool());
        poolAddressesProvider.setPoolConfiguratorImpl(address(_poolConfigurator));
        poolConfigurator = PoolConfigurator(poolAddressesProvider.getPoolConfigurator());
        poolAddressesProvider.setACLManager(address(aclManager));

        aTokenImpl = new AToken(pool);
        stableDebtTokenImpl = new StableDebtToken(pool);
        variableDebtTokenImpl = new VariableDebtToken(pool);

        treasuryController = new CollectorController(admin);
        treasury = createCollector(admin);
        daiTreasury = createCollector(admin);

        InitializableAdminUpgradeabilityProxy incentivesProxy = new InitializableAdminUpgradeabilityProxy();
        incentives = RewardsController(address(incentivesProxy));
        emissionManager = new EmissionManager(admin);
        RewardsController rewardsController = new RewardsController(address(emissionManager));
        incentivesProxy.initialize(
            address(rewardsController),
            admin,
            abi.encodeWithSignature("initialize(address)", address(emissionManager))
        );

        // Init reserves
        ReserveConfig[] memory reserveConfigs = parseReserves();
        for (uint256 i = 0; i < reserveConfigs.length; i++) {
            ReserveConfig memory cfg = reserveConfigs[i];

            if (cfg.token == address(0)) {
                if (cfg.name.eq("WETH")) {
                    cfg.token = address(new WETH9Mocked());
                } else {
                    cfg.token = address(new MintableERC20(cfg.name, cfg.name, uint8(cfg.decimals)));
                }
            }
            if (cfg.oracle == address(0)) {
                cfg.oracle = address(new MockAggregator(int256(cfg.oracleMockPrice * 10 ** 8)));
            }

            if (cfg.name.eq("WETH")) {
                weth = cfg.token;
                wethOracle = cfg.oracle;
            }

            if (cfg.name.eq("sDAI")) {
                savingsDai = cfg.token;
            }

            require(IERC20Detailed(address(cfg.token)).symbol().eq(cfg.name), "Token name doesn't match symbol");

            reserves.push(makeReserve(
                IERC20Detailed(address(cfg.token)),
                cfg.name.eq("DAI") ?
                    IReserveInterestRateStrategy(new DaiInterestRateStrategy(
                        address(dss.vat),
                        address(dss.pot),
                        config.readString(".ilk").stringToBytes32(),
                        0,
                        0,
                        75 * RAY / 100,  // 75%
                        500_000_000 * WAD
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

            poolConfigurator.setReserveBorrowing(address(cfg.token), cfg.borrowEnabled == 1);
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
        }
        
        // Deploy a faucet if this is a testnet
        address makerFaucet = config.readAddress(".makerFaucet");
        if (makerFaucet != address(0)) {
            faucet = new Faucet(makerFaucet, config.readAddress(".usdcPsm"), savingsDai);
        }
        vm.stopBroadcast();

        ScriptTools.exportContract("LENDING_POOL_ADDRESS_PROVIDER", address(poolAddressesProvider));
        ScriptTools.exportContract("LENDING_POOL", address(pool));
        ScriptTools.exportContract("WETH_GATEWAY", address(wethGateway));
        if (address(faucet) != address(0)) ScriptTools.exportContract("FAUCET", address(faucet));
        ScriptTools.exportContract("WALLET_BALANCE_PROVIDER", address(walletBalanceProvider));
        ScriptTools.exportContract("UI_POOL_DATA_PROVIDER", address(uiPoolDataProvider));
        ScriptTools.exportContract("UI_INCENTIVE_DATA_PROVIDER", address(uiIncentiveDataProvider));
    }

}
