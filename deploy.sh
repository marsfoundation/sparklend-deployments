#!/bin/bash
# Deploy all contracts
set -e

echo "Deploying Aave contracts..."

export AAVE_ADMIN="$ETH_FROM"
export FOUNDRY_ROOT_CHAINID="$(cast chain-id)"
export EXPORT_DIR="script/output/$FOUNDRY_ROOT_CHAINID"
export FOUNDRY_EXPORTS_NAME="spark"

mkdir -p "$EXPORT_DIR"

forge script script/DeployAave.s.sol:DeployAave --use solc:0.8.10 --rpc-url $ETH_RPC_URL --sender $ETH_FROM --broadcast

GENERATED_FILE=`ls -tr script/output/1/spark-*.json | tail -1`
export FOUNDRY_SCRIPT_CONFIG_TEXT=`jq -c ". + { adai: $(jq ".DAI_aToken" < $GENERATED_FILE), lendingPool: $(jq ".pool" < $GENERATED_FILE) }" < script/input/$FOUNDRY_ROOT_CHAINID/d3m-spark.json`

cd lib/dss-direct-deposit

#if [ "$FOUNDRY_ROOT_CHAINID" -eq 5 ]; then
#    echo "No D3M hub on Goerli. Deploying..."
#    
#    forge script script/D3MCoreDeploy.s.sol:D3MCoreDeployScript --use solc:0.8.14 --rpc-url $ETH_RPC_URL --sender $ETH_FROM --broadcast
#
#    export FOUNDRY_SCRIPT_CONFIG_TEXT=`echo $FOUNDRY_SCRIPT_CONFIG_TEXT | jq -c ". + { hub: \"$FOUNDRY_EXPORT_HUB\" }"`
#fi

echo "Deploying D3M contracts..."

forge script script/D3MDeploy.s.sol:D3MDeployScript --use solc:0.8.14 --rpc-url $ETH_RPC_URL --sender $ETH_FROM --broadcast
GENERATED_FILE=`ls -tr script/output/1/spark-*.json | tail -1`
mv "$GENERATED_FILE" "../../$EXPORT_DIR/"

cd ../..
