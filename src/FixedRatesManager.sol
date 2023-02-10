// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.10;

import {IERC20} from 'aave-v3-core/contracts/dependencies/openzeppelin/contracts/IERC20.sol';
import {Ownable} from 'aave-v3-core/contracts/dependencies/openzeppelin/contracts/Ownable.sol';
import {GPv2SafeERC20} from 'aave-v3-core/contracts/dependencies/gnosis/contracts/GPv2SafeERC20.sol';
import {IPool} from 'aave-v3-core/contracts/interfaces/IPool.sol';
import {IAToken} from 'aave-v3-core/contracts/interfaces/IAToken.sol';
import {WadRayMath} from 'aave-v3-core/contracts/protocol/libraries/math/WadRayMath.sol';
import {IFixedRatesManager} from './interfaces/IFixedRatesManager.sol';
import {IVariableInterestToken} from './interfaces/IVariableInterestToken.sol';

/**
 * @title Spark Fixed Rates Manager
 * @notice Mints variable interest tokens and sends them to external protocols.
 */
contract FixedRatesManager is Ownable, IFixedRatesManager {
    using WadRayMath for uint256;
    using GPv2SafeERC20 for IERC20;

    IPool internal immutable _pool;
    IVariableInterestToken internal immutable _vToken;
    IAToken internal immutable _aToken;
    address internal immutable _underlyingAsset;
    address internal immutable _treasurySource;
    address internal immutable _treasuryDestination;

    /**
     * @notice Creates the fixed rates manager
     * @param pool The pool contract
     * @param vToken The address of the vToken
     * @param admin The address of the admin of this contract
     * @param treasurySource The treasury contract to pull funds from
     * @param treasuryDestination The treasury contract to send excess funds to
     */
    constructor(
        IPool pool,
        IVariableInterestToken vToken,
        address admin,
        address treasurySource,
        address treasuryDestination
    ) {
        _pool = pool;
        _vToken = vToken;
        _aToken = IAToken(vToken.ATOKEN_ADDRESS());
        _underlyingAsset = vToken.UNDERLYING_ASSET_ADDRESS();
        _treasurySource = treasurySource;
        _treasuryDestination = treasuryDestination;
        transferOwnership(admin);

        IERC20(_underlyingAsset).approve(address(pool), type(uint256).max);
        _aToken.approve(address(vToken), type(uint256).max);
    }

    /// @inheritdoc IFixedRatesManager
    function mint(address to, uint256 amount) external onlyOwner {
        _pullFunds();
        _vToken.mint(to, amount);
        _pushFunds();
    }

    /// @inheritdoc IFixedRatesManager
    function redeem(address to, uint256 amount) external {
        _pullFunds();
        _vToken.burn(msg.sender, to, amount);
        _pushFunds();
    }

    /// @inheritdoc IFixedRatesManager
    function redeemAndRepay(address to, uint256 amount) external {
        _pullFunds();
        _vToken.burn(msg.sender, address(this), amount);
        _pushFunds();

        _pool.withdraw(_underlyingAsset, amount, address(this));
        _pool.repay(_underlyingAsset, amount, 2, to);
    }

    // Pull latest amount of funds from the pool / treasury source
    function _pullFunds() private {
        _triggerIndexUpdate();
        address[] memory assets = new address[](1);
        assets[0] = _underlyingAsset;
        _pool.mintToTreasury(assets);
        IERC20(address(_aToken)).safeTransferFrom(_treasurySource, address(this), _aToken.balanceOf(_treasurySource));
    }

    // Push any unclaimed funds to the treausry destination
    function _pushFunds() private {
        IERC20(address(_aToken)).safeTransfer(_treasuryDestination, _aToken.balanceOf(address(this)));
    }

    /// @inheritdoc IFixedRatesManager
    function POOL() external view override returns (address) {
        return address(_pool);
    }

    /// @inheritdoc IFixedRatesManager
    function VTOKEN_ADDRESS() external view override returns (address) {
        return address(_vToken);
    }

    /// @inheritdoc IFixedRatesManager
    function ATOKEN_ADDRESS() external view override returns (address) {
        return address(_aToken);
    }

    /// @inheritdoc IFixedRatesManager
    function UNDERLYING_ASSET_ADDRESS() external view override returns (address) {
        return _underlyingAsset;
    }

    /// @inheritdoc IFixedRatesManager
    function TREASURY_SOURCE() external view override returns (address) {
        return _treasurySource;
    }

    /// @inheritdoc IFixedRatesManager
    function TREASURY_DESTINATION() external view override returns (address) {
        return _treasuryDestination;
    }

    /// @inheritdoc IFixedRatesManager
    function rescueTokens(
        address token,
        address to,
        uint256 amount
    ) external override onlyOwner {
        IERC20(token).safeTransfer(to, amount);
    }

    function _triggerIndexUpdate() private {
        // Not great for gas, but this is the only way to trigger index update without requiring any assets
        _pool.flashLoanSimple(address(this), _underlyingAsset, 1, "", 0);
    }
    function executeOperation(
        address,
        uint256,
        uint256,
        address,
        bytes calldata
    ) external pure returns (bool) {
        return true;
    }

}
