// File: cadence/transactions/scheduled_defi_test_3_reward_claiming.cdc
import "FungibleToken" from 0x9a0766d93b6608b7
import "FlowToken" from 0x7e60df042a9c0868
import "FungibleTokenConnectors" from 0x5a7b9cee9aaf4e4e
import "SwapConnectors" from 0xaddd594cf410166a
import "DeFiActions" from 0x4c2ff9dd03ab442f

// Simulates automated reward claiming and compounding - perfect for scheduled execution
transaction() {
    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController) &Account) {
        log("=== Automated Reward Claiming & Compounding Strategy ===")
        
        // Create operation ID for this compounding cycle
        let operationID = DeFiActions.createUniqueIdentifier()
        log("Compounding cycle ID: ".concat(operationID.uuid.toString()))
        
        // Step 1: Simulate claiming rewards (in real scenario, this would be from staking pools)
        let vaultRef = signer.storage.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)!
        let initialBalance = vaultRef.balance
        log("Current balance: ".concat(initialBalance.toString()))
        
        // Simulate getting "rewards" - in reality this would come from IncrementFi staking
        let rewardAmount: UFix64 = 0.5  // Simulated reward amount
        log("Simulated rewards available: ".concat(rewardAmount.toString()))
        
        if initialBalance >= rewardAmount {
            // Step 2: Create source for reward tokens
            let withdrawCap = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
                /storage/flowTokenVault
            )
            
            let rewardSource = FungibleTokenConnectors.VaultSource(
                min: 2.0,  // Keep minimum for gas
                withdrawVault: withdrawCap,
                uniqueID: operationID
            )
            
            // Step 3: Claim rewards
            let claimedRewards <- rewardSource.withdrawAvailable(maxAmount: rewardAmount)
            log("Rewards claimed: ".concat(claimedRewards.balance.toString()))
            
            // Step 4: Auto-compound - deposit back for more rewards
            let depositCap = getAccount(signer.address).capabilities.get<&{FungibleToken.Vault}>(
                /public/flowTokenReceiver
            )
            
            let compoundingSink = FungibleTokenConnectors.VaultSink(
                max: nil,  // No limit for compounding
                depositVault: depositCap,
                uniqueID: operationID
            )
            
            // Simulate converting rewards to LP tokens (in real scenario)
            log("Converting rewards to LP tokens for compounding...")
            
            // Deposit for compounding
            compoundingSink.depositCapacity(from: &claimedRewards as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
            
            // Clean up
            if claimedRewards.balance > 0.0 {
                vaultRef.deposit(from: <-claimedRewards)
                log("Returned excess to vault")
            } else {
                destroy claimedRewards
                log("All rewards compounded successfully")
            }
            
            log("✅ Automatic compounding completed")
            log("This strategy would run every 24 hours via Scheduled Transactions")
            
        } else {
            log("❌ No rewards to claim at this time")
        }
        
        let finalBalance = vaultRef.balance
        log("Final balance: ".concat(finalBalance.toString()))
        log("=== Reward Compounding Complete ===")
    }
}

// Run with:
// flow transactions send cadence/transactions/scheduled_defi_test_3_reward_claiming.cdc --signer testnet --network testnet