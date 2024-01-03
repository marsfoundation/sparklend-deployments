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

    address STADER     = 0x1d734A02eF1e1f5886e66b0673b71Af5B53ffA94;  // Reward token
    address APOLMATICX = 0x80cA0d8C38d2e2BcbaB66aA1648Bd1C7160500FE;  // aToken

    uint256 REWARD_AMOUNT = 20 ether;
    uint256 DURATION      = 30 days;

    PullRewardsTransferStrategy transferStrategy;

    address whale1 = 0x522DFfc539c264A8f7E0B91102E899b33f4DAbc3;
    address whale2 = 0x679cDA4FC31b4C03B967d3D7D929be69f54917b3;

    function setUp() public {
        vm.createSelectFork(getChain("polygon").rpcUrl, 51889872);  // Jan 3, 2024

        // transferStrategy = new PullRewardsTransferStrategy(
        //     address(incentives),
        //     admin,
        //     operator
        // );

        // deal(APOLMATICX, operator, REWARD_AMOUNT);

        // vm.prank(operator);
        // IERC20(APOLMATICX).approve(address(transferStrategy), REWARD_AMOUNT);

        // vm.prank(admin);
        // emissionManager.setEmissionAdmin(APOLMATICX, operator);
    }

    // function _setupDistribution() internal {
    //     RewardsDataTypes.RewardsConfigInput[] memory configs = new RewardsDataTypes.RewardsConfigInput[](1);

    //     configs[0] = RewardsDataTypes.RewardsConfigInput({
    //         emissionPerSecond: uint88(REWARD_AMOUNT / DURATION),
    //         totalSupply:       0,  // Set by the rewards controller
    //         distributionEnd:   uint32(block.timestamp + DURATION),
    //         asset:             _getAToken(MATICX),  // Rewards on MATICX supplies
    //         reward:            APOLMATICX,
    //         transferStrategy:  transferStrategy,
    //         rewardOracle:      IEACAggregatorProxy(aaveOracle.getSourceOfAsset(APOLMATICX))
    //     });

    //     vm.prank(operator);
    //     emissionManager.configureAssets(configs);
    // }

    function test_setup_distribution_matic() public {
        (
            uint256 index,
            uint256 emissionPerSecond,
            uint256 lastUpdateTimestamp,
            uint256 distributionEnd
        ) = incentives.getRewardsData(APOLMATICX, STADER);
        assertEq(index,                                  0);
        assertEq(emissionPerSecond,                      0);
        assertEq(lastUpdateTimestamp,                    0);
        assertEq(distributionEnd,                        0);
        assertEq(incentives.getTransferStrategy(APOLMATICX), address(0));
        assertEq(incentives.getRewardOracle(APOLMATICX),     address(0));


        // _setupDistribution();

        // (
        //     index,
        //     emissionPerSecond,
        //     lastUpdateTimestamp,
        //     distributionEnd
        // ) = incentives.getRewardsData(wethAToken, APOLMATICX);
        // assertEq(index,                                  0);
        // assertEq(emissionPerSecond,                      REWARD_AMOUNT / DURATION);
        // assertEq(lastUpdateTimestamp,                    block.timestamp);
        // assertEq(distributionEnd,                        block.timestamp + DURATION);
        // assertEq(incentives.getTransferStrategy(APOLMATICX), address(transferStrategy));
        // assertEq(incentives.getRewardOracle(APOLMATICX),     address(aaveOracle.getSourceOfAsset(APOLMATICX)));
    }

    function test_user_claim_matic() public {
        address claimAddress = makeAddr("claimAddress");
        address[] memory assets = new address[](1);
        assets[0] = APOLMATICX;

        vm.prank(whale1);
        incentives.claimAllRewards(assets, claimAddress);
        assertEq(IERC20(STADER).balanceOf(claimAddress), 178.046664373153971754 ether);

        uint256 skipAmount = DURATION / 2;  // 50% of rewards distributed
        skip(skipAmount);

        incentives.claimAllRewards(assets, claimAddress);

        assertEq(IERC20(STADER).balanceOf(claimAddress), 178.046664373153971754 ether);
        assertEq(IERC20(STADER).balanceOf(operator),     0);

        // address newAddress = makeAddr("newAddress");

        // uint256 amount = IERC20(APOLMATICX).balanceOf(whale1) / 10;

        // console2.log("amount", amount);

        // vm.startPrank(whale1);
        // IERC20(APOLMATICX).transfer(newAddress, amount);
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
    //     assertEq(IERC20(APOLMATICX).balanceOf(claimAddress1), whale1Reward1);
    //     assertEq(IERC20(APOLMATICX).balanceOf(operator),      REWARD_AMOUNT - whale1Reward1);

    //     vm.prank(whale2);
    //     incentives.claimAllRewards(assets, claimAddress2);
    //     uint256 whale2Reward1 = 0.423580642569205639 ether;
    //     assertEq(IERC20(APOLMATICX).balanceOf(claimAddress2), whale2Reward1);
    //     assertEq(IERC20(APOLMATICX).balanceOf(operator),      REWARD_AMOUNT - whale1Reward1 - whale2Reward1);

    //     skip(DURATION);  // Skip past the end of the rewards period

    //     uint256 amount = IERC20(_getAToken(MATICX)).balanceOf(whale1) / 10;

    //     console2.log("amount", amount);

    //     console2.log("whale1");

    //     vm.prank(whale1);
    //     incentives.claimAllRewards(assets, claimAddress1);
    //     uint256 whale1Reward2 = 10.057468271224879968 ether;
    //     assertEq(IERC20(APOLMATICX).balanceOf(claimAddress1), whale1Reward2);
    //     assertEq(IERC20(APOLMATICX).balanceOf(operator),      REWARD_AMOUNT - whale1Reward2 - whale2Reward1);

    //     vm.startPrank(whale1);
    //     IERC20(_getAToken(MATICX)).transfer(whale2, amount);
    //     vm.stopPrank();

    //     console2.log("whale2");

    //     vm.prank(whale2);
    //     incentives.claimAllRewards(assets, claimAddress2);
    //     uint256 whale2Reward2      = 1.270741927707626814 ether;
    //     uint256 finalEscrowBalance = 8.671789801067493218 ether;
    //     assertEq(IERC20(APOLMATICX).balanceOf(claimAddress2), whale2Reward2);
    //     assertEq(IERC20(APOLMATICX).balanceOf(operator),      REWARD_AMOUNT - whale1Reward2 - whale2Reward2);
    //     assertEq(IERC20(APOLMATICX).balanceOf(operator),      finalEscrowBalance);
    // }

    // function _getAToken(address reserve) internal view returns (address aToken) {
    //     (aToken,,) = poolDataProvider.getReserveTokensAddresses(reserve);
    // }

}
