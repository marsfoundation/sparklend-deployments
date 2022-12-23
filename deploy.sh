#!/bin/bash
set -e

export ETH_FROM_ORIG="$ETH_FROM"
cast rpc anvil_setBalance $MCD_PAUSE_PROXY 0x10000000000000000

echo "Deploying Aave contracts..."

export AAVE_ADMIN="$ETH_FROM"

rm -f out/contract-exports.env
forge script script/DeployAave.s.sol:DeployAave --use solc:0.8.10 --rpc-url $ETH_RPC_URL --sender $ETH_FROM --broadcast
source out/contract-exports.env

cd dependencies/dss-direct-deposit

export D3M_TYPE="aave"
export D3M_PLAN_TYPE="debt-ceiling"
export D3M_ADMIN="$MCD_PAUSE_PROXY"
export D3M_ILK="DIRECT-SPARK-DAI"
export D3M_AAVE_LENDING_POOL="$FOUNDRY_EXPORT_LENDING_POOL"

if [ $(cast chain-id) -eq 5 ]; then
    echo "No D3M hub on Goerli. Deploying..."
    
    rm -f out/contract-exports.env
    forge script script/D3MCoreDeploy.s.sol:D3MCoreDeployScript --use solc:0.8.14 --rpc-url $ETH_RPC_URL --sender $ETH_FROM --broadcast
    source out/contract-exports.env

    cast rpc anvil_impersonateAccount $MCD_PAUSE_PROXY
    unset ETH_FROM
    forge script script/D3MCoreInit.s.sol:D3MCoreInitScript --use solc:0.8.14 --rpc-url $ETH_RPC_URL --broadcast --unlocked --sender $MCD_PAUSE_PROXY
    cast rpc anvil_stopImpersonatingAccount $MCD_PAUSE_PROXY
    export ETH_FROM="$ETH_FROM_ORIG"
fi

echo "Deploying D3M contracts..."

rm -f out/contract-exports.env
forge script script/D3MDeploy.s.sol:D3MDeployScript --use solc:0.8.14 --rpc-url $ETH_RPC_URL --sender $ETH_FROM --broadcast
source out/contract-exports.env

echo "Initializing D3M contracts..."

export D3M_MAX_LINE="300000000"
export D3M_GAP="300000000"

cast rpc anvil_impersonateAccount $MCD_PAUSE_PROXY
unset ETH_FROM
forge script script/D3MInit.s.sol:D3MInitScript --use solc:0.8.14 --rpc-url $ETH_RPC_URL --broadcast --unlocked --sender $MCD_PAUSE_PROXY
cast rpc anvil_stopImpersonatingAccount $MCD_PAUSE_PROXY
export ETH_FROM="$ETH_FROM_ORIG"
cd ../..
