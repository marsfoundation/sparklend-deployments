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
import { ACLManager } from "aave-v3-core/contracts/protocol/configuration/ACLManager.sol";
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

    function supply(address _token, uint256 _amount) public onlyOwner {
        IERC20(_token).approve(address(pool), _amount);
        pool.supply(_token, _amount, address(this), 0);
    }

    function withdraw(address _token, uint256 _amount, address _to) public onlyOwner {
        pool.withdraw(_token, _amount, _to);
    }

    function borrow(address _token, uint256 _amount) public onlyOwner {
        pool.borrow(_token, _amount, 2, 0, address(this));
    }

    function repay(address _token, uint256 _amount) public onlyOwner {
        pool.repay(_token, _amount, 2, address(this));
    }

    function setUserEMode(uint8 _categoryId) external onlyOwner {
        pool.setUserEMode(_categoryId);
    }

    function rescueTokens(address _token, address _to, uint256 _amount) external onlyOwner {
        IERC20(_token).transfer(_to, _amount);
    }

    function openPosition(
        address ctoken,
        address btoken,
        uint256 ctokenAmount,
        uint256 btokenAmount,
        uint256 ltv,
        uint256 liquidationThreshold,
        uint256 paddingFactor
    ) external onlyOwner {
        uint256 depositAmount = ctokenAmount;
        uint256 borrowAmount = btokenAmount * ltv / 1e4;
        // Spark allows you to withdraw collateral up to the liquidation threshold
        uint256 targetDepositAmount = _divup(ctokenAmount * ltv * paddingFactor, (liquidationThreshold * 1e4));
        require(depositAmount >= targetDepositAmount, "1");
        IERC20(ctoken).transferFrom(msg.sender, address(this), depositAmount);
        supply(ctoken, depositAmount);
        borrow(btoken, borrowAmount);
        withdraw(ctoken, depositAmount - targetDepositAmount, msg.sender);
    }

    function _divup(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            z = x != 0 ? ((x - 1) / y) + 1 : 0;
        }
    }

}

contract CreateLiquidations is Script {

    struct ReserveSettings {
        address asset;
        uint256 ltv;
        uint256 liquidationThreshold;
        uint256 liquidationBonus;
        bool borrowingEnabled;
        uint8 emodeCategory;
    }

    struct EModeSettings {
        uint8 category;
        uint16 ltv;
        uint16 liquidationThreshold;
        uint16 liquidationBonus;
        address oracle;
        string label;
    }

    using stdJson for string;
    using ScriptTools for string;

    string config;
    string deployedContracts;
    DssInstance dss;

    address deployer;

    PoolAddressesProvider poolAddressesProvider;
    ACLManager aclManager;
    Pool pool;
    PoolConfigurator configurator;
    AaveOracle oracle;

    address[] tokens;
    address usdc;
    address dai;
    address sdai;
    ReserveSettings[] originalSettings;
    EModeSettings[] emodeSettings;
    uint256 i;
    SparkUser[] users;
    uint256 tokensSquared;
    bool recursive;
    bool emode;
    bool crossMargin;
    uint256 paddingFactor;
    uint256 valuePerAssetUSD;
    uint256 depositAmountPerAssetUSD;

    function run() external {
        config = ScriptTools.readInput("config");
        deployedContracts = ScriptTools.readOutput("spark");
        dss = MCD.loadFromChainlog(config.readAddress(".chainlog"));

        poolAddressesProvider = PoolAddressesProvider(deployedContracts.readAddress(".poolAddressesProvider"));
        aclManager = ACLManager(poolAddressesProvider.getACLManager());
        usdc = deployedContracts.readAddress(".USDC_token");
        dai = deployedContracts.readAddress(".DAI_token");
        sdai = deployedContracts.readAddress(".sDAI_token");
        pool = Pool(poolAddressesProvider.getPool());
        configurator = PoolConfigurator(poolAddressesProvider.getPoolConfigurator());
        oracle = AaveOracle(poolAddressesProvider.getPriceOracle());
        tokens = pool.getReservesList();
        tokensSquared = tokens.length * tokens.length;
        recursive = vm.envOr("RECURSIVE_POSITIONS", false);
        emode = vm.envOr("EMODE", true);
        crossMargin = vm.envOr("CROSS_MARGIN", false);
        paddingFactor = vm.envOr("PADDING_FACTOR", uint256(10200)); // 2% under liquidation threshold is target
        valuePerAssetUSD = vm.envOr("VALUE_PER_ASSET_USD", uint256(1));
        depositAmountPerAssetUSD = vm.envOr("DEPOSIT_AMOUNT_PER_ASSET_USD", uint256(10));

        deployer = msg.sender;

        vm.startBroadcast();

        // Save settings and set everything to ~100% LTV (if it is allowed as collateral)
        for (i = 0; i < tokens.length; i++) {
            originalSettings.push(getReserveSettings(tokens[i]));
            if (originalSettings[i].ltv == 0) continue;

            // Can only change settings if we are pool admin
            if (aclManager.isPoolAdmin(deployer)) {
                configurator.configureReserveAsCollateral(
                    tokens[i],
                    9998,
                    9998,
                    10002
                );
            }

            // Make sure we have enough liquidity for each asset
            address atoken = getAToken(tokens[i]);
            IERC20 token = IERC20(tokens[i]);
            uint256 depositAmountPerAsset = convertUSDToTokenAmount(address(token), depositAmountPerAssetUSD, true);
            if (token.balanceOf(atoken) < depositAmountPerAsset) {
                uint256 amountToDeposit = depositAmountPerAsset - token.balanceOf(atoken);
                if (token.allowance(deployer, address(pool)) < amountToDeposit) token.approve(address(pool), amountToDeposit);
                pool.supply(address(token), depositAmountPerAsset, deployer, 0);
            }
        }

        // Save e-mode settings and set everything to ~100% LTV
        for (i = 1; i <= 1; i++) {
            uint8 category = uint8(i);
            emodeSettings.push(getEModeSettings(category));

            if (aclManager.isPoolAdmin(deployer)) {
                configurator.setEModeCategory(
                    category,
                    9999,
                    9999,
                    10001,
                    emodeSettings[i - 1].oracle,
                    emodeSettings[i - 1].label
                );
            }
        }

        // Create a bunch of positions that will be underwater with original settings
        for (i = 0; i < tokensSquared; i++) {
            uint256 cindex = i % tokens.length;
            if (tokens[cindex] == usdc) continue;    // USDC is not collateral (or borrowable)
            uint256 bindex = (i / tokens.length) % tokens.length;
            if (!recursive && cindex == bindex) continue;
            address ctoken = tokens[cindex];
            if (!originalSettings[bindex].borrowingEnabled) {
                continue;
            }
            address btoken = tokens[bindex];
            if (!recursive && ((btoken == dai && ctoken == sdai) || (btoken == sdai && ctoken == dai))) continue; // Count sDAI/DAI as the same asset
            SparkUser user = new SparkUser(address(pool));
            users.push(user);
            
            // Make a dangerous position
            uint256 amountToDeposit = convertUSDToTokenAmount(ctoken, valuePerAssetUSD, true);
            IERC20(ctoken).approve(address(user), amountToDeposit);
            user.openPosition(
                ctoken,
                btoken,
                amountToDeposit,
                convertUSDToTokenAmount(btoken, valuePerAssetUSD, false),
                getLTV(ctoken),
                getLiquidationThreshold(ctoken),
                paddingFactor
            );

            // Add an e-mode user if it exists
            uint8 eModeCategory = originalSettings[cindex].emodeCategory;
            if (emode && eModeCategory > 0 && eModeCategory == originalSettings[bindex].emodeCategory) {
                SparkUser emodeUser = new SparkUser(address(pool));
                emodeUser.setUserEMode(eModeCategory);
                users.push(emodeUser);

                IERC20(ctoken).approve(address(emodeUser), amountToDeposit);
                emodeUser.openPosition(
                    ctoken,
                    btoken,
                    amountToDeposit,
                    convertUSDToTokenAmount(btoken, valuePerAssetUSD, false),
                    getLTV(eModeCategory),
                    getLiquidationThreshold(eModeCategory),
                    paddingFactor
                );
            }

            // Add a cross collateralization position
            /*if (crossMargin && bindex != cindex) {
                SparkUser ccUser = new SparkUser(address(pool));
                users.push(ccUser);

                depositAmount = convertUSDToTokenAmount(ctoken, valuePerAssetUSD);
                uint256 depositAmount2 = convertUSDToTokenAmount(btoken, valuePerAssetUSD);
                borrowAmount =  convertUSDToTokenAmount(btoken, valuePerAssetUSD) * getLTV(ctoken) / 1e4 +
                                convertUSDToTokenAmount(btoken, valuePerAssetUSD) * getLTV(btoken) / 1e4;
                if (IERC20(ctoken).balanceOf(deployer) >= depositAmount) {
                    IERC20(ctoken).transfer(address(ccUser), depositAmount);
                } else {
                    revert("Insufficient balance");
                }
                if (IERC20(btoken).balanceOf(deployer) >= depositAmount2) {
                    IERC20(btoken).transfer(address(ccUser), depositAmount2);
                } else {
                    revert("Insufficient balance");
                }
                ccUser.supply(ctoken, depositAmount);
                ccUser.supply(btoken, depositAmount2);
                ccUser.borrow(btoken, borrowAmount);
            }*/
        }

        if (aclManager.isPoolAdmin(deployer)) {
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
            for (i = 0; i < emodeSettings.length; i++) {
                configurator.setEModeCategory(
                    emodeSettings[i].category,
                    emodeSettings[i].ltv,
                    emodeSettings[i].liquidationThreshold,
                    emodeSettings[i].liquidationBonus,
                    emodeSettings[i].oracle,
                    emodeSettings[i].label
                );
            }
        }

        vm.stopBroadcast();

        for (i = 0; i < users.length; i++) {
            ScriptTools.exportContract("liquidations", string(string.concat("user", bytes(vm.toString(i)))), address(users[i]));
        }
    }

    function getReserveSettings(address asset) internal view returns (ReserveSettings memory) {
        DataTypes.ReserveData memory data = pool.getReserveData(asset);
        return ReserveSettings(
            asset,
            ReserveConfiguration.getLtv(data.configuration),
            ReserveConfiguration.getLiquidationThreshold(data.configuration),
            ReserveConfiguration.getLiquidationBonus(data.configuration),
            ReserveConfiguration.getBorrowingEnabled(data.configuration),
            uint8(ReserveConfiguration.getEModeCategory(data.configuration))
        );
    }

    function getEModeSettings(uint8 category) internal view returns (EModeSettings memory) {
        DataTypes.EModeCategory memory data = pool.getEModeCategoryData(category);
        return EModeSettings(
            category,
            data.ltv,
            data.liquidationThreshold,
            data.liquidationBonus,
            data.priceSource,
            data.label
        );
    }

    function convertUSDToTokenAmount(address token, uint256 amountUSD, bool roundUp) internal view returns (uint256) {
        uint256 num = amountUSD * (10 ** IERC20Detailed(token).decimals()) * oracle.BASE_CURRENCY_UNIT();
        uint256 den = oracle.getAssetPrice(token);
        return roundUp ? _divup(num, den) : num / den;
    }

    function getLTV(address asset) internal view returns (uint256) {
        DataTypes.ReserveData memory data = pool.getReserveData(asset);
        return ReserveConfiguration.getLtv(data.configuration);
    }

    function getLiquidationThreshold(address asset) internal view returns (uint256) {
        DataTypes.ReserveData memory data = pool.getReserveData(asset);
        return ReserveConfiguration.getLiquidationThreshold(data.configuration);
    }

    function getLTV(uint8 category) internal view returns (uint256) {
        DataTypes.EModeCategory memory data = pool.getEModeCategoryData(category);
        return data.ltv;
    }

    function getLiquidationThreshold(uint8 category) internal view returns (uint256) {
        DataTypes.EModeCategory memory data = pool.getEModeCategoryData(category);
        return data.liquidationThreshold;
    }

    function getAToken(address asset) internal view returns (address) {
        DataTypes.ReserveData memory data = pool.getReserveData(asset);
        return data.aTokenAddress;
    }

    function _divup(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            z = x != 0 ? ((x - 1) / y) + 1 : 0;
        }
    }

}
