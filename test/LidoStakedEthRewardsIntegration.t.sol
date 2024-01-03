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

    IAaveOracle        aaveOracle       = IAaveOracle(0x8105f69D9C41644c6A0803fDA7D03Aa70996cFD9);
    IPoolDataProvider  poolDataProvider = IPoolDataProvider(0xFc21d6d146E6086B8359705C8b28512a983db0cb);
    IEmissionManager   emissionManager  = IEmissionManager(0xf09e48dd4CA8e76F63a57ADd428bB06fee7932a4);
    IRewardsController incentives       = IRewardsController(0x4370D3b6C9588E02ce9D22e684387859c7Ff5b34);

    address admin    = 0x3300f198988e4C9C63F75dF86De36421f06af8c4;  // SubDAO Proxy
    address operator = 0x8076807464DaC94Ac8Aa1f7aF31b58F73bD88A27;  // Operator multi-sig (also custodies the rewards)

    address WETH   = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    uint256 REWARD_AMOUNT = 20 ether;
    uint256 DURATION      = 30 days;

    PullRewardsTransferStrategy transferStrategy;

    address whale1 = 0xf8dE75c7B95edB6f1E639751318f117663021Cf0;
    address whale2 = 0xAA1582084c4f588eF9BE86F5eA1a919F86A3eE57;

    function setUp() public {
        vm.createSelectFork(getChain("mainnet").rpcUrl, 18707715);  // Dec 3rd, 2023

        transferStrategy = new PullRewardsTransferStrategy(
            address(incentives),
            admin,
            operator
        );

        deal(WSTETH, operator, REWARD_AMOUNT);

        vm.prank(operator);
        IERC20(WSTETH).approve(address(transferStrategy), REWARD_AMOUNT);

        vm.prank(admin);
        emissionManager.setEmissionAdmin(WSTETH, operator);
    }

    function _setupDistribution() internal {
        RewardsDataTypes.RewardsConfigInput[] memory configs = new RewardsDataTypes.RewardsConfigInput[](1);

        configs[0] = RewardsDataTypes.RewardsConfigInput({
            emissionPerSecond: uint88(REWARD_AMOUNT / DURATION),
            totalSupply:       0,  // Set by the rewards controller
            distributionEnd:   uint32(block.timestamp + DURATION),
            asset:             _getAToken(WETH),  // Rewards on WETH supplies
            reward:            WSTETH,
            transferStrategy:  transferStrategy,
            rewardOracle:      IEACAggregatorProxy(aaveOracle.getSourceOfAsset(WSTETH))
        });

        vm.prank(operator);
        emissionManager.configureAssets(configs);
    }

    function test_setup_distribution() public {
        address wethAToken = _getAToken(WETH);

        (
            uint256 index,
            uint256 emissionPerSecond,
            uint256 lastUpdateTimestamp,
            uint256 distributionEnd
        ) = incentives.getRewardsData(wethAToken, WSTETH);
        assertEq(index,                                  0);
        assertEq(emissionPerSecond,                      0);
        assertEq(lastUpdateTimestamp,                    0);
        assertEq(distributionEnd,                        0);
        assertEq(incentives.getTransferStrategy(WSTETH), address(0));
        assertEq(incentives.getRewardOracle(WSTETH),     address(0));


        _setupDistribution();

        (
            index,
            emissionPerSecond,
            lastUpdateTimestamp,
            distributionEnd
        ) = incentives.getRewardsData(wethAToken, WSTETH);
        assertEq(index,                                  0);
        assertEq(emissionPerSecond,                      REWARD_AMOUNT / DURATION);
        assertEq(lastUpdateTimestamp,                    block.timestamp);
        assertEq(distributionEnd,                        block.timestamp + DURATION);
        assertEq(incentives.getTransferStrategy(WSTETH), address(transferStrategy));
        assertEq(incentives.getRewardOracle(WSTETH),     address(aaveOracle.getSourceOfAsset(WSTETH)));
    }

    function test_user_claim() public {
        address claimAddress = makeAddr("claimAddress");
        address[] memory assets = new address[](1);
        assets[0] = _getAToken(WETH);

        vm.prank(whale1);
        incentives.claimAllRewards(assets, claimAddress);
        assertEq(IERC20(WSTETH).balanceOf(claimAddress), 0);

        _setupDistribution();

        vm.prank(whale1);
        incentives.claimAllRewards(assets, claimAddress);
        assertEq(IERC20(WSTETH).balanceOf(claimAddress), 0);

        uint256 skipAmount = DURATION / 2;  // 50% of rewards distributed
        skip(skipAmount);

        address newAddress = makeAddr("newAddress");

        uint256 amount = IERC20(_getAToken(WETH)).balanceOf(whale1) / 10;

        console2.log("amount", amount);

        vm.startPrank(whale1);
        IERC20(_getAToken(WETH)).transfer(newAddress, amount);

        incentives.claimAllRewards(assets, claimAddress);

        uint256 whaleReward1 = 5.028734135612479150 ether;
        assertEq(IERC20(WSTETH).balanceOf(claimAddress), whaleReward1);
        assertEq(IERC20(WSTETH).balanceOf(operator),     REWARD_AMOUNT - whaleReward1);


        // // whale1 wallet should get about half of the rewards at this time
        // // 79k ETH deposit out of 157k total supplied
        // vm.prank(whale1);
        // incentives.claimAllRewards(assets, claimAddress);
        // uint256 whaleReward1 = 5.028734135612479150 ether;
        // assertEq(IERC20(WSTETH).balanceOf(claimAddress), whaleReward1);
        // assertEq(IERC20(WSTETH).balanceOf(operator),     REWARD_AMOUNT - whaleReward1);

        // skip(DURATION - skipAmount);

        // // whale1 wallet should get about 50% of the total rewards ~10 wstETH
        // vm.prank(whale1);
        // incentives.claimAllRewards(assets, claimAddress);
        // uint256 whaleReward2 = 10.057468271224958300 ether;
        // assertEq(whaleReward2, whaleReward1 * 2);
        // assertEq(IERC20(WSTETH).balanceOf(claimAddress), whaleReward2);
        // assertEq(IERC20(WSTETH).balanceOf(operator),     REWARD_AMOUNT - whaleReward2);

        // skip(DURATION);  // Skip twice the rewards period

        // // whale1 should receive no more rewards
        // vm.prank(whale1);
        // incentives.claimAllRewards(assets, claimAddress);
        // assertEq(IERC20(WSTETH).balanceOf(claimAddress), whaleReward2);
        // assertEq(IERC20(WSTETH).balanceOf(operator),     REWARD_AMOUNT - whaleReward2);
    }

    function test_multiple_users_claim() public {
        address claimAddress1 = makeAddr("claimAddress1");
        address claimAddress2 = makeAddr("claimAddress2");
        address[] memory assets = new address[](1);
        assets[0] = _getAToken(WETH);

        _setupDistribution();

        uint256 skipAmount = DURATION / 3;  // 33% of rewards distributed
        skip(skipAmount);

        vm.prank(whale1);
        incentives.claimAllRewards(assets, claimAddress1);
        uint256 whale1Reward1 = 3.352489423741600545 ether;
        assertEq(IERC20(WSTETH).balanceOf(claimAddress1), whale1Reward1);
        assertEq(IERC20(WSTETH).balanceOf(operator),      REWARD_AMOUNT - whale1Reward1);

        vm.prank(whale2);
        incentives.claimAllRewards(assets, claimAddress2);
        uint256 whale2Reward1 = 0.423580642569205639 ether;
        assertEq(IERC20(WSTETH).balanceOf(claimAddress2), whale2Reward1);
        assertEq(IERC20(WSTETH).balanceOf(operator),      REWARD_AMOUNT - whale1Reward1 - whale2Reward1);

        skip(DURATION);  // Skip past the end of the rewards period

        uint256 amount = IERC20(_getAToken(WETH)).balanceOf(whale1) / 10;

        console2.log("amount", amount);

        console2.log("whale1");

        vm.prank(whale1);
        incentives.claimAllRewards(assets, claimAddress1);
        uint256 whale1Reward2 = 10.057468271224879968 ether;
        assertEq(IERC20(WSTETH).balanceOf(claimAddress1), whale1Reward2);
        assertEq(IERC20(WSTETH).balanceOf(operator),      REWARD_AMOUNT - whale1Reward2 - whale2Reward1);

        vm.startPrank(whale1);
        IERC20(_getAToken(WETH)).transfer(whale2, amount);
        vm.stopPrank();

        console2.log("whale2");

        vm.prank(whale2);
        incentives.claimAllRewards(assets, claimAddress2);
        uint256 whale2Reward2      = 1.270741927707626814 ether;
        uint256 finalEscrowBalance = 8.671789801067493218 ether;
        assertEq(IERC20(WSTETH).balanceOf(claimAddress2), whale2Reward2);
        assertEq(IERC20(WSTETH).balanceOf(operator),      REWARD_AMOUNT - whale1Reward2 - whale2Reward2);
        assertEq(IERC20(WSTETH).balanceOf(operator),      finalEscrowBalance);
    }

    function _getAToken(address reserve) internal view returns (address aToken) {
        (aToken,,) = poolDataProvider.getReserveTokensAddresses(reserve);
    }

}
