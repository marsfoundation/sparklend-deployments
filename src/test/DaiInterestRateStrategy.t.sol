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

    bytes32 constant ILK = "DIRECT-SPARK-DAI";
    uint256 constant DSR_ONE_PERCENT = 1000000000315522921573372069;
    uint256 constant DSR_TWO_HUNDRED_PERCENT = 1000000034836767751273470154;
    uint256 constant ONE_PERCENT_APY_AS_APR = 9950330854737861567984000;
    uint256 constant ONE_BPS = RAY / 10000;
    uint256 constant FLAT_RATE = ONE_PERCENT_APY_AS_APR + 50 * ONE_BPS;

    function setUp() public {
        vat = new VatMock();
        vat.setLine(1_000_000 * RAD);
        pot = new PotMock();
        pot.setDSR(RAY);    // DSR is off

        interestStrategy = new DaiInterestRateStrategy(
            address(vat),
            address(pot),
            ILK,
            50 * ONE_BPS,       // 0.5% spread
            7500 * ONE_BPS      // 75% max rate
        );
    }

    function test_constructor() public {
        assertEq(address(interestStrategy.vat()), address(vat));
        assertEq(address(interestStrategy.pot()), address(pot));
        assertEq(interestStrategy.ilk(), ILK);
        assertEq(interestStrategy.spread(), 50 * ONE_BPS);
        assertEq(interestStrategy.maxRate(), 7500 * ONE_BPS);

        // Recompute should occur
        assertEq(interestStrategy.getDebtCeiling(), 1_000_000);
        assertEq(interestStrategy.getRate(), 50 * ONE_BPS);
        assertEq(interestStrategy.getLastUpdateTimestamp(), block.timestamp);
    }

    function test_recompute() public {
        vat.setLine(2_000_000 * RAD);
        pot.setDSR(DSR_ONE_PERCENT);
        vm.warp(block.timestamp + 1 days);

        assertEq(interestStrategy.getDebtCeiling(), 1_000_000);
        assertEq(interestStrategy.getRate(), 50 * ONE_BPS);
        assertEq(interestStrategy.getLastUpdateTimestamp(), block.timestamp - 1 days);

        interestStrategy.recompute();

        assertEq(interestStrategy.getDebtCeiling(), 2_000_000);
        assertEq(interestStrategy.getRate(), FLAT_RATE);
        assertEq(interestStrategy.getLastUpdateTimestamp(), block.timestamp);
    }

    function test_recompute_rate_over_max_rate() public {
        pot.setDSR(DSR_TWO_HUNDRED_PERCENT);

        assertEq(interestStrategy.getRate(), 50 * ONE_BPS);

        interestStrategy.recompute();

        assertEq(interestStrategy.getRate(), 7500 * ONE_BPS);
    }

    function test_calculateInterestRates() public {
        pot.setDSR(DSR_ONE_PERCENT);
        interestStrategy.recompute();

        assertEq(getBorrowRate(0), FLAT_RATE, "borrow should be flat rate at 0 debt");
        assertEq(getBorrowRate(1_000_000 * WAD), FLAT_RATE, "borrow should be flat rate at debt ceiling");
        assertEq(getBorrowRate(2_000_000 * WAD), FLAT_RATE + (7500 * ONE_BPS - FLAT_RATE) / 2, "borrow should be about half the max rate when 200% over capacity");
        vat.setLine(0);
        interestStrategy.recompute();
        assertEq(getBorrowRate(1), 7500 * ONE_BPS, "borrow should be max rate when no capacity and any outstanding borrow");
        assertEq(getBorrowRate(0), FLAT_RATE, "borrow should be flat rate when both are 0");
    }

    function makeParams(uint256 totalVariableDebt) internal pure returns (DataTypes.CalculateInterestRatesParams memory) {
        return DataTypes.CalculateInterestRatesParams(
            0,
            0,
            0,
            0,
            totalVariableDebt,
            0,
            0,
            address(0),
            address(0)
        );
    }

    function getBorrowRate(uint256 totalVariableDebt) internal view returns (uint256 borrowRate) {
        (,,borrowRate) = interestStrategy.calculateInterestRates(makeParams(totalVariableDebt));
    }

}
