import IncrementFiPoolLiquidityConnectors from 0x49bae091e5ea16b5
import SwapConnectors from 0xaddd594cf410166a
import DeFiActions from 0x4c2ff9dd03ab442f
import FungibleToken from 0x9a0766d93b6608b7
import FlowToken from 0x7e60df042a9c0868

// Script to test IncrementFi Zapper with known working token types
access(all) fun main(amount: UFix64): {String: AnyStruct} {
    log("Testing IncrementFi Zapper functionality...")
    log("Amount: ".concat(amount.toString()))
    
    // Use FlowToken as a base - we know this exists
    let flowType = Type<@FlowToken.Vault>()
    
    // Try to find working token types by testing common ones
    // We'll attempt with FlowToken and see what error we get to understand available pairs
    let testTypes: [String] = [
        "A.7e60df042a9c0868.FlowToken.Vault"
    ]
    
    var results: {String: AnyStruct} = {
        "testedAmount": amount,
        "flowTokenType": flowType.identifier,
        "availableTests": testTypes,
        "timestamp": getCurrentBlock().timestamp
    }
    
    // Try creating a basic quote structure without actual Zapper
    let basicQuote = SwapConnectors.BasicQuote(
        inType: flowType,
        outType: flowType, // This is wrong but let's see the structure
        inAmount: amount,
        outAmount: 0.0
    )
    
    results["basicQuoteStructure"] = {
        "inType": basicQuote.inType.identifier,
        "outType": basicQuote.outType.identifier,
        "inAmount": basicQuote.inAmount,
        "outAmount": basicQuote.outAmount
    }
    
    log("Basic quote created successfully")
    log("Quote inType: ".concat(basicQuote.inType.identifier))
    
    return results
}