deploy     :; forge script script/DeploySpark.s.sol:DeploySpark --rpc-url ${ETH_RPC_URL} --sender ${ETH_FROM} --broadcast --verify --slow
deploy-sce :; forge script script/DeploySparkConfigEngine.s.sol:DeploySparkConfigEngine --optimizer-runs 200 --rpc-url ${ETH_RPC_URL} --sender ${ETH_FROM} --broadcast --verify --slow
