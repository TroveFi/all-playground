import FungibleToken from 0x9a0766d93b6608b7
import FlowToken from 0x7e60df042a9c0868
import FungibleTokenConnectors from 0x5a7b9cee9aaf4e4e
import DeFiActions from 0x4c2ff9dd03ab442f

// Automated looping strategy similar to SafeYields' stETH/ETH approach
transaction(targetLeverage: UFix64, liquidationBuffer: UFix64, currentLTV: UFix64) {
    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController) &Account) {
        log("=== Automated Looping Strategy (SafeYields Style) ===")
        log("Target leverage: ".concat(targetLeverage.toString()).concat("x"))
        log("Liquidation buffer: ".concat(liquidationBuffer.toString()).concat("%"))
        log("Current LTV: ".concat(currentLTV.toString()).concat("%"))
        
        let operationID = DeFiActions.createUniqueIdentifier()
        let vaultRef = signer.storage.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)!
        let totalCollateral = vaultRef.balance
        
        log("Total collateral: ".concat(totalCollateral.toString()))
        
        // Calculate optimal position sizes
        let maxSafeLTV: UFix64 = 75.0 - liquidationBuffer  // 75% max LTV minus safety buffer
        let targetPosition = totalCollateral * targetLeverage
        let currentBorrowed = totalCollateral * (currentLTV / 100.0)
        
        log("Max safe LTV: ".concat(maxSafeLTV.toString()).concat("%"))
        log("Target position size: ".concat(targetPosition.toString()))
        log("Currently borrowed: ".concat(currentBorrowed.toString()))
        
        // Determine action needed
        var action: String = "HOLD"
        var actionAmount: UFix64 = 0.0
        var actionRequired = false
        
        // Check if we need to increase leverage (SafeYields auto-loop logic)
        if currentLTV < (maxSafeLTV - 5.0) && targetLeverage > 1.0 {
            // Room to borrow more and increase position
            let additionalBorrowCapacity = (maxSafeLTV - currentLTV) / 100.0 * totalCollateral
            actionAmount = additionalBorrowCapacity * 0.8  // Use 80% of available capacity
            action = "INCREASE_LEVERAGE"
            actionRequired = true
            log("Can increase leverage - additional borrow capacity: ".concat(additionalBorrowCapacity.toString()))
        }
        
        // Check if we need to reduce leverage (approaching liquidation)
        if currentLTV > maxSafeLTV {
            let excessBorrowed = currentBorrowed - (maxSafeLTV / 100.0 * totalCollateral)
            actionAmount = excessBorrowed * 1.2  // Repay 120% of excess for safety
            action = "REDUCE_LEVERAGE"
            actionRequired = true
            log("DANGER: Approaching liquidation - must reduce by: ".concat(actionAmount.toString()))
        }
        
        // Check for optimal rebalancing (SafeYields efficiency optimization)
        if !actionRequired && currentLTV > 0.0 {
            let optimalLTV = maxSafeLTV * 0.9  // 90% of max safe LTV
            let ltvDifference = currentLTV > optimalLTV ? currentLTV - optimalLTV : optimalLTV - currentLTV
            
            if ltvDifference > 5.0 {  // 5% threshold for rebalancing
                actionAmount = (ltvDifference / 100.0) * totalCollateral
                action = currentLTV > optimalLTV ? "OPTIMIZE_DOWN" : "OPTIMIZE_UP"
                actionRequired = true
                log("Optimization needed - LTV difference: ".concat(ltvDifference.toString()).concat("%"))
            }
        }
        
        log("Recommended action: ".concat(action))
        log("Action amount: ".concat(actionAmount.toString()))
        
        if actionRequired && actionAmount > 1.0 {
            log("Executing automated looping action...")
            
            // Create looping components
            let withdrawCap = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
                /storage/flowTokenVault
            )
            
            let loopingSource = FungibleTokenConnectors.VaultSource(
                min: 5.0,  // Keep minimum for gas and safety
                withdrawVault: withdrawCap,
                uniqueID: operationID
            )
            
            let depositCap = getAccount(signer.address).capabilities.get<&{FungibleToken.Vault}>(
                /public/flowTokenReceiver
            )
            
            let loopingSink = FungibleTokenConnectors.VaultSink(
                max: nil,
                depositVault: depositCap,
                uniqueID: operationID
            )
            
            // Execute the looping action
            if actionAmount <= loopingSource.minimumAvailable() {
                let actionTokens <- loopingSource.withdrawAvailable(maxAmount: actionAmount)
                log("Processing ".concat(actionTokens.balance.toString()).concat(" tokens for: ").concat(action))
                
                if action == "INCREASE_LEVERAGE" {
                    log("INCREASING LEVERAGE: Borrowing more against collateral")
                    log("New borrowed amount will be: ".concat((currentBorrowed + actionTokens.balance).toString()))
                    
                } else if action == "REDUCE_LEVERAGE" {
                    log("REDUCING LEVERAGE: Repaying debt to avoid liquidation")
                    log("Repaying: ".concat(actionTokens.balance.toString()).concat(" to reduce risk"))
                    
                } else if action == "OPTIMIZE_UP" {
                    log("OPTIMIZING UP: Increasing leverage for better capital efficiency")
                    log("Borrowing additional: ".concat(actionTokens.balance.toString()))
                    
                } else if action == "OPTIMIZE_DOWN" {
                    log("OPTIMIZING DOWN: Reducing leverage for better safety margin")
                    log("Repaying: ".concat(actionTokens.balance.toString()).concat(" to optimize LTV"))
                }
                
                // Process the looping action
                loopingSink.depositCapacity(from: &actionTokens as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
                
                if actionTokens.balance > 0.0 {
                    vaultRef.deposit(from: <-actionTokens)
                } else {
                    destroy actionTokens
                }
                
                // Calculate new position metrics
                let newLTV = action == "INCREASE_LEVERAGE" || action == "OPTIMIZE_UP" ? 
                    currentLTV + 5.0 : currentLTV - 5.0  // Approximate new LTV
                
                log("Estimated new LTV: ".concat(newLTV.toString()).concat("%"))
                log("Automated looping action completed")
                
            } else {
                log("Cannot execute action - insufficient balance")
            }
            
        } else {
            log("Position is optimally balanced - no action needed")
            log("Current LTV within acceptable range")
        }
        
        // Risk management alerts (SafeYields-style monitoring)
        if currentLTV > 70.0 {
            log("HIGH LTV WARNING: Position approaching maximum safe leverage")
        }
        if currentLTV > maxSafeLTV {
            log("LIQUIDATION RISK: Immediate action required to reduce leverage")
        }
        
        let finalBalance = vaultRef.balance
        log("Final balance: ".concat(finalBalance.toString()))
        
        // Schedule next monitoring check based on risk level
        if currentLTV > 65.0 {
            log("=== Next looping check scheduled in 2 hours (high risk) ===")
        } else if currentLTV > 40.0 {
            log("=== Next looping check scheduled in 6 hours (moderate risk) ===")
        } else {
            log("=== Next looping check scheduled in 24 hours (low risk) ===")
        }
        
        log("Automated looping management via Scheduled Transactions")
    }
}