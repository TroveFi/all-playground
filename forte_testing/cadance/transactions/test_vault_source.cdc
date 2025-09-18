import "FungibleToken"
import "FlowToken"
import "FungibleTokenConnectors"

transaction(withdrawAmount: UFix64) {
    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController) &Account) {
        // Get Flow Token vault capability
        let withdrawCap = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
            /storage/flowTokenVault
        )
        
        // Create VaultSource with minimum balance protection
        let source = FungibleTokenConnectors.VaultSource(
            min: 10.0,  // Keep minimum 10 FLOW
            withdrawVault: withdrawCap,
            uniqueID: nil
        )
        
        // Test withdrawal
        let available = source.minimumAvailable()
        log("Available for withdrawal: ".concat(available.toString()))
        
        // Withdraw tokens
        let tokens <- source.withdrawAvailable(maxAmount: withdrawAmount)
        log("Actually withdrew: ".concat(tokens.balance.toString()))
        
        // Return tokens to vault (don't lose them!)
        let vaultRef = signer.storage.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)!
        vaultRef.deposit(from: <-tokens)
    }
}