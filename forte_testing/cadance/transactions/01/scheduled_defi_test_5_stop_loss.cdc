// File: cadence/transactions/scheduled_defi_test_5_stop_loss.cdc
import "FungibleToken" from 0x9a0766d93b6608b7
import "FlowToken" from 0x7e60df042a9c0868
import "FungibleTokenConnectors" from 0x5a7b9cee9aaf4e4e
import "DeFiActions" from 0x4c2ff9dd03ab442f

// Simulates automated stop-loss execution - critical for scheduled DeFi risk management
transaction(stopLossThreshold: UFix64, emergencyExitAmount: UFix64) {
    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController) &Account) {
        log("=== Automated Stop-Loss Risk Management ===")
        log("Stop-loss threshold: ".concat(stopLossThreshold.toString()).concat(" FLOW"))
        log("Emergency exit amount: ".concat(emergencyExitAmount.toString()).concat(" FLOW"))
        
        // Create risk management operation ID
        let operationID = DeFiActions.createUniqueIdentifier()
        log("Risk management ID: ".concat(operationID.uuid.toString()))
        
        // Get current portfolio value
        let vaultRef = signer.storage.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)!
        let currentValue = vaultRef.balance
        log("Current portfolio value: ".concat(currentValue.toString()).concat(" FLOW"))
        
        // Check if stop-loss should trigger
        if currentValue <= stopLossThreshold {
            log("🚨 STOP-LOSS TRIGGERED! Portfolio below threshold")
            log("Executing emergency exit strategy...")
            
            // Create emergency withdrawal source
            let withdrawCap = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
                /storage/flowTokenVault
            )
            
            let emergencySource = FungibleTokenConnectors.VaultSource(
                min: 0.1,  // Keep minimal amount for final transactions
                withdrawVault: withdrawCap,
                uniqueID: operationID
            )
            
            let availableForExit = emergencySource.minimumAvailable()
            log("Available for emergency exit: ".concat(availableForExit.toString()))
            
            if availableForExit >= emergencyExitAmount {
                // Execute emergency exit
                let emergencyTokens <- emergencySource.withdrawAvailable(maxAmount: emergencyExitAmount)
                log("Emergency tokens withdrawn: ".concat(emergencyTokens.balance.toString()))
                
                // Create safe haven sink (in reality: convert to stablecoins, move to cold storage)
                let safeCap = getAccount(signer.address).capabilities.get<&{FungibleToken.Vault}>(
                    /public/flowTokenReceiver
                )
                
                let safeHavenSink = FungibleTokenConnectors.VaultSink(
                    max: nil,
                    depositVault: safeCap,
                    uniqueID: operationID
                )
                
                // Move to safety (simulate converting to stablecoins)
                log("Converting position to stable assets...")
                safeHavenSink.depositCapacity(from: &emergencyTokens as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
                
                // Clean up
                if emergencyTokens.balance > 0.0 {
                    vaultRef.deposit(from: <-emergencyTokens)
                } else {
                    destroy emergencyTokens
                }
                
                log("✅ Emergency exit completed successfully")
                log("Position moved to safe assets")
                
            } else {
                log("❌ Insufficient balance for full emergency exit")
                log("Partial exit would be executed with available funds")
            }
            
        } else {
            log("✅ Portfolio above stop-loss threshold - no action needed")
            let cushion = currentValue - stopLossThreshold
            log("Safety cushion: ".concat(cushion.toString()).concat(" FLOW"))
        }
        
        let finalValue = vaultRef.balance
        log("Final portfolio value: ".concat(finalValue.toString()))
        
        log("=== Risk Management Check Complete ===")
        log("Next check scheduled in 1 hour via Scheduled Transactions")
    }
}

// Run with:
// flow transactions send cadence/transactions/scheduled_defi_test_5_stop_loss.cdc --args-json '[{"type":"UFix64","value":"5.0"},{"type":"UFix64","value":"2.0"}]' --signer testnet --network testnet