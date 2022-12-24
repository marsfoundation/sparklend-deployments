pragma solidity ^0.8.10;

import {
    Pool,
    IPoolAddressesProvider
} from "aave-v3-core/contracts/protocol/pool/Pool.sol";

interface D3MLike {
    function pull(uint256 wad) external;
    function push(uint256 wad) external;
}

/**
 * @title D3MPool
 * @author TODO
 * @notice Pool that is aware of a Maker D3M and will pull or push liquidity as needed.
 */
contract D3MPool is Pool {

    address public dai;
    D3MLike public d3m;

    /**
    * @dev Constructor.
    * @param provider The address of the PoolAddressesProvider contract
    * @param _dai The address of the DAI token
    * @param _d3m The address of the D3M instance
    */
    constructor(
        IPoolAddressesProvider provider,
        address _dai,
        address _d3m
    ) Pool(provider) {
        dai = _dai;
        d3m = D3MLike(_d3m);
    }

    function borrow(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        uint16 referralCode,
        address onBehalfOf
    ) public virtual override {
        if (asset == dai) {
            d3m.pull(amount);
        }

        borrow(
            asset,
            amount,
            interestRateMode,
            referralCode,
            onBehalfOf
        );
    }

}
