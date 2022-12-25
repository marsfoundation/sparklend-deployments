#!/bin/bash
# Run admin init scripts as if you were the pause proxy
# Only works on an anvil fork
set -e

source out/contract-exports.env

cd dependencies/dss-direct-deposit
source out/contract-exports.env

export ETH_FROM_ORIG="$ETH_FROM"
cast rpc anvil_setBalance $MCD_PAUSE_PROXY 0x10000000000000000
cast rpc anvil_impersonateAccount $MCD_PAUSE_PROXY
unset ETH_FROM

export D3M_TYPE="aave"
export D3M_PLAN_TYPE="debt-ceiling"
export D3M_ADMIN="$MCD_PAUSE_PROXY"
export D3M_ILK="DIRECT-SPARK-DAI"
export D3M_AAVE_LENDING_POOL="$FOUNDRY_EXPORT_LENDING_POOL"
export D3M_MAX_LINE="300000000"
export D3M_GAP="300000000"

if [ $(cast chain-id) -eq 5 ]; then
    echo "Initializing D3M Core contracts..."    
    forge script script/D3MCoreInit.s.sol:D3MCoreInitScript --use solc:0.8.14 --rpc-url $ETH_RPC_URL --broadcast --unlocked --sender $MCD_PAUSE_PROXY
fi

echo "Initializing D3M contracts..."
forge script script/D3MInit.s.sol:D3MInitScript --use solc:0.8.14 --rpc-url $ETH_RPC_URL --broadcast --unlocked --sender $MCD_PAUSE_PROXY

cast rpc anvil_stopImpersonatingAccount $MCD_PAUSE_PROXY
export ETH_FROM="$ETH_FROM_ORIG"

cd ../..
