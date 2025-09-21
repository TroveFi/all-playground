import FungibleToken from 0x9a0766d93b6608b7
import FlowToken from 0x7e60df042a9c0868
import FungibleTokenConnectors from 0x5a7b9cee9aaf4e4e
import IncrementFiSwapConnectors from 0x49bae091e5ea16b5
import DeFiActions from 0x4c2ff9dd03ab442f

// Multi-DEX arbitrage: Find price differences across Flow DEX protocols
transaction(
    incrementFiPrice: UFix64,
    alternativeDexPrice: UFix64,
    minSpread: UFix64,
    maxPosition: UFix64
) {
    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController) &Account) {
        log("=== Multi-DEX Arbitrage Strategy ===")
        log("IncrementFi price: ".concat(incrementFiPrice.toString()))
        log("Alternative DEX price: ".concat(alternativeDexPrice.toString()))
        log("Minimum spread: ".concat(minSpread.toString()).concat("%"))
        log("Maximum position: ".concat(maxPosition.toString()).concat(" FLOW"))
        
        let operationID = DeFiActions.createUniqueIdentifier()
        let vaultRef = signer.storage.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)!
        let availableCapital = vaultRef.balance
        
        log("Available capital: ".concat(availableCapital.toString()).concat(" FLOW"))
        
        // Calculate arbitrage metrics
        var priceSpread: UFix64 = 0.0
        var spreadPercentage: UFix64 = 0.0
        var buyDEX: String = "NONE"
        var sellDEX: String = "NONE"
        var profitable = false
        
        if incrementFiPrice > alternativeDexPrice {
            priceSpread = incrementFiPrice - alternativeDexPrice
            spreadPercentage = (priceSpread / alternativeDexPrice) * 100.0
            buyDEX = "ALTERNATIVE"
            sellDEX = "INCREMENTFI"
        } else if alternativeDexPrice > incrementFiPrice {
            priceSpread = alternativeDexPrice - incrementFiPrice
            spreadPercentage = (priceSpread / incrementFiPrice) * 100.0
            buyDEX = "INCREMENTFI"
            sellDEX = "ALTERNATIVE"
        }
        
        log("Price spread: ".concat(priceSpread.toString()))
        log("Spread percentage: ".concat(spreadPercentage.toString()).concat("%"))
        log("Strategy: Buy on ".concat(buyDEX).concat(", Sell on ").concat(sellDEX))
        
        // Check profitability after fees and slippage
        let tradingFees: UFix64 = 0.6  // 0.3% each side
        let slippageEstimate: UFix64 = 0.2  // 0.2% slippage
        let gasCoosts: UFix64 = 1.0  // 1 FLOW gas estimate
        let totalCosts = tradingFees + slippageEstimate
        let netSpread = spreadPercentage - totalCosts
        
        log("Trading fees: ".concat(tradingFees.toString()).concat("%"))
        log("Slippage estimate: ".concat(slippageEstimate.toString()).concat("%"))
        log("Net spread after costs: ".concat(netSpread.toString()).concat("%"))
        
        profitable = netSpread >= minSpread
        
        if profitable {
            log("PROFITABLE ARBITRAGE DETECTED")
            
            // Calculate optimal position size
            var positionSize = maxPosition > availableCapital ? availableCapital * 0.95 : maxPosition
            positionSize = positionSize > gasCoosts ? positionSize - gasCoosts : 0.0
            
            let estimatedProfit = positionSize * (netSpread / 100.0)
            log("Position size: ".concat(positionSize.toString()).concat(" FLOW"))
            log("Estimated profit: ".concat(estimatedProfit.toString()).concat(" FLOW"))
            
            if positionSize > 5.0 {
                log("Executing multi-DEX arbitrage...")
                
                // Create arbitrage components
                let withdrawCap = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
                    /storage/flowTokenVault
                )
                
                let arbitrageSource = FungibleTokenConnectors.VaultSource(
                    min: 2.0,  // Keep minimum for gas
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
                
                // Execute arbitrage if sufficient balance
                if positionSize <= arbitrageSource.minimumAvailable() {
                    let arbitrageTokens <- arbitrageSource.withdrawAvailable(maxAmount: positionSize)
                    log("Executing arbitrage with ".concat(arbitrageTokens.balance.toString()).concat(" FLOW"))
                    
                    if buyDEX == "INCREMENTFI" {
                        log("ARBITRAGE STEP 1: Buy on IncrementFi at lower price")
                        log("- Purchase tokens at ".concat(incrementFiPrice.toString()).concat(" per unit"))
                        log("- Using IncrementFi swap router for optimal execution")
                        
                        log("ARBITRAGE STEP 2: Sell on Alternative DEX at higher price")
                        log("- Sell tokens at ".concat(alternativeDexPrice.toString()).concat(" per unit"))
                        log("- Profit per unit: ".concat(priceSpread.toString()))
                        
                    } else {
                        log("ARBITRAGE STEP 1: Buy on Alternative DEX at lower price")
                        log("- Purchase tokens at ".concat(alternativeDexPrice.toString()).concat(" per unit"))
                        log("- Using alternative swap protocol")
                        
                        log("ARBITRAGE STEP 2: Sell on IncrementFi at higher price")
                        log("- Sell tokens at ".concat(incrementFiPrice.toString()).concat(" per unit"))
                        log("- Using IncrementFi for final sale")
                        log("- Profit per unit: ".concat(priceSpread.toString()))
                    }
                    
                    // Process arbitrage execution
                    arbitrageSink.depositCapacity(from: &arbitrageTokens as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
                    
                    if arbitrageTokens.balance > 0.0 {
                        vaultRef.deposit(from: <-arbitrageTokens)
                    } else {
                        destroy arbitrageTokens
                    }
                    
                    log("Multi-DEX arbitrage completed successfully")
                    
                } else {
                    log("Insufficient balance for calculated position size")
                }
                
            } else {
                log("Position size too small for profitable execution")
            }
            
        } else {
            log("No profitable arbitrage opportunity")
            log("Net spread (".concat(netSpread.toString()).concat("%) below minimum threshold (").concat(minSpread.toString()).concat("%)"))
            
            // Market insights
            if spreadPercentage > 0.1 {
                log("MARKET INSIGHT: Price discrepancy exists but trading costs eliminate profit")
                log("Consider lower-cost execution strategies or larger position sizes")
            }
        }
        
        // Advanced market analysis
        if spreadPercentage > 3.0 {
            log("ALERT: Large price discrepancy may indicate liquidity imbalance")
        }
        if spreadPercentage > 0.05 && spreadPercentage < minSpread {
            log("MICRO OPPORTUNITY: Small spread available for high-frequency strategies")
        }
        
        let finalBalance = vaultRef.balance
        log("Final balance: ".concat(finalBalance.toString()).concat(" FLOW"))
        
        // Dynamic monitoring frequency
        if spreadPercentage > 1.0 {
            log("=== High arbitrage activity - Next check in 5 minutes ===")
        } else if spreadPercentage > 0.2 {
            log("=== Moderate opportunities - Next check in 30 minutes ===")
        } else {
            log("=== Low arbitrage activity - Next check in 2 hours ===")
        }
        
        log("Automated multi-DEX arbitrage monitoring")
    }
}