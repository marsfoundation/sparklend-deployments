#!/bin/bash
# Deploy all contracts
set -e

echo "Deploying Aave contracts..."

export AAVE_ADMIN="$ETH_FROM"
export CHAINID="$(cast chain-id)"

rm -f out/contract-exports.env
forge script script/DeployAave.s.sol:DeployAave --use solc:0.8.10 --rpc-url $ETH_RPC_URL --sender $ETH_FROM --broadcast
source out/contract-exports.env

export FOUNDRY_SCRIPT_CONFIG_TEXT=`jq -c ". + { lendingPool: \"$FOUNDRY_EXPORT_LENDING_POOL\" }" < script/input/$CHAINID/d3m-aave.json`

cd lib/dss-direct-deposit
rm -f out/contract-exports.env

if [ $(cast chain-id) -eq 5 ]; then
    echo "No D3M hub on Goerli. Deploying..."
    
    forge script script/D3MCoreDeploy.s.sol:D3MCoreDeployScript --use solc:0.8.14 --rpc-url $ETH_RPC_URL --sender $ETH_FROM --broadcast
    source out/contract-exports.env

    export FOUNDRY_SCRIPT_CONFIG_TEXT=`echo $FOUNDRY_SCRIPT_CONFIG_TEXT | jq -c ". + { hub: \"$FOUNDRY_EXPORT_HUB\" }"`
fi

echo "Deploying D3M contracts..."

forge script script/D3MDeploy.s.sol:D3MDeployScript --use solc:0.8.14 --rpc-url $ETH_RPC_URL --sender $ETH_FROM --broadcast
source out/contract-exports.env

cd ../..
