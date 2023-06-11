deploy        :; forge script script/DeploySpark.s.sol:DeploySpark --rpc-url ${ETH_RPC_URL} --sender ${ETH_FROM} --broadcast --verify --slow
deploy-engine :; forge script script/SparkConfigEngine.s.sol:DeploySparkConfig --optimizer-runs 200 --rpc-url ${ETH_RPC_URL} --sender ${ETH_FROM} --broadcast --verify --slow
