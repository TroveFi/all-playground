import BandOracleConnectors from 0x1a9f5d18d096cd7a
import FungibleToken from 0x9a0766d93b6608b7
import FlowToken from 0x7e60df042a9c0868

// Script to explore Band Oracle available symbols
access(all) fun main(baseSymbol: String, quoteSymbol: String): {String: AnyStruct} {
    log("Exploring Band Oracle available symbols")
    log("Requested Base Symbol: ".concat(baseSymbol))
    log("Requested Quote Symbol: ".concat(quoteSymbol))
    
    // Check what symbols are available in the connector
    let assetSymbols = BandOracleConnectors.assetSymbols
    let flowTokenType = Type<@FlowToken.Vault>()
    
    // Get available symbols
    var availableSymbols: [String] = []
    var availableTypes: [String] = []
    
    for typeKey in assetSymbols.keys {
        availableTypes.append(typeKey.identifier)
        if let symbol = assetSymbols[typeKey] {
            availableSymbols.append(symbol)
        }
    }
    
    let result: {String: AnyStruct} = {
        "requestedBaseSymbol": baseSymbol,
        "requestedQuoteSymbol": quoteSymbol,
        "availableSymbols": availableSymbols,
        "availableTypes": availableTypes,
        "symbolCount": assetSymbols.keys.length,
        "flowTokenSupported": assetSymbols[flowTokenType] != nil,
        "flowSymbol": assetSymbols[flowTokenType],
        "note": "Band Oracle requires FLOW fees for price queries - this script just shows available symbols",
        "timestamp": getCurrentBlock().timestamp,
        "source": "BandProtocol"
    }
    
    log("Available symbols count: ".concat(assetSymbols.keys.length.toString()))
    log("FLOW token supported: ".concat(assetSymbols[flowTokenType] != nil ? "true" : "false"))
    
    if let flowSymbol = assetSymbols[flowTokenType] {
        log("FLOW symbol: ".concat(flowSymbol))
    }
    
    return result
}