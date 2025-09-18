import "FlowToken"
import "FungibleToken"
import "IncrementFiPoolLiquidityConnectors"
import "stFlowToken"

transaction(inputAmount: UFix64) {
    prepare(signer: auth(BorrowValue) &Account) {
        // Create zapper for FLOW/stFLOW pair
        let zapper = IncrementFiPoolLiquidityConnectors.Zapper(
            token0Type: Type<@FlowToken.Vault>(),
            token1Type: Type<@stFlowToken.Vault>(),
            stableMode: false,  // Volatile pair
            uniqueID: nil
        )
        
        log("=== Testing Zapper ===")
        log("Input Type: ".concat(zapper.inType().identifier))
        log("Output Type: ".concat(zapper.outType().identifier))
        
        // Get quote for zapping
        let quote = zapper.quoteOut(forProvided: inputAmount, reverse: false)
        log("Quote for ".concat(inputAmount.toString()).concat(" FLOW: ").concat(quote.outAmount.toString()).concat(" LP tokens"))
        
        // Note: This will fail in testing without actual liquidity pools
        // but it demonstrates the interface
    }
}