// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.10;

import {IAaveIncentivesController} from 'aave-v3-core/contracts/interfaces/IAaveIncentivesController.sol';
import {IPool} from 'aave-v3-core/contracts/interfaces/IPool.sol';
import {IAToken} from 'aave-v3-core/contracts/interfaces/IAToken.sol';

/**
 * @title IInitializableVariableInterestToken
 * @notice Interface for the initialize function on VariableInterestToken
 **/
interface IInitializableVariableInterestToken {
    /**
    * @dev Emitted when an variableInterestToken is initialized
    * @param aToken The address of the aToken
    * @param pool The address of the associated pool
    * @param manager The address of the manager
    * @param incentivesController The address of the incentives controller for this aToken
    * @param variableInterestTokenDecimals The decimals of the underlying
    * @param variableInterestTokenName The name of the aToken
    * @param variableInterestTokenSymbol The symbol of the aToken
    * @param params A set of encoded parameters for additional initialization
    **/
    event Initialized(
        address indexed aToken,
        address indexed pool,
        address manager,
        address incentivesController,
        uint8 variableInterestTokenDecimals,
        string variableInterestTokenName,
        string variableInterestTokenSymbol,
        bytes params
    );

    /**
    * @notice Initializes the variableInterestToken
    * @param pool The pool contract that is initializing this contract
    * @param manager The address of the Aave manager, receiving the fees on this aToken
    * @param aToken The address of the aToken
    * @param incentivesController The smart contract managing potential incentives distribution
    * @param variableInterestTokenDecimals The decimals of the aToken, same as the underlying asset's
    * @param variableInterestTokenName The name of the aToken
    * @param variableInterestTokenSymbol The symbol of the aToken
    * @param params A set of encoded parameters for additional initialization
    */
    function initialize(
        IPool pool,
        address manager,
        IAToken aToken,
        IAaveIncentivesController incentivesController,
        uint8 variableInterestTokenDecimals,
        string calldata variableInterestTokenName,
        string calldata variableInterestTokenSymbol,
        bytes calldata params
    ) external;
}
