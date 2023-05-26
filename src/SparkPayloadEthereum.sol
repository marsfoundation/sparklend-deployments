// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import 'aave-helpers/v3-config-engine/AaveV3PayloadBase.sol';

/**
 * @dev Base smart contract for a Spark v3.0.1 (compatible with 3.0.0) listing on Ethereum.
 * @author Phoenix Labs
 */
abstract contract SparkPayloadEthereum is
  AaveV3PayloadBase(IEngine(0x9D3DA37d36BB0B825CD319ed129c2872b893f538))
{
  function getPoolContext() public pure override returns (IEngine.PoolContext memory) {
    return IEngine.PoolContext({networkName: 'Ethereum', networkAbbreviation: 'Eth'});
  }
}
