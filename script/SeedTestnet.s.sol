// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { MCD, DssInstance } from "dss-test/MCD.sol";
import { ScriptTools } from "dss-test/ScriptTools.sol";

import { PoolAddressesProvider } from "aave-v3-core/contracts/protocol/configuration/PoolAddressesProvider.sol";
import { Pool } from "aave-v3-core/contracts/protocol/pool/Pool.sol";
import { AaveOracle } from 'aave-v3-core/contracts/misc/AaveOracle.sol';
import { MintableERC20 } from "aave-v3-core/contracts/mocks/tokens/MintableERC20.sol";

import { IUniswapV3Factory } from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import { DaiFaucet } from "../src/DaiFaucet.sol";
import { LiquidityAmounts } from "../src/LiquidityAmounts.sol";

contract SeedTestnet is Script {

    using stdJson for string;
    using ScriptTools for string;

    string config;
    DssInstance dss;

    PoolAddressesProvider poolAddressesProvider;
    Pool pool;
    AaveOracle oracle;

    IUniswapV3Factory factory;

    address[] tokens;
    address tokenA;
    address tokenB;
    uint24 fee;
    address token0;
    address token1;

    function run() external {
        config = ScriptTools.readInput("config");
        dss = MCD.loadFromChainlog(config.readAddress(".chainlog", "SEED_CHAINLOG"));

        poolAddressesProvider = PoolAddressesProvider(ScriptTools.importContract("LENDING_POOL_ADDRESS_PROVIDER"));
        pool = Pool(ScriptTools.importContract("LENDING_POOL"));
        oracle = AaveOracle(poolAddressesProvider.getPriceOracle());
        factory = IUniswapV3Factory(vm.envAddress("UNISWAP_V3_FACTORY"));

        address deployer = msg.sender;

        vm.startBroadcast();
        // Add some faucet DAI to the pool to simulate a D3M deposit
        DaiFaucet daiFaucet = new DaiFaucet(dss.chainlog.getAddress("MCD_PSM_USDC_A"), dss.chainlog.getAddress("FAUCET"));
        daiFaucet.gulp(deployer, 1);
        dss.dai.approve(address(pool), type(uint256).max);
        pool.supply(address(dss.dai), dss.dai.balanceOf(deployer) / 2, deployer, 0);    // Only supply half to pool (other half goes to Uni V3 pools)

        // Add tokens to each of the Uniswap V3 pools
        tokens = pool.getReservesList();
        tokenB = address(dss.dai);
        fee = 500;
        uint256 perTokenDai = dss.dai.balanceOf(deployer) / (tokens.length - 1);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenA = tokens[i];
            if (tokenA == address(dss.dai)) continue;

            // Create the pool if it doesn't exist
            (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
            address upool = factory.getPool(token0, token1, fee);
            if (upool == address(0)) {
                upool = factory.createPool(token0, token1, fee);
            }

            // Add some liquidity to the pool
            uint256 tokensToMint = perTokenDai * oracle.getAssetPrice(tokenB) * 100 / oracle.getAssetPrice(tokenA);
            MintableERC20(tokenA).mint(deployer, tokensToMint);
            (uint160 sqrtRatioX96, , , , , , ) = IUniswapV3Pool(upool).slot0();
            IUniswapV3Pool(upool).mint(deployer, -887272, 887272, LiquidityAmounts.getLiquidityForAmounts(
                sqrtRatioX96,
                4295128739,
                1461446703485210103287273052203988822378723970342,
                tokenA == token0 ? tokensToMint : perTokenDai,
                tokenA == token0 ? perTokenDai : tokensToMint
            ), "");
        }
        vm.stopBroadcast();
    }

}
