// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

import "forge-std/Test.sol";

import { RateSourceMock } from "./mocks/RateSourceMock.sol";

import {
    RateTargetBaseInterestRateStrategy,
    IPoolAddressesProvider
} from "../src/RateTargetBaseInterestRateStrategy.sol";

contract RateTargetBaseInterestRateStrategyTest is Test {

    RateSourceMock rateSource;

    RateTargetBaseInterestRateStrategy interestStrategy;

    function setUp() public {
        rateSource = new RateSourceMock(0.05e27);

        interestStrategy = new RateTargetBaseInterestRateStrategy({
            provider: IPoolAddressesProvider(address(123)),
            rateSource: address(rateSource),
            optimalUsageRatio: 0,
            baseVariableBorrowRateSpread: 0.005e27,
            variableRateSlope1: 0.01e27,
            variableRateSlope2: 0.45e27,
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
        assertEq(interestStrategy.getVariableRateSlope1(), 0.01e27);
        assertEq(interestStrategy.getVariableRateSlope2(), 0.45e27);
        assertEq(interestStrategy.getStableRateSlope1(), 0);
        assertEq(interestStrategy.getStableRateSlope2(), 0);
        assertEq(interestStrategy.getStableRateExcessOffset(), 0);
        assertEq(interestStrategy.getBaseStableBorrowRate(), 0.01e27);
        assertEq(interestStrategy.getBaseVariableBorrowRate(), 0.055e27);
        assertEq(interestStrategy.getMaxVariableBorrowRate(), 0.515e27);
    }

    function test_rateSource_change() public {
        assertEq(interestStrategy.getVariableRateSlope1(), 0.01e27);
        assertEq(interestStrategy.getVariableRateSlope2(), 0.45e27);
        assertEq(interestStrategy.getBaseVariableBorrowRate(), 0.055e27);
        assertEq(interestStrategy.getMaxVariableBorrowRate(), 0.515e27);

        rateSource.setRate(0.07e27);

        assertEq(interestStrategy.getVariableRateSlope1(), 0.01e27);
        assertEq(interestStrategy.getVariableRateSlope2(), 0.45e27);
        assertEq(interestStrategy.getBaseVariableBorrowRate(), 0.075e27);
        assertEq(interestStrategy.getMaxVariableBorrowRate(), 0.535e27);
    }

}
