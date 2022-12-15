// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.10;

import "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {IERC20Detailed} from 'aave-v3-core/contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol';
import {Strings} from 'aave-v3-core/contracts/dependencies/openzeppelin/contracts/Strings.sol';
import {ERC20} from 'aave-v3-core/contracts/dependencies/openzeppelin/contracts/ERC20.sol';
import {IERC20} from 'aave-v3-core/contracts/dependencies/openzeppelin/contracts/IERC20.sol';

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

import {UiPoolDataProviderV3} from "aave-v3-periphery/misc/UiPoolDataProviderV3.sol";
import {UiIncentiveDataProviderV3} from "aave-v3-periphery/misc/UiIncentiveDataProviderV3.sol";
import {WrappedTokenGatewayV3} from "aave-v3-periphery/misc/WrappedTokenGatewayV3.sol";
import {IPool} from "aave-v3-core/contracts/interfaces/IPool.sol";
import {WalletBalanceProvider} from "aave-v3-periphery/misc/WalletBalanceProvider.sol";
import {IEACAggregatorProxy} from "aave-v3-periphery/misc/interfaces/IEACAggregatorProxy.sol";

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

struct ReserveConfig {
    string name;
    address token;
    uint256 borrowEnabled;
    uint256 irOptimalUsageRatio;
    uint256 irBaseVariableBorrowRate;
    uint256 irVariableRateSlope1;
    uint256 irVariableRateSlope2;
    address oracle;
    uint256 ltv;
    uint256 liquidationThreshold;
    uint256 liquidationBonus;
    uint256 reserveFactor;
    uint256 eModeCategory;
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

    string config;

    PoolAddressesProvider poolAddressesProvider;
    AaveProtocolDataProvider protocolDataProvider;
    PoolConfigurator poolConfigurator;
    Pool pool;
    ACLManager aclManager;
    AaveOracle aaveOracle;

    AToken aTokenImpl;
    StableDebtToken stableDebtTokenImpl;
    VariableDebtToken variableDebtTokenImpl;

    UiPoolDataProviderV3 uiPoolDataProvider;
    UiIncentiveDataProviderV3 uiIncentiveDataProvider;
    WrappedTokenGatewayV3 wethGateway;
    WalletBalanceProvider walletBalanceProvider;

    ConfiguratorInputTypes.InitReserveInput[] reserves;
    address[] assets;
    address[] assetOracleSources;

    function readInput(string memory input) internal view returns (string memory) {
        string memory root = vm.projectRoot();
        string memory chainInputFolder = string(string.concat(bytes("/script/input/"), bytes(vm.toString(block.chainid)), bytes("/")));
        return vm.readFile(string(string.concat(bytes(root), bytes(chainInputFolder), string.concat(bytes(input), bytes(".json")))));
    }

