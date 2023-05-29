all               :; forge build
clean             :; forge clean
test              :; ./test.sh $(match)
deploy            :; ./deploy.sh
deploy-engine-eth :; forge script script/SparkConfigEngine.s.sol:DeploySparkConfig --rpc-url ${ETH_RPC_URL} --sender ${ETH_FROM} --broadcast --verify --slow
