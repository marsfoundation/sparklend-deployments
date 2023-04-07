// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from 'forge-std/Test.sol';
import {console} from 'forge-std/console.sol';

import {AaveV2Ethereum} from 'aave-address-book/AaveV2Ethereum.sol';

import {IERC20} from 'solidity-utils/contracts/oz-common/interfaces/IERC20.sol';
import {ICreditDelegationToken} from 'V2-V3-migration-helpers/src/interfaces/ICreditDelegationToken.sol';
import {IMigrationHelper} from 'V2-V3-migration-helpers/src/interfaces/IMigrationHelper.sol';
import {IERC20WithATokenCompatibility} from 'V2-V3-migration-helpers/tests/helpers/IERC20WithATokenCompatibility.sol';

import {DataTypes as DataTypesV2, IAaveProtocolDataProvider} from 'aave-address-book/AaveV2.sol';
import {DataTypes, IAaveProtocolDataProvider as IAaveProtocolDataProviderV3} from 'aave-address-book/AaveV3.sol';

import {SparkMigrationHelper, IERC20WithPermit} from '../SparkMigrationHelper.sol';

import {SigUtils} from 'V2-V3-migration-helpers/tests/helpers/SigUtils.sol';

contract MigrationHelperTest is Test {
  IAaveProtocolDataProvider public v2DataProvider;
  IAaveProtocolDataProviderV3 public v3DataProvider;
  SparkMigrationHelper public migrationHelper;
  SigUtils public sigUtils;

  address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
  address public constant ETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

  address[] public usersSimple;
  address[] public usersWithDebt;
  address[] public v2Reserves;

  mapping(address => uint256) private assetsIndex;

  function setUp() public {
    migrationHelper = new SparkMigrationHelper();

    v2DataProvider = AaveV2Ethereum.AAVE_PROTOCOL_DATA_PROVIDER;
    v3DataProvider = IAaveProtocolDataProviderV3(0xFc21d6d146E6086B8359705C8b28512a983db0cb);
    v2Reserves = migrationHelper.V2_POOL().getReservesList();

    sigUtils = new SigUtils();

    // Make sure there is enough liquidity to do flash loans
    deal(DAI, migrationHelper.V3_POOL().getReserveData(DAI).aTokenAddress, 100000e18);
    deal(ETH, migrationHelper.V3_POOL().getReserveData(ETH).aTokenAddress, 100e18);

    // @dev users who has only supplied positions, no borrowings
    usersSimple = new address[](17);
    usersSimple[0] = 0x5FFAcBDaA5754224105879c03392ef9FE6ae0c17;
    usersSimple[1] = 0x5d3f81Ad171616571BF3119a3120E392B914Fd7C;
    usersSimple[2] = 0x07F294e84a9574f657A473f94A242F1FdFAFB823;
    usersSimple[3] = 0x7734280A4337F37Fbf4651073Db7c28C80B339e9;
    usersSimple[4] = 0x000000003853FCeDcd0355feC98cA3192833F00b;
    usersSimple[5] = 0xbeC1101FF3f3474A3789Bb18A88117C169178d9F;
    usersSimple[6] = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F;
    usersSimple[7] = 0x004C572659319871bE9D4ab337fB3Df6237979D7;
    usersSimple[8] = 0x0134af0F5cf7C32128231deA65B52Bb892780bae;
    usersSimple[9] = 0x0040a8fbD83A82c0742923C6802C3d9a22128d1c;
    usersSimple[10] = 0x00F63722233F5e19010e5daF208472A8F27D304B;
    usersSimple[11] = 0x114558d984bb24FDDa0CD279Ffd5F073F2d44F49;
    usersSimple[12] = 0x17B23Be942458E6EfC17F000976A490EC428f49A;
    usersSimple[13] = 0x7c0714297f15599E7430332FE45e45887d7Da341;
    usersSimple[14] = 0x1776Fd7CCf75C889d62Cd03B5116342EB13268Bc;
    usersSimple[15] = 0x53498839353845a30745b56a22524Df934F746dE;
    usersSimple[16] = 0x3126ffE1334d892e0c53d8e2Fc83a605DcDCf037;
  }

  function testCacheATokens() public {
    for (uint256 i = 0; i < v2Reserves.length; i++) {
      DataTypesV2.ReserveData memory reserveData = migrationHelper.V2_POOL().getReserveData(
        v2Reserves[i]
      );
      assertEq(address(migrationHelper.aTokens(v2Reserves[i])), reserveData.aTokenAddress);

      uint256 maxApproval = type(uint256).max;
      if (v2Reserves[i] == 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984) {
        maxApproval = type(uint96).max;
      }

      uint256 allowanceToPoolV2 = IERC20(v2Reserves[i]).allowance(
        address(migrationHelper),
        address(migrationHelper.V2_POOL())
      );
      assertEq(allowanceToPoolV2, maxApproval);

      uint256 allowanceToPool = IERC20(v2Reserves[i]).allowance(
        address(migrationHelper),
        address(migrationHelper.V3_POOL())
      );
      assertEq(allowanceToPool, maxApproval);
    }
  }

  /*function testMigrationNoBorrowNoPermit() public {
    address[] memory suppliedPositions;
    uint256[] memory suppliedBalances;
    IMigrationHelper.RepayInput[] memory borrowedPositions;

    for (uint256 i = 0; i < usersSimple.length; i++) {
      // get positions
      (suppliedPositions, suppliedBalances, borrowedPositions) = _getV2UserPosition(usersSimple[i]);

      require(
        borrowedPositions.length == 0 && suppliedPositions.length != 0,
        'BAD_USER_FOR_THIS_TEST'
      );

      vm.startPrank(usersSimple[i]);
      // approve aTokens to helper
      for (uint256 j = 0; j < suppliedPositions.length; j++) {
        migrationHelper.aTokens(suppliedPositions[j]).approve(
          address(migrationHelper),
          type(uint256).max
        );
      }

      // migrate positions to V3
      migrationHelper.migrate(
        suppliedPositions,
        new IMigrationHelper.RepaySimpleInput[](0),
        new IMigrationHelper.PermitInput[](0),
        new IMigrationHelper.CreditDelegationInput[](0)
      );

      vm.stopPrank();

      // check that positions were migrated successfully
      _checkMigratedSupplies(usersSimple[i], suppliedPositions, suppliedBalances);
    }
  }*/

  function testMigrationNoBorrowWithPermit() public {
    (address user, uint256 privateKey) = _getUserWithPosition();

    // get positions
    (address[] memory suppliedPositions, uint256[] memory suppliedBalances, ) = _getV2UserPosition(
      user
    );

    // calculate permits
    IMigrationHelper.PermitInput[] memory permits = _getPermits(
      user,
      privateKey,
      suppliedPositions,
      suppliedBalances
    );

    vm.startPrank(user);

    // migrate positions to V3
    migrationHelper.migrate(
      suppliedPositions,
      new IMigrationHelper.RepaySimpleInput[](0),
      permits,
      new IMigrationHelper.CreditDelegationInput[](0)
    );

    vm.stopPrank();

    // check that positions were migrated successfully
    _checkMigratedSupplies(user, suppliedPositions, suppliedBalances);
  }

  function testMigrationWithCreditDelegation() public {
    (address user, uint256 privateKey) = _getUserWithBorrowPosition();
    // get positions
    (
      address[] memory suppliedPositions,
      uint256[] memory suppliedBalances,
      IMigrationHelper.RepayInput[] memory positionsToRepay
    ) = _getV2UserPosition(user);

    IMigrationHelper.RepaySimpleInput[] memory positionsToRepaySimple = _getSimplePositionsToRepay(
      positionsToRepay
    );

    // calculate permits
    IMigrationHelper.PermitInput[] memory permits = _getPermits(
      user,
      privateKey,
      suppliedPositions,
      suppliedBalances
    );

    // calculate credit
    IMigrationHelper.CreditDelegationInput[] memory creditDelegations = _getCreditDelegations(
      user,
      privateKey,
      positionsToRepay
    );

    // migrate positions to V3
    vm.startPrank(user);

    migrationHelper.migrate(suppliedPositions, positionsToRepaySimple, permits, creditDelegations);

    vm.stopPrank();

    // check that positions were migrated successfully
    _checkMigratedSupplies(user, suppliedPositions, suppliedBalances);

    _checkMigratedBorrowings(user, positionsToRepay);
  }

  function _checkMigratedSupplies(
    address user,
    address[] memory suppliedPositions,
    uint256[] memory suppliedBalances
  ) internal {
    for (uint256 i = 0; i < suppliedPositions.length; i++) {
        if (suppliedPositions[i] == USDC) {
            suppliedPositions[i] = DAI;
            suppliedBalances[i] = suppliedBalances[i] * 10**12;
        }
      (uint256 currentATokenBalance, , , , , , , , ) = v3DataProvider.getUserReserveData(
        suppliedPositions[i],
        user
      );

      assertTrue(currentATokenBalance >= suppliedBalances[i], "supply not migrated");
    }
  }

  function _checkMigratedBorrowings(
    address user,
    IMigrationHelper.RepayInput[] memory borrowedPositions
  ) internal {
    for (uint256 i = 0; i < borrowedPositions.length; i++) {
        if (borrowedPositions[i].asset == USDC) {
            borrowedPositions[i].asset = DAI;
            borrowedPositions[i].amount = borrowedPositions[i].amount * 10**12;
        }
      (, , uint256 currentVariableDebt, , , , , , ) = v3DataProvider.getUserReserveData(
        borrowedPositions[i].asset,
        user
      );

      assertTrue(currentVariableDebt >= borrowedPositions[i].amount, "borrow not migrated");
    }
  }

  function _getV2UserPosition(
    address user
  )
    internal
    view
    returns (address[] memory, uint256[] memory, IMigrationHelper.RepayInput[] memory)
  {
    uint256 numberOfSupplied;
    uint256 numberOfBorrowed;
    address[] memory suppliedPositions = new address[](v2Reserves.length);
    uint256[] memory suppliedBalances = new uint256[](v2Reserves.length);
    IMigrationHelper.RepayInput[] memory borrowedPositions = new IMigrationHelper.RepayInput[](
      v2Reserves.length * 2
    );
    for (uint256 i = 0; i < v2Reserves.length; i++) {
      (
        uint256 currentATokenBalance,
        uint256 currentStableDebt,
        uint256 currentVariableDebt,
        ,
        ,
        ,
        ,
        ,

      ) = v2DataProvider.getUserReserveData(v2Reserves[i], user);
      if (currentATokenBalance != 0) {
        suppliedPositions[numberOfSupplied] = v2Reserves[i];
        suppliedBalances[numberOfSupplied] = currentATokenBalance;
        numberOfSupplied++;
      }
      if (currentStableDebt != 0) {
        borrowedPositions[numberOfBorrowed] = IMigrationHelper.RepayInput({
          asset: v2Reserves[i],
          amount: currentStableDebt,
          rateMode: 1
        });
        numberOfBorrowed++;
      }
      if (currentVariableDebt != 0) {
        borrowedPositions[numberOfBorrowed] = IMigrationHelper.RepayInput({
          asset: v2Reserves[i],
          amount: currentVariableDebt,
          rateMode: 2
        });
        numberOfBorrowed++;
      }
    }

    // shrink unused elements of the arrays
    assembly {
      mstore(suppliedPositions, numberOfSupplied)
      mstore(suppliedBalances, numberOfSupplied)
      mstore(borrowedPositions, numberOfBorrowed)
    }

    return (suppliedPositions, suppliedBalances, borrowedPositions);
  }

  function _getSimplePositionsToRepay(
    IMigrationHelper.RepayInput[] memory positionsToRepay
  ) internal pure returns (IMigrationHelper.RepaySimpleInput[] memory) {
    IMigrationHelper.RepaySimpleInput[]
      memory positionsToRepaySimple = new IMigrationHelper.RepaySimpleInput[](
        positionsToRepay.length
      );
    for (uint256 i; i < positionsToRepay.length; ++i) {
      positionsToRepaySimple[i] = IMigrationHelper.RepaySimpleInput({
        asset: positionsToRepay[i].asset,
        rateMode: positionsToRepay[i].rateMode
      });
    }

    return positionsToRepaySimple;
  }

  function _getFlashloanParams(
    IMigrationHelper.RepayInput[] memory borrowedPositions
  ) internal returns (address[] memory, uint256[] memory, uint256[] memory) {
    address[] memory borrowedAssets = new address[](borrowedPositions.length);
    uint256[] memory borrowedAmounts = new uint256[](borrowedPositions.length);
    uint256[] memory interestRateModes = new uint256[](borrowedPositions.length);
    uint256 index = 0;

    for (uint256 i = 0; i < borrowedPositions.length; i++) {
      address asset = borrowedPositions[i].asset;
      uint256 amount = borrowedPositions[i].amount;

      uint256 existingIndex = assetsIndex[asset];

      if (existingIndex > 0) {
        borrowedAmounts[existingIndex - 1] += amount;
      } else {
        assetsIndex[asset] = index + 1;
        borrowedAssets[index] = asset;
        borrowedAmounts[index] = amount;
        interestRateModes[index] = 2;
        index++;
      }
    }

    // clean mapping
    for (uint256 i = 0; i < borrowedAssets.length; i++) {
      delete assetsIndex[borrowedAssets[i]];
    }

    // shrink unused elements of the arrays
    assembly {
      mstore(borrowedAssets, index)
      mstore(borrowedAmounts, index)
      mstore(interestRateModes, index)
    }

    return (borrowedAssets, borrowedAmounts, interestRateModes);
  }

  function _getUserWithPosition() internal returns (address, uint256) {
    uint256 ownerPrivateKey = 0xA11CEA;

    address owner = vm.addr(ownerPrivateKey);
    deal(DAI, owner, 10000e18);
    deal(ETH, owner, 10e18);

    vm.startPrank(owner);

    IERC20(DAI).approve(address(migrationHelper.V2_POOL()), type(uint256).max);
    IERC20(ETH).approve(address(migrationHelper.V2_POOL()), type(uint256).max);

    migrationHelper.V2_POOL().deposit(DAI, 10000 ether, owner, 0);
    migrationHelper.V2_POOL().deposit(ETH, 10 ether, owner, 0);

    vm.stopPrank();

    return (owner, ownerPrivateKey);
  }

  function _getUserWithBorrowPosition() internal returns (address, uint256) {
    uint256 ownerPrivateKey = 0xA11CEB;

    address owner = vm.addr(ownerPrivateKey);
    deal(USDC, owner, 10000e6);
    deal(ETH, owner, 10e18);

    vm.startPrank(owner);

    IERC20(USDC).approve(address(migrationHelper.V2_POOL()), type(uint256).max);
    IERC20(ETH).approve(address(migrationHelper.V2_POOL()), type(uint256).max);

    migrationHelper.V2_POOL().deposit(USDC, 10000 * 1e6, owner, 0);
    migrationHelper.V2_POOL().deposit(ETH, 10 ether, owner, 0);

    // migrationHelper.V2_POOL().borrow(ETH, 2 ether, 1, 0, owner);
    migrationHelper.V2_POOL().borrow(USDC, 1000 * 1e6, 2, 0, owner);

    vm.stopPrank();

    return (owner, ownerPrivateKey);
  }

  function _getPermits(
    address user,
    uint256 privateKey,
    address[] memory suppliedPositions,
    uint256[] memory suppliedBalances
  ) internal view returns (IMigrationHelper.PermitInput[] memory) {
    IMigrationHelper.PermitInput[] memory permits = new IMigrationHelper.PermitInput[](
      suppliedPositions.length
    );

    for (uint256 i = 0; i < suppliedPositions.length; i++) {
      IERC20WithPermit token = migrationHelper.aTokens(suppliedPositions[i]);

      SigUtils.Permit memory permit = SigUtils.Permit({
        owner: user,
        spender: address(migrationHelper),
        value: suppliedBalances[i],
        nonce: IERC20WithATokenCompatibility(address(token))._nonces(user),
        deadline: type(uint256).max
      });

      bytes32 digest = sigUtils.getPermitTypedDataHash(permit, token.DOMAIN_SEPARATOR());

      (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

      permits[i] = IMigrationHelper.PermitInput({
        aToken: token,
        value: suppliedBalances[i],
        deadline: type(uint256).max,
        v: v,
        r: r,
        s: s
      });
    }

    return permits;
  }

  function _getCreditDelegations(
    address user,
    uint256 privateKey,
    IMigrationHelper.RepayInput[] memory positionsToRepay
  ) internal returns (IMigrationHelper.CreditDelegationInput[] memory) {
    IMigrationHelper.CreditDelegationInput[]
      memory creditDelegations = new IMigrationHelper.CreditDelegationInput[](
        positionsToRepay.length
      );

    // calculate params for v3 credit delegation
    (address[] memory borrowedAssets, uint256[] memory borrowedAmounts, ) = _getFlashloanParams(
      positionsToRepay
    );

    // First want to merge USDC into DAI
    {
        bool daiFound = false;
        uint256 daiIndex = 0;
        for (uint256 i = 0; i < borrowedAssets.length; i++) {
            if (borrowedAssets[i] == DAI) {
                daiIndex = i;
                daiFound = true;
                break;
            }
        }

        for (uint256 i = 0; i < borrowedAssets.length; i++) {
            if (borrowedAssets[i] == USDC) {
                if (daiFound) {
                    borrowedAmounts[daiIndex] += borrowedAmounts[i] * 1e12;
                } else {
                    borrowedAssets[i] = DAI;
                    borrowedAmounts[i] = borrowedAmounts[i] * 1e12;
                }
            }
        }
    }

    for (uint256 i = 0; i < borrowedAssets.length; i++) {
        if (borrowedAssets[i] == USDC) continue;

      // get v3 variable debt token
      DataTypes.ReserveData memory reserveData = migrationHelper.V3_POOL().getReserveData(
        borrowedAssets[i]
      );

      IERC20WithPermit token = IERC20WithPermit(reserveData.variableDebtTokenAddress);

      SigUtils.CreditDelegation memory creditDelegation = SigUtils.CreditDelegation({
        delegatee: address(migrationHelper),
        value: borrowedAmounts[i],
        nonce: token.nonces(user),
        deadline: type(uint256).max
      });

      bytes32 digest = sigUtils.getCreditDelegationTypedDataHash(
        creditDelegation,
        token.DOMAIN_SEPARATOR()
      );

      (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

      creditDelegations[i] = IMigrationHelper.CreditDelegationInput({
        debtToken: ICreditDelegationToken(address(token)),
        value: borrowedAmounts[i],
        deadline: type(uint256).max,
        v: v,
        r: r,
        s: s
      });
    }

    return creditDelegations;
  }
}
