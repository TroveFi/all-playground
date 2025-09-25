// File: cadence/transactions/scheduled_defi_test_4_portfolio_rebalancing.cdc
import "FungibleToken" from 0x9a0766d93b6608b7
import "FlowToken" from 0x7e60df042a9c0868
import "FungibleTokenConnectors" from 0x5a7b9cee9aaf4e4e
import "DeFiActions" from 0x4c2ff9dd03ab442f

// Simulates automated portfolio rebalancing - ideal for scheduled execution
transaction(targetAllocation: UFix64) {
    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController) &Account) {
        log("=== Automated DeFi Portfolio Rebalancing ===")
        log("Target allocation: ".concat(targetAllocation.toString()).concat(" FLOW"))
        
        // Create rebalancing operation ID
        let operationID = DeFiActions.createUniqueIdentifier()
        log("Rebalancing operation ID: ".concat(operationID.uuid.toString()))
        
        // Get current portfolio balance
        let vaultRef = signer.storage.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)!
        let currentBalance = vaultRef.balance
        log("Current portfolio balance: ".concat(currentBalance.toString()))
        
        // Calculate rebalancing needs
        let difference = targetAllocation - currentBalance
        log("Rebalancing difference: ".concat(difference.toString()))
        
        if difference > 0.0 && difference <= 2.0 {
            log("📈 Portfolio needs more allocation (+".concat(difference.toString()).concat(")"))
            
            // Simulate adding to position (in reality: claim rewards, sell other assets, etc.)
            let withdrawCap = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
                /storage/flowTokenVault
            )
            
            let rebalanceSource = FungibleTokenConnectors.VaultSource(
                min: 3.0,  // Keep minimum for operations
                withdrawVault: withdrawCap,
                uniqueID: operationID
            )
            
            // Simulate getting funds for rebalancing
            if rebalanceSource.minimumAvailable() >= difference {
                let rebalanceTokens <- rebalanceSource.withdrawAvailable(maxAmount: difference)
                log("Tokens allocated for rebalancing: ".concat(rebalanceTokens.balance.toString()))
                
                // Simulate rebalancing action (swap, stake, provide liquidity, etc.)
                let depositCap = getAccount(signer.address).capabilities.get<&{FungibleToken.Vault}>(
                    /public/flowTokenReceiver
                )
                
                let rebalanceSink = FungibleTokenConnectors.VaultSink(
                    max: nil,
                    depositVault: depositCap,
                    uniqueID: operationID
                )
                
                rebalanceSink.depositCapacity(from: &rebalanceTokens as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
                
                // Clean up
                if rebalanceTokens.balance > 0.0 {
                    vaultRef.deposit(from: <-rebalanceTokens)
                } else {
                    destroy rebalanceTokens
                }
                
                log("✅ Portfolio rebalanced successfully")
            } else {
                log("❌ Insufficient funds for rebalancing")
            }
            
        } else if difference < 0.0 && difference >= -2.0 {
            log("📉 Portfolio is over-allocated (".concat((-difference).toString()).concat(" excess)"))
            log("Would reduce position by selling or unstaking assets")
            log("✅ Rebalancing simulation complete")
            
        } else {
            log("✅ Portfolio is already balanced within tolerance")
        }
        
        let newBalance = vaultRef.balance
        log("New portfolio balance: ".concat(newBalance.toString()))
        log("Rebalancing delta: ".concat((newBalance - currentBalance).toString()))
        
        log("=== Automated Rebalancing Complete ===")
        log("Next rebalancing scheduled in 1 week via Scheduled Transactions")
    }
}

// Run with:
// flow transactions send cadence/transactions/scheduled_defi_test_4_portfolio_rebalancing.cdc --args-json '[{"type":"UFix64","value":"10.0"}]' --signer testnet --network testnet