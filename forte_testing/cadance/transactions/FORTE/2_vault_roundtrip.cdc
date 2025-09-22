import FungibleToken from 0x9a0766d93b6608b7
import FlowToken from 0x7e60df042a9c0868
import FungibleTokenConnectors from 0x5a7b9cee9aaf4e4e
import DeFiActions from 0x4c2ff9dd03ab442f

// Transaction to test FT Source/Sink round-trip with vault operations
transaction(amount: UFix64) {
    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController) &Account) {
        log("Starting FT Source/Sink smoke test")
        
        let vaultRef = signer.storage.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)!
        let initialBalance = vaultRef.balance
        
        log("Initial balance: ".concat(initialBalance.toString()))
        
        // Create unique identifier for tracking
        let operationID = DeFiActions.createUniqueIdentifier()
        
        // Create VaultSource
        let withdrawCap = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
            /storage/flowTokenVault
        )
        
        let vaultSource = FungibleTokenConnectors.VaultSource(
            min: 1.0,  // Keep minimum balance
            withdrawVault: withdrawCap,
            uniqueID: operationID
        )
        
        // Withdraw via source
        let tempVault <- vaultSource.withdrawAvailable(maxAmount: amount)
        log("Withdrawn amount: ".concat(tempVault.balance.toString()))
        
        // Create VaultSink
        let depositCap = getAccount(signer.address).capabilities.get<&{FungibleToken.Vault}>(
            /public/flowTokenReceiver
        )
        
        let vaultSink = FungibleTokenConnectors.VaultSink(
            max: nil,
            depositVault: depositCap,
            uniqueID: operationID
        )
        
        // Deposit via sink
        vaultSink.depositCapacity(from: &tempVault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
        
        // Handle any remaining tokens
        if tempVault.balance > 0.0 {
            vaultRef.deposit(from: <-tempVault)
        } else {
            destroy tempVault
        }
        
        let finalBalance = vaultRef.balance
        log("Final balance: ".concat(finalBalance.toString()))
        
        // Assert no net loss beyond minimal fees
        assert(finalBalance >= initialBalance - 0.001, message: "Unexpected balance loss")
        
        log("FT Source/Sink round-trip test completed successfully")
    }
}