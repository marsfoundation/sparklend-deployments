#!/bin/bash
# Seed the testnet with DAI and Uniswap V3 pools
set -e

source out/contract-exports.env

export UNISWAP_V3_FACTORY="0x1F98431c8aD98523631AE4a59f267346ea31F984"

echo "Seeding DAI pool..."   
forge script script/SeedTestnet.s.sol:SeedTestnet --rpc-url $ETH_RPC_URL --sender $ETH_FROM --broadcast
