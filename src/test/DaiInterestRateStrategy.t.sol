// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.10;

import "dss-test/DssTest.sol";

import "../DaiInterestRateStrategy.sol";

contract VatMock {

    uint256 line;

    function ilks(bytes32) public view returns (uint256, uint256, uint256, uint256, uint256) {
        return (0, 0, 0, line, 0);
    }

    function setLine(uint256 _line) external {
        line = _line;
    }

}

contract PotMock {

    uint256 public dsr;

    function setDSR(uint256 _dsr) external {
        dsr = _dsr;
    }

}

contract DaiInterestRateStrategyTest is DssTest {

    VatMock vat;
    PotMock pot;

    DaiInterestRateStrategy interestStrategy;
    DaiInterestRateStrategy interestStrategyNoSubsidy;

    bytes32 constant ILK = "DIRECT-SPARK-DAI";
    uint256 constant DSR_ONE_PERCENT = 1000000000315522921573372069;
    uint256 constant DSR_TWO_HUNDRED_PERCENT = 1000000034836767751273470154;
    uint256 constant BR = 9950330854737861567984000;    // DSR at 1% APY expressed as an APR
    uint256 constant RBPS = RAY / 10000;

    function setUp() public {
        vat = new VatMock();
        vat.setLine(1_000_000 * RAD);
        pot = new PotMock();
        pot.setDSR(DSR_ONE_PERCENT);

        interestStrategy = new DaiInterestRateStrategy(
            address(vat),
            address(pot),
            ILK,
            50 * RBPS,       // 0.5% borrow spread
            25 * RBPS,       // 0.25% supply spread
            7500 * RBPS,     // 75% max rate
            100_000 * WAD   // We are subsidizing up to 100k DAI
        );
    }

    function test_constructor() public {
        assertEq(address(interestStrategy.vat()), address(vat));
        assertEq(address(interestStrategy.pot()), address(pot));
        assertEq(interestStrategy.ilk(), ILK);
        assertEq(interestStrategy.borrowSpread(), 50 * RBPS);
        assertEq(interestStrategy.supplySpread(), 25 * RBPS);
        assertEq(interestStrategy.maxRate(), 7500 * RBPS);
        assertEq(interestStrategy.subsidy(), 100_000 * WAD);

        // Recompute should occur
        assertEq(interestStrategy.getDebtCeiling(), 1_000_000);
        assertEq(interestStrategy.getBaseRate(), BR);
        assertEq(interestStrategy.getLastUpdateTimestamp(), block.timestamp);
    }

    function test_recompute() public {
        vat.setLine(2_000_000 * RAD);
        pot.setDSR(RAY);
        vm.warp(block.timestamp + 1 days);

        assertEq(interestStrategy.getDebtCeiling(), 1_000_000);
        assertEq(interestStrategy.getBaseRate(), BR);
        assertEq(interestStrategy.getLastUpdateTimestamp(), block.timestamp - 1 days);

        interestStrategy.recompute();

        assertEq(interestStrategy.getDebtCeiling(), 2_000_000);
        assertEq(interestStrategy.getBaseRate(), 0);
        assertEq(interestStrategy.getLastUpdateTimestamp(), block.timestamp);
    }

    function test_calculateInterestRates_under_debt_ceiling() public {
        assertRates(1_000_000 * WAD, (BR + 25 * RBPS) * 9 / 10, BR + 50 * RBPS, "Should be normal conditions. supply = dsr + 25bps @ 90%, borrow = dsr + 50bps");
    }

    function test_calculateInterestRates_under_subsidy() public {
        assertRates(50_000 * WAD, 0, BR + 50 * RBPS, "Should be normal conditions, but within subsidy. supply = 0, borrow = dsr + 50bps");
    }

    function test_calculateInterestRates_over_debt_ceiling() public {
        assertRates(2_000_000 * WAD, (BR + 25 * RBPS) * 19 / 20, BR + 50 * RBPS + (7500 * RBPS - BR - 50 * RBPS) / 2, "We are 2x debt ceiling - borrow rate should be high. supply = dsr + 25bps @ 95%, borrow ~= half of max rate");
    }

    function test_calculateInterestRates_zero_debt() public {
        // Subtle difference in when subsidy exists or not and zero debt, but in practise makes no difference
        assertRates(0, 0, BR + 50 * RBPS, "Zero debt. supply = 0, borrow = dsr + 50bps");
    }

    function test_calculateInterestRates_zero_debt_ceiling() public {
        vat.setLine(0);
        interestStrategy.recompute();

        assertRates(200_000 * WAD, (BR + 25 * RBPS) * 1 / 2, 7500 * RBPS, "above subsidy, zero DC. supply = dsr + 25bps @ 50%, borrow is max rate");
        assertRates(1, 0, 7500 * RBPS, "very small debt with zero debt ceiling means supply = 0, borrow is max rate");
        assertRates(0, 0, BR + 50 * RBPS, "zero debt with zero debt ceiling means supply = 0, borrow = dsr + 50bps");
    }

    function assertRates(uint256 totalVariableDebt, uint256 expectedSupplyRate, uint256 expectedBorrowRate, string memory errorMessage) internal {
        (uint256 supplyRate,, uint256 borrowRate) = interestStrategy.calculateInterestRates(DataTypes.CalculateInterestRatesParams(
            0,
            0,
            0,
            0,
            totalVariableDebt,
            0,
            0,
            address(0),
            address(0)
        ));

        assertEq(supplyRate, expectedSupplyRate, errorMessage);
        assertEq(borrowRate, expectedBorrowRate, errorMessage);
    }

}
