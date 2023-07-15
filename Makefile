deploy      :; forge script script/DeploySpark.s.sol:DeploySpark --rpc-url ${ETH_RPC_URL} --sender ${ETH_FROM} --broadcast --verify --slow
deploy-sce  :; forge script script/DeploySparkConfigEngine.s.sol:DeploySparkConfigEngine --optimizer-runs 200 --rpc-url ${ETH_RPC_URL} --sender ${ETH_FROM} --broadcast --verify --slow
deploy-pool :; forge script script/DeployPoolImplementation.s.sol:DeployPoolImplementation --rpc-url ${ETH_RPC_URL} --sender ${ETH_FROM} --broadcast --verify --slow
<<<<<<< HEAD

# Special case for verifier url and we remove --slow
deploy-gnosis :; ETHERSCAN_API_KEY=${GNOSISSCAN_API_KEY} forge script script/DeploySpark.s.sol:DeploySpark --rpc-url ${ETH_RPC_URL} --sender ${ETH_FROM} --broadcast --verify --verifier-url "https://api.gnosisscan.io/api"
=======
>>>>>>> master
