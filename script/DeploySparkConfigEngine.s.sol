// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {ScriptTools} from "dss-test/ScriptTools.sol";

import {AaveV3ConfigEngine}    from 'aave-helpers/v3-config-engine/AaveV3ConfigEngine.sol';
import {V3RateStrategyFactory} from 'aave-helpers/v3-config-engine/V3RateStrategyFactory.sol';

// Note: We need to link to aave-v3-core instead of sparklend-v1-core because of conflicts with the helper library
import {IAaveOracle}                  from 'aave-v3-core/contracts/interfaces/IAaveOracle.sol';
import {IDefaultInterestRateStrategy} from 'aave-v3-core/contracts/interfaces/IDefaultInterestRateStrategy.sol';
import {IPoolAddressesProvider}       from 'aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol';
import {IPoolConfigurator}            from 'aave-v3-core/contracts/interfaces/IPoolConfigurator.sol';
import {IPool}                        from 'aave-v3-core/contracts/interfaces/IPool.sol';

import {ITransparentProxyFactory} from 'solidity-utils/contracts/transparent-proxy/interfaces/ITransparentProxyFactory.sol';
import {ProxyAdmin}               from 'solidity-utils/contracts/transparent-proxy/ProxyAdmin.sol';
import {TransparentProxyFactory}  from 'solidity-utils/contracts/transparent-proxy/TransparentProxyFactory.sol';

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

contract DeploySparkConfigEngine is Script {

    using stdJson for string;
    using ScriptTools for string;

    string config;
    string instanceId;
    string outputName;
    string deployedContracts;

    address admin;
    address deployer;

    IPoolAddressesProvider poolAddressesProvider;

    TransparentProxyFactory transparentProxyFactory;
    ProxyAdmin proxyAdmin;
    V3RateStrategyFactory ratesFactory;
    AaveV3ConfigEngine configEngine;

    function run() external {
        instanceId = vm.envOr("INSTANCE_ID", string("primary"));
        outputName = string(abi.encodePacked(instanceId, "-sce"));
        vm.setEnv("FOUNDRY_ROOT_CHAINID", vm.toString(block.chainid));

        config                = ScriptTools.readInput(instanceId);
        deployedContracts     = ScriptTools.readOutput(instanceId);
        poolAddressesProvider = IPoolAddressesProvider(deployedContracts.readAddress(".poolAddressesProvider"));

        admin    = config.readAddress(".admin");
        deployer = msg.sender;

        address[] memory reservesToSkip = new address[](1);
        reservesToSkip[0] = config.readAddress(".daiToken");

        vm.startBroadcast();
        transparentProxyFactory = new TransparentProxyFactory();
        proxyAdmin              = ProxyAdmin(transparentProxyFactory.createProxyAdmin(admin));

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

        ScriptTools.exportContract(outputName, "admin",                   admin);
        ScriptTools.exportContract(outputName, "deployer",                deployer);
        ScriptTools.exportContract(outputName, "transparentProxyFactory", address(transparentProxyFactory));
        ScriptTools.exportContract(outputName, "proxyAdmin",              address(proxyAdmin));
        ScriptTools.exportContract(outputName, "ratesFactory",            address(ratesFactory));
        ScriptTools.exportContract(outputName, "configEngine",            address(configEngine));
    }

}
