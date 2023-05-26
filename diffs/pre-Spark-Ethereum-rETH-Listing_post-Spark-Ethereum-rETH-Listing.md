## Reserve changes

### Reserves added

#### rETH ([0xae78736Cd615f374D3085123A210448E74Fc6393](https://etherscan.io/address/0xae78736Cd615f374D3085123A210448E74Fc6393))

| description | value |
| --- | --- |
| decimals | 18 |
| isActive | true |
| isFrozen | false |
| supplyCap | 20,000 rETH |
| borrowCap | 2,400 rETH |
| debtCeiling | 0 $ |
| isSiloed | false |
| isFlashloanable | true |
| eModeCategory | 1 |
| oracle | [0x553303d460EE0afB37EdFf9bE42922D8FF63220e](https://etherscan.io/address/0x553303d460EE0afB37EdFf9bE42922D8FF63220e) |
| oracleDecimals | 8 |
| oracleDescription | UNI / USD |
| oracleLatestAnswer | 4.9904 |
| usageAsCollateralEnabled | true |
| ltv | 68.5 % |
| liquidationThreshold | 79.5 % |
| liquidationBonus | 7 % |
| liquidationProtocolFee | 10 % |
| reserveFactor | 15 % |
| aToken | [0x7b481aCC9fDADDc9af2cBEA1Ff2342CB1733E50F](https://etherscan.io/address/0x7b481aCC9fDADDc9af2cBEA1Ff2342CB1733E50F) |
| aTokenImpl | [0x6175ddEc3B9b38c88157C10A01ed4A3fa8639cC6](https://etherscan.io/address/0x6175ddEc3B9b38c88157C10A01ed4A3fa8639cC6) |
| variableDebtToken | [0x57a2957651DA467fCD4104D749f2F3684784c25a](https://etherscan.io/address/0x57a2957651DA467fCD4104D749f2F3684784c25a) |
| variableDebtTokenImpl | [0x86C71796CcDB31c3997F8Ec5C2E3dB3e9e40b985](https://etherscan.io/address/0x86C71796CcDB31c3997F8Ec5C2E3dB3e9e40b985) |
| stableDebtToken | [0xbf13910620722D4D4F8A03962894EB3335Bf4FaE](https://etherscan.io/address/0xbf13910620722D4D4F8A03962894EB3335Bf4FaE) |
| stableDebtTokenImpl | [0x026a5B6114431d8F3eF2fA0E1B2EDdDccA9c540E](https://etherscan.io/address/0x026a5B6114431d8F3eF2fA0E1B2EDdDccA9c540E) |
| borrowingEnabled | true |
| stableBorrowRateEnabled | false |
| isBorrowableInIsolation | false |
| interestRateStrategy | [0xDD57c0Ba58A8BF08169b9FFdcEea8B2d8E35aeC6](https://etherscan.io/address/0xDD57c0Ba58A8BF08169b9FFdcEea8B2d8E35aeC6) |
| optimalUsageRatio | 45 % |
| maxExcessUsageRatio | 55 % |
| baseVariableBorrowRate | 0 % |
| variableRateSlope1 | 7 % |
| variableRateSlope2 | 300 % |
| baseStableBorrowRate | 7 % |
| stableRateSlope1 | 0 % |
| stableRateSlope2 | 0 % |
| optimalStableToTotalDebtRatio | 0 % |
| maxExcessStableToTotalDebtRatio | 100 % |
| interestRate | ![ir](/.assets/b092ae756c2e4a62477e7558d139088069f992d2.svg) |

## Raw diff

```json
{
  "reserves": {
    "0xae78736Cd615f374D3085123A210448E74Fc6393": {
      "from": null,
      "to": {
        "aToken": "0x7b481aCC9fDADDc9af2cBEA1Ff2342CB1733E50F",
        "aTokenImpl": "0x6175ddEc3B9b38c88157C10A01ed4A3fa8639cC6",
        "borrowCap": 2400,
        "borrowingEnabled": true,
        "debtCeiling": 0,
        "decimals": 18,
        "eModeCategory": 1,
        "interestRateStrategy": "0xDD57c0Ba58A8BF08169b9FFdcEea8B2d8E35aeC6",
        "isActive": true,
        "isBorrowableInIsolation": false,
        "isFlashloanable": true,
        "isFrozen": false,
        "isSiloed": false,
        "liquidationBonus": 10700,
        "liquidationProtocolFee": 1000,
        "liquidationThreshold": 7950,
        "ltv": 6850,
        "oracle": "0x553303d460EE0afB37EdFf9bE42922D8FF63220e",
        "oracleDecimals": 8,
        "oracleDescription": "UNI / USD",
        "oracleLatestAnswer": 499040000,
        "reserveFactor": 1500,
        "stableBorrowRateEnabled": false,
        "stableDebtToken": "0xbf13910620722D4D4F8A03962894EB3335Bf4FaE",
        "stableDebtTokenImpl": "0x026a5B6114431d8F3eF2fA0E1B2EDdDccA9c540E",
        "supplyCap": 20000,
        "symbol": "rETH",
        "underlying": "0xae78736Cd615f374D3085123A210448E74Fc6393",
        "usageAsCollateralEnabled": true,
        "variableDebtToken": "0x57a2957651DA467fCD4104D749f2F3684784c25a",
        "variableDebtTokenImpl": "0x86C71796CcDB31c3997F8Ec5C2E3dB3e9e40b985"
      }
    }
  },
  "strategies": {
    "0xDD57c0Ba58A8BF08169b9FFdcEea8B2d8E35aeC6": {
      "from": null,
      "to": {
        "baseStableBorrowRate": "70000000000000000000000000",
        "baseVariableBorrowRate": 0,
        "maxExcessStableToTotalDebtRatio": "1000000000000000000000000000",
        "maxExcessUsageRatio": "550000000000000000000000000",
        "optimalStableToTotalDebtRatio": 0,
        "optimalUsageRatio": "450000000000000000000000000",
        "stableRateSlope1": 0,
        "stableRateSlope2": 0,
        "variableRateSlope1": "70000000000000000000000000",
        "variableRateSlope2": "3000000000000000000000000000"
      }
    }
  }
}
```