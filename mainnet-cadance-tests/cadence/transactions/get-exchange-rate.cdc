// get-exchange-rate-v3.cdc
// This script gets the current exchange rate from ActionRouterV3 (which gets it from LiquidStaking)

import ActionRouterV3 from 0x79f5b5b0f95a160b

access(all) fun main(): UFix64 {
    return ActionRouterV3.getExchangeRate()
}