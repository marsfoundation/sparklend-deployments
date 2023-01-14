#!/bin/bash
# Seed the testnet with DAI and Uniswap V3 pools
set -e

source out/contract-exports.env
export DEPLOY_PATH="deployments/$(cast chain-id)/active.json"
for s in $( jq -r ".transactions|map(select(.transactionType == \"CREATE\"))|to_entries|map_values(\"\(.value.contractName)=\(.value.contractAddress)\")|.[]" $DEPLOY_PATH ); do
    export "DEPLOY_$s"
done

export AAVE_ATOKEN_IMPL="$DEPLOY_AToken"
export AAVE_VARIABLE_DEBT_IMPL="$DEPLOY_VariableDebtToken"
export AAVE_STABLE_DEBT_IMPL="$DEPLOY_StableDebtToken"
export AAVE_TREASURY="$DEPLOY_Treasury"
export AAVE_DAI_TREASURY="0x902b79a11fc1F9dA1622cd190Ba676F957331112"

echo "Add missing reserves..."   
forge script script/AddMissingReserves.s.sol:AddMissingReserves --rpc-url $ETH_RPC_URL --sender $ETH_FROM --broadcast