    function parseReserves() internal view returns (ReserveConfig[] memory) {
        // JSON parsing is a bit janky and I don't know why, so I'm doing this more manually
        bytes[] memory a = config.readBytesArray(".reserves");
        ReserveConfig[] memory reserves = new ReserveConfig[](a.length);
        for (uint256 i = 0; i < a.length; i++) {
            string memory base = string(string.concat(bytes(".reserves["), bytes(Strings.toString(i)), "]"));
            reserves[i] = ReserveConfig({
                name: config.readString(string(string.concat(bytes(base), bytes(".name")))),
                token: config.readAddress(string(string.concat(bytes(base), bytes(".token")))),
                borrowEnabled: config.readUint(string(string.concat(bytes(base), bytes(".borrow")))),
                irOptimalUsageRatio: config.readUint(string(string.concat(bytes(base), bytes(".irOptimalUsageRatio")))),
                irBaseVariableBorrowRate: config.readUint(string(string.concat(bytes(base), bytes(".irBaseVariableBorrowRate")))),
                irVariableRateSlope1: config.readUint(string(string.concat(bytes(base), bytes(".irVariableRateSlope1")))),
                irVariableRateSlope2: config.readUint(string(string.concat(bytes(base), bytes(".irVariableRateSlope2")))),
                oracle: config.readAddress(string(string.concat(bytes(base), bytes(".oracle")))),
                ltv: config.readUint(string(string.concat(bytes(base), bytes(".ltv")))),
                liquidationThreshold: config.readUint(string(string.concat(bytes(base), bytes(".liquidationThreshold")))),
                liquidationBonus: config.readUint(string(string.concat(bytes(base), bytes(".liquidationBonus")))),
                reserveFactor: config.readUint(string(string.concat(bytes(base), bytes(".reserveFactor")))),
                eModeCategory: config.readUint(string(string.concat(bytes(base), bytes(".eModeCategory"))))
            });
        }
        return reserves;
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
        input.treasury = address(0);
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

    function giveTokens(address token, uint256 amount) internal {
        // Edge case - balance is already set for some reason
        if (IERC20(token).balanceOf(address(this)) == amount) return;

        // Scan the storage for the balance storage slot
        for (uint256 i = 0; i < 200; i++) {
            // Solidity-style storage layout for maps
            {
                bytes32 prevValue = vm.load(
                    address(token),
                    keccak256(abi.encode(address(this), uint256(i)))
                );

                vm.store(
                    address(token),
                    keccak256(abi.encode(address(this), uint256(i))),
                    bytes32(amount)
                );
                if (IERC20(token).balanceOf(address(this)) == amount) {
                    // Found it
                    return;
                } else {
                    // Keep going after restoring the original value
                    vm.store(
                        address(token),
                        keccak256(abi.encode(address(this), uint256(i))),
                        prevValue
                    );
                }
            }

            // Vyper-style storage layout for maps
            {
                bytes32 prevValue = vm.load(
                    address(token),
                    keccak256(abi.encode(uint256(i), address(this)))
                );

                vm.store(
                    address(token),
                    keccak256(abi.encode(uint256(i), address(this))),
                    bytes32(amount)
                );
                if (IERC20(token).balanceOf(address(this)) == amount) {
                    // Found it
                    return;
                } else {
                    // Keep going after restoring the original value
                    vm.store(
                        address(token),
                        keccak256(abi.encode(uint256(i), address(this))),
                        prevValue
                    );
                }
            }
        }

        // We have failed if we reach here
        require(false, "giveTokens-slot-not-found");
    }

    function run() external {
        config = readInput("config");

        vm.startBroadcast();
        address admin = msg.sender;

        poolAddressesProvider = new PoolAddressesProvider(config.readString(".marketId"), admin);
        poolAddressesProvider.setACLAdmin(admin);
        protocolDataProvider = new AaveProtocolDataProvider(poolAddressesProvider);
        PoolConfigurator _poolConfigurator = new PoolConfigurator();
        Pool _pool = new Pool(poolAddressesProvider);
        aclManager = new ACLManager(poolAddressesProvider);
        aclManager.addPoolAdmin(admin);

        poolAddressesProvider.setPoolDataProvider(address(protocolDataProvider));
        poolAddressesProvider.setPoolImpl(address(_pool));
        pool = Pool(poolAddressesProvider.getPool());
        poolAddressesProvider.setPoolConfiguratorImpl(address(_poolConfigurator));
        poolConfigurator = PoolConfigurator(poolAddressesProvider.getPoolConfigurator());
        poolAddressesProvider.setACLManager(address(aclManager));

        aTokenImpl = new AToken(pool);
        stableDebtTokenImpl = new StableDebtToken(pool);
        variableDebtTokenImpl = new VariableDebtToken(pool);

        IEACAggregatorProxy proxy = IEACAggregatorProxy(config.readAddress(".uiPoolCurrencyAggregatorProxy"));
        uiPoolDataProvider = new UiPoolDataProviderV3(proxy, proxy);
        uiIncentiveDataProvider = new UiIncentiveDataProviderV3();
        wethGateway = new WrappedTokenGatewayV3(config.readAddress(".weth"), admin, IPool(address(pool)));
        walletBalanceProvider = new WalletBalanceProvider();

        // Init reserves
        ReserveConfig[] memory reserveConfigs = parseReserves();
        for (uint256 i = 0; i < reserveConfigs.length; i++) {
            ReserveConfig memory cfg = reserveConfigs[i];

            require(keccak256(bytes(IERC20Detailed(address(cfg.token)).symbol())) == keccak256(bytes(cfg.name)), "Token name doesn't match symbol");

            reserves.push(makeReserve(
                IERC20Detailed(address(cfg.token)),
                new DefaultReserveInterestRateStrategy(
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
                )
            ));
            assets.push(address(cfg.token));
            assetOracleSources.push(address(cfg.oracle));
        }
        poolConfigurator.initReserves(reserves);
        poolConfigurator.updateFlashloanPremiumTotal(0);    // Flash loans are free

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
        }
        vm.stopBroadcast();

        console.log(string(abi.encodePacked("LENDING_POOL_ADDRESS_PROVIDER=", Strings.toHexString(uint256(uint160(address(poolAddressesProvider))), 20))));
        console.log(string(abi.encodePacked("LENDING_POOL=", Strings.toHexString(uint256(uint160(address(pool))), 20))));
        console.log(string(abi.encodePacked("WETH_GATEWAY=", Strings.toHexString(uint256(uint160(address(wethGateway))), 20))));
        console.log(string(abi.encodePacked("WALLET_BALANCE_PROVIDER=", Strings.toHexString(uint256(uint160(address(walletBalanceProvider))), 20))));
        console.log(string(abi.encodePacked("UI_POOL_DATA_PROVIDER=", Strings.toHexString(uint256(uint160(address(uiPoolDataProvider))), 20))));
        console.log(string(abi.encodePacked("UI_INCENTIVE_DATA_PROVIDER=", Strings.toHexString(uint256(uint160(address(uiIncentiveDataProvider))), 20))));

        // Run some tests to verify deploy
        //executeTests(reserveConfigs);
    }

    function executeTests(ReserveConfig[] memory reserveConfigs) internal {
        User[3] memory users = [
            new User(pool),
            new User(pool),
            new User(pool)
        ];

        // Mint $100k worth of tokens for each user
        uint256 valuePerAsset = 100_000;
        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            uint256 numTokens = valuePerAsset * (10 ** IERC20Detailed(asset).decimals()) * aaveOracle.BASE_CURRENCY_UNIT() / aaveOracle.getAssetPrice(asset);
            if (i != 2) {   // Skip Lido for now stETH doesn't work
                for (uint256 o = 0; o < users.length; o++) {
                    giveTokens(asset, numTokens);
                    IERC20(asset).transfer(address(users[o]), numTokens);
                }

                // Have the first user seed all pools
                users[0].supply(IERC20(asset), numTokens);
            }
        }

        // User 2 is going to borrow asset 1 against asset 2
        {
            User user = users[1];
            IERC20 supplyAsset = IERC20(assets[1]);
            IERC20 borrowAsset = IERC20(assets[0]);
            uint256 collateralAmount = supplyAsset.balanceOf(address(user));

            user.supply(supplyAsset, collateralAmount);
            user.borrow(borrowAsset, collateralAmount * reserveConfigs[0].ltv / 1e4 * aaveOracle.getAssetPrice(address(supplyAsset)) / aaveOracle.getAssetPrice(address(borrowAsset)));
        }

        // Case 2 user use e-mode to borrow eth with stETH
        //user2.supply(stETH, 100 ether);
        //user2.setEMode(1);
        //user2.borrow(weth, 95 ether);   // Should be able to borrow up to 95%
    }

}
