// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPoolAddressesProvider} from 'aave-v3-core/contracts/intefaces/IPoolAddressesProvider.sol';
import {IPool} from 'aave-v3-core/contracts/intefaces/IPool.sol';
import {IDefaultInterestRateStrategy} from 'aave-v3-core/contracts/intefaces/IDefaultInterestRateStrategy.sol';
import {ITransparentProxyFactory} from 'solidity-utils/contracts/transparent-proxy/interfaces/ITransparentProxyFactory.sol';
import {TransparentProxyFactory} from 'solidity-utils/contracts/transparent-proxy/TransparentProxyFactory.sol';
import {ProxyAdmin} from 'solidity-utils/contracts/transparent-proxy/ProxyAdmin.sol';
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

contract DeploySparkConfigEthereum is Script {

    string constant NAME = "spark-config-engine";

    using stdJson for string;
    using ScriptTools for string;

    string config;
    string deployedContracts;

    address admin;
    address deployer;

    IPoolAddressesProvider poolAddressesProvider;

    TransparentProxyFactory transparentProxyFactory;
    ProxyAdmin proxyAdmin;

    function run() external {
        config = ScriptTools.readInput(NAME);
        deployedContracts = ScriptTools.readOutput("spark");
        poolAddressesProvider = IPoolAddressesProvider(deployedContracts.readAddress(".poolAddressesProvider"));

        admin = config.readAddress(".admin");
        deployer = msg.sender;

        vm.startBroadcast();
        transparentProxyFactory = new TransparentProxyFactory();
        proxyAdmin = transparentProxyFactory.createProxyAdmin(admin);

        DeployRatesFactoryLib._createAndSetupRatesFactory(
            poolAddressesProvider,
            address(transparentProxyFactory),
            address(proxyAdmin)
        );
        vm.stopBroadcast();

        ScriptTools.exportContract(NAME, "admin", admin);
        ScriptTools.exportContract(NAME, "deployer", deployer);
        ScriptTools.exportContract(NAME, "transparentProxyFactory", address(transparentProxyFactory));
        ScriptTools.exportContract(NAME, "proxyAdmin", address(proxyAdmin));
    }

}
