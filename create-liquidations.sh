#!/bin/bash
# Create liquidations for the testnet
set -e

source out/contract-exports.env

export NUM_USERS=16

echo "Creating users with liquidations..."   
forge script script/CreateLiquidations.s.sol:CreateLiquidations --rpc-url $ETH_RPC_URL --sender $ETH_FROM --broadcast
