#!/bin/bash
# Deploy all contracts
set -e

echo "Deploying Aave contracts..."

export AAVE_ADMIN="$ETH_FROM"

rm -f out/contract-exports.env
forge script script/DeployAave.s.sol:DeployAave --use solc:0.8.10 --rpc-url $ETH_RPC_URL --sender $ETH_FROM --broadcast
source out/contract-exports.env

cd lib/dss-direct-deposit
rm -f out/contract-exports.env

export D3M_TYPE="aave"
export D3M_PLAN_TYPE="debt-ceiling"
export D3M_ADMIN="$MCD_PAUSE_PROXY"
export D3M_ILK="DIRECT-SPARK-DAI"
export D3M_AAVE_LENDING_POOL="$FOUNDRY_EXPORT_LENDING_POOL"

if [ $(cast chain-id) -eq 5 ]; then
    echo "No D3M hub on Goerli. Deploying..."
    
    forge script script/D3MCoreDeploy.s.sol:D3MCoreDeployScript --use solc:0.8.14 --rpc-url $ETH_RPC_URL --sender $ETH_FROM --broadcast
    source out/contract-exports.env
fi

export D3M_HUB="$FOUNDRY_EXPORT_HUB"

echo "Deploying D3M contracts..."

forge script script/D3MDeploy.s.sol:D3MDeployScript --use solc:0.8.14 --rpc-url $ETH_RPC_URL --sender $ETH_FROM --broadcast
source out/contract-exports.env

cd ../..
