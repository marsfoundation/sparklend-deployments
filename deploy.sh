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
export LIBS_IN="$(jq -c '.libraries[]' < broadcast/DeployAave.s.sol/$FOUNDRY_ROOT_CHAINID/run-latest.json | sed 's/"//g')"
export LIBS=""
for l in $LIBS_IN; do
    ADDR="$(cast --to-checksum-address `echo $l | cut -d':' -f3`)"
    export LIBS="$LIBS --libraries `echo $l | cut -d':' -f1`:`echo $l | cut -d':' -f2`:$ADDR"
done
export COMMON_ARGS="--chain-id $FOUNDRY_ROOT_CHAINID --watch $LIBS"
forge verify-contract $DEPLOY_poolAddressesProviderRegistry PoolAddressesProviderRegistry $COMMON_ARGS --constructor-args `cast abi-encode 'ctor(address)' $ETH_FROM`
forge verify-contract $DEPLOY_poolAddressesProvider PoolAddressesProvider $COMMON_ARGS --constructor-args `cast abi-encode 'ctor(string,address)' 'Spark Protocol' $ETH_FROM`
forge verify-contract $DEPLOY_protocolDataProvider AaveProtocolDataProvider $COMMON_ARGS --constructor-args `cast abi-encode 'ctor(address)' $DEPLOY_poolAddressesProvider`
forge verify-contract $DEPLOY_poolConfiguratorImpl PoolConfigurator $COMMON_ARGS
forge verify-contract $DEPLOY_poolConfigurator InitializableImmutableAdminUpgradeabilityProxy $COMMON_ARGS --constructor-args `cast abi-encode 'ctor(address)' $DEPLOY_poolAddressesProvider`
# BUG IN FOUNDRY - Two versions of BorrowLogic being deployed, fix this
#forge verify-contract $DEPLOY_poolImpl Pool $COMMON_ARGS --constructor-args `cast abi-encode 'ctor(address)' $DEPLOY_poolAddressesProvider`
forge verify-contract $DEPLOY_pool InitializableImmutableAdminUpgradeabilityProxy $COMMON_ARGS --constructor-args `cast abi-encode 'ctor(address)' $DEPLOY_poolAddressesProvider`
forge verify-contract $DEPLOY_aclManager ACLManager $COMMON_ARGS --constructor-args `cast abi-encode 'ctor(address)' $DEPLOY_poolAddressesProvider`
forge verify-contract $DEPLOY_aTokenImpl AToken $COMMON_ARGS --constructor-args `cast abi-encode 'ctor(address)' $DEPLOY_pool`
forge verify-contract $DEPLOY_stableDebtTokenImpl StableDebtToken $COMMON_ARGS --constructor-args `cast abi-encode 'ctor(address)' $DEPLOY_pool`
forge verify-contract $DEPLOY_variableDebtTokenImpl VariableDebtToken $COMMON_ARGS --constructor-args `cast abi-encode 'ctor(address)' $DEPLOY_pool`
forge verify-contract $DEPLOY_treasuryController CollectorController $COMMON_ARGS --constructor-args `cast abi-encode 'ctor(address)' $DEPLOY_admin`
forge verify-contract $DEPLOY_treasuryImpl Collector $COMMON_ARGS
forge verify-contract $DEPLOY_treasury InitializableAdminUpgradeabilityProxy $COMMON_ARGS
# THESE GET VERIFIED BY THE PREVIOUS VERIFIES
#forge verify-contract $DEPLOY_daiTreasuryImpl Collector $COMMON_ARGS
#forge verify-contract $DEPLOY_daiTreasury InitializableAdminUpgradeabilityProxy $COMMON_ARGS
forge verify-contract $DEPLOY_incentivesImpl RewardsController $COMMON_ARGS --constructor-args `cast abi-encode 'ctor(address)' $DEPLOY_emissionManager`
#forge verify-contract $DEPLOY_incentives InitializableAdminUpgradeabilityProxy $COMMON_ARGS
forge verify-contract $DEPLOY_uiPoolDataProvider UiPoolDataProviderV3 $COMMON_ARGS --constructor-args `cast abi-encode 'ctor(address,address)' $DEPLOY_WETH_oracle $DEPLOY_WETH_oracle`
forge verify-contract $DEPLOY_uiIncentiveDataProvider UiIncentiveDataProviderV3 $COMMON_ARGS
forge verify-contract $DEPLOY_wethGateway WrappedTokenGatewayV3 $COMMON_ARGS --constructor-args `cast abi-encode 'ctor(address,address,address)' $DEPLOY_WETH_token $DEPLOY_admin $DEPLOY_pool`
forge verify-contract $DEPLOY_walletBalanceProvider WalletBalanceProvider $COMMON_ARGS
ORACLE_ASSET_ADDRESSES="$DEPLOY_DAI_token,$DEPLOY_sDAI_token,$DEPLOY_USDC_token,$DEPLOY_WETH_token,$DEPLOY_wstETH_token,$DEPLOY_WBTC_token"
ORACLE_ASSET_SOURCES="$DEPLOY_DAI_oracle,$DEPLOY_sDAI_oracle,$DEPLOY_USDC_oracle,$DEPLOY_WETH_oracle,$DEPLOY_wstETH_oracle,$DEPLOY_WBTC_oracle"
forge verify-contract $DEPLOY_aaveOracle AaveOracle $COMMON_ARGS --constructor-args `cast abi-encode 'ctor(address,address[],address[],address,address,uint256)' $DEPLOY_poolAddressesProvider \[$ORACLE_ASSET_ADDRESSES\] \[$ORACLE_ASSET_SOURCES\] 0x0000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000 100000000`
# TODO oracle verify

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
