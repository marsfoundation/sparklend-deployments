#!/bin/bash
set -e

echo "Deploying Aave contracts..."
forge script script/DeployAave.s.sol:DeployAave --use solc:0.8.10 --rpc-url $ETH_RPC_URL --sender $ETH_FROM --broadcast
loaddeploy broadcast/DeployAave.s.sol/1/run-latest.json

echo "Deploying D3M contracts..."

export DEPLOY_D3M_TYPE="aave"
export DEPLOY_ADMIN="$ETH_FROM"
export DEPLOY_ILK="DIRECT-SPARK-DAI"
export DEPLOY_AAVE_LENDING_POOL="$DEPLOY_Pool"

forge script dependencies/dss-direct-deposit/script/DeployD3M.s.sol:DeployD3M --use solc:0.8.14 --rpc-url $ETH_RPC_URL --sender $ETH_FROM --broadcast
