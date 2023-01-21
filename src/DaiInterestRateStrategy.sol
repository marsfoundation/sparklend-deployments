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
        uint128 rate;
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
    uint256 public immutable spread;
    uint256 public immutable maxRate;

    Slot0 private _slot0;

    /**
     * @param _vat The address of the vat contract
     * @param _pot The address of the pot contract
     * @param _ilk The ilk identifier
     * @param _spread The spread on top of the dsr
     * @param _maxRate The maximum rate that can be returned by this strategy
     */
    constructor(
        address _vat,
        address _pot,
        bytes32 _ilk,
        uint256 _spread,
        uint256 _maxRate
    ) {
        vat = _vat;
        pot = _pot;
        ilk = _ilk;
        spread = _spread;
        maxRate = _maxRate;
    }

    /**
    * @notice Fetch debt ceiling and dsr. Expensive operation should be called only when underlying values change.
    * @dev This incurs a lot of SLOADs and infrequently changes. No need to call this on every calculation.
    */
    function recompute() external {
        (,,, uint256 line,) = VatLike(vat).ilks(ilk);
        uint256 rate = (PotLike(pot).dsr() - RAY) * SECONDS_PER_YEAR + spread;

        _slot0 = Slot0({
            debtCeiling: uint88(line / RAD),
            // Convert the dsr to an APR with spread
            rate: uint128(rate < maxRate ? rate : maxRate),
            lastUpdateTimestamp: uint40(block.timestamp)
        });
    }

    /// @inheritdoc IReserveInterestRateStrategy
    function calculateInterestRates(DataTypes.CalculateInterestRatesParams memory params)
        external
        view
        override
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        Slot0 memory slot0 = _slot0;

        uint256 outstandingBorrow = params.totalVariableDebt;
        uint256 debtCeiling;
        unchecked {
            // Debt ceiling is a uint88, so it will definitely fit in a uint256 with a WAD multiplication
            debtCeiling = uint256(slot0.debtCeiling) * WAD;
        }

        if (outstandingBorrow <= debtCeiling) {
            // Users can borrow at a flat rate
            return (
                0,
                0,
                slot0.rate
            );
        } else {
            // Maker needs liquidity - rates increase until outstanding borrow is brought back to the debt ceiling
            uint256 borrowDelta;
            uint256 maxRateDelta;
            unchecked {
                // will not underflow due to conditional block
                borrowDelta = outstandingBorrow - debtCeiling;
                // maxRate enforced to be greater than slot0.rate in cached computation
                maxRateDelta = maxRate - slot0.rate;
            }
            return (
                0,
                0,
                slot0.rate + maxRateDelta * borrowDelta / outstandingBorrow
            );
        }
    }

    function getDebtCeiling() external view returns (uint256) {
        return _slot0.debtCeiling;
    }

    function getRate() external view returns (uint256) {
        return _slot0.rate;
    }

    function getLastUpdateTimestamp() external view returns (uint256) {
        return _slot0.lastUpdateTimestamp;
    }

}
