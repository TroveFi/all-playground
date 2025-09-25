// File: cadence/transactions/test_2_vault_source.cdc
import "FungibleToken" from 0x9a0766d93b6608b7
import "FlowToken" from 0x7e60df042a9c0868
import "FungibleTokenConnectors" from 0x5a7b9cee9aaf4e4e

transaction(withdrawAmount: UFix64) {
    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController) &Account) {
        // Create vault capability
        let withdrawCap = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
            /storage/flowTokenVault
        )
        
        // Create VaultSource with minimum balance protection
        let source = FungibleTokenConnectors.VaultSource(
            min: 1.0,  // Keep minimum 1 FLOW
            withdrawVault: withdrawCap,
            uniqueID: nil
        )
        
        log("=== VaultSource Test ===")
        log("Source Type: ".concat(source.getSourceType().identifier))
        
        // Test source functionality  
        let available = source.minimumAvailable()
        log("Available for withdrawal: ".concat(available.toString()))
        
        if available >= withdrawAmount {
            let tokens <- source.withdrawAvailable(maxAmount: withdrawAmount)
            log("Successfully withdrew: ".concat(tokens.balance.toString()))
            
            // Return tokens (don't lose them!)
            let vaultRef = signer.storage.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)!
            vaultRef.deposit(from: <-tokens)
            log("Tokens returned to vault")
        } else {
            log("Insufficient balance for withdrawal")
            log("Requested: ".concat(withdrawAmount.toString()))
            log("Available: ".concat(available.toString()))
        }
        
        log("=== Test Complete ===")
    }
}

// Run with:
// flow transactions send cadence/transactions/test_2_vault_source.cdc --arg UFix64:0.1 --signer testnet --network testnet