// File: cadence/transactions/scheduled_compound_rewards.cdc
import FungibleToken from 0x9a0766d93b6608b7
import FlowToken from 0x7e60df042a9c0868
import FungibleTokenConnectors from 0x5a7b9cee9aaf4e4e
import DeFiActions from 0x4c2ff9dd03ab442f

// This transaction simulates what would run automatically every 24 hours via Scheduled Transactions
transaction(rewardAmount: UFix64) {
    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController) &Account) {
        log("=== SCHEDULED: Daily Reward Compounding ===")
        log("Simulated reward amount: ".concat(rewardAmount.toString()))
        
        let operationID = DeFiActions.createUniqueIdentifier()
        let vaultRef = signer.storage.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)!
        let currentBalance = vaultRef.balance
        
        log("Current portfolio balance: ".concat(currentBalance.toString()))
        
        if currentBalance >= rewardAmount + 1.0 {
            // Step 1: Simulate claiming rewards (VaultSource)
            let withdrawCap = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
                /storage/flowTokenVault
            )
            
            let rewardsSource = FungibleTokenConnectors.VaultSource(
                min: 1.0,  // Keep gas money
                withdrawVault: withdrawCap,
                uniqueID: operationID
            )
            
            // Claim simulated rewards
            let claimedRewards <- rewardsSource.withdrawAvailable(maxAmount: rewardAmount)
            log("Rewards claimed: ".concat(claimedRewards.balance.toString()))
            
            // Step 2: Auto-compound rewards (VaultSink)  
            let depositCap = getAccount(signer.address).capabilities.get<&{FungibleToken.Vault}>(
                /public/flowTokenReceiver
            )
            
            let compoundingSink = FungibleTokenConnectors.VaultSink(
                max: nil,
                depositVault: depositCap,
                uniqueID: operationID
            )
            
            log("Auto-compounding rewards...")
            compoundingSink.depositCapacity(from: &claimedRewards as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
            
            // Clean up
            if claimedRewards.balance > 0.0 {
                vaultRef.deposit(from: <-claimedRewards)
            } else {
                destroy claimedRewards
            }
            
            let newBalance = vaultRef.balance
            let compoundedAmount = newBalance - currentBalance
            
            log("Compounding complete!")
            log("Amount compounded: ".concat(compoundedAmount.toString()))
            log("New balance: ".concat(newBalance.toString()))
            
        } else {
            log("Insufficient balance for compounding")
        }
        
        log("=== NEXT SCHEDULED EXECUTION: 24 hours ===")
        log("This would run automatically without manual intervention")
    }
}