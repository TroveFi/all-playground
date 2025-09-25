// File: cadence/transactions/test_3_vault_sink.cdc
import "FungibleToken" from 0x9a0766d93b6608b7
import "FlowToken" from 0x7e60df042a9c0868
import "FungibleTokenConnectors" from 0x5a7b9cee9aaf4e4e

transaction() {
    prepare(signer: auth(BorrowValue) &Account) {
        // Get public deposit capability
        let depositCap = getAccount(signer.address).capabilities.get<&{FungibleToken.Vault}>(
            /public/flowTokenReceiver
        )
        
        // Create VaultSink with capacity limit
        let sink = FungibleTokenConnectors.VaultSink(
            max: 1000.0,  // Max capacity
            depositVault: depositCap,
            uniqueID: nil
        )
        
        log("=== VaultSink Test ===")
        log("Sink Type: ".concat(sink.getSinkType().identifier))
        
        // Check sink capacity
        let capacity = sink.minimumCapacity()
        log("Sink capacity: ".concat(capacity.toString()))
        
        // Test deposit (0.01 FLOW)
        let vaultRef = signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(from: /storage/flowTokenVault)!
        let balanceBefore = vaultRef.balance
        log("Balance before deposit: ".concat(balanceBefore.toString()))
        
        let tokens <- vaultRef.withdraw(amount: 0.01)
        log("Tokens to deposit: ".concat(tokens.balance.toString()))
        
        sink.depositCapacity(from: &tokens as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
        log("Tokens remaining after sink: ".concat(tokens.balance.toString()))
        
        // Return any remaining tokens
        vaultRef.deposit(from: <-tokens)
        
        let balanceAfter = vaultRef.balance
        log("Balance after: ".concat(balanceAfter.toString()))
        log("Net change: ".concat((balanceAfter - balanceBefore).toString()))
        log("=== Test Complete ===")
    }
}

// Run with:
// flow transactions send cadence/transactions/test_3_vault_sink.cdc --signer testnet --network testnet