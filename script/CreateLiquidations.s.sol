// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { MCD, DssInstance } from "dss-test/MCD.sol";
import { ScriptTools } from "dss-test/ScriptTools.sol";

import { PoolAddressesProvider } from "aave-v3-core/contracts/protocol/configuration/PoolAddressesProvider.sol";
import { Pool } from "aave-v3-core/contracts/protocol/pool/Pool.sol";
import { PoolConfigurator } from "aave-v3-core/contracts/protocol/pool/PoolConfigurator.sol";
import { AaveOracle } from 'aave-v3-core/contracts/misc/AaveOracle.sol';
import { MintableERC20 } from "aave-v3-core/contracts/mocks/tokens/MintableERC20.sol";
import {DataTypes} from "aave-v3-core/contracts/protocol/libraries/types/DataTypes.sol";
import {ReserveConfiguration} from "aave-v3-core/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";

contract AaveUser {

    Pool public pool;

    constructor(address _pool) {
        pool = Pool(_pool);
    }

    function deposit(address _token, uint256 _amount) external {
        MintableERC20(_token).approve(address(pool), _amount);
        pool.deposit(_token, _amount, address(this), 0);
    }

    function borrow(address _token, uint256 _amount) external {
        pool.borrow(_token, _amount, 2, 0, address(this));
    }

}

contract CreateLiquidations is Script {

    struct ReserveSettings {
        address asset;
        uint256 ltv;
        uint256 liquidationThreshold;
        uint256 liquidationBonus;
        bool borrowingEnabled;
    }

    using stdJson for string;
    using ScriptTools for string;

    string config;
    DssInstance dss;

    address deployer;

    PoolAddressesProvider poolAddressesProvider;
    Pool pool;
    PoolConfigurator configurator;
    AaveOracle oracle;

    address[] tokens;
    ReserveSettings[] originalSettings;
    uint256 i;
    uint256 valuePerAsset;

    function run() external {
        config = ScriptTools.readInput("config");
        dss = MCD.loadFromChainlog(config.readAddress(".chainlog", "SEED_CHAINLOG"));

        poolAddressesProvider = PoolAddressesProvider(ScriptTools.importContract("LENDING_POOL_ADDRESS_PROVIDER"));
        pool = Pool(poolAddressesProvider.getPool());
        configurator = PoolConfigurator(poolAddressesProvider.getPoolConfigurator());
        oracle = AaveOracle(poolAddressesProvider.getPriceOracle());
        tokens = pool.getReservesList();
        uint256 numUsers = vm.envOr("NUM_USERS", tokens.length * tokens.length);

        deployer = msg.sender;

        vm.startBroadcast();
        
        // Save settings and set everything to 100% LTV (if it is allowed as collateral)
        for (i = 0; i < tokens.length; i++) {
            originalSettings.push(getReserveSettings(tokens[i]));
            if (originalSettings[i].ltv == 0) continue;
            configurator.configureReserveAsCollateral(
                tokens[i],
                9900,
                9900,
                10100
            );
        }

        // Create a bunch of positions that will be underwater with original settings
        valuePerAsset = 10;
        for (i = 0; i < numUsers; i++) {
            uint256 cindex = i % tokens.length;
            uint256 bindex = (i / tokens.length) % tokens.length;
            address ctoken = tokens[cindex];
            if (!originalSettings[bindex].borrowingEnabled) {
                numUsers++;
                continue;
            }
            address btoken = tokens[bindex];
            uint256 bfactor = (((block.number + i) % 2) == 0) ? 10200 : 11000;
            AaveUser user = new AaveUser(address(pool));
            
            // Deposit collateral
            uint256 depositAmount = valuePerAsset * (10 ** MintableERC20(ctoken).decimals()) * oracle.BASE_CURRENCY_UNIT() / oracle.getAssetPrice(ctoken);
            uint256 borrowAmount = valuePerAsset * originalSettings[cindex].liquidationThreshold * bfactor * (10 ** MintableERC20(btoken).decimals()) * oracle.BASE_CURRENCY_UNIT() / (oracle.getAssetPrice(btoken) * 1e8);
            if (MintableERC20(ctoken).balanceOf(deployer) >= depositAmount) {
                MintableERC20(ctoken).transfer(address(user), depositAmount);
            } else {
                try MintableERC20(ctoken).mint(address(user), depositAmount) {
                } catch {
                    numUsers++;
                    continue;
                }
            }
            user.deposit(ctoken, depositAmount);
            user.borrow(btoken, borrowAmount);
        }

        // Restore original settings
        for (i = 0; i < originalSettings.length; i++) {
            configurator.configureReserveAsCollateral(
                originalSettings[i].asset,
                originalSettings[i].ltv,
                originalSettings[i].liquidationThreshold,
                originalSettings[i].liquidationBonus
            );
        }

        vm.stopBroadcast();
    }

    function getReserveSettings(address asset) internal view returns (ReserveSettings memory) {
        DataTypes.ReserveData memory data = pool.getReserveData(asset);
        return ReserveSettings(
            asset,
            ReserveConfiguration.getLtv(data.configuration),
            ReserveConfiguration.getLiquidationThreshold(data.configuration),
            ReserveConfiguration.getLiquidationBonus(data.configuration),
            ReserveConfiguration.getBorrowingEnabled(data.configuration)
        );
    }

}
