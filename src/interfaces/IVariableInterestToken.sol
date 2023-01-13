// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.10;

import {IERC20} from 'aave-v3-core/contracts/dependencies/openzeppelin/contracts/IERC20.sol';
import {IScaledBalanceToken} from 'aave-v3-core/contracts/interfaces/IScaledBalanceToken.sol';
import {IInitializableVariableInterestToken} from './IInitializableVariableInterestToken.sol';

/**
 * @title IVariableInterestToken
 * @notice Defines the basic interface for an VariableInterestToken.
 **/
interface IVariableInterestToken is IERC20, IScaledBalanceToken, IInitializableVariableInterestToken {

    /**
     * @notice Mints `amount` variableInterestTokens to `to`
     * @param to The address of the user that will receive the minted variableInterestTokens
     * @param amount The amount of tokens getting minted
     * @return `true` if the the previous balance of the user was 0
     */
    function mint(
        address to,
        uint256 amount
    ) external returns (bool);

    /**
     * @notice Burns variableInterestTokens from `user` and sends the equivalent amount of underlying to `receiverOfUnderlying`
     * @dev In some instances, the mint event could be emitted from a burn transaction
     * if the amount to burn is less than the interest that the user accrued
     * @param from The address from which the variableInterestTokens will be burned
     * @param receiverOfUnderlying The address that will receive the underlying
     * @param amount The amount being burned
     **/
    function burn(
        address from,
        address receiverOfUnderlying,
        uint256 amount
    ) external;

    /**
     * @notice Allow passing a signed message to approve spending
     * @dev implements the permit function as for
     * https://github.com/ethereum/EIPs/blob/8a34d644aacf0f9f8f00815307fd7dd5da07655f/EIPS/eip-2612.md
     * @param owner The owner of the funds
     * @param spender The spender
     * @param value The amount
     * @param deadline The deadline timestamp, type(uint256).max for max deadline
     * @param v Signature param
     * @param s Signature param
     * @param r Signature param
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /**
     * @notice Returns the address of the aToken
     * @return The address of the aToken
     **/
    function ATOKEN_ADDRESS() external view returns (address);

    /**
     * @notice Returns the address of the underlying asset of this aToken (E.g. WETH for aWETH)
     * @return The address of the underlying asset
     **/
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);

    /**
     * @notice Returns the address of the manager.
     * @return Address of the manager
     **/
    function RESERVE_MANAGER_ADDRESS() external view returns (address);

    /**
     * @notice Get the domain separator for the token
     * @dev Return cached value if chainId matches cache, otherwise recomputes separator
     * @return The domain separator of the token at current chain
     */
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    /**
     * @notice Returns the nonce for owner.
     * @param owner The address of the owner
     * @return The nonce of the owner
     **/
    function nonces(address owner) external view returns (uint256);

    /**
     * @notice Rescue and transfer tokens locked in this contract
     * @param token The address of the token
     * @param to The address of the recipient
     * @param amount The amount of token to transfer
     */
    function rescueTokens(
        address token,
        address to,
        uint256 amount
    ) external;
}
