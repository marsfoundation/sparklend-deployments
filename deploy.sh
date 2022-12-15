#!/bin/bash
set -e

echo "Deploying Aave contracts..."
if [[ -z "$ETH_PASSWORD" ]]; then
    forge script script/DeployAave.s.sol:DeployAave --use solc:0.8.10 --rpc-url $ETH_RPC_URL --sender $ETH_FROM --broadcast | tee out/tmp.out
else
    PASS=$(cat $ETH_PASSWORD)

    forge script script/DeployAave.s.sol:DeployAave --use solc:0.8.10 --rpc-url $ETH_RPC_URL --sender $ETH_FROM --broadcast --password "$PASS" | tee out/tmp.out
fi

if test -f ".env-deploy"; then
    rm .env-deploy
fi
for i in $(grep "LENDING_POOL_ADDRESS_PROVIDER=" -A 5 <(cat "out/tmp.out")); do
    echo "export $i" >> .env-deploy
done
