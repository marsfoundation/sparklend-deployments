// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.10;

import "dss-test/DssTest.sol";

import "../DaiInterestRateStrategy.sol";

contract VatMock {

    uint256 Art;
    uint256 line;

    function ilks(bytes32) public view returns (uint256, uint256, uint256, uint256, uint256) {
        return (Art, 0, 0, line, 0);
    }

    function setArt(uint256 _art) external {
        Art = _art;
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

contract DaiMock {

    uint256 public liquidity;

    function balanceOf(address) external view returns (uint256) {
        return liquidity;
    }

    function setLiquidity(uint256 _liquidity) external {
        liquidity = _liquidity;
    }

}

contract DaiInterestRateStrategyTest is DssTest {

    VatMock vat;
    PotMock pot;
    DaiMock dai;

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
        dai = new DaiMock();

        interestStrategy = new DaiInterestRateStrategy(
            address(vat),
            address(pot),
            ILK,
            50 * RBPS,       // 0.5% borrow spread
            25 * RBPS,       // 0.25% supply spread
            7500 * RBPS,     // 75% max rate
            100_000 * WAD    // 100k is reserved for performance bonus
        );
    }

    function test_constructor() public {
        assertEq(address(interestStrategy.vat()), address(vat));
        assertEq(address(interestStrategy.pot()), address(pot));
        assertEq(interestStrategy.ilk(), ILK);
        assertEq(interestStrategy.borrowSpread(), 50 * RBPS);
        assertEq(interestStrategy.supplySpread(), 25 * RBPS);
        assertEq(interestStrategy.maxRate(), 7500 * RBPS);
        assertEq(interestStrategy.performanceBonus(), 100_000 * WAD);

        // Recompute should occur
        assertEq(interestStrategy.getDebtRatio(), 0);
        assertEq(interestStrategy.getBaseRate(), BR);
        assertEq(interestStrategy.getLastUpdateTimestamp(), block.timestamp);
    }

    function test_recompute() public {
        vat.setArt(1_000_000 * WAD);
        vat.setLine(2_000_000 * RAD);
        pot.setDSR(RAY);
        vm.warp(block.timestamp + 1 days);

        assertEq(interestStrategy.getDebtRatio(), 0);
        assertEq(interestStrategy.getBaseRate(), BR);
        assertEq(interestStrategy.getLastUpdateTimestamp(), block.timestamp - 1 days);

        interestStrategy.recompute();

        assertEq(interestStrategy.getDebtRatio(), WAD / 2);
        assertEq(interestStrategy.getBaseRate(), 0);
        assertEq(interestStrategy.getLastUpdateTimestamp(), block.timestamp);
    }

    function test_calculateInterestRates_no_maker_debt_no_borrows() public {
        assertRates(0, 0, BR + 50 * RBPS, "No Maker debt, no borrows. supply = 0, borrow = dsr + 50bps");
    }

    function test_calculateInterestRates_no_maker_debt_with_borrows() public {
        dai.setLiquidity(200_000 * WAD);

        assertRates(100_000 * WAD, 0, BR + 50 * RBPS, "No Maker debt, user-only supply under performance bonus. supply = 0, borrow = dsr + 50bps");
        assertRates(200_000 * WAD, (BR + 25 * RBPS) * 1 / 2 * 1 / 2, BR + 50 * RBPS, "No Maker debt, user-only supply over performance bonus. supply = 0, borrow = dsr + 50bps");
    }

    function test_calculateInterestRates_maker_debt_no_borrows() public {
        vat.setArt(200_000 * WAD);
        dai.setLiquidity(200_000 * WAD);
        interestStrategy.recompute();

        assertRates(0, 0, BR + 50 * RBPS, "Only Maker as LP. supply = 0, borrow = dsr + 50bps");
    }

    function test_calculateInterestRates_maker_debt_with_borrows() public {
        vat.setArt(200_000 * WAD);
        dai.setLiquidity(100_000 * WAD);
        interestStrategy.recompute();

        assertRates(100_000 * WAD, 0, BR + 50 * RBPS, "Only Maker as LP, borrows under performance bonus. supply = 0, borrow = dsr + 50bps");
        dai.setLiquidity(0);    // Pool is fully utilized
        assertRates(200_000 * WAD, (BR + 25 * RBPS) * 1 / 2, BR + 50 * RBPS, "Only Maker as LP, borrows over performance bonus. supply = 0, borrow = dsr + 50bps");
    }

    function test_calculateInterestRates_over_debt_limit() public {
        vat.setArt(2_000_000 * WAD);    // 2x over capacity
        interestStrategy.recompute();

        uint256 br = 7500 * RBPS - (7500 * RBPS - (BR + 50 * RBPS)) / 2;
        assertEq(br, 382475165427368930783992000, "borrow rate should be about half of max rate");
        assertRates(2_000_000 * WAD, br, br, "Only Maker as LP, 2x over capacity, 100% utilization. supply = ~maxRate/2, borrow = ~maxRate/2");
        dai.setLiquidity(1_000_000 * WAD);  // User adds some liquidity, still over capacity
        assertRates(2_000_000 * WAD, 254983443618245953601011223, br, "Maker+Users as LP, 2x over capacity, 66.7% utilization. supply = ~maxRate/2 * 66.7%, borrow = ~maxRate/2");
    }

    function test_calculateInterestRates_debt_ceiling_zero() public {
        vat.setLine(0);
        vat.setArt(1);  // Infinitely over capacity even with 1 wei of debt
        interestStrategy.recompute();

        uint256 br = 749999997624926423513756790;
        assertRates(100_000 * WAD, br, br, "Maker wants to go to zero debt - always maxRate. supply = maxRate, borrow = maxRate");
    }

    function assertRates(
        uint256 totalVariableDebt,
        uint256 expectedSupplyRate,
        uint256 expectedBorrowRate,
        string memory errorMessage
    ) internal {
        (uint256 supplyRate,, uint256 borrowRate) = interestStrategy.calculateInterestRates(DataTypes.CalculateInterestRatesParams(
            0,
            0,
            0,
            0,
            totalVariableDebt,
            0,
            0,
            address(dai),
            address(0)
        ));

        assertEq(supplyRate, expectedSupplyRate, errorMessage);
        assertEq(borrowRate, expectedBorrowRate, errorMessage);
    }

}
