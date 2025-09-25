// File: cadence/transactions/fixed_stop_loss_management.cdc
import FungibleToken from 0x9a0766d93b6608b7
import FlowToken from 0x7e60df042a9c0868
import FungibleTokenConnectors from 0x5a7b9cee9aaf4e4e
import DeFiActions from 0x4c2ff9dd03ab442f

transaction(stopLossThreshold: UFix64, emergencyExitPercentage: UFix64) {
    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController) &Account) {
        log("=== SCHEDULED: Stop-Loss Risk Management ===")
        log("Stop-loss threshold: ".concat(stopLossThreshold.toString()))
        log("Emergency exit percentage: ".concat(emergencyExitPercentage.toString()).concat("%"))
        
        let operationID = DeFiActions.createUniqueIdentifier()
        let vaultRef = signer.storage.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)!
        let currentPortfolioValue = vaultRef.balance
        
        log("Current portfolio value: ".concat(currentPortfolioValue.toString()))
        
        // Simulate historical high (would be stored onchain in real implementation)
        let portfolioHigh: UFix64 = 102000.0  // Previous high
        
        // Calculate drawdown safely (avoid underflow)
        var currentDrawdown: UFix64 = 0.0
        if portfolioHigh > currentPortfolioValue {
            let drawdownAmount = portfolioHigh - currentPortfolioValue
            currentDrawdown = (drawdownAmount / portfolioHigh) * 100.0
        }
        
        log("Portfolio high: ".concat(portfolioHigh.toString()))
        log("Current drawdown: ".concat(currentDrawdown.toString()).concat("%"))
        
        // Check if stop-loss should trigger
        let shouldTriggerStopLoss = currentPortfolioValue <= stopLossThreshold || currentDrawdown >= 20.0
        
        if shouldTriggerStopLoss {
            log("STOP-LOSS TRIGGERED!")
            log("Executing emergency risk management protocol...")
            
            let emergencyExitAmount = currentPortfolioValue * (emergencyExitPercentage / 100.0)
            log("Emergency exit amount: ".concat(emergencyExitAmount.toString()))
            
            if emergencyExitAmount > 1.0 {  // Minimum threshold for emergency exit
                // Create emergency exit components
                let withdrawCap = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
                    /storage/flowTokenVault
                )
                
                let emergencySource = FungibleTokenConnectors.VaultSource(
                    min: 0.5,  // Keep minimal for final transactions
                    withdrawVault: withdrawCap,
                    uniqueID: operationID
                )
                
                // Check if we can execute emergency exit
                let availableForExit = emergencySource.minimumAvailable()
                log("Available for emergency exit: ".concat(availableForExit.toString()))
                
                if availableForExit >= emergencyExitAmount {
                    // Execute emergency exit
                    let emergencyTokens <- emergencySource.withdrawAvailable(maxAmount: emergencyExitAmount)
                    log("Emergency tokens withdrawn: ".concat(emergencyTokens.balance.toString()))
                    
                    // Create safe haven sink (in production: convert to stablecoins)
                    let depositCap = getAccount(signer.address).capabilities.get<&{FungibleToken.Vault}>(
                        /public/flowTokenReceiver
                    )
                    
                    let safeHavenSink = FungibleTokenConnectors.VaultSink(
                        max: nil,
                        depositVault: depositCap,
                        uniqueID: operationID
                    )
                    
                    log("Converting to safe assets (simulated)...")
                    // In production: this would swap to USDC, move to cold storage, etc.
                    safeHavenSink.depositCapacity(from: &emergencyTokens as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
                    
                    if emergencyTokens.balance > 0.0 {
                        vaultRef.deposit(from: <-emergencyTokens)
                    } else {
                        destroy emergencyTokens
                    }
                    
                    log("Emergency exit completed - position secured")
                } else {
                    log("Insufficient funds for full emergency exit")
                    log("Would execute partial exit with available funds")
                }
                
            } else {
                log("Emergency exit amount too small to execute")
            }
            
        } else {
            // Calculate safety buffer safely (avoid underflow)
            if currentPortfolioValue >= stopLossThreshold {
                let safetyBuffer = currentPortfolioValue - stopLossThreshold
                log("Portfolio above stop-loss threshold")
                log("Safety buffer: ".concat(safetyBuffer.toString()).concat(" FLOW"))
            } else {
                log("Portfolio below threshold but drawdown acceptable")
            }
            log("Drawdown: ".concat(currentDrawdown.toString()).concat("% < 20% threshold"))
            log("No emergency action required")
        }
        
        let finalValue = vaultRef.balance
        log("Final portfolio value: ".concat(finalValue.toString()))
        log("=== NEXT SCHEDULED CHECK: 15 minutes ===")
    }
}