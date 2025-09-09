// 6. get-exchange-rate.cdc
// This script gets the current exchange rate

import ActionRouter from 0x79f5b5b0f95a160b

access(all) fun main(): UFix64 {
    let exchangeRate = ActionRouter.getExchangeRate()
    log("Current stFLOW exchange rate: ".concat(exchangeRate.toString()))
    return exchangeRate
}