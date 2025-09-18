import "FungibleToken"
import "FlowToken"
import "FungibleTokenConnectors"
import "DeFiActions"

transaction() {
    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController) &Account) {
        // Create unique identifier for tracing
        let operationID = DeFiActions.createUniqueIdentifier()
        
        // Create source
        let withdrawCap = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
            /storage/flowTokenVault
        )
        let source = FungibleTokenConnectors.VaultSource(
            min: 50.0,
            withdrawVault: withdrawCap,
            uniqueID: operationID
        )
        
        // Create sink
        let depositCap = getAccount(signer.address).capabilities.get<&{FungibleToken.Vault}>(
            /public/flowTokenReceiver
        )
        let sink = FungibleTokenConnectors.VaultSink(
            max: nil,  // No limit
            depositVault: depositCap,
            uniqueID: operationID
        )
        
        // Execute Source → Sink workflow
        log("=== Starting Source → Sink Test ===")
        log("Source ID: ".concat(source.id()?.uuid?.toString() ?? "nil"))
        log("Sink ID: ".concat(sink.id()?.uuid?.toString() ?? "nil"))
        
        // Withdraw from source
        let tokens <- source.withdrawAvailable(maxAmount: 10.0)
        log("Tokens withdrawn: ".concat(tokens.balance.toString()))
        
        // Deposit to sink
        sink.depositCapacity(from: &tokens as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
        log("Tokens remaining after sink: ".concat(tokens.balance.toString()))
        
        // Clean up any remaining tokens
        if tokens.balance > 0.0 {
            let vaultRef = signer.storage.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)!
            vaultRef.deposit(from: <-tokens)
        } else {
            destroy tokens
        }
        
        log("=== Source → Sink Test Complete ===")
    }
}