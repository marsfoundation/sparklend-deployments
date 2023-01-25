// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

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
        // The debt ceiling of this ilk in whole DAI units
        uint88 debtCeiling;
        // The base rate of the reserve. Expressed in ray
        uint128 baseRate;
        // Timestamp of last update
        uint40 lastUpdateTimestamp;
    }

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
    uint256 public immutable subsidy;

    Slot0 private _slot0;

    /**
     * @param _vat The address of the vat contract
     * @param _pot The address of the pot contract
     * @param _ilk The ilk identifier
     * @param _borrowSpread The borrow spread on top of the dsr as an APR in RAY units
     * @param _supplySpread The supply spread on top of the dsr as an APR in RAY units
     * @param _maxRate The maximum rate that can be returned by this strategy in RAY units
     * @param _subsidy Suppliers will subsidize the specified amount of DAI in WAD units.
     */
    constructor(
        address _vat,
        address _pot,
        bytes32 _ilk,
        uint256 _borrowSpread,
        uint256 _supplySpread,
        uint256 _maxRate,
        uint256 _subsidy
    ) {
        vat = _vat;
        pot = _pot;
        ilk = _ilk;
        borrowSpread = _borrowSpread;
        supplySpread = _supplySpread;
        maxRate = _maxRate;
        subsidy = _subsidy;

        recompute();
    }

    /**
    * @notice Fetch debt ceiling and dsr. Expensive operation should be called only when underlying values change.
    * @dev This incurs a lot of SLOADs and infrequently changes. No need to call this on every calculation.
    */
    function recompute() public {
        (,,, uint256 line,) = VatLike(vat).ilks(ilk);
        // Convert the dsr to an APR
        uint256 baseRate = (PotLike(pot).dsr() - RAY) * SECONDS_PER_YEAR;

        _slot0 = Slot0({
            debtCeiling: uint88(line / RAD),
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
        
        if (outstandingBorrow > subsidy) {
            uint256 delta;
            unchecked {
                delta = outstandingBorrow - subsidy;
            }
            supplyRate = (baseRate + supplySpread) * delta / outstandingBorrow;
        }
        uint256 debtCeiling;
        unchecked {
            // Debt ceiling is a uint88, so it will definitely fit in a uint256 with a WAD multiplication
            debtCeiling = uint256(slot0.debtCeiling) * WAD;
        }
        stableBorrowRate = 0;
        variableBorrowRate = baseRate + borrowSpread;
        
        if (variableBorrowRate > maxRate) {
            variableBorrowRate = maxRate;
        } else if (outstandingBorrow > debtCeiling) {
            // Maker needs liquidity - rates increase until outstanding borrow is brought back to the debt ceiling
            uint256 borrowDelta;
            uint256 maxRateDelta;
            // Both of these overflows enforced by conditionals above
            unchecked {
                borrowDelta = outstandingBorrow - debtCeiling;
                maxRateDelta = maxRate - variableBorrowRate;
            }
            
            variableBorrowRate = variableBorrowRate + maxRateDelta * borrowDelta / outstandingBorrow;
        }
    }

    function getDebtCeiling() external view returns (uint256) {
        return _slot0.debtCeiling;
    }

    function getBaseRate() external view returns (uint256) {
        return _slot0.baseRate;
    }

    function getLastUpdateTimestamp() external view returns (uint256) {
        return _slot0.lastUpdateTimestamp;
    }

}
