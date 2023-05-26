#!/bin/bash
# Deploy all contracts
set -e

echo "Deploying Aave contracts..."

export FOUNDRY_ROOT_CHAINID="$(cast chain-id)"
export EXPORT_DIR="script/output/$FOUNDRY_ROOT_CHAINID"
export FOUNDRY_EXPORTS_NAME="spark"

mkdir -p "$EXPORT_DIR"

if [ "$FOUNDRY_ROOT_CHAINID" -eq 1 ]; then
    # Mainnet
    export LIBS="--libraries lib/aave-v3-core/contracts/protocol/libraries/logic/BorrowLogic.sol:BorrowLogic:0x39fb3e784012eb3e650bf79b6909d857e0a49f0c --libraries lib/aave-v3-core/contracts/protocol/libraries/logic/BridgeLogic.sol:BridgeLogic:0x7f3e0bbf4aaee28abc2cfbd571fc2b983662ad52 --libraries lib/aave-v3-core/contracts/protocol/libraries/logic/ConfiguratorLogic.sol:ConfiguratorLogic:0x66ac02c3120b848d65231ce977af3db1f60b97f9 --libraries lib/aave-v3-core/contracts/protocol/libraries/logic/EModeLogic.sol:EModeLogic:0x202f310828467bb04680a8fe879a7d1814677a24 --libraries lib/aave-v3-core/contracts/protocol/libraries/logic/FlashLoanLogic.sol:FlashLoanLogic:0x111b4b22ee7ea68703d8e54ea49aa1bb0d158128 --libraries lib/aave-v3-core/contracts/protocol/libraries/logic/LiquidationLogic.sol:LiquidationLogic:0x6d0bc1defe4379d9cb86bcd8d7c005413ab0e8fb --libraries lib/aave-v3-core/contracts/protocol/libraries/logic/PoolLogic.sol:PoolLogic:0xbc6d76108729be0e85938845b74c2f8ab88b7ea6 --libraries lib/aave-v3-core/contracts/protocol/libraries/logic/SupplyLogic.sol:SupplyLogic:0x666835b336a3a5198b2895d94109131d1b23ad11"
else
    # Goerli
    export LIBS="--libraries lib/aave-v3-core/contracts/protocol/libraries/logic/BorrowLogic.sol:BorrowLogic:0xF606870D702263235F8BA0bC49cA64Ff3eE8F832 --libraries lib/aave-v3-core/contracts/protocol/libraries/logic/BridgeLogic.sol:BridgeLogic:0xB9C222C708E10ef9287a16bdfe7Eed7B2c5b5E7E --libraries lib/aave-v3-core/contracts/protocol/libraries/logic/ConfiguratorLogic.sol:ConfiguratorLogic:0xc7129924D87043D8B12Ae879e161a0d378080f31 --libraries lib/aave-v3-core/contracts/protocol/libraries/logic/EModeLogic.sol:EModeLogic:0x3Ee111c3fb80Ad67F80305Ac0d51B16A357aF7f1 --libraries lib/aave-v3-core/contracts/protocol/libraries/logic/FlashLoanLogic.sol:FlashLoanLogic:0x2C8E811e12B46FF39f17b968fdf9309Ef88751Db --libraries lib/aave-v3-core/contracts/protocol/libraries/logic/LiquidationLogic.sol:LiquidationLogic:0x28298a3e41c41246080E8BBE09B2E886a180D9fe --libraries lib/aave-v3-core/contracts/protocol/libraries/logic/PoolLogic.sol:PoolLogic:0xCE5f067F3D0AEe076EB6122c8989A48f82f2499a --libraries lib/aave-v3-core/contracts/protocol/libraries/logic/SupplyLogic.sol:SupplyLogic:0x96177A6e8226D0CE86eeB133c5C9e47FD5fAdd13"
fi

forge script script/DeployAave.s.sol:DeployAave --rpc-url $ETH_RPC_URL --sender $ETH_FROM --optimizer-runs 100000 --broadcast --verify --slow $LIBS

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
