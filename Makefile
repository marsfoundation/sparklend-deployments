deploy        :; forge script script/DeploySpark.s.sol:DeploySpark --optimizer-runs 100000 --rpc-url ${ETH_RPC_URL} --sender ${ETH_FROM} --broadcast --verify --slow
deploy-engine :; forge script script/SparkConfigEngine.s.sol:DeploySparkConfig --rpc-url ${ETH_RPC_URL} --sender ${ETH_FROM} --broadcast --verify --slow
