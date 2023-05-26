// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPoolAddressesProvider} from 'aave-v3-core/contracts/intefaces/IPoolAddressesProvider.sol';
import {IPool} from 'aave-v3-core/contracts/intefaces/IPool.sol';
import {IDefaultInterestRateStrategy} from 'aave-v3-core/contracts/intefaces/IDefaultInterestRateStrategy.sol';
import {ITransparentProxyFactory} from 'solidity-utils/contracts/transparent-proxy/interfaces/ITransparentProxyFactory.sol';
import {V3RateStrategyFactory} from 'aave-helpers/v3-config-engine/V3RateStrategyFactory.sol';

library DeployRatesFactoryLib {
    // TODO check also by param, potentially there could be different contracts, but with exactly same params
    function _getUniqueStrategiesOnPool(IPool pool)
        internal
        view
        returns (IDefaultInterestRateStrategy[] memory)
    {
        address[] memory listedAssets = pool.getReservesList();
        IDefaultInterestRateStrategy[] memory uniqueRateStrategies = new IDefaultInterestRateStrategy[](
            listedAssets.length
        );
        uint256 uniqueRateStrategiesSize;
        for (uint256 i = 0; i < listedAssets.length; i++) {
            address strategy = pool.getReserveData(listedAssets[i]).interestRateStrategyAddress;

            bool found;
            for (uint256 j = 0; j < uniqueRateStrategiesSize; j++) {
                if (strategy == address(uniqueRateStrategies[j])) {
                    found = true;
                    break;
                }
            }

            if (!found) {
                uniqueRateStrategies[uniqueRateStrategiesSize] = IDefaultInterestRateStrategy(strategy);
                uniqueRateStrategiesSize++;
            }
        }

        // The famous one (modify dynamic array size)
        assembly {
            mstore(uniqueRateStrategies, uniqueRateStrategiesSize)
        }

        return uniqueRateStrategies;
    }

    function _createAndSetupRatesFactory(
        IPoolAddressesProvider addressesProvider,
        address transparentProxyFactory,
        address ownerForFactory
    ) internal returns (address, address[] memory) {
        IDefaultInterestRateStrategy[] memory uniqueStrategies = _getUniqueStrategiesOnPool(
            IPool(addressesProvider.getPool())
        );

        V3RateStrategyFactory ratesFactory = V3RateStrategyFactory(
            ITransparentProxyFactory(transparentProxyFactory).create(
                address(new V3RateStrategyFactory(addressesProvider)),
                ownerForFactory,
                abi.encodeWithSelector(V3RateStrategyFactory.initialize.selector, uniqueStrategies)
            )
        );

        address[] memory strategiesOnFactory = ratesFactory.getAllStrategies();

        return (address(ratesFactory), strategiesOnFactory);
    }
}

library DeployRatesFactoryEthLib {
    function deploy() internal returns (address, address[] memory) {
        return
            DeployRatesFactoryLib._createAndSetupRatesFactory(
                AaveV3Ethereum.POOL_ADDRESSES_PROVIDER,
                AaveMisc.TRANSPARENT_PROXY_FACTORY_ETHEREUM,
                AaveMisc.PROXY_ADMIN_ETHEREUM
            );
    }
}

contract DeployRatesFactoryEth {
    function run() external broadcast {
        vm.startBroadcast();
        DeployRatesFactoryLib._createAndSetupRatesFactory(
            AaveV3Ethereum.POOL_ADDRESSES_PROVIDER,
            AaveMisc.TRANSPARENT_PROXY_FACTORY_ETHEREUM,
            AaveMisc.PROXY_ADMIN_ETHEREUM
        );
        vm.stopBroadcast();
    }
}
