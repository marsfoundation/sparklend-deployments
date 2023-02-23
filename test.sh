#!/usr/bin/env bash
set -e

export FOUNDRY_ROOT_CHAINID=`cast chain-id`

source out/contract-exports.env

if [[ -z "$1" ]]; then
    forge test --rpc-url="$ETH_RPC_URL"
else
    forge test --rpc-url="$ETH_RPC_URL" --match "$1" -vvvv
fi
