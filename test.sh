#!/usr/bin/env bash
set -e

if [ ! -f ".env-deploy" ]; then
    echo "Missing file '.env-deploy'. Run deploy script first."
    exit
fi

source ".env-deploy"

if [[ -z "$1" ]]; then
  forge test --rpc-url="$ETH_RPC_URL"
else
  forge test --rpc-url="$ETH_RPC_URL" --match "$1" -vvvv
fi
