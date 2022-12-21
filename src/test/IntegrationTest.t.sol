// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.10;

import "dss-test/DSSTest.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {IERC20Detailed} from 'aave-v3-core/contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol';
import {IERC20} from 'aave-v3-core/contracts/dependencies/openzeppelin/contracts/IERC20.sol';

import {PoolAddressesProvider} from "aave-v3-core/contracts/protocol/configuration/PoolAddressesProvider.sol";
import {Pool} from "aave-v3-core/contracts/protocol/pool/Pool.sol";
import {AaveOracle} from 'aave-v3-core/contracts/misc/AaveOracle.sol';

import {DataTypes} from "aave-v3-core/contracts/protocol/libraries/types/DataTypes.sol";
import {ReserveConfiguration} from "aave-v3-core/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";

interface stETHLike {
    function getTotalShares() external view returns (uint256);
}

interface D3MHubLike {
    function exec(bytes32) external;
}

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

contract IntegrationTest is DSSTest {

    using stdJson for string;
    using MCD for *;

    string config;
    DssInstance dss;

    PoolAddressesProvider poolAddressesProvider;
    Pool pool;
    AaveOracle aaveOracle;

    User[] users;
    address[] assets;

    D3MHubLike hub;
    IERC20 weth;
    IERC20 stETH;
    IERC20 wbtc;
    IERC20 dai;

    function setUp() public {
        config = ScriptTools.readInput("config");
        dss = MCD.loadFromChainlog(config.readAddress(".chainlog"));

        hub = D3MHubLike(dss.chainlog.getAddress("DIRECT_HUB"));
        weth = IERC20(dss.chainlog.getAddress("ETH"));
        stETH = IERC20(dss.chainlog.getAddress("STETH"));
        wbtc = IERC20(dss.chainlog.getAddress("WBTC"));
        dai = IERC20(dss.chainlog.getAddress("MCD_DAI"));

        poolAddressesProvider = PoolAddressesProvider(ScriptTools.importContract("LENDING_POOL_ADDRESS_PROVIDER"));
        pool = Pool(poolAddressesProvider.getPool());
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
            for (uint256 o = 0; o < users.length; o++) {
                giveTokens(asset, numTokens);
                IERC20(asset).transfer(address(users[o]), numTokens);
            }

            // Have the third user seed all pools
            users[2].supply(IERC20(asset), numTokens);
        }
    }

    function getLTV(address asset) internal view returns (uint256) {
        DataTypes.ReserveData memory data = pool.getReserveData(asset);
        return ReserveConfiguration.getLtv(data.configuration);
    }

    function getAToken(address asset) internal view returns (IERC20) {
        DataTypes.ReserveData memory data = pool.getReserveData(asset);
        return IERC20(data.aTokenAddress);
    }

    function test_d3m() public {
        IERC20 adai = getAToken(address(dai));
        uint256 prevAmount = dai.balanceOf(address(adai));

        hub.exec("DIRECT-SPARK-DAI");

        assertEq(dai.balanceOf(address(adai)), prevAmount + 300_000_000 * 10 ** 18);
    }

    function test_borrow() public {
        User user = users[0];
        IERC20 supplyAsset = weth;
        IERC20 borrowAsset = dai;
        uint256 collateralAmount = supplyAsset.balanceOf(address(user));

        user.supply(supplyAsset, collateralAmount);
        user.borrow(borrowAsset, collateralAmount * getLTV(address(borrowAsset)) / 1e4 * aaveOracle.getAssetPrice(address(supplyAsset)) / aaveOracle.getAssetPrice(address(borrowAsset)));
    }

    function test_emode() public {
        User user = users[0];
        user.setEMode(1);
        user.supply(stETH, 10 ether);
        user.borrow(weth, 8.5 ether);   // Should be able to borrow up to 85%
    }

    function _divup(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            z = x != 0 ? ((x - 1) / y) + 1 : 0;
        }
    }

    function giveTokens(address token, uint256 amount) internal {
        // Edge case - balance is already set for some reason
        if (IERC20(token).balanceOf(address(this)) == amount) return;

        // Special exceptions for rebase tokens
        uint256 convertedAmount = amount;
        if (token == address(stETH)) {
            convertedAmount = _divup(amount * stETHLike(token).getTotalShares(), IERC20(token).totalSupply());
        }

        // Scan the storage for the balance storage slot
        for (uint256 i = 0; i < 20; i++) {
            // Solidity-style storage layout for maps
            {
                bytes32 prevValue = vm.load(
                    address(token),
                    keccak256(abi.encode(address(this), uint256(i)))
                );

                vm.store(
                    address(token),
                    keccak256(abi.encode(address(this), uint256(i))),
                    bytes32(convertedAmount)
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
        }

        // We have failed if we reach here
        require(false, "giveTokens-slot-not-found");
    }

}
