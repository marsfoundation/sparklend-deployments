// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { IAaveOracle }         from "aave-v3-core/contracts/interfaces/IAaveOracle.sol";
import { IERC20 }              from "aave-v3-core/contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import { IPoolDataProvider }   from "aave-v3-core/contracts/interfaces/IPoolDataProvider.sol";

import { IEACAggregatorProxy }         from "aave-v3-periphery/misc/interfaces/IEACAggregatorProxy.sol";
import { IEmissionManager }            from "aave-v3-periphery/rewards/interfaces/IEmissionManager.sol";
import { IRewardsController }          from "aave-v3-periphery/rewards/interfaces/IRewardsController.sol";
import { PullRewardsTransferStrategy } from "aave-v3-periphery/rewards/transfer-strategies/PullRewardsTransferStrategy.sol";
import { RewardsDataTypes }            from "aave-v3-periphery/rewards/libraries/RewardsDataTypes.sol";

contract LidoStakedEthRewardsIntegrationTest is Test {

    IAaveOracle        aaveOracle       = IAaveOracle(0xb023e699F5a33916Ea823A16485e259257cA8Bd1);
    IPoolDataProvider  poolDataProvider = IPoolDataProvider(0x69FA688f1Dc47d4B5d8029D5a35FB7a548310654);
    IEmissionManager   emissionManager  = IEmissionManager(0x048f2228D7Bf6776f99aB50cB1b1eaB4D1d4cA73);
    IRewardsController incentives       = IRewardsController(0x929EC64c34a17401F460460D4B9390518E5B473e);

    address admin    = 0x3300f198988e4C9C63F75dF86De36421f06af8c4;  // SubDAO Proxy
    address operator = 0x8076807464DaC94Ac8Aa1f7aF31b58F73bD88A27;  // Operator multi-sig (also custodies the rewards)

    address REWARDS_TOKEN = 0xC3C7d422809852031b44ab29EEC9F1EfF2A58756;  // Reward token
    address STAKING_TOKEN = 0xEA1132120ddcDDA2F119e99Fa7A27a0d036F7Ac9;  // aToken

    uint256 REWARD_AMOUNT = 20 ether;
    uint256 DURATION      = 30 days;

    PullRewardsTransferStrategy transferStrategy;

    address whale1 = 0x7B503004695502299EfB5CfD62C34cC093e0255f;
    address whale2 = 0xD5BB24152217BEA7A617525DDFA64ea3B41B9c0a;

    function setUp() public {
        vm.createSelectFork(getChain("polygon").rpcUrl, 42000000);  // Mar 5, 2023
    }

    function test_setup_distribution_matic() public {
        console.log("block.timestamp    ", block.timestamp);
        (
            uint256 index,
            uint256 emissionPerSecond,
            uint256 lastUpdateTimestamp,
            uint256 distributionEnd
        ) = incentives.getRewardsData(STAKING_TOKEN, REWARDS_TOKEN);
        assertEq(index,               0.000574002579753002e18);
        assertEq(emissionPerSecond,   0.003100198412698414e18);
        assertEq(lastUpdateTimestamp, 1682555211);
        assertEq(distributionEnd,     1684584000);
    }

    function test_user_claim_matic() public {
        address claimAddress = makeAddr("claimAddress");
        address[] memory assets = new address[](1);
        assets[0] = STAKING_TOKEN;

        console.log("block.timestamp    ", block.timestamp);

        (
            uint256 index,
            uint256 emissionPerSecond,
            uint256 lastUpdateTimestamp,
            uint256 distributionEnd
        ) = incentives.getRewardsData(STAKING_TOKEN, REWARDS_TOKEN);

        console.log("index              ", index);
        console.log("emissionPerSecond  ", emissionPerSecond);
        console.log("lastUpdateTimestamp", lastUpdateTimestamp);
        console.log("distributionEnd    ", distributionEnd);

        assertEq(IERC20(REWARDS_TOKEN).balanceOf(claimAddress), 0);

        // 1. Claim rewards at beginning of distribution

        vm.prank(whale1);
        incentives.claimAllRewards(assets, claimAddress);
        assertEq(IERC20(REWARDS_TOKEN).balanceOf(claimAddress), 9.172189908011223608 ether);

        // 2. Warp 15 days

        uint256 skipAmount = DURATION / 2;  // 50% of rewards distributed
        skip(skipAmount);

        // 3. Snapshot state

        uint256 snapshot = vm.snapshot();

        (
            index,
            emissionPerSecond,
            lastUpdateTimestamp,
            distributionEnd
        ) = incentives.getRewardsData(STAKING_TOKEN, REWARDS_TOKEN);

        console.log("---");

        console.log("index              ", index);
        console.log("emissionPerSecond  ", emissionPerSecond);
        console.log("lastUpdateTimestamp", lastUpdateTimestamp);
        console.log("distributionEnd    ", distributionEnd);

        console.log("block.timestamp    ", block.timestamp);

        // 4. Claim rewards after 15 days (without transfer)

        vm.prank(whale1);
        incentives.claimAllRewards(assets, claimAddress);

        assertEq(IERC20(REWARDS_TOKEN).balanceOf(claimAddress), 430.384717473587677676 ether);
        assertEq(IERC20(REWARDS_TOKEN).balanceOf(operator),     0);

        // 5. Revert to reset state to before claim

        vm.revertTo(snapshot);

        address newAddress = makeAddr("newAddress");

        uint256 amount = IERC20(STAKING_TOKEN).balanceOf(whale1) / 10;

        // console2.log("amount", amount);

        // 6. Transfer 10% of staked tokens to new address

        vm.prank(whale1);
        IERC20(STAKING_TOKEN).transfer(newAddress, amount);

        // 7. Claim rewards after 15 days (with transfer)

        vm.prank(whale1);
        incentives.claimAllRewards(assets, claimAddress);

        console.log("block.timestamp    ", block.timestamp);

        assertEq(IERC20(REWARDS_TOKEN).balanceOf(claimAddress), 430.384717473587677676 ether);
        assertEq(IERC20(REWARDS_TOKEN).balanceOf(operator),     0);
    }

    // function test_multiple_users_claim() public {
    //     address claimAddress1 = makeAddr("claimAddress1");
    //     address claimAddress2 = makeAddr("claimAddress2");
    //     address[] memory assets = new address[](1);
    //     assets[0] = _getAToken(MATICX);

    //     _setupDistribution();

    //     uint256 skipAmount = DURATION / 3;  // 33% of rewards distributed
    //     skip(skipAmount);

    //     vm.prank(whale1);
    //     incentives.claimAllRewards(assets, claimAddress1);
    //     uint256 whale1Reward1 = 3.352489423741600545 ether;
    //     assertEq(IERC20(STAKING_TOKEN).balanceOf(claimAddress1), whale1Reward1);
    //     assertEq(IERC20(STAKING_TOKEN).balanceOf(operator),      REWARD_AMOUNT - whale1Reward1);

    //     vm.prank(whale2);
    //     incentives.claimAllRewards(assets, claimAddress2);
    //     uint256 whale2Reward1 = 0.423580642569205639 ether;
    //     assertEq(IERC20(STAKING_TOKEN).balanceOf(claimAddress2), whale2Reward1);
    //     assertEq(IERC20(STAKING_TOKEN).balanceOf(operator),      REWARD_AMOUNT - whale1Reward1 - whale2Reward1);

    //     skip(DURATION);  // Skip past the end of the rewards period

    //     uint256 amount = IERC20(_getAToken(MATICX)).balanceOf(whale1) / 10;

    //     console2.log("amount", amount);

    //     console2.log("whale1");

    //     vm.prank(whale1);
    //     incentives.claimAllRewards(assets, claimAddress1);
    //     uint256 whale1Reward2 = 10.057468271224879968 ether;
    //     assertEq(IERC20(STAKING_TOKEN).balanceOf(claimAddress1), whale1Reward2);
    //     assertEq(IERC20(STAKING_TOKEN).balanceOf(operator),      REWARD_AMOUNT - whale1Reward2 - whale2Reward1);

    //     vm.startPrank(whale1);
    //     IERC20(_getAToken(MATICX)).transfer(whale2, amount);
    //     vm.stopPrank();

    //     console2.log("whale2");

    //     vm.prank(whale2);
    //     incentives.claimAllRewards(assets, claimAddress2);
    //     uint256 whale2Reward2      = 1.270741927707626814 ether;
    //     uint256 finalEscrowBalance = 8.671789801067493218 ether;
    //     assertEq(IERC20(STAKING_TOKEN).balanceOf(claimAddress2), whale2Reward2);
    //     assertEq(IERC20(STAKING_TOKEN).balanceOf(operator),      REWARD_AMOUNT - whale1Reward2 - whale2Reward2);
    //     assertEq(IERC20(STAKING_TOKEN).balanceOf(operator),      finalEscrowBalance);
    // }

    // function _getAToken(address reserve) internal view returns (address aToken) {
    //     (aToken,,) = poolDataProvider.getReserveTokensAddresses(reserve);
    // }

}
