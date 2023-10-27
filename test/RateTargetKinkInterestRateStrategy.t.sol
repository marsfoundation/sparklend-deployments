// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

import "forge-std/Test.sol";

import { RateSourceMock } from "./mocks/RateSourceMock.sol";

import {
    RateTargetKinkInterestRateStrategy,
    IPoolAddressesProvider
} from "../src/RateTargetKinkInterestRateStrategy.sol";

contract RateTargetKinkInterestRateStrategyTest is Test {

    RateSourceMock rateSource;

    RateTargetKinkInterestRateStrategy interestStrategy;
    RateTargetKinkInterestRateStrategy interestStrategyPositiveSpread;

    function setUp() public {
        rateSource = new RateSourceMock(0.05e27);

        interestStrategy = new RateTargetKinkInterestRateStrategy({
            provider: IPoolAddressesProvider(address(123)),
            rateSource: address(rateSource),
            optimalUsageRatio: 0,
            baseVariableBorrowRate: 0.01e27,
            variableRateSlope1Spread: -0.005e27,
            variableRateSlope2: 0.55e27,
            stableRateSlope1: 0,
            stableRateSlope2: 0,
            baseStableRateOffset: 0,
            stableRateExcessOffset: 0,
            optimalStableToTotalDebtRatio: 0
        });

        interestStrategyPositiveSpread = new RateTargetKinkInterestRateStrategy({
            provider: IPoolAddressesProvider(address(123)),
            rateSource: address(rateSource),
            optimalUsageRatio: 0,
            baseVariableBorrowRate: 0.01e27,
            variableRateSlope1Spread: 0.005e27,
            variableRateSlope2: 0.55e27,
            stableRateSlope1: 0,
            stableRateSlope2: 0,
            baseStableRateOffset: 0,
            stableRateExcessOffset: 0,
            optimalStableToTotalDebtRatio: 0
        });
    }

    function test_constructor() public {
        assertEq(address(interestStrategy.ADDRESSES_PROVIDER()), address(123));
        assertEq(address(interestStrategy.RATE_SOURCE()), address(rateSource));
        assertEq(interestStrategy.OPTIMAL_USAGE_RATIO(), 0);
        assertEq(interestStrategy.OPTIMAL_STABLE_TO_TOTAL_DEBT_RATIO(), 0);
        assertEq(interestStrategy.MAX_EXCESS_USAGE_RATIO(), 1e27);
        assertEq(interestStrategy.MAX_EXCESS_STABLE_TO_TOTAL_DEBT_RATIO(), 1e27);
        assertEq(interestStrategy.MAX_EXCESS_STABLE_TO_TOTAL_DEBT_RATIO(), 1e27);
        assertEq(interestStrategy.getVariableRateSlope1(), 0.035e27);
        assertEq(interestStrategy.getVariableRateSlope2(), 0.55e27);
        assertEq(interestStrategy.getStableRateSlope1(), 0);
        assertEq(interestStrategy.getStableRateSlope2(), 0);
        assertEq(interestStrategy.getStableRateExcessOffset(), 0);
        assertEq(interestStrategy.getBaseStableBorrowRate(), 0.035e27);
        assertEq(interestStrategy.getBaseVariableBorrowRate(), 0.01e27);
        assertEq(interestStrategy.getMaxVariableBorrowRate(), 0.595e27);

        assertEq(interestStrategyPositiveSpread.getVariableRateSlope1(), 0.045e27);
        assertEq(interestStrategyPositiveSpread.getVariableRateSlope2(), 0.55e27);
        assertEq(interestStrategyPositiveSpread.getMaxVariableBorrowRate(), 0.605e27);
    }

    function test_rateSource_change_kink_above_base() public {
        assertEq(interestStrategy.getVariableRateSlope1(), 0.035e27);
        assertEq(interestStrategy.getVariableRateSlope2(), 0.55e27);
        assertEq(interestStrategy.getBaseVariableBorrowRate(), 0.01e27);
        assertEq(interestStrategy.getMaxVariableBorrowRate(), 0.595e27);

        rateSource.setRate(0.07e27);

        assertEq(interestStrategy.getVariableRateSlope1(), 0.055e27);
        assertEq(interestStrategy.getVariableRateSlope2(), 0.55e27);
        assertEq(interestStrategy.getBaseVariableBorrowRate(), 0.01e27);
        assertEq(interestStrategy.getMaxVariableBorrowRate(), 0.615e27);
    }

    function test_rateSource_change_kink_below_base() public {
        assertEq(interestStrategy.getVariableRateSlope1(), 0.035e27);
        assertEq(interestStrategy.getVariableRateSlope2(), 0.55e27);
        assertEq(interestStrategy.getBaseVariableBorrowRate(), 0.01e27);
        assertEq(interestStrategy.getMaxVariableBorrowRate(), 0.595e27);

        rateSource.setRate(0.012e27);   // 1.2% - 0.5% = 0.7% < 1.0%

        assertEq(interestStrategy.getVariableRateSlope1(), 0);
        assertEq(interestStrategy.getVariableRateSlope2(), 0.55e27);
        assertEq(interestStrategy.getBaseVariableBorrowRate(), 0.01e27);
        assertEq(interestStrategy.getMaxVariableBorrowRate(), 0.56e27);
    }

    function test_rateSource_change_rate_below_base() public {
        assertEq(interestStrategy.getVariableRateSlope1(), 0.035e27);
        assertEq(interestStrategy.getVariableRateSlope2(), 0.55e27);
        assertEq(interestStrategy.getBaseVariableBorrowRate(), 0.01e27);
        assertEq(interestStrategy.getMaxVariableBorrowRate(), 0.595e27);

        rateSource.setRate(0);

        assertEq(interestStrategy.getVariableRateSlope1(), 0);
        assertEq(interestStrategy.getVariableRateSlope2(), 0.55e27);
        assertEq(interestStrategy.getBaseVariableBorrowRate(), 0.01e27);
        assertEq(interestStrategy.getMaxVariableBorrowRate(), 0.56e27);
    }

}
