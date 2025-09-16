access(all) struct LiquidityCalculation {
    access(all) let token0Amount: UFix64
    access(all) let token1Amount: UFix64
    access(all) let minToken0Amount: UFix64
    access(all) let minToken1Amount: UFix64
    access(all) let estimatedLPTokens: UFix64
    access(all) let priceImpact: UFix64
    access(all) let slippageTolerance: UFix64
    
    init(
        token0Amount: UFix64,
        token1Amount: UFix64,
        minToken0Amount: UFix64,
        minToken1Amount: UFix64,
        estimatedLPTokens: UFix64,
        priceImpact: UFix64,
        slippageTolerance: UFix64
    ) {
        self.token0Amount = token0Amount
        self.token1Amount = token1Amount
        self.minToken0Amount = minToken0Amount
        self.minToken1Amount = minToken1Amount
        self.estimatedLPTokens = estimatedLPTokens
        self.priceImpact = priceImpact
        self.slippageTolerance = slippageTolerance
    }
}

access(all) fun main(
    token0AmountDesired: UFix64,
    token1AmountDesired: UFix64,
    slippageTolerance: UFix64
): LiquidityCalculation {
    
    let token0Amount = token0AmountDesired
    let token1Amount = token1AmountDesired
    
    // Calculate minimum amounts with slippage
    let minToken0 = token0Amount * (1.0 - slippageTolerance)
    let minToken1 = token1Amount * (1.0 - slippageTolerance)
    
    // Simple LP token estimate (arithmetic mean since we can't use square root)
    let estimatedLP = (token0Amount + token1Amount) / 2.0
    
    // Simple price impact estimate
    let priceImpact = slippageTolerance * 0.5
    
    return LiquidityCalculation(
        token0Amount: token0Amount,
        token1Amount: token1Amount,
        minToken0Amount: minToken0,
        minToken1Amount: minToken1,
        estimatedLPTokens: estimatedLP,
        priceImpact: priceImpact,
        slippageTolerance: slippageTolerance
    )
}