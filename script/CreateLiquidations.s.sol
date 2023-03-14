// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { MCD, DssInstance } from "dss-test/MCD.sol";
import { ScriptTools } from "dss-test/ScriptTools.sol";

import { IERC20 } from "aave-v3-core/contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import { IERC20Detailed } from "aave-v3-core/contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol";
import { Ownable } from "aave-v3-core/contracts/dependencies/openzeppelin/contracts/Ownable.sol";
import { PoolAddressesProvider } from "aave-v3-core/contracts/protocol/configuration/PoolAddressesProvider.sol";
import { Pool } from "aave-v3-core/contracts/protocol/pool/Pool.sol";
import { PoolConfigurator } from "aave-v3-core/contracts/protocol/pool/PoolConfigurator.sol";
import { AaveOracle } from 'aave-v3-core/contracts/misc/AaveOracle.sol';
import { DataTypes } from "aave-v3-core/contracts/protocol/libraries/types/DataTypes.sol";
import { ReserveConfiguration } from "aave-v3-core/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";

contract SparkUser is Ownable {

    Pool public pool;

    constructor(address _pool) {
        pool = Pool(_pool);
    }

    function supply(address _token, uint256 _amount) external onlyOwner {
        IERC20(_token).approve(address(pool), _amount);
        pool.supply(_token, _amount, address(this), 0);
    }

    function withdraw(address _token, uint256 _amount, address _to) external onlyOwner {
        pool.withdraw(_token, _amount, _to);
    }

    function borrow(address _token, uint256 _amount) external onlyOwner {
        pool.borrow(_token, _amount, 2, 0, address(this));
    }

    function repay(address _token, uint256 _amount) external onlyOwner {
        pool.repay(_token, _amount, 2, address(this));
    }

    function rescueTokens(address _token, address _to, uint256 _amount) external onlyOwner {
        IERC20(_token).transfer(_to, _amount);
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
    string deployedContracts;
    DssInstance dss;

    address deployer;

    PoolAddressesProvider poolAddressesProvider;
    Pool pool;
    PoolConfigurator configurator;
    AaveOracle oracle;

    address[] tokens;
    address usdc;
    ReserveSettings[] originalSettings;
    uint256 i;

    function run() external {
        config = ScriptTools.readInput("config");
        deployedContracts = ScriptTools.readOutput("spark");
        dss = MCD.loadFromChainlog(config.readAddress(".chainlog"));

        poolAddressesProvider = PoolAddressesProvider(deployedContracts.readAddress(".poolAddressesProvider"));
        usdc = deployedContracts.readAddress(".USDC_token");
        pool = Pool(poolAddressesProvider.getPool());
        configurator = PoolConfigurator(poolAddressesProvider.getPoolConfigurator());
        oracle = AaveOracle(poolAddressesProvider.getPriceOracle());
        tokens = pool.getReservesList();
        uint256 numUsers = vm.envOr("NUM_USERS", (tokens.length - 1) * (tokens.length - 1));

        deployer = msg.sender;
        uint256 valuePerAssetUSD = 1;
        uint256 depositAmountPerAssetUSD = 10;

        vm.startBroadcast();
        
        // Save settings and set everything to 100% LTV (if it is allowed as collateral)
        for (i = 0; i < tokens.length; i++) {
            originalSettings.push(getReserveSettings(tokens[i]));
            if (originalSettings[i].ltv == 0) continue;
            configurator.configureReserveAsCollateral(
                tokens[i],
                9999,
                9999,
                10001
            );

            // Make sure we have enough liquidity for each asset
            if (IERC20(tokens[i]).allowance(deployer, address(pool)) < type(uint256).max) IERC20(tokens[i]).approve(address(pool), type(uint256).max);
            pool.supply(tokens[i], convertUSDToTokenAmount(tokens[i], depositAmountPerAssetUSD), deployer, 0);
        }

        // Create a bunch of positions that will be underwater with original settings
        for (i = 0; i < numUsers; i++) {
            uint256 cindex = i % tokens.length;
            if (tokens[cindex] == usdc) continue;    // USDC is not collateral (or borrowable
            uint256 bindex = (i / tokens.length) % tokens.length;
            address ctoken = tokens[cindex];
            if (!originalSettings[bindex].borrowingEnabled) {
                continue;
            }
            address btoken = tokens[bindex];
            uint256 bfactor = 10200;
            SparkUser user = new SparkUser(address(pool));
            
            // Deposit collateral
            uint256 depositAmount = convertUSDToTokenAmount(ctoken, valuePerAssetUSD);
            uint256 borrowAmount = convertUSDToTokenAmount(btoken, valuePerAssetUSD) * originalSettings[cindex].liquidationThreshold * bfactor / 1e8;
            if (IERC20(ctoken).balanceOf(deployer) >= depositAmount) {
                IERC20(ctoken).transfer(address(user), depositAmount);
            } else {
                revert("Insufficient balance");
            }
            user.supply(ctoken, depositAmount);
            user.borrow(btoken, borrowAmount);
        }

        // Restore original settings
        for (i = 0; i < originalSettings.length; i++) {
            if (originalSettings[i].ltv == 0) continue;
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

    function convertUSDToTokenAmount(address token, uint256 amountUSD) internal view returns (uint256) {
        return amountUSD * (10 ** IERC20Detailed(token).decimals()) * oracle.BASE_CURRENCY_UNIT() / oracle.getAssetPrice(token);
    }

}
