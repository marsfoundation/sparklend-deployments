#!/bin/bash
set -e

echo "Deploying Aave contracts..."
forge script script/DeployAave.s.sol:DeployAave --use solc:0.8.10 --rpc-url $ETH_RPC_URL --sender $ETH_FROM --broadcast
for s in $( jq -r ".transactions|to_entries|map_values(\"\(.value.contractName)=\(.value.contractAddress)\")|.[]" broadcast/DeployAave.s.sol/1/run-latest.json ); do
    export "DEPLOY_$s"
done

echo "Deploying D3M contracts..."

export D3M_TYPE="aave"
export D3M_ADMIN="$MCD_PAUSE_PROXY"
export D3M_ILK="DIRECT-SPARK-DAI"
export D3M_AAVE_LENDING_POOL="$(cast call $DEPLOY_PoolAddressesProvider 'getPool()(address)')"

cd dependencies/dss-direct-deposit
forge script script/DeployD3M.s.sol:DeployD3M --use solc:0.8.14 --rpc-url $ETH_RPC_URL --sender $ETH_FROM --broadcast
for s in $( jq -r ".transactions|to_entries|map_values(\"\(.value.contractName)=\(.value.contractAddress)\")|.[]" broadcast/DeployD3M.s.sol/1/run-latest.json ); do
    export "DEPLOY_$s"
done

export DSSTEST_EXPORT_POOL="$DEPLOY_D3MAavePool"
export DSSTEST_EXPORT_PLAN="$DEPLOY_D3MAavePlan"
export DSSTEST_EXPORT_ORACLE="$DEPLOY_D3MOracle"

cast rpc anvil_impersonateAccount $MCD_PAUSE_PROXY
forge script script/InitD3M.s.sol:InitD3M --use solc:0.8.14 --rpc-url $ETH_RPC_URL --sender $MCD_PAUSE_PROXY --broadcast
cast rpc anvil_stopImpersonatingAccount
cd ../..
