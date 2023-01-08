#!/bin/bash
# Seed the testnet with DAI and Uniswap V3 pools
set -e

source out/contract-exports.env

export AAVE_ATOKEN_IMPL="0xa034d0d238ac1fd37be61070b429f6f45e966ba8"
export AAVE_VARIABLE_DEBT_IMPL="0x742cdbcb357455c1430abd147ddd64758bec1e78"
export AAVE_STABLE_DEBT_IMPL="0x6c2bf4831a50b2dafa71a8138522378000f8f7db"
export AAVE_TREASURY="0xC80948530521E4C850a183cBf216d0d0559D4848"

echo "Add missing reserves..."   
forge script script/AddMissingReserves.s.sol:AddMissingReserves --rpc-url $ETH_RPC_URL --sender $ETH_FROM --broadcast
