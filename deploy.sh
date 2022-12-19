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

echo "Initializing D3M contracts..."

export DSSTEST_EXPORT_POOL="$DEPLOY_D3MAavePool"
export DSSTEST_EXPORT_PLAN="$DEPLOY_D3MAavePlan"
export DSSTEST_EXPORT_ORACLE="$DEPLOY_D3MOracle"

cast rpc anvil_setBalance $MCD_PAUSE_PROXY 0x10000000000000000
cast rpc anvil_impersonateAccount $MCD_PAUSE_PROXY
forge script script/InitD3M.s.sol:InitD3M --use solc:0.8.14 --rpc-url $ETH_RPC_URL --sender $MCD_PAUSE_PROXY
# Can't impersonate with forge script so broadcast all the txs manually
for s in $( jq -r ".transactions|to_entries|map_values(\"\(.value.transaction.to):\(.value.transaction.data)\")|.[]" broadcast/InitD3M.s.sol/1/dry-run/run-latest.json ); do
    cast send --from $MCD_PAUSE_PROXY "$(echo $s | cut -d ':' -f 1)" "$(echo $s | cut -d ':' -f 2)"
done
cast rpc anvil_stopImpersonatingAccount $MCD_PAUSE_PROXY
cd ../..
