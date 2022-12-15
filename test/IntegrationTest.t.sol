// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.10;

import "forge-std/Test.sol";

import {IERC20Detailed} from 'aave-v3-core/contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol';
import {IERC20} from 'aave-v3-core/contracts/dependencies/openzeppelin/contracts/IERC20.sol';

import {PoolAddressesProvider} from "aave-v3-core/contracts/protocol/configuration/PoolAddressesProvider.sol";
import {Pool} from "aave-v3-core/contracts/protocol/pool/Pool.sol";
import {AaveOracle} from 'aave-v3-core/contracts/misc/AaveOracle.sol';

import {DataTypes} from "aave-v3-core/contracts/protocol/libraries/types/DataTypes.sol";
import {ReserveConfiguration} from "aave-v3-core/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";

contract User {

    Pool public pool;

    constructor(Pool _pool) {
        pool = _pool;
    }

    function supply(IERC20 asset, uint256 amount) external {
        asset.approve(address(pool), amount);
        pool.supply(address(asset), amount, address(this), 0);
    }

    function borrow(IERC20 asset, uint256 amount) external {
        pool.borrow(address(asset), amount, 2, 0, address(this));
    }

    function setEMode(uint8 categoryId) external {
        pool.setUserEMode(categoryId);
    }

}

contract IntegrationTest is Test {

    PoolAddressesProvider poolAddressesProvider;
    Pool pool;
    AaveOracle aaveOracle;

    User[] users;
    address[] assets;

    function giveTokens(address token, uint256 amount) internal {
        // Edge case - balance is already set for some reason
        if (IERC20(token).balanceOf(address(this)) == amount) return;

        // Scan the storage for the balance storage slot
        for (uint256 i = 0; i < 200; i++) {
            // Solidity-style storage layout for maps
            {
                bytes32 prevValue = vm.load(
                    address(token),
                    keccak256(abi.encode(address(this), uint256(i)))
                );

                vm.store(
                    address(token),
                    keccak256(abi.encode(address(this), uint256(i))),
                    bytes32(amount)
                );
                if (IERC20(token).balanceOf(address(this)) == amount) {
                    // Found it
                    return;
                } else {
                    // Keep going after restoring the original value
                    vm.store(
                        address(token),
                        keccak256(abi.encode(address(this), uint256(i))),
                        prevValue
                    );
                }
            }

            // Vyper-style storage layout for maps
            {
                bytes32 prevValue = vm.load(
                    address(token),
                    keccak256(abi.encode(uint256(i), address(this)))
                );

                vm.store(
                    address(token),
                    keccak256(abi.encode(uint256(i), address(this))),
                    bytes32(amount)
                );
                if (IERC20(token).balanceOf(address(this)) == amount) {
                    // Found it
                    return;
                } else {
                    // Keep going after restoring the original value
                    vm.store(
                        address(token),
                        keccak256(abi.encode(uint256(i), address(this))),
                        prevValue
                    );
                }
            }
        }

        // We have failed if we reach here
        require(false, "giveTokens-slot-not-found");
    }

    function setUp() public {
        poolAddressesProvider = PoolAddressesProvider(vm.envAddress("LENDING_POOL_ADDRESS_PROVIDER"));
        pool = Pool(vm.envAddress("LENDING_POOL"));
        aaveOracle = AaveOracle(poolAddressesProvider.getPriceOracle());

        assets = pool.getReservesList();

        users.push(new User(pool));
        users.push(new User(pool));
        users.push(new User(pool));

        // Mint $100k worth of tokens for each user
        uint256 valuePerAsset = 100_000;
        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            uint256 numTokens = valuePerAsset * (10 ** IERC20Detailed(asset).decimals()) * aaveOracle.BASE_CURRENCY_UNIT() / aaveOracle.getAssetPrice(asset);
            if (i != 2) {   // Skip Lido for now stETH doesn't work
                for (uint256 o = 0; o < users.length; o++) {
                    giveTokens(asset, numTokens);
                    IERC20(asset).transfer(address(users[o]), numTokens);
                }

                // Have the first user seed all pools
                users[0].supply(IERC20(asset), numTokens);
            }
        }
    }

    function getLTV(address asset) internal view returns (uint256) {
        DataTypes.ReserveData memory borrowData = pool.getReserveData(asset);
        return ReserveConfiguration.getLtv(borrowData.configuration);
    }

    function test_borrow() public {
        User user = users[1];
        IERC20 supplyAsset = IERC20(assets[1]);
        IERC20 borrowAsset = IERC20(assets[0]);
        uint256 collateralAmount = supplyAsset.balanceOf(address(user));

        user.supply(supplyAsset, collateralAmount);
        user.borrow(borrowAsset, collateralAmount * getLTV(address(borrowAsset)) / 1e4 * aaveOracle.getAssetPrice(address(supplyAsset)) / aaveOracle.getAssetPrice(address(borrowAsset)));
    }

    function test_emode() public {
        //user2.supply(stETH, 100 ether);
        //user2.setEMode(1);
        //user2.borrow(weth, 95 ether);   // Should be able to borrow up to 95%
    }

}
