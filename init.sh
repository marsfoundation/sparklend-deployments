#!/bin/bash
# Run admin init scripts as if you were the pause proxy
# Only works on an anvil fork
set -e

export FOUNDRY_ROOT_CHAINID="$(cast chain-id)"
export FOUNDRY_SCRIPT_CONFIG_TEXT=`jq -c < script/input/$FOUNDRY_ROOT_CHAINID/d3m-spark.json`

cd lib/dss-direct-deposit

cast rpc anvil_setBalance $MCD_PAUSE_PROXY 0x10000000000000000 > null
cast rpc anvil_impersonateAccount $MCD_PAUSE_PROXY > null
unset ETH_FROM

#if [ $(cast chain-id) -eq 5 ]; then
#    echo "Initializing D3M Core contracts..."    
#    forge script script/D3MCoreInit.s.sol:D3MCoreInitScript --use solc:0.8.14 --rpc-url $ETH_RPC_URL --broadcast --unlocked --sender $MCD_PAUSE_PROXY
#fi

echo "Initializing D3M contracts..."
forge script script/D3MInit.s.sol:D3MInitScript --use solc:0.8.14 --rpc-url $ETH_RPC_URL --broadcast --unlocked --sender $MCD_PAUSE_PROXY

cast rpc anvil_stopImpersonatingAccount $MCD_PAUSE_PROXY > null

cd ../..
