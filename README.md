# Spark Lend

This is the repository for Spark Lend deploy scripts and custom code. Primarily this repository acts as an orchestration toolkit for deploying and managing Spark Lend instances across many chains. Apart from the custom code below everything is combined from third party vendors.

## Usage

Run tests: `make test`  
Deploy Spark Lend: `ETH_RPC_URL=<YOUR RPC ENDPOINT> make deploy`  
Deploy Config Engine: `ETH_RPC_URL=<YOUR RPC ENDPOINT> make deploy-engine`  
Deploy Spark Lend (Custom Instance): `INSTANCE_ID=<Custom Instance Name> ETH_RPC_URL=<YOUR RPC ENDPOINT> make deploy`  
Deploy Config Engine (Custom Instance): `INSTANCE_ID=<Custom Instance Name> ETH_RPC_URL=<YOUR RPC ENDPOINT> make deploy-engine`  
Deploy Pool Upgrade: `ETH_RPC_URL=<YOUR RPC ENDPOINT> make deploy-pool` (Please note you need to set the proper `POOL_REVISION` in `Pool.sol`)  

Please note there may be some custom configs so please check the `Makefile`.

## Full Instructions to Deploy

These instructions assume that an `admin` L2 Executor governance relay has already been deployed. If you haven't deployed this already then please follow the instructions to deploy in https://github.com/marsfoundation/spark-gov-relay .

As deployer:

1. Create directory `script/input/<CHAINID>/`.
1. Copy `primary.json` from `script/input/100/` to your newly created directory.
1. Update relevant fields in the json. `admin` will usually point to the L2 Executor governance relay.
1. Run `ETH_RPC_URL=<YOUR RPC ENDPOINT> make deploy` to deploy an empty instance of Spark Lend.
1. This will generate an output file in `script/output/<CHAINID>/primary-<TIMESTAMP>.json`. Rename this to `primary-latest.json`.
1. Inside `script/output/<CHAINID>/` create the directory `broadcast`.
1. Copy the broadcast file generated from `broadcast/DeploySpark.s.sol/<CHAINID>/run-latest.json` into the newly created broadcast directory. Rename it to `primary-<DATE>.json`. This broadcast file will be used to validate the deploy by reviewers.
1. Run `ETH_RPC_URL=<YOUR RPC ENDPOINT> make deploy-engine` to deploy an instance of the config engine.
1. This will generate an output file in `script/output/<CHAINID>/primary-sce-<TIMESTAMP>.json`. Rename this to `primary-sce-latest.json`.
1. Copy the broadcast file generated from `broadcast/DeploySparkConfigEngine.s.sol/<CHAINID>/run-latest.json` into the broadcast directory. Rename it to `primary-sce-<DATE>.json`.
1. Copy the file `test/deploys/100/primary/SparkDeploy_20230714_GnosisPrimary.t.sol` to `test/deploys/<CHAINID>/primary/SparkDeploy_<DATE>_<CHAINNAME>Primary.t.sol`.
1. Update the file as necessary. Tests should pass.
1. Notify the reviewers that the deploy is ready for review.

As reviewer:

1. Verify the deployer followed all steps above.
1. Verify all contract addresses in the json files makes sense. IE `admin` is the L2 Executor. `pool` is the pool proxy, etc.
1. Run `forge test`. This will ensure the deployment configuration was done correctly, and will check most of the permissions (not all - you need to check some manually below).
1. Verify the bytecode of all deployed contracts for both the Spark Lend and Config Engine Deploys. (see detailed instructions below on how to do this)
1. Manually verify no extra permissions have been added on the `ACLManager`. The automated checks will prove that `admin` has access and `deployer` doesn't, but the `deployer` may have added another address in an intermediate transaction. In the transactions tab for the `ACLManager` ensure that only the proper adds and removes that correspond to the deployer script are present with either the address `deployer` (which should be the deployer address) and the `admin`.

## Verifying Bytecode on Deploys

### To Install

1. Install local instance of sourcify via https://docs.sourcify.dev/docs/run-locally/#running-the-server
2. Default `.env.dev` is mostly fine, but update `NODE_URL_MAINNET` to be a valid rpc endpoint.
3. Start the server `npm run server:start`.

### To Run

Run `./validate-deploy.sh path/to/broadcast.json --local` (Be sure to `forge build` with proper settings first)

If you want to delete previously verified contracts then run `rm -rf /tmp/sourcify/repository/contracts/*`

## Custom Code

### DaiInterestRateStrategy

A special interest rate strategy is used for the DAI market which anchors to the Dai Savings Rate (DSR). It is a flat rate up to the debt ceiling. If Maker needs to bring back liquidity by lowering the debt ceiling then the interest rate will spike to ensure user deposits and borrow repayments.

You can read more about this [here](https://forum.makerdao.com/t/mip116-d3m-to-spark-lend/19732#mip116c3-debt-ceiling-fee-structure-10).

### RateTargetBaseInterestRateStrategy + RateTargetKinkInterestRateStrategy

Custom IRMs to automate base or kink values to track some non-hardcoded value. The base version can be used to set a floor on the DAI market that is the DSR for example. The kink version can be used to target some APR + spread which is useful for USDC/USDT/ETH markets to track the safe yield of the asset.

### SavingsDaiOracle

This is the oracle for sDAI which will take the input of a standard DAI price feed and convert it via the `pot.chi` factor.

## Bug Bounty

There is a bug bounty program at https://immunefi.com/bounty/sparklend/
***
*The IP in this repository was assigned to Mars SPC Limited in respect of the MarsOne SP*
