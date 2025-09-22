import IncrementFiStakingConnectors from 0x49bae091e5ea16b5
import IncrementFiPoolLiquidityConnectors from 0x49bae091e5ea16b5
import IncrementFiSwapConnectors from 0x49bae091e5ea16b5
import SwapConnectors from 0xaddd594cf410166a
import BandOracleConnectors from 0x1a9f5d18d096cd7a
import DeFiActionsUtils from 0x4c2ff9dd03ab442f
import DeFiActions from 0x4c2ff9dd03ab442f

// Transaction skeleton for guarded arbitrage with comprehensive safety checks
transaction(pid: UInt64, minOut: UFix64, uid: String) {
    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController) &Account) {
        log("Starting guarded arbitrage skeleton")
        log("Pool ID: ".concat(pid.toString()))
        log("Min output: ".concat(minOut.toString()))
        log("UID: ".concat(uid))
        
        // Create unique identifier for tracking
        let operationID = DeFiActionsUtils.UniqueIdentifier(uid)
        
        // === SAFETY CHECK 1: Band Oracle Price Sanity ===
        let oracle = BandOracleConnectors.BandPriceOracle()
        let priceQuote = oracle.getPrice(baseSymbol: "FLOW", quoteSymbol: "USD")
        
        log("Oracle price: $".concat(priceQuote.price.toString()))
        log("Price timestamp: ".concat(priceQuote.timestamp.toString()))
        log("Price confidence: ".concat(priceQuote.confidence.toString()))
        
        // Guard: Price must be recent and reasonable
        let currentTime = getCurrentBlock().timestamp
        let priceAge = currentTime - priceQuote.timestamp
        let maxPriceAge: UFix64 = 3600.0  // 1 hour
        
        if priceAge > maxPriceAge {
            log("GUARD FAILED: Oracle price too stale (".concat(priceAge.toString()).concat("s)")
            log("Exiting early - no state changes")
            return
        }
        
        // Guard: Price must be within reasonable bounds (off-by-decimals check)
        if priceQuote.price < 0.01 || priceQuote.price > 1000.0 {
            log("GUARD FAILED: Oracle price out of reasonable bounds")
            log("Exiting early - no state changes")
            return
        }
        
        log("✓ Oracle price sanity check passed")
        
        // === SAFETY CHECK 2: Pool Liquidity Check ===
        let stakingConnector = IncrementFiStakingConnectors.PoolStakeManager(
            poolID: pid,
            uniqueID: operationID
        )
        
        let poolInfo = stakingConnector.getPoolInfo()
        log("Pool TVL: ".concat(poolInfo.totalValueLocked.toString()))
        log("Pool APR: ".concat(poolInfo.apr.toString()).concat("%"))
        
        // Guard: Pool must have sufficient liquidity
        if poolInfo.totalValueLocked < 1000.0 {
            log("GUARD FAILED: Pool TVL too low for safe arbitrage")
            log("Exiting early - no state changes")
            return
        }
        
        log("✓ Pool liquidity check passed")
        
        // === SAFETY CHECK 3: Rewards Availability ===
        let rewardsSource = IncrementFiStakingConnectors.PoolRewardsSource(
            poolID: pid,
            staker: signer.address,
            uniqueID: operationID
        )
        
        let availableRewards = rewardsSource.getAvailable()
        log("Available rewards: ".concat(availableRewards.toString()))
        
        // Guard: Must have meaningful rewards to make arbitrage worthwhile
        if availableRewards < 0.01 {
            log("GUARD FAILED: Insufficient rewards for arbitrage")
            log("Exiting early - no state changes")
            return
        }
        
        log("✓ Rewards availability check passed")
        
        // === SAFETY CHECK 4: Slippage Protection ===
        let zapper = IncrementFiPoolLiquidityConnectors.Zapper(
            tokenInType: Type<@FlowToken.Vault>(),
            poolID: pid,
            uniqueID: operationID
        )
        
        let zapQuote = zapper.quote(input: availableRewards)
        log("Expected LP out: ".concat(zapQuote.output.toString()))
        log("Price impact: ".concat(zapQuote.priceImpact.toString()).concat("%"))
        
        // Guard: Price impact must be acceptable
        if zapQuote.priceImpact > 5.0 {  // Max 5% price impact
            log("GUARD FAILED: Price impact too high (".concat(zapQuote.priceImpact.toString()).concat("%)")
            log("Exiting early - no state changes")
            return
        }
        
        // Guard: Output must meet minimum threshold
        if zapQuote.output < minOut {
            log("GUARD FAILED: Expected output below minimum")
            log("Expected: ".concat(zapQuote.output.toString()).concat(", Required: ").concat(minOut.toString()))
            log("Exiting early - no state changes")
            return
        }
        
        log("✓ Slippage protection check passed")
        
        // === CONDITIONAL EXECUTION ===
        // All guards passed - proceed with arbitrage
        log("All guards passed - executing arbitrage workflow")
        
        // Create pool sink for restaking
        let poolSink = IncrementFiStakingConnectors.PoolSink(
            poolID: pid,
            staker: signer.address,
            uniqueID: operationID
        )
        
        // Wire the complete flow: PoolRewardsSource → Zapper → PoolSink
        let swapSource = SwapConnectors.SwapSource(
            source: rewardsSource,
            swapper: zapper,
            sink: poolSink,
            uniqueID: operationID
        )
        
        // Execute with final slippage check
        let finalMinOut = zapQuote.output * 0.98  // 2% slippage tolerance
        let result = swapSource.swap(input: availableRewards, minOutput: finalMinOut)
        
        log("Arbitrage executed successfully")
        log("Final output: ".concat(result.output.toString()))
        log("Profit vs expected: ".concat((result.output - zapQuote.output).toString()))
        
        // Emit completion event for monitoring
        emit GuardedArbitrageCompleted(
            uid: uid,
            poolID: pid,
            rewardsProcessed: availableRewards,
            lpTokensReceived: result.output,
            priceImpact: zapQuote.priceImpact
        )
        
        log("Guarded arbitrage skeleton completed successfully")
    }
}

// Event for monitoring arbitrage execution
access(all) event GuardedArbitrageCompleted(
    uid: String,
    poolID: UInt64,
    rewardsProcessed: UFix64,
    lpTokensReceived: UFix64,
    priceImpact: UFix64
)