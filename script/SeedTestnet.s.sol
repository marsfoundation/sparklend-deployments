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

import { TickMath } from "../src/testnet/TickMath.sol";
import { Faucet } from "../src/testnet/Faucet.sol";
import { LiquidityAmounts } from "../src/testnet/LiquidityAmounts.sol";
import { INonfungiblePositionManager } from "../src/testnet/INonfungiblePositionManager.sol";

contract SeedTestnet is Script {

    using stdJson for string;
    using ScriptTools for string;

    string config;
    string deployedContracts;
    DssInstance dss;

    address deployer;

    PoolAddressesProvider poolAddressesProvider;
    Pool pool;
    AaveOracle oracle;

    Faucet faucet;

    IUniswapV3Factory factory;
    INonfungiblePositionManager manager;
    address[] tokens;
    address tokenA;
    address tokenB;
    uint24 fee;
    address token0;
    address token1;
    uint256 tokensToMint;
    address upool;
    uint256 perTokenDai;
    uint160 sqrtPriceX96;

    function run() external {
        config = ScriptTools.readInput("config");
        deployedContracts = ScriptTools.readOutput("spark");
        dss = MCD.loadFromChainlog(config.readAddress(".chainlog", "SEED_CHAINLOG"));

        poolAddressesProvider = PoolAddressesProvider(deployedContracts.readAddress("poolAddressesProvider"));
        pool = Pool(poolAddressesProvider.getPool());
        oracle = AaveOracle(poolAddressesProvider.getPriceOracle());
        factory = IUniswapV3Factory(vm.envAddress("UNISWAP_V3_FACTORY"));
        manager = INonfungiblePositionManager(vm.envAddress("UNISWAP_V3_POSITION_MANAGER"));
        faucet = Faucet(deployedContracts.readAddress("faucet"));

        deployer = msg.sender;

        vm.startBroadcast();
        // Add some faucet DAI to the pool to simulate a D3M deposit
        faucet.mint(address(dss.dai), 1);
        dss.dai.approve(address(pool), type(uint256).max);
        pool.supply(address(dss.dai), dss.dai.balanceOf(deployer) / 2, deployer, 0);    // Only supply half to pool (other half goes to Uni V3 pools)

        // Add tokens to each of the Uniswap V3 pools
        tokens = pool.getReservesList();
        tokenB = address(dss.dai);
        fee = 500;
        perTokenDai = dss.dai.balanceOf(deployer) / (tokens.length - 1);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenA = tokens[i];
            if (tokenA == address(dss.dai)) continue;

            // Create the pool if it doesn't exist and initialize
            (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
            upool = factory.getPool(token0, token1, fee);
            sqrtPriceX96;
            if (upool == address(0)) {
                upool = factory.createPool(token0, token1, fee);
                sqrtPriceX96 = uint160(sqrt(oracle.getAssetPrice(tokenB) * (10 ** MintableERC20(tokenA).decimals()) * (1 << 96) / (oracle.getAssetPrice(tokenA) * (10 ** MintableERC20(tokenB).decimals()))) << 48);
                IUniswapV3Pool(upool).initialize(sqrtPriceX96);
            } else {
                (sqrtPriceX96,,,,,,) = IUniswapV3Pool(upool).slot0();
            }

            // Add some liquidity to the pool
            tokensToMint = perTokenDai * oracle.getAssetPrice(tokenB) * (10 ** MintableERC20(tokenA).decimals()) * 100 / (oracle.getAssetPrice(tokenA) * (10 ** MintableERC20(tokenB).decimals()));
            faucet.mint(tokenA, tokensToMint);
            tokensToMint = MintableERC20(tokenA).balanceOf(deployer);
            MintableERC20(tokenA).approve(address(manager), type(uint256).max);
            MintableERC20(tokenB).approve(address(manager), type(uint256).max);
            manager.mint(
                INonfungiblePositionManager.MintParams({
                    token0: token0,
                    token1: token1,
                    fee: fee,
                    tickLower: TickMath.MIN_TICK + 2,
                    tickUpper: TickMath.MAX_TICK - 2,
                    amount0Desired: tokenA == token0 ? tokensToMint : perTokenDai,
                    amount1Desired: tokenA == token0 ? perTokenDai : tokensToMint,
                    amount0Min: 0,
                    amount1Min: 0,
                    recipient: deployer,
                    deadline: block.timestamp + 1 hours
                })
            );
        }
        vm.stopBroadcast();
    }

    function sqrt(uint256 _x) private pure returns (uint128) {
        if (_x == 0) return 0;
        else {
            uint256 xx = _x;
            uint256 r = 1;
            if (xx >= 0x100000000000000000000000000000000) { xx >>= 128; r <<= 64; }
            if (xx >= 0x10000000000000000) { xx >>= 64; r <<= 32; }
            if (xx >= 0x100000000) { xx >>= 32; r <<= 16; }
            if (xx >= 0x10000) { xx >>= 16; r <<= 8; }
            if (xx >= 0x100) { xx >>= 8; r <<= 4; }
            if (xx >= 0x10) { xx >>= 4; r <<= 2; }
            if (xx >= 0x8) { r <<= 1; }
            r = (r + _x / r) >> 1;
            r = (r + _x / r) >> 1;
            r = (r + _x / r) >> 1;
            r = (r + _x / r) >> 1;
            r = (r + _x / r) >> 1;
            r = (r + _x / r) >> 1;
            r = (r + _x / r) >> 1; // Seven iterations should be enough
            uint256 r1 = _x / r;
            return uint128 (r < r1 ? r : r1);
        }
    }

}
