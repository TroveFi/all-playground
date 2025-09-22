import UniswapV2Connectors from 0xfef8e4c5c16ccda5
import DeFiActions from 0x4c2ff9dd03ab442f

// Script to get UniswapV2 quote on Flow EVM (read-only, no state change)
access(all) fun main(tokenInAddress: String, tokenOutAddress: String, amountIn: UFix64): {String: AnyStruct} {
    log("Getting UniswapV2 quote on Flow EVM")
    log("Token In Address: ".concat(tokenInAddress))
    log("Token Out Address: ".concat(tokenOutAddress))
    log("Amount In: ".concat(amountIn.toString()))
    
    let operationID = DeFiActions.createUniqueIdentifier()
    
    // Create UniswapV2 swapper for EVM pair
    let swapper = UniswapV2Connectors.UniswapV2Swapper(
        tokenInAddress: tokenInAddress,   // EVM_TOKEN_IN_ADDRESS placeholder
        tokenOutAddress: tokenOutAddress, // EVM_TOKEN_OUT_ADDRESS placeholder
        pairAddress: "0x1234567890abcdef1234567890abcdef12345678", // EVM_PAIR_ADDRESS placeholder
        uniqueID: operationID
    )
    
    // Get quote for swap amount
    let quote = swapper.quote(input: amountIn)
    
    let result: {String: AnyStruct} = {
        "tokenInAddress": tokenInAddress,
        "tokenOutAddress": tokenOutAddress,
        "amountIn": amountIn,
        "expectedAmountOut": quote.output,
        "priceImpact": quote.priceImpact,
        "exchangeRate": quote.output / amountIn,
        "timestamp": getCurrentBlock().timestamp,
        "source": "UniswapV2_FlowEVM"
    }
    
    log("Expected amount out: ".concat(quote.output.toString()))
    log("Price impact: ".concat(quote.priceImpact.toString()).concat("%"))
    
    return result
}