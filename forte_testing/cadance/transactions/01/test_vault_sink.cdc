import "FungibleToken"
import "FlowToken"
import "FungibleTokenConnectors"

transaction(depositAmount: UFix64) {
    prepare(signer: auth(BorrowValue) &Account) {
        // Get public deposit capability
        let depositCap = getAccount(signer.address).capabilities.get<&{FungibleToken.Vault}>(
            /public/flowTokenReceiver
        )
        
        // Create VaultSink with capacity limit
        let sink = FungibleTokenConnectors.VaultSink(
            max: 1000.0,  // Max 1000 FLOW capacity
            depositVault: depositCap,
            uniqueID: nil
        )
        
        // Check capacity
        let capacity = sink.minimumCapacity()
        log("Sink capacity: ".concat(capacity.toString()))
        
        // Get tokens to deposit
        let vaultRef = signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(from: /storage/flowTokenVault)!
        let tokens <- vaultRef.withdraw(amount: depositAmount)
        
        // Test deposit via sink
        sink.depositCapacity(from: &tokens as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
        
        // Return any remaining tokens
        vaultRef.deposit(from: <-tokens)
    }
}