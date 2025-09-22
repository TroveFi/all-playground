import BandOracleConnectors from 0x1a9f5d18d096cd7a
import FungibleToken from 0x9a0766d93b6608b7
import FlowToken from 0x7e60df042a9c0868

// Script to query Band Oracle for token pair price
access(all) fun main(tokenXType: String, tokenYType: String): {String: AnyStruct} {
    log("Querying Band Oracle for price")
    log("Token X: ".concat(tokenXType))
    log("Token Y: ".concat(tokenYType))
    
    // Create Band Oracle connector
    let oracle = BandOracleConnectors.BandPriceOracle()
    
    // Get price quote for the pair
    let quote = oracle.getPrice(
        baseSymbol: tokenXType,
        quoteSymbol: tokenYType
    )
    
    let result: {String: AnyStruct} = {
        "baseToken": tokenXType,
        "quoteToken": tokenYType,
        "price": quote.price,
        "decimals": quote.decimals,
        "timestamp": quote.timestamp,
        "confidence": quote.confidence,
        "source": "BandProtocol"
    }
    
    log("Price: ".concat(quote.price.toString()))
    log("Timestamp: ".concat(quote.timestamp.toString()))
    log("Confidence: ".concat(quote.confidence.toString()))
    
    return result
}