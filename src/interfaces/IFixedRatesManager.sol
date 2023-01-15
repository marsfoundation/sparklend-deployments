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
     * @notice Mints `amount` variableInterestTokens to `to`
     * @dev You can call this with `amount` = 0 to pull update the interest and send excess
     *      to the destination treasury
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
     * @notice Returns the address of the underlying asset
     * @return The address of the underlying asset
     **/
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);

    /**
     * @notice Returns the address of the treasury source
     * @return The address of the treasury source
     **/
    function TREASURY_SOURCE() external view returns (address);

    /**
     * @notice Returns the address of the treasury destination
     * @return The address of the treasury destination
     **/
    function TREASURY_DESTINATION() external view returns (address);

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
