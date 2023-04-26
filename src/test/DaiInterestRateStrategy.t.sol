// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.10;

import "dss-test/DssTest.sol";

import "../DaiInterestRateStrategy.sol";

contract VatMock {

    uint256 Art;
    uint256 line;
    uint256 public live = 1;

    function ilks(bytes32) public view returns (uint256, uint256, uint256, uint256, uint256) {
        return (Art, 10 ** 27, 0, line, 0);
    }

    function setArt(uint256 _art) external {
        Art = _art;
    }

    function setLine(uint256 _line) external {
        line = _line;
    }

    function cage() external {
        live = 0;
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
    uint256 constant BR = 11055923171930957297759999;    // DSR at 1% / 90% to get SFBR as yearly APR
    uint256 constant RBPS = RAY / 10000;
    uint256 constant ONE_TRILLION = 1_000_000_000_000;

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
            100 * RAY / 90,  // SFBR is defined as DSR / 90%
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
        assertEq(interestStrategy.baseRateConversion(), 1111111111111111111111111111);
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
        assertEq(br, 383027961585965478648880000, "borrow rate should be about half of max rate");
        assertRates(2_000_000 * WAD, br, br, "Only Maker as LP, 2x over capacity, 100% utilization. supply = ~maxRate/2, borrow = ~maxRate/2");
        dai.setLiquidity(1_000_000 * WAD);  // User adds some liquidity, still over capacity
        assertRates(2_000_000 * WAD, 255351974390643652177234692, br, "Maker+Users as LP, 2x over capacity, 66.7% utilization. supply = ~maxRate/2 * 66.7%, borrow = ~maxRate/2");
    }

    function test_calculateInterestRates_debt_ceiling_zero() public {
        vat.setLine(0);
        vat.setArt(1);  // Infinitely over capacity even with 1 wei of debt
        interestStrategy.recompute();

        uint256 br = 749999997628498784959732204;   // Pretty much maxRate with some rounding errors
        assertRates(100_000 * WAD, br, br, "Maker wants to go to zero debt - always maxRate. supply = maxRate, borrow = maxRate");
    }

    function test_calculateInterestRates_vat_caged() public {
        vat.setArt(500_000 * WAD);
        vat.cage();
        interestStrategy.recompute();

        uint256 br = 749999997628498784959732204;   // Pretty much maxRate with some rounding errors
        assertRates(500_000 * WAD, br, br, "Should be near max rate when vat is caged. supply = maxRate, borrow = maxRate");
    }

    function test_calculateInterestRates_fuzz(
        uint256 line,
        uint256 art,
        uint256 dsr,
        uint256 baseRateConversion,
        uint256 totalVariableDebt,
        uint256 liquidity,
        uint256 borrowSpread,
        uint256 supplySpread,
        uint256 maxRate,
        uint256 performanceBonus
    ) public {
        // Keep the numbers sane
        line = line % (ONE_TRILLION * RAD);
        art = art % (ONE_TRILLION * WAD);
        dsr = dsr % (DSR_TWO_HUNDRED_PERCENT - RAY) + RAY;
        baseRateConversion = baseRateConversion % (10 * RAY);
        totalVariableDebt = totalVariableDebt % (ONE_TRILLION * WAD);
        liquidity = liquidity % (ONE_TRILLION * WAD);
        maxRate = maxRate % 1_000_000_00 * RBPS;
        borrowSpread = maxRate > 0 ? borrowSpread % maxRate : 0;
        supplySpread = borrowSpread > 0 ? supplySpread % borrowSpread : 0;
        performanceBonus = performanceBonus % (ONE_TRILLION * WAD);

        interestStrategy = new DaiInterestRateStrategy(
            address(vat),
            address(pot),
            ILK,
            baseRateConversion,
            borrowSpread,
            supplySpread,
            maxRate,
            performanceBonus
        );

        vat.setLine(line);
        vat.setArt(art);
        pot.setDSR(dsr);
        dai.setLiquidity(liquidity);
        interestStrategy.recompute();

        uint256 supplyRatio = totalVariableDebt > 0 ? totalVariableDebt * WAD / (totalVariableDebt + liquidity) : 0;
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

        assertLe(supplyRatio, WAD, "supply ratio should be less than or equal to 1");
        if (supplyRatio > 0) {
            uint256 adjBorrowRate = borrowRate * supplyRatio;
            assertGe(adjBorrowRate, supplyRate, "adjusted borrow rate should always be greater than or equal to the supply rate");
        } else {
            assertGe(borrowRate, supplyRate, "borrow rate should always be greater than or equal to the supply rate");
        }
        assertGe(borrowRate, interestStrategy.getBaseRate() + borrowSpread, "borrow rate should be greater than or equal to base rate + spread");
        assertLe(borrowRate, maxRate, "borrow rate should be less than or equal to max rate");
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
