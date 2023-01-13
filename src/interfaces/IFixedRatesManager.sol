// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.10;

import {IPool} from 'aave-v3-core/contracts/interfaces/IPool.sol';
import {IVariableInterestToken} from './IVariableInterestToken.sol';

/**
 * @title Spark Fixed Rates Manager
 * @notice Interface for the Fixed Rates Manager contract.
 */
interface IFixedRatesManager {
    /**
     * @dev Emitted when an fixedRatesManager is initialized
     * @param pool The pool contract that is initializing this contract
     * @param vToken The address of the vToken
     * @param admin The address of the admin of this contract
     * @param treasury The treasury contract
     **/
    event Initialized(
        address indexed pool,
        address indexed vToken,
        address admin,
        address treasury
    );

    /**
     * @dev Emitted during the transfer of ownership of the administrator address
     * @param admin The new administrator address
     **/
    event NewAdmin(address indexed admin);

    /**
     * @notice Initializes the variableInterestToken
     * @param pool The pool contract that is initializing this contract
     * @param vToken The address of the vToken
     * @param admin The address of the admin of this contract
     * @param treasury The treasury contract
     */
    function initialize(
        IPool pool,
        IVariableInterestToken vToken,
        address admin,
        address treasury
    ) external;

    /**
     * @notice Mints `amount` variableInterestTokens to `to`
     * @param to The address of the user that will receive the minted variableInterestTokens
     * @param amount The amount of tokens getting minted
     */
    function mint(
        address to,
        uint256 amount
    ) external;

    /**
     * @notice Burns `amount` variableInterestTokens and sends the aTokens to `to`
     * @param to The address of the user that will receive the aTokens
     * @param amount The amount of tokens getting burned / sent
     */
    function redeem(
        address to,
        uint256 amount
    ) external;

    /**
     * @notice Burns `amount` variableInterestTokens and repays the loan of `to`
     * @dev Note that this only works if there is enough liquidity in the pool
     * @param to The address of the user that has a loan
     * @param amount The amount of tokens getting repaid
     */
    function redeemAndRepay(
        address to,
        uint256 amount
    ) external;

    /**
     * @notice Updates all interest rate calculations, pulls in tokens and splits between vToken and treasury
     * @return The variable borrow index as of this current timestamp
     */
    function update() external returns (uint256);

    /**
     * @notice Returns the last index value
     * @return The last index value
     */
    function getLastIndex() external view returns (uint256);

    /**
     * @notice Returns the address of the pool
     * @return The address of the pool
     **/
    function POOL() external view returns (address);

    /**
     * @notice Returns the address of the vToken
     * @return The address of the vToken
     **/
    function VTOKEN_ADDRESS() external view returns (address);

    /**
     * @notice Returns the address of the aToken
     * @return The address of the aToken
     **/
    function ATOKEN_ADDRESS() external view returns (address);

    /**
     * @notice Returns the address of the underlying asset of this vToken
     * @return The address of the underlying asset
     **/
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);

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

    /**
     * @dev Retrieve the current administrator
     * @return The address of the administrator
     */
    function getAdmin() external view returns (address);

    /**
     * @dev Transfer the ownership of the administrator role.
            This function should only be callable by the current administrator.
     * @param admin The address of the new administrator
     */
    function setAdmin(address admin) external;
}
