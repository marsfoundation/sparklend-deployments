// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.10;

import {VersionedInitializable} from '@aave/core-v3/contracts/protocol/libraries/aave-upgradeability/VersionedInitializable.sol';
import {IERC20} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20.sol';
import {ICollector} from 'aave-v3-periphery/treasury/interfaces/ICollector.sol';
import {IPool} from '@aave/core-v3/contracts/interfaces/IPool.sol';
import {IAToken} from '@aave/core-v3/contracts/interfaces/IAToken.sol';
import {DataTypes} from '@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol';

/**
 * @title Dai Collector
 * @notice Collector for DAI with support for fixing the asset and liabilities mismatch.
 */
contract DaiCollector is VersionedInitializable, ICollector {
    // Store the current funds administrator address
    address internal _fundsAdmin;

    // Revision version of this implementation contract
    uint256 public constant REVISION = 2;

    // -- Added for Dai Collector --
    IPool public immutable pool;
    IERC20 public immutable dai;
    address public immutable targetCollector;

    /**
     * @dev Allow only the funds administrator address to call functions marked by this modifier
     */
    modifier onlyFundsAdmin() {
        require(msg.sender == _fundsAdmin, 'ONLY_BY_FUNDS_ADMIN');
        _;
    }

    constructor(IPool _pool, IERC20 _dai, address _targetCollector) {
        pool = _pool;
        dai = _dai;
        targetCollector = _targetCollector;
    }

    /**
     * @dev Initialize the transparent proxy with the admin of the Collector
     * @param reserveController The address of the admin that controls Collector
     */
    function initialize(address reserveController) external initializer {
        _setFundsAdmin(reserveController);
    }

    /// @inheritdoc VersionedInitializable
    function getRevision() internal pure override returns (uint256) {
        return REVISION;
    }

    /// @inheritdoc ICollector
    function getFundsAdmin() external view returns (address) {
        return _fundsAdmin;
    }

    /// @inheritdoc ICollector
    function approve(
        IERC20 token,
        address recipient,
        uint256 amount
    ) external onlyFundsAdmin {
        token.approve(recipient, amount);
    }

    /// @inheritdoc ICollector
    function transfer(
        IERC20 token,
        address recipient,
        uint256 amount
    ) external onlyFundsAdmin {
        token.transfer(recipient, amount);
    }

    /// @inheritdoc ICollector
    function setFundsAdmin(address admin) external onlyFundsAdmin {
        _setFundsAdmin(admin);
    }

    /**
     * @dev Transfer the ownership of the funds administrator role.
     * @param admin The address of the new funds administrator
     */
    function _setFundsAdmin(address admin) internal {
        _fundsAdmin = admin;
        emit NewFundsAdmin(admin);
    }

    function _divup(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            z = x != 0 ? ((x - 1) / y) + 1 : 0;
        }
    }

    /**
     * @dev Will send the aDAI in this contract to the target collector after burning excess liabilities.
     *      Note: If the pool happens to be full you can wrap this in a flash loan.
     */
    function push() external {
        // Mint all accumulated aDAI to this contract
        address[] memory toMint = new address[](1);
        toMint[0] = address(dai);
        pool.mintToTreasury(toMint);

        // Calculate asset/liability mismatch (if any)
        DataTypes.ReserveData memory data = pool.getReserveData(address(dai));
        IAToken adai = IAToken(data.aTokenAddress);
        uint256 assets = dai.balanceOf(address(adai)) + IERC20(data.variableDebtTokenAddress).totalSupply() + IERC20(data.stableDebtTokenAddress).totalSupply();
        uint256 liabilities = _divup((adai.scaledTotalSupply() + uint256(data.accruedToTreasury)) * data.liquidityIndex, 10 ** 27);
        uint256 remainingExcess = 0;
        if (liabilities > assets) {
            // Burn excess liabilities by withdrawing and donating back to the pool
            uint256 excess = liabilities - assets;
            uint256 poolLiquidity = dai.balanceOf(address(adai));
            if (poolLiquidity < excess) {
                remainingExcess = excess - poolLiquidity;
                excess = poolLiquidity;
            }
            pool.withdraw(address(dai), excess, address(adai));
        }

        // Transfer anything remaining to the target collector
        uint256 adaiBalance = adai.balanceOf(address(this));
        if (adaiBalance > remainingExcess) {
            adai.transfer(targetCollector, adaiBalance - remainingExcess);
        }
    }
}
