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
    uint256 constant ONE_PERCENT_APY_AS_APR = 9950330854737861567984000;
    uint256 constant ONE_BPS = RAY / 10000;

    function setUp() public {
        vat = new VatMock();
        vat.setLine(1_000_000 * RAD);
        pot = new PotMock();
        pot.setDSR(DSR_ONE_PERCENT);

        interestStrategy = new DaiInterestRateStrategy(
            address(vat),
            address(pot),
            ILK,
            50 * ONE_BPS,       // 0.5% borrow spread
            25 * ONE_BPS,       // 0.25% supply spread
            7500 * ONE_BPS,     // 75% max rate
            100_000 * WAD       // We are subsidizing up to 100k DAI
        );
        interestStrategyNoSubsidy = new DaiInterestRateStrategy(
            address(vat),
            address(pot),
            ILK,
            50 * ONE_BPS,       // 0.5% borrow spread
            25 * ONE_BPS,       // 0.25% supply spread
            7500 * ONE_BPS,     // 75% max rate
            0
        );
    }

    function test_constructor() public {
        assertEq(address(interestStrategy.vat()), address(vat));
        assertEq(address(interestStrategy.pot()), address(pot));
        assertEq(interestStrategy.ilk(), ILK);
        assertEq(interestStrategy.borrowSpread(), 50 * ONE_BPS);
        assertEq(interestStrategy.supplySpread(), 25 * ONE_BPS);
        assertEq(interestStrategy.maxRate(), 7500 * ONE_BPS);
        assertEq(interestStrategy.subsidy(), 100_000 * WAD);

        // Recompute should occur
        assertEq(interestStrategy.getDebtCeiling(), 1_000_000);
        assertEq(interestStrategy.getBaseRate(), ONE_PERCENT_APY_AS_APR);
        assertEq(interestStrategy.getLastUpdateTimestamp(), block.timestamp);
    }

    function test_recompute() public {
        vat.setLine(2_000_000 * RAD);
        pot.setDSR(RAY);
        vm.warp(block.timestamp + 1 days);

        assertEq(interestStrategy.getDebtCeiling(), 1_000_000);
        assertEq(interestStrategy.getBaseRate(), ONE_PERCENT_APY_AS_APR);
        assertEq(interestStrategy.getLastUpdateTimestamp(), block.timestamp - 1 days);

        interestStrategy.recompute();

        assertEq(interestStrategy.getDebtCeiling(), 2_000_000);
        assertEq(interestStrategy.getBaseRate(), 0);
        assertEq(interestStrategy.getLastUpdateTimestamp(), block.timestamp);
    }

    function test_calculateInterestRates_under_debt_ceiling() public {
        assertRates(1_000_000 * WAD, ONE_PERCENT_APY_AS_APR + 25 * ONE_BPS, ONE_PERCENT_APY_AS_APR + 50 * ONE_BPS, "Should be normal conditions. supply = dsr + 25bps, borrow = dsr + 50bps");
    }

    function test_calculateInterestRates_under_subsidy() public {
        assertRates(50_000 * WAD, (ONE_PERCENT_APY_AS_APR + 25 * ONE_BPS) / 2, ONE_PERCENT_APY_AS_APR + 50 * ONE_BPS, "Should be normal conditions, but within subsidy. supply = (dsr + 25bps) * 50% (subsidy), borrow = dsr + 50bps");
    }

    function test_calculateInterestRates_over_debt_ceiling() public {
        assertRates(2_000_000 * WAD, ONE_PERCENT_APY_AS_APR + 25 * ONE_BPS, ONE_PERCENT_APY_AS_APR + 50 * ONE_BPS + (7500 * ONE_BPS - ONE_PERCENT_APY_AS_APR - 50 * ONE_BPS) / 2, "We are 2x debt ceiling - borrow rate should be high. supply = dsr + 25bps, borrow ~= half of max rate");
    }

    function test_calculateInterestRates_zero_debt() public {
        // Subtle difference in when subsidy exists or not and zero debt, but in practise makes no difference
        assertRates(0, 0, ONE_PERCENT_APY_AS_APR + 50 * ONE_BPS, "Zero debt with subsidy. supply = zero, borrow = dsr + 50bps");
        assertRatesNoSubsidy(0, ONE_PERCENT_APY_AS_APR + 25 * ONE_BPS, ONE_PERCENT_APY_AS_APR + 50 * ONE_BPS, "Zero debt without subsidy. supply = dsr + 25bps, borrow = dsr + 50bps");
    }

    function test_calculateInterestRates_zero_debt_ceiling() public {
        vat.setLine(0);
        interestStrategy.recompute();
        interestStrategyNoSubsidy.recompute();

        assertRates(1, 124, 7500 * ONE_BPS, "non-zero debt with zero debt ceiling means supply = very small value with subsidy, borrow is max rate");
        assertRatesNoSubsidy(1, ONE_PERCENT_APY_AS_APR + 25 * ONE_BPS, 7500 * ONE_BPS, "non-zero debt with zero debt ceiling (no subsidy) means supply is the flat rate, borrow is max rate");
        assertRates(0, 0, ONE_PERCENT_APY_AS_APR + 50 * ONE_BPS, "zero debt with zero debt ceiling means supply is zero, borrow is max rate");
        assertRatesNoSubsidy(0, ONE_PERCENT_APY_AS_APR + 25 * ONE_BPS, ONE_PERCENT_APY_AS_APR + 50 * ONE_BPS, "zero debt with zero debt ceiling (no subsidy) means supply is flat rate, borrow is flat rate");
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

    function assertRatesNoSubsidy(uint256 totalVariableDebt, uint256 expectedSupplyRate, uint256 expectedBorrowRate, string memory errorMessage) internal {
        (uint256 supplyRate,, uint256 borrowRate) = interestStrategyNoSubsidy.calculateInterestRates(DataTypes.CalculateInterestRatesParams(
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
