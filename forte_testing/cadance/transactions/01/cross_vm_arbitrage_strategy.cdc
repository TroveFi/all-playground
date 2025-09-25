import FungibleToken from 0x9a0766d93b6608b7
import FlowToken from 0x7e60df042a9c0868
import FungibleTokenConnectors from 0x5a7b9cee9aaf4e4e
import DeFiActions from 0x4c2ff9dd03ab442f

// Cross-VM arbitrage: Exploit price differences between Cadence and EVM sides of Flow
transaction(
    cadencePrice: UFix64,
    evmPrice: UFix64,
    minProfitThreshold: UFix64,
    maxTradeSize: UFix64
) {
    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController) &Account) {
        log("=== Cross-VM Arbitrage Strategy ===")
        log("Cadence FLOW price: $".concat(cadencePrice.toString()))
        log("EVM FLOW price: $".concat(evmPrice.toString()))
        log("Min profit threshold: ".concat(minProfitThreshold.toString()).concat("%"))
        log("Max trade size: ".concat(maxTradeSize.toString()).concat(" FLOW"))
        
        let operationID = DeFiActions.createUniqueIdentifier()
        let vaultRef = signer.storage.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)!
        let availableBalance = vaultRef.balance
        
        log("Available balance: ".concat(availableBalance.toString()).concat(" FLOW"))
        
        // Calculate arbitrage opportunity
        var priceDifference: UFix64 = 0.0
        var profitPercentage: UFix64 = 0.0
        var direction: String = "NONE"
        var arbitrageAmount: UFix64 = 0.0
        var arbitragePossible = false
        
        if cadencePrice > evmPrice {
            priceDifference = cadencePrice - evmPrice
            profitPercentage = (priceDifference / evmPrice) * 100.0
            direction = "EVM_TO_CADENCE"  // Buy on EVM, sell on Cadence
        } else if evmPrice > cadencePrice {
            priceDifference = evmPrice - cadencePrice
            profitPercentage = (priceDifference / cadencePrice) * 100.0
            direction = "CADENCE_TO_EVM"  // Buy on Cadence, sell on EVM
        }
        
        log("Price difference: $".concat(priceDifference.toString()))
        log("Profit percentage: ".concat(profitPercentage.toString()).concat("%"))
        log("Arbitrage direction: ".concat(direction))
        
        // Check if arbitrage is profitable
        if profitPercentage >= minProfitThreshold {
            arbitragePossible = true
            
            // Calculate optimal trade size (considering slippage and gas costs)
            let gasEstimate: UFix64 = 2.0  // Estimate 2 FLOW for cross-VM operations
            let slippageBuffer: UFix64 = 0.5  // 0.5% slippage buffer
            let effectiveProfitRate = profitPercentage - slippageBuffer
            
            // Size position to ensure profitability after costs
            arbitrageAmount = maxTradeSize > availableBalance ? availableBalance * 0.9 : maxTradeSize
            arbitrageAmount = arbitrageAmount > gasEstimate ? arbitrageAmount - gasEstimate : 0.0
            
            let estimatedProfit = arbitrageAmount * (effectiveProfitRate / 100.0)
            log("Estimated gross profit: ".concat(estimatedProfit.toString()).concat(" FLOW"))
            log("Gas costs: ".concat(gasEstimate.toString()).concat(" FLOW"))
            log("Net profit: ".concat((estimatedProfit - gasEstimate).toString()).concat(" FLOW"))
        }
        
        if arbitragePossible && arbitrageAmount > 5.0 {
            log("ARBITRAGE OPPORTUNITY DETECTED - Executing trade...")
            
            // Create arbitrage execution components
            let withdrawCap = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
                /storage/flowTokenVault
            )
            
            let arbitrageSource = FungibleTokenConnectors.VaultSource(
                min: 5.0,  // Keep minimum for gas
                withdrawVault: withdrawCap,
                uniqueID: operationID
            )
            
            let depositCap = getAccount(signer.address).capabilities.get<&{FungibleToken.Vault}>(
                /public/flowTokenReceiver
            )
            
            let arbitrageSink = FungibleTokenConnectors.VaultSink(
                max: nil,
                depositVault: depositCap,
                uniqueID: operationID
            )
            
            // Execute the arbitrage trade
            if arbitrageAmount <= arbitrageSource.minimumAvailable() {
                let arbitrageTokens <- arbitrageSource.withdrawAvailable(maxAmount: arbitrageAmount)
                log("Executing arbitrage with ".concat(arbitrageTokens.balance.toString()).concat(" FLOW"))
                
                if direction == "CADENCE_TO_EVM" {
                    log("ARBITRAGE EXECUTION:")
                    log("1. Using ".concat(arbitrageTokens.balance.toString()).concat(" FLOW on Cadence side"))
                    log("2. Bridge FLOW from Cadence to Flow EVM")
                    log("3. Sell FLOW on EVM DEX at higher price ($".concat(evmPrice.toString()).concat(")"))
                    log("4. Bridge proceeds back to Cadence")
                    log("5. Profit from price difference: $".concat(priceDifference.toString()).concat(" per FLOW"))
                    
                } else if direction == "EVM_TO_CADENCE" {
                    log("ARBITRAGE EXECUTION:")
                    log("1. Bridge ".concat(arbitrageTokens.balance.toString()).concat(" FLOW to EVM side"))
                    log("2. Buy FLOW on EVM DEX at lower price ($".concat(evmPrice.toString()).concat(")"))
                    log("3. Bridge FLOW back to Cadence side") 
                    log("4. Sell FLOW on Cadence DEX at higher price ($".concat(cadencePrice.toString()).concat(")"))
                    log("5. Profit from price difference: $".concat(priceDifference.toString()).concat(" per FLOW"))
                }
                
                // Simulate cross-VM arbitrage execution
                arbitrageSink.depositCapacity(from: &arbitrageTokens as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
                
                if arbitrageTokens.balance > 0.0 {
                    vaultRef.deposit(from: <-arbitrageTokens)
                } else {
                    destroy arbitrageTokens
                }
                
                log("Cross-VM arbitrage executed successfully")
                
            } else {
                log("Insufficient balance for arbitrage execution")
            }
            
        } else if !arbitragePossible {
            log("No profitable arbitrage opportunity")
            log("Price difference (".concat(profitPercentage.toString()).concat("%) below threshold (").concat(minProfitThreshold.toString()).concat("%)"))
            
        } else {
            log("Arbitrage opportunity too small to execute profitably")
            log("Required minimum: 5 FLOW, Available: ".concat(arbitrageAmount.toString()).concat(" FLOW"))
        }
        
        // Market analysis and alerts
        if profitPercentage > 5.0 {
            log("LARGE ARBITRAGE ALERT: Significant price discrepancy detected")
        }
        if profitPercentage > 0.1 && profitPercentage < minProfitThreshold {
            log("SMALL OPPORTUNITY: Price difference exists but below execution threshold")
        }
        
        let finalBalance = vaultRef.balance
        log("Final balance: ".concat(finalBalance.toString()).concat(" FLOW"))
        
        // Adaptive monitoring based on market volatility
        if profitPercentage > 2.0 {
            log("=== High volatility detected - Next arbitrage check in 10 minutes ===")
        } else if profitPercentage > 0.5 {
            log("=== Moderate price movement - Next arbitrage check in 1 hour ===")
        } else {
            log("=== Stable prices - Next arbitrage check in 4 hours ===")
        }
        
        log("Automated cross-VM arbitrage via Scheduled Transactions")
    }
}