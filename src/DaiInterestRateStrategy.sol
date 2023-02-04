// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

import {IERC20} from 'aave-v3-core/contracts/dependencies/openzeppelin/contracts/IERC20.sol';
import {IReserveInterestRateStrategy} from 'aave-v3-core/contracts/interfaces/IReserveInterestRateStrategy.sol';
import {DataTypes} from 'aave-v3-core/contracts/protocol/libraries/types/DataTypes.sol';

interface VatLike {
    function ilks(bytes32) external view returns (uint256, uint256, uint256, uint256, uint256);
}

interface PotLike {
    function dsr() external view returns (uint256);
}

/**
 * @title DaiInterestRateStrategy
 * @notice Flat interest rate curve which is a spread on the DSR unless Maker needs liquidity.
 * @dev Only supports variable interest pool.
 */
contract DaiInterestRateStrategy is IReserveInterestRateStrategy {

    struct Slot0 {
        // The ratio of outstanding debt to debt ceiling in the vault. Expressed in wad
        uint88 debtRatio;
        // The base rate of the reserve. Expressed in ray
        uint128 baseRate;
        // Timestamp of last update
        uint40 lastUpdateTimestamp;
    }

    uint256 private constant HWAD = 10 ** 9;
    uint256 private constant WAD = 10 ** 18;
    uint256 private constant RAY = 10 ** 27;
    uint256 private constant RAD = 10 ** 45;
    uint256 private constant SECONDS_PER_YEAR = 365 days;

    address public immutable vat;
    address public immutable pot;
    bytes32 public immutable ilk;
    uint256 public immutable borrowSpread;
    uint256 public immutable supplySpread;
    uint256 public immutable maxRate;
    uint256 public immutable performanceBonus;

    Slot0 private _slot0;

    /**
     * @param _vat The address of the vat contract
     * @param _pot The address of the pot contract
     * @param _ilk The ilk identifier
     * @param _borrowSpread The borrow spread on top of the dsr as an APR in RAY units
     * @param _supplySpread The supply spread on top of the dsr as an APR in RAY units
     * @param _maxRate The maximum rate that can be returned by this strategy in RAY units
     * @param _performanceBonus The first part of the interest earned on the debt goes to the reserve as a performance bonus in WAD units.
     */
    constructor(
        address _vat,
        address _pot,
        bytes32 _ilk,
        uint256 _borrowSpread,
        uint256 _supplySpread,
        uint256 _maxRate,
        uint256 _performanceBonus
    ) {
        vat = _vat;
        pot = _pot;
        ilk = _ilk;
        borrowSpread = _borrowSpread;
        supplySpread = _supplySpread;
        maxRate = _maxRate;
        performanceBonus = _performanceBonus;

        recompute();
    }

    /**
    * @notice Fetch debt ceiling and dsr. Expensive operation should be called only when underlying values change.
    * @dev This incurs a lot of SLOADs and infrequently changes. No need to call this on every calculation.
    */
    function recompute() public {
        (uint256 Art,,, uint256 line,) = VatLike(vat).ilks(ilk);    // Assume rate == RAY because this is a D3M
        // Convert the dsr to an APR
        uint256 baseRate = (PotLike(pot).dsr() - RAY) * SECONDS_PER_YEAR;

        uint256 _line = line / RAD;
        uint256 debtRatio = Art > 0 ? (_line > 0 ? Art / _line : type(uint88).max) : 0;
        if (debtRatio > type(uint88).max) {
            debtRatio = type(uint88).max;
        }

        _slot0 = Slot0({
            debtRatio: uint88(debtRatio),
            baseRate: uint128(baseRate),
            lastUpdateTimestamp: uint40(block.timestamp)
        });
    }

    /// @inheritdoc IReserveInterestRateStrategy
    function calculateInterestRates(DataTypes.CalculateInterestRatesParams memory params)
        external
        view
        override
        returns (
            uint256 supplyRate,
            uint256 stableBorrowRate,
            uint256 variableBorrowRate
        )
    {
        Slot0 memory slot0 = _slot0;

        uint256 baseRate = slot0.baseRate;
        uint256 outstandingBorrow = params.totalVariableDebt;
        uint256 supplyUtilization;
        
        if (outstandingBorrow > 0) {
            uint256 availableLiquidity =
                IERC20(params.reserve).balanceOf(params.aToken) +
                params.liquidityAdded -
                params.liquidityTaken;
            supplyUtilization = outstandingBorrow * WAD / (availableLiquidity + outstandingBorrow);
        }
        if (outstandingBorrow > performanceBonus) {
            uint256 delta;
            unchecked {
                delta = outstandingBorrow - performanceBonus;
            }
            supplyRate =
                (baseRate + supplySpread) *     // Flat rate
                supplyUtilization / WAD *       // Supply utilization
                delta / outstandingBorrow;      // Performance bonus deduction
        }
        uint256 debtRatio = slot0.debtRatio;
        stableBorrowRate = 0;
        variableBorrowRate = baseRate + borrowSpread;
        
        if (variableBorrowRate > maxRate) {
            variableBorrowRate = maxRate;
        } else if (debtRatio > WAD) {
            // Maker needs liquidity - rates increase until D3M debt is brought back to the debt ceiling
            uint256 maxRateDelta;
            // Overflow enforced by conditional above
            unchecked {
                maxRateDelta = maxRate - variableBorrowRate;
            }
            
            variableBorrowRate = maxRate - maxRateDelta * WAD / debtRatio;
            // Drop the performance bonus to incentivize third party suppliers as much as possible
            supplyRate = variableBorrowRate * supplyUtilization / WAD;
        }
    }

    function getDebtRatio() external view returns (uint256) {
        return _slot0.debtRatio;
    }

    function getBaseRate() external view returns (uint256) {
        return _slot0.baseRate;
    }

    function getLastUpdateTimestamp() external view returns (uint256) {
        return _slot0.lastUpdateTimestamp;
    }

}
