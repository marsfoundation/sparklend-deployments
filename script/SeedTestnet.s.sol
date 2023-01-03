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

import { DaiFaucet } from "../src/DaiFaucet.sol";

interface UniswapV3FactoryLike {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool);
}

interface UniswapV3PoolLike {
    function mint(address to, int24 tickLower, int24 tickUpper, uint128 amount, bytes calldata data) external;
}

contract SeedTestnet is Script {

    using stdJson for string;
    using ScriptTools for string;

    string config;
    DssInstance dss;

    PoolAddressesProvider poolAddressesProvider;
    Pool pool;
    AaveOracle oracle;
    UniswapV3FactoryLike factory;

    function run() external {
        config = ScriptTools.readInput("config");
        dss = MCD.loadFromChainlog(config.readAddress(".chainlog", "SEED_CHAINLOG"));

        poolAddressProvider = PoolAddressesProvider(ScriptTools.importContract("LENDING_POOL_ADDRESS_PROVIDER"));
        pool = Pool(ScriptTools.importContract("LENDING_POOL"));
        oracle = AaveOracle(poolAddressProvider.getPriceOracle());
        factory = UniswapV3FactoryLike(vm.envAddr("UNISWAP_V3_FACTORY"));

        address deployer = msg.sender;

        vm.startBroadcast();
        // Add some faucet DAI to the pool to simulate a D3M deposit
        DaiFaucet daiFaucet = new DaiFaucet(dss.chainlog.getAddress("MCD_PSM_USDC_A"), dss.chainlog.getAddress("FAUCET"));
        daiFaucet.gulp(deployer, 1);
        dss.dai.approve(address(pool), type(uint256).max);
        pool.supply(address(dss.dai), dss.dai.balanceOf(deployer) / 2, deployer, 0);    // Only supply half to pool (other half goes to Uni V3 pools)

        // Add tokens to each of the Uniswap V3 pools
        address[] memory tokens = pool.getReservesList();
        address tokenB = address(dss.dai);
        uint24 fee = 500;
        uint256 perTokenDai = dss.dai.balanceOf(deployer) / (tokens.length - 1);
        for (uint256 i = 0; i < tokens.length; i++) {
            address tokenA = tokens[i];
            if (tokenA == address(dss.dai)) continue;

            // Create the pool if it doesn't exist
            (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
            address pool = factory.getPool(token0, token1, fee);
            if (pool == address(0)) {
                pool = factory.createPool(token0, token1, fee);
            }

            // Add some liquidity to the pool
            MintableERC20(tokenA).mint(deployer, amtToMint);
            UniswapV3PoolLike(pool).mint(deployer, -887272, 887272, amtToMint, "");
        }
        vm.stopBroadcast();
    }

}
