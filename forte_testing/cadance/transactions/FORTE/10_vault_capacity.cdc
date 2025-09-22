import FungibleToken from 0x9a0766d93b6608b7
import FlowToken from 0x7e60df042a9c0868
import FungibleTokenConnectors from 0x5a7b9cee9aaf4e4e
import DeFiActions from 0x4c2ff9dd03ab442f

// Transaction to test FT Vault capacity and minimum balance safety checks
transaction(targetWithdraw: UFix64, minRemaining: UFix64) {
    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController) &Account) {
        pre {
            targetWithdraw > 0.0: "Target withdraw must be positive"
            minRemaining > 0.0: "Minimum remaining must be positive"
        }
        
        log("Starting FT Vault capacity safety test")
        log("Target withdraw: ".concat(targetWithdraw.toString()))
        log("Minimum remaining: ".concat(minRemaining.toString()))
        
        let vaultRef = signer.storage.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)!
        let initialBalance = vaultRef.balance
        
        log("Initial balance: ".concat(initialBalance.toString()))
        
        let operationID = DeFiActions.createUniqueIdentifier()
        
        // Create VaultSource with minimum balance protection
        let withdrawCap = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
            /storage/flowTokenVault
        )
        
        let vaultSource = FungibleTokenConnectors.VaultSource(
            min: minRemaining,  // Enforce minimum remaining balance
            withdrawVault: withdrawCap,
            uniqueID: operationID
        )
        
        // Check available capacity (respecting minimum)
        let available = vaultSource.minimumAvailable()
        log("Available for withdrawal: ".concat(available.toString()))
        
        // Calculate safe withdrawal amount
        let safeAmount = targetWithdraw < available ? targetWithdraw : available
        log("Safe withdrawal amount: ".concat(safeAmount.toString()))
        
        if safeAmount > 0.0 {
            // Withdraw respecting capacity limits
            let withdrawnVault <- vaultSource.withdrawAvailable(maxAmount: safeAmount)
            log("Actually withdrawn: ".concat(withdrawnVault.balance.toString()))
            
            let afterWithdrawBalance = vaultRef.balance
            log("Balance after withdraw: ".concat(afterWithdrawBalance.toString()))
            
            // Verify minimum balance respected
            assert(afterWithdrawBalance >= minRemaining, message: "Minimum balance violated")
            
            // Create sink and deposit back
            let depositCap = getAccount(signer.address).capabilities.get<&{FungibleToken.Vault}>(
                /public/flowTokenReceiver
            )
            
            let vaultSink = FungibleTokenConnectors.VaultSink(
                max: nil,
                depositVault: depositCap,
                uniqueID: operationID
            )
            
            vaultSink.depositCapacity(from: &withdrawnVault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
            
            // Handle any remaining tokens
            if withdrawnVault.balance > 0.0 {
                vaultRef.deposit(from: <-withdrawnVault)
            } else {
                destroy withdrawnVault
            }
            
            let finalBalance = vaultRef.balance
            log("Final balance: ".concat(finalBalance.toString()))
            
            post {
                finalBalance >= minRemaining: "Final balance must respect minimum"
                finalBalance >= initialBalance - 0.001: "No unexpected loss"
            }
            
        } else {
            log("No funds available for withdrawal while respecting minimum balance")
        }
        
        log("FT Vault capacity safety test completed")
    }
}