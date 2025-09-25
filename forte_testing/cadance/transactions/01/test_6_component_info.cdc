// File: cadence/transactions/test_6_component_info.cdc
import "FungibleToken" from 0x9a0766d93b6608b7
import "FlowToken" from 0x7e60df042a9c0868
import "FungibleTokenConnectors" from 0x5a7b9cee9aaf4e4e
import "DeFiActions" from 0x4c2ff9dd03ab442f

transaction() {
    prepare(signer: auth(IssueStorageCapabilityController) &Account) {
        log("=== Component Info Test ===")
        
        // Create unique identifier
        let uniqueID = DeFiActions.createUniqueIdentifier()
        log("Created unique ID: ".concat(uniqueID.uuid.toString()))
        
        // Create vault capability
        let withdrawCap = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
            /storage/flowTokenVault
        )
        
        // Create VaultSource
        let source = FungibleTokenConnectors.VaultSource(
            min: 0.5,
            withdrawVault: withdrawCap,
            uniqueID: uniqueID
        )
        
        // Test component info
        let info = source.getComponentInfo()
        log("Component Name: ".concat(info.name))
        log("Component Description: ".concat(info.description))
        log("Component Version: ".concat(info.version))
        
        // Test source-specific info
        log("Source Type: ".concat(source.getSourceType().identifier))
        log("Available Tokens: ".concat(source.minimumAvailable().toString()))
        
        // Test ID traceability
        let sourceID = source.id()
        if let id = sourceID {
            log("Source UUID: ".concat(id.uuid.toString()))
            log("ID matches created: ".concat((id.uuid == uniqueID.uuid).toString()))
        } else {
            log("No ID assigned to source")
        }
        
        log("=== Component Info Test Complete ===")
    }
}

// Run with:
// flow transactions send cadence/transactions/test_6_component_info.cdc --signer testnet --network testnet