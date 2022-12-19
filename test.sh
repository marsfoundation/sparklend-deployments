#!/usr/bin/env bash
set -e

for s in $( jq -r ".transactions|to_entries|map_values(\"\(.value.contractName)=\(.value.contractAddress)\")|.[]" broadcast/DeployAave.s.sol/1/run-latest.json ); do
    export "DEPLOY_$s"
done

if [[ -z "$1" ]]; then
    forge test --rpc-url="$ETH_RPC_URL"
else
    forge test --rpc-url="$ETH_RPC_URL" --match "$1" -vvvv
fi
