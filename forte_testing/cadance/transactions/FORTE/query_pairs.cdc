import SwapFactory from 0x49bae091e5ea16b5
import StableSwapFactory from 0x49bae091e5ea16b5
import FlowToken from 0x7e60df042a9c0868

// Script to find valid pair addresses on IncrementFi
access(all) fun main(): {String: AnyStruct} {
    let result: {String: AnyStruct} = {}
    
    // Common token types on Flow testnet
    let flowToken = "A.7e60df042a9c0868.FlowToken"
    
    // Try to find some common pairs
    let commonTokens = [
        "A.b19436aae4d94622.FiatToken", // USDC
        "A.e223d8a629e49c68.FUSD",      // FUSD  
        "A.d6f80565193ad727.BloctoToken" // BLT
    ]
    
    var availablePairs: [String] = []
    var stablePairs: [String] = []
    
    // Check volatile pairs
    for token in commonTokens {
        let pairAddress = SwapFactory.getPairAddress(
            token0Key: flowToken,
            token1Key: token
        )
        
        if pairAddress != nil {
            availablePairs.append(
                "FLOW/".concat(token.split(separator: ".")[2])
                .concat(" -> ").concat(pairAddress!.toString())
            )
        }
    }
    
    // Check stable pairs
    for token in commonTokens {
        let stablePairAddress = StableSwapFactory.getPairAddress(
            token0Key: flowToken,
            token1Key: token
        )
        
        if stablePairAddress != nil {
            stablePairs.append(
                "FLOW/".concat(token.split(separator: ".")[2])
                .concat(" -> ").concat(stablePairAddress!.toString())
            )
        }
    }
    
    result["availablePairs"] = availablePairs
    result["stablePairs"] = stablePairs
    
    // Try to get some existing pairs from factory
    let factoryInfo = SwapFactory.getAllPairsLength()
    result["totalPairs"] = factoryInfo
    
    if factoryInfo > 0 {
        let firstPair = SwapFactory.getPairByIndex(index: 0)
        if firstPair != nil {
            result["firstPairAddress"] = firstPair!.toString()
        }
    }
    
    return result
}