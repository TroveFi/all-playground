// File: cadence/transactions/test_4_source_sink_composition.cdc
import "FungibleToken" from 0x9a0766d93b6608b7
import "FlowToken" from 0x7e60df042a9c0868
import "FungibleTokenConnectors" from 0x5a7b9cee9aaf4e4e
import "DeFiActions" from 0x4c2ff9dd03ab442f

transaction() {
    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController) &Account) {
        // Create unique identifier for operation tracing
        let operationID = DeFiActions.createUniqueIdentifier()
        
        log("=== Flow Actions Composition Test ===")
        log("Operation ID created: ".concat(operationID.uuid.toString()))
        
        // Create source
        let withdrawCap = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
            /storage/flowTokenVault
        )
        let source = FungibleTokenConnectors.VaultSource(
            min: 1.0,  // Keep 1 FLOW minimum
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
        
        // Verify same operation ID
        log("Source ID: ".concat(source.id()?.uuid?.toString() ?? "nil"))
        log("Sink ID: ".concat(sink.id()?.uuid?.toString() ?? "nil"))
        log("IDs match: ".concat((source.id()?.uuid == sink.id()?.uuid).toString()))
        
        // Get initial balance
        let vaultRef = signer.storage.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)!
        let initialBalance = vaultRef.balance
        log("Initial balance: ".concat(initialBalance.toString()))
        
        // Execute Source → Sink workflow atomically
        let tokens <- source.withdrawAvailable(maxAmount: 0.05)
        log("Tokens from source: ".concat(tokens.balance.toString()))
        
        sink.depositCapacity(from: &tokens as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
        log("After sink processing: ".concat(tokens.balance.toString()))
        
        // Clean up
        if tokens.balance > 0.0 {
            vaultRef.deposit(from: <-tokens)
            log("Returned remaining tokens to vault")
        } else {
            destroy tokens
            log("No tokens to return - all processed by sink")
        }
        
        let finalBalance = vaultRef.balance
        log("Final balance: ".concat(finalBalance.toString()))
        log("Net change: ".concat((finalBalance - initialBalance).toString()))
        log("=== Composition Test Complete ===")
    }
}

// Run with:
// flow transactions send cadence/transactions/test_4_source_sink_composition.cdc --signer testnet --network testnet