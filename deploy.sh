#!/bin/bash
# Deploy all contracts
set -e

echo "Deploying Aave contracts..."

export FOUNDRY_ROOT_CHAINID="$(cast chain-id)"
export EXPORT_DIR="script/output/$FOUNDRY_ROOT_CHAINID"
export FOUNDRY_EXPORTS_NAME="spark"

mkdir -p "$EXPORT_DIR"

forge script script/DeployAave.s.sol:DeployAave --use solc:0.8.10 --rpc-url $ETH_RPC_URL --sender $ETH_FROM --broadcast --verify --slow

GENERATED_FILE=`ls -tr script/output/$FOUNDRY_ROOT_CHAINID/spark-*.json | tail -1`
for s in $(jq -r "to_entries|map(\"\(.key)=\(.value|tostring)\")|.[]" < $GENERATED_FILE); do
    export DEPLOY_$s
done
export FOUNDRY_SCRIPT_CONFIG_TEXT=`jq -c ". + { adai: $(jq ".DAI_aToken" < $GENERATED_FILE), lendingPool: $(jq ".pool" < $GENERATED_FILE) }" < script/input/$FOUNDRY_ROOT_CHAINID/d3m-spark.json`

# Verify the contracts (automated process not working that well)
export COMMON_ARGS="--chain-id $FOUNDRY_ROOT_CHAINID --watch"
forge verify-contract $DEPLOY_poolAddressesProviderRegistry PoolAddressesProviderRegistry $COMMON_ARGS --constructor-args `cast abi-encode 'ctor(address)' $ETH_FROM`
forge verify-contract $DEPLOY_poolAddressesProvider PoolAddressesProvider $COMMON_ARGS --constructor-args `cast abi-encode 'ctor(string,address)' 'Spark Protocol' $ETH_FROM`
forge verify-contract $DEPLOY_protocolDataProvider AaveProtocolDataProvider $COMMON_ARGS --constructor-args `cast abi-encode 'ctor(address)' $DEPLOY_poolAddressesProvider`
#forge verify-contract $DEPLOY_poolConfiguratorImpl PoolConfigurator $COMMON_ARGS // THIS IS BROKEN
forge verify-contract $DEPLOY_poolConfigurator InitializableImmutableAdminUpgradeabilityProxy $COMMON_ARGS --constructor-args `cast abi-encode 'ctor(address)' $DEPLOY_poolAddressesProvider`
#forge verify-contract $DEPLOY_poolImpl Pool $COMMON_ARGS --constructor-args `cast abi-encode 'ctor(address)' $DEPLOY_poolAddressesProvider`
forge verify-contract $DEPLOY_pool InitializableImmutableAdminUpgradeabilityProxy $COMMON_ARGS --constructor-args `cast abi-encode 'ctor(address)' $DEPLOY_poolAddressesProvider`
forge verify-contract $DEPLOY_aclManager ACLManager $COMMON_ARGS --constructor-args `cast abi-encode 'ctor(address)' $DEPLOY_poolAddressesProvider`
forge verify-contract $DEPLOY_aTokenImpl AToken $COMMON_ARGS --constructor-args `cast abi-encode 'ctor(address)' $DEPLOY_pool`
forge verify-contract $DEPLOY_stableDebtTokenImpl StableDebtToken $COMMON_ARGS --constructor-args `cast abi-encode 'ctor(address)' $DEPLOY_pool`
forge verify-contract $DEPLOY_variableDebtTokenImpl VariableDebtToken $COMMON_ARGS --constructor-args `cast abi-encode 'ctor(address)' $DEPLOY_pool`
forge verify-contract $DEPLOY_treasuryController CollectorController $COMMON_ARGS --constructor-args `cast abi-encode 'ctor(address)' $DEPLOY_admin`
forge verify-contract $DEPLOY_treasuryImpl Collector $COMMON_ARGS
forge verify-contract $DEPLOY_treasury InitializableAdminUpgradeabilityProxy $COMMON_ARGS
#forge verify-contract $DEPLOY_daiTreasuryImpl Collector $COMMON_ARGS       // THESE GET VERIFIED BY THE PREVIOUS VERIFIES
#forge verify-contract $DEPLOY_daiTreasury InitializableAdminUpgradeabilityProxy $COMMON_ARGS
forge verify-contract $DEPLOY_incentivesImpl RewardsController $COMMON_ARGS --constructor-args `cast abi-encode 'ctor(address)' $DEPLOY_emissionManager`
#forge verify-contract $DEPLOY_incentives InitializableAdminUpgradeabilityProxy $COMMON_ARGS

exit

cd lib/dss-direct-deposit

#if [ "$FOUNDRY_ROOT_CHAINID" -eq 5 ]; then
#    echo "No D3M hub on Goerli. Deploying..."
#    
#    forge script script/D3MCoreDeploy.s.sol:D3MCoreDeployScript --use solc:0.8.14 --rpc-url $ETH_RPC_URL --sender $ETH_FROM --broadcast
#
#    export FOUNDRY_SCRIPT_CONFIG_TEXT=`echo $FOUNDRY_SCRIPT_CONFIG_TEXT | jq -c ". + { hub: \"$FOUNDRY_EXPORT_HUB\" }"`
#fi

echo "Deploying D3M contracts..."

forge script script/D3MDeploy.s.sol:D3MDeployScript --use solc:0.8.14 --rpc-url $ETH_RPC_URL --sender $ETH_FROM --broadcast --verify
GENERATED_FILE=`ls -tr script/output/$FOUNDRY_ROOT_CHAINID/spark-*.json | tail -1`
mv "$GENERATED_FILE" "../../$EXPORT_DIR/"

cd ../..
