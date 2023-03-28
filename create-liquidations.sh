#!/bin/bash
# Create liquidations for the testnet
set -e

export FOUNDRY_ROOT_CHAINID=1

#cast rpc anvil_setBalance $MCD_PAUSE_PROXY 0x10000000000000000 > /dev/null
#cast rpc anvil_impersonateAccount $MCD_PAUSE_PROXY > /dev/null

#cast send 0xdA135Cd78A086025BcdC87B038a1C462032b510C 'addPoolAdmin(address)' $ETH_FROM --from $MCD_PAUSE_PROXY

#cast rpc anvil_stopImpersonatingAccount $MCD_PAUSE_PROXY > /dev/null

# Give a bunch of tokens to the deployer account

# DAI
cast rpc anvil_setStorageAt $MCD_DAI `cast keccak $(cast abi-encode 'a(address,uint256)' $ETH_FROM 2)` 0x0000000000000000000000000000000000000000010000000000000000000000

# sDAI
cast send $MCD_DAI 'approve(address,uint256)' 0x83F20F44975D03b1b09e64809B757c47f942BEeA 1000000000000000000000000
cast send 0x83F20F44975D03b1b09e64809B757c47f942BEeA 'deposit(uint256,address)' 1000000000000000000000000 $ETH_FROM

# WETH
cast send 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2 'deposit()' --value 1000000000000000000000

# wstETH
cast send 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84 'submit(address)' $ETH_FROM --value 1000000000000000000000
cast send 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84 'approve(address,uint256)' 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0 1000000000000000000000
cast send 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0 'wrap(uint256)' 1000000000000000000000

# WBTC
cast rpc anvil_setStorageAt 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599 `cast keccak $(cast abi-encode 'a(address,uint256)' $ETH_FROM 0)` 0x0000000000000000000000000000000000000000010000000000000000000000

echo "Creating a bunch of positions in danger of liquidation..."

forge script script/CreateLiquidations.s.sol:CreateLiquidations --rpc-url $ETH_RPC_URL --broadcast --sender $ETH_FROM --slow
