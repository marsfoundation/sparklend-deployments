// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {ScriptTools} from "dss-test/ScriptTools.sol";
import {IPoolAddressesProvider} from 'aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol';
import {IPool} from 'aave-v3-core/contracts/interfaces/IPool.sol';
import {IPoolConfigurator} from 'aave-v3-core/contracts/interfaces/IPoolConfigurator.sol';
import {IAaveOracle} from 'aave-v3-core/contracts/interfaces/IAaveOracle.sol';
import {IDefaultInterestRateStrategy} from 'aave-v3-core/contracts/interfaces/IDefaultInterestRateStrategy.sol';
import {ITransparentProxyFactory} from 'solidity-utils/contracts/transparent-proxy/interfaces/ITransparentProxyFactory.sol';
import {TransparentProxyFactory} from 'solidity-utils/contracts/transparent-proxy/TransparentProxyFactory.sol';
import {ProxyAdmin} from 'solidity-utils/contracts/transparent-proxy/ProxyAdmin.sol';
import {V3RateStrategyFactory} from 'aave-helpers/v3-config-engine/V3RateStrategyFactory.sol';
import {AaveV3ConfigEngine} from 'aave-helpers/v3-config-engine/AaveV3ConfigEngine.sol';

library DeployRatesFactoryLib {
    // TODO check also by param, potentially there could be different contracts, but with exactly same params
    function _getUniqueStrategiesOnPool(
        IPool pool,
        address[] memory reservesToSkip
    )
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
            bool shouldSkip;
            for (uint256 j = 0; j < reservesToSkip.length; j++) {
                if (listedAssets[i] == reservesToSkip[j]) {
                    shouldSkip = true;
                    break;
                }
            }
            if (shouldSkip) continue;
            
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
        address ownerForFactory,
        address[] memory reservesToSkip
    ) internal returns (V3RateStrategyFactory, address[] memory) {
        IDefaultInterestRateStrategy[] memory uniqueStrategies = _getUniqueStrategiesOnPool(
            IPool(addressesProvider.getPool()),
            reservesToSkip
        );

        V3RateStrategyFactory ratesFactory = V3RateStrategyFactory(
            ITransparentProxyFactory(transparentProxyFactory).create(
                address(new V3RateStrategyFactory(addressesProvider)),
                ownerForFactory,
                abi.encodeWithSelector(V3RateStrategyFactory.initialize.selector, uniqueStrategies)
            )
        );

        address[] memory strategiesOnFactory = ratesFactory.getAllStrategies();

        return (ratesFactory, strategiesOnFactory);
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
    V3RateStrategyFactory ratesFactory;
    AaveV3ConfigEngine configEngine;

    function run() external {
        vm.setEnv("FOUNDRY_ROOT_CHAINID", vm.toString(block.chainid));
        config = ScriptTools.readInput(NAME);
        deployedContracts = ScriptTools.readOutput("spark");
        poolAddressesProvider = IPoolAddressesProvider(deployedContracts.readAddress(".poolAddressesProvider"));

        admin = config.readAddress(".admin");
        deployer = msg.sender;

        address[] memory reservesToSkip = new address[](1);
        reservesToSkip[0] = deployedContracts.readAddress(".DAI_token");

        vm.startBroadcast();
        transparentProxyFactory = new TransparentProxyFactory();
        proxyAdmin = ProxyAdmin(transparentProxyFactory.createProxyAdmin(admin));

        (ratesFactory,) = DeployRatesFactoryLib._createAndSetupRatesFactory(
            poolAddressesProvider,
            address(transparentProxyFactory),
            address(proxyAdmin),
            reservesToSkip
        );


        configEngine = new AaveV3ConfigEngine(
            IPool(deployedContracts.readAddress(".pool")),
            IPoolConfigurator(deployedContracts.readAddress(".poolConfigurator")),
            IAaveOracle(deployedContracts.readAddress(".aaveOracle")),
            deployedContracts.readAddress(".aTokenImpl"),
            deployedContracts.readAddress(".variableDebtTokenImpl"),
            deployedContracts.readAddress(".stableDebtTokenImpl"),
            deployedContracts.readAddress(".incentives"),
            deployedContracts.readAddress(".treasury"),
            ratesFactory
        );

        vm.stopBroadcast();

        ScriptTools.exportContract(NAME, "admin", admin);
        ScriptTools.exportContract(NAME, "deployer", deployer);
        ScriptTools.exportContract(NAME, "transparentProxyFactory", address(transparentProxyFactory));
        ScriptTools.exportContract(NAME, "proxyAdmin", address(proxyAdmin));
        ScriptTools.exportContract(NAME, "ratesFactory", address(ratesFactory));
        ScriptTools.exportContract(NAME, "configEngine", address(configEngine));
    }

}