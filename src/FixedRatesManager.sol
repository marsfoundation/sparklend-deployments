// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.10;

import {IERC20} from 'aave-v3-core/contracts/dependencies/openzeppelin/contracts/IERC20.sol';
import {GPv2SafeERC20} from 'aave-v3-core/contracts/dependencies/gnosis/contracts/GPv2SafeERC20.sol';
import {VersionedInitializable} from 'aave-v3-core/contracts/protocol/libraries/aave-upgradeability/VersionedInitializable.sol';
import {IPool} from 'aave-v3-core/contracts/interfaces/IPool.sol';
import {IAToken} from 'aave-v3-core/contracts/interfaces/IAToken.sol';
import {WadRayMath} from 'aave-v3-core/contracts/protocol/libraries/math/WadRayMath.sol';
import {IFixedRatesManager} from './interfaces/IFixedRatesManager.sol';
import {IVariableInterestToken} from './interfaces/IVariableInterestToken.sol';

/**
 * @title Spark Fixed Rates Manager
 * @notice Mints variable interest tokens and sends them to external protocols.
 */
contract FixedRatesManager is VersionedInitializable, IFixedRatesManager {
    using WadRayMath for uint256;
    using GPv2SafeERC20 for IERC20;

    uint256 public constant FIXED_RATES_MANAGER_REVISION = 0x1;
    uint256 public constant DUST = 1 ether;

    uint256 private constant RAY = 10 ** 27;

    IPool internal _pool;
    IVariableInterestToken internal _vToken;
    address internal _admin;
    IAToken internal _aToken;
    address internal _underlyingAsset;
    address internal _treasury;

    uint256 internal _lastIndex;

    /**
     * @dev Allow only the administrator address to call functions marked by this modifier
     */
    modifier onlyAdmin() {
        require(msg.sender == _admin, 'ONLY_BY_ADMIN');
        _;
    }

    /// @inheritdoc IFixedRatesManager
    function initialize(
        IPool pool,
        IVariableInterestToken vToken,
        address admin,
        address treasury
    ) external override initializer {
        _pool = pool;
        _vToken = vToken;
        _aToken = IAToken(vToken.ATOKEN_ADDRESS());
        _underlyingAsset = vToken.UNDERLYING_ASSET_ADDRESS();
        _treasury = treasury;
        _lastIndex = 10 ** 27;
        _setAdmin(admin);

        // Need DUST amount of dai to trigger index updates
        IERC20(_underlyingAsset).safeTransferFrom(msg.sender, address(this), DUST);
        IERC20(_underlyingAsset).approve(address(pool), type(uint256).max);

        emit Initialized(
            address(pool),
            address(vToken),
            admin,
            treasury
        );
    }

    function _triggerIndexUpdate() private {
        _pool.supply(_underlyingAsset, 1, address(this), 2);
    }

    /// @inheritdoc IFixedRatesManager
    function mint(address to, uint256 amount) external onlyAdmin {
        this.update();
        _vToken.mint(to, amount);
    }

    /// @inheritdoc IFixedRatesManager
    function redeem(address to, uint256 amount) external {
        this.update();
        _vToken.burn(msg.sender, to, amount);
    }

    /// @inheritdoc IFixedRatesManager
    function redeemAndRepay(address to, uint256 amount) external {
        this.update();
        _vToken.burn(msg.sender, address(this), amount);
        _pool.withdraw(_underlyingAsset, amount, address(this));
        _pool.repay(_underlyingAsset, amount, 2, to);
    }

    /// @inheritdoc IFixedRatesManager
    function update() public returns (uint256 index) {
        _triggerIndexUpdate();
        index = _pool.getReserveNormalizedVariableDebt(_underlyingAsset);

        // Pull latest amount of the asset back
        address[] memory assets = new address[](1);
        assets[0] = _underlyingAsset;
        _pool.mintToTreasury(assets);

        // Send the delta to the vToken
        uint256 delta = (index - _lastIndex).rayMul(_vToken.totalSupply());  // TODO: check this math is correct
        _aToken.transfer(address(_vToken), delta);
        _lastIndex = index;

        // Send anything left over to the treasury
        _aToken.transfer(_treasury, _aToken.balanceOf(address(this)));
    }

    /// @inheritdoc VersionedInitializable
    function getRevision() internal pure virtual override returns (uint256) {
        return FIXED_RATES_MANAGER_REVISION;
    }

    /// @inheritdoc IFixedRatesManager
    function getLastIndex() external view override returns (uint256) {
        return _lastIndex;
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
    function rescueTokens(
        address token,
        address to,
        uint256 amount
    ) external override onlyAdmin {
        IERC20(token).safeTransfer(to, amount);
    }

    /// @inheritdoc IFixedRatesManager
    function setAdmin(address admin) external onlyAdmin {
        _setAdmin(admin);
    }

    /**
     * @dev Transfer the ownership of the administrator role.
     * @param admin The address of the new administrator
     */
    function _setAdmin(address admin) internal {
        _admin = admin;
        emit NewAdmin(admin);
    }

    /// @inheritdoc IFixedRatesManager
    function getAdmin() external view returns (address) {
        return _admin;
    }

}
