// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import {IERC20} from 'aave-v3-core/contracts/dependencies/openzeppelin/contracts/IERC20.sol';
import {GPv2SafeERC20} from 'aave-v3-core/contracts/dependencies/gnosis/contracts/GPv2SafeERC20.sol';
import {SafeCast} from 'aave-v3-core/contracts/dependencies/openzeppelin/contracts/SafeCast.sol';
import {VersionedInitializable} from 'aave-v3-core/contracts/protocol/libraries/aave-upgradeability/VersionedInitializable.sol';
import {Errors} from 'aave-v3-core/contracts/protocol/libraries/helpers/Errors.sol';
import {WadRayMath} from 'aave-v3-core/contracts/protocol/libraries/math/WadRayMath.sol';
import {IPool} from 'aave-v3-core/contracts/interfaces/IPool.sol';
import {IAaveIncentivesController} from 'aave-v3-core/contracts/interfaces/IAaveIncentivesController.sol';
import {ScaledBalanceTokenBase} from 'aave-v3-core/contracts/protocol/tokenization/base/ScaledBalanceTokenBase.sol';
import {IncentivizedERC20} from 'aave-v3-core/contracts/protocol/tokenization/base/IncentivizedERC20.sol';
import {EIP712Base} from 'aave-v3-core/contracts/protocol/tokenization/base/EIP712Base.sol';
import {IVariableInterestToken} from './IVariableInterestToken.sol';
import {IInitializableVariableInterestToken} from './IInitializableVariableInterestToken.sol';

/**
 * @title Spark Variable Interest Token
 * @notice Similar to the AToken, but tracks 100% of the borrow interest.
 */
contract VariableInterestToken is VersionedInitializable, ScaledBalanceTokenBase, EIP712Base, IVariableInterestToken {
    using WadRayMath for uint256;
    using SafeCast for uint256;
    using GPv2SafeERC20 for IERC20;

    bytes32 public constant PERMIT_TYPEHASH =
        keccak256('Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)');

    uint256 public constant VARIABLE_INTEREST_REVISION = 0x1;

    address internal _manager;
    address internal _underlyingAsset;

    /**
    * @dev Only manager can call functions marked by this modifier.
    **/
    modifier onlyManager() {
        require(_msgSender() == address(_manager), "ONLY_MANAGER");
        _;
    }

    /// @inheritdoc VersionedInitializable
    function getRevision() internal pure virtual override returns (uint256) {
        return VARIABLE_INTEREST_REVISION;
    }

    /**
     * @dev Constructor.
     * @param pool The address of the Pool contract
     */
    constructor(IPool pool)
        ScaledBalanceTokenBase(pool, 'VARIABLE_DEBT_TOKEN_IMPL', 'VARIABLE_DEBT_TOKEN_IMPL', 0)
        EIP712Base()
    {
        // Intentionally left blank
    }

    /// @inheritdoc IInitializableVariableInterestToken
    function initialize(
        IPool initializingPool,
        address manager,
        address underlyingAsset,
        IAaveIncentivesController incentivesController,
        uint8 variableInterestTokenDecimals,
        string calldata variableInterestTokenName,
        string calldata variableInterestTokenSymbol,
        bytes calldata params
    ) external override initializer {
        require(initializingPool == POOL, Errors.POOL_ADDRESSES_DO_NOT_MATCH);
        _setName(variableInterestTokenName);
        _setSymbol(variableInterestTokenSymbol);
        _setDecimals(variableInterestTokenDecimals);

        _manager = manager;
        _underlyingAsset = underlyingAsset;
        _incentivesController = incentivesController;

        _domainSeparator = _calculateDomainSeparator();

        emit Initialized(
            underlyingAsset,
            address(POOL),
            manager,
            address(incentivesController),
            variableInterestTokenDecimals,
            variableInterestTokenName,
            variableInterestTokenSymbol,
            params
        );
    }

    /// @inheritdoc IVariableInterestToken
    function mint(
        address caller,
        address onBehalfOf,
        uint256 amount,
        uint256 index
    ) external virtual override onlyManager returns (bool) {
        return _mintScaled(caller, onBehalfOf, amount, index);
    }

    /// @inheritdoc IVariableInterestToken
    function burn(
        address from,
        address receiverOfUnderlying,
        uint256 amount,
        uint256 index
    ) external virtual override onlyManager {
        _burnScaled(from, receiverOfUnderlying, amount, index);
        if (receiverOfUnderlying != address(this)) {
            IERC20(_underlyingAsset).safeTransfer(receiverOfUnderlying, amount);
        }
    }

    /// @inheritdoc IERC20
    function balanceOf(address user)
        public
        view
        virtual
        override(IncentivizedERC20, IERC20)
        returns (uint256)
    {
        return super.balanceOf(user).rayMul(POOL.getReserveNormalizedVariableDebt(_underlyingAsset));
    }

    /// @inheritdoc IERC20
    function totalSupply() public view virtual override(IncentivizedERC20, IERC20) returns (uint256) {
        uint256 currentSupplyScaled = super.totalSupply();

        if (currentSupplyScaled == 0) {
            return 0;
        }

        return currentSupplyScaled.rayMul(POOL.getReserveNormalizedVariableDebt(_underlyingAsset));
    }

    /// @inheritdoc IVariableInterestToken
    function RESERVE_MANAGER_ADDRESS() external view override returns (address) {
        return _manager;
    }

    /// @inheritdoc IVariableInterestToken
    function UNDERLYING_ASSET_ADDRESS() external view override returns (address) {
        return _underlyingAsset;
    }

    /// @inheritdoc IVariableInterestToken
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {
        require(owner != address(0), Errors.ZERO_ADDRESS_NOT_VALID);
        //solium-disable-next-line
        require(block.timestamp <= deadline, Errors.INVALID_EXPIRATION);
        uint256 currentValidNonce = _nonces[owner];
        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19\x01',
                DOMAIN_SEPARATOR(),
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, currentValidNonce, deadline))
            )
        );
        require(owner == ecrecover(digest, v, r, s), Errors.INVALID_SIGNATURE);
        _nonces[owner] = currentValidNonce + 1;
        _approve(owner, spender, value);
    }

    /**
     * @dev Overrides the base function to fully implement IVariableInterestToken
     * @dev see `IncentivizedERC20.DOMAIN_SEPARATOR()` for more detailed documentation
     */
    function DOMAIN_SEPARATOR() public view override(IVariableInterestToken, EIP712Base) returns (bytes32) {
        return super.DOMAIN_SEPARATOR();
    }

    /**
     * @dev Overrides the base function to fully implement IVariableInterestToken
     * @dev see `IncentivizedERC20.nonces()` for more detailed documentation
     */
    function nonces(address owner) public view override(IVariableInterestToken, EIP712Base) returns (uint256) {
        return super.nonces(owner);
    }

    /// @inheritdoc EIP712Base
    function _EIP712BaseId() internal view override returns (string memory) {
        return name();
    }

    /// @inheritdoc IVariableInterestToken
    function rescueTokens(
        address token,
        address to,
        uint256 amount
    ) external override onlyPoolAdmin {
        require(token != _underlyingAsset, Errors.UNDERLYING_CANNOT_BE_RESCUED);
        IERC20(token).safeTransfer(to, amount);
    }
}
