import "FungibleToken"
import "FlowToken"
import "FungibleTokenConnectors"
import "DeFiActions"

transaction() {
    prepare(signer: auth(IssueStorageCapabilityController) &Account) {
        let withdrawCap = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
            /storage/flowTokenVault
        )
        
        let source = FungibleTokenConnectors.VaultSource(
            min: 0.0,
            withdrawVault: withdrawCap,
            uniqueID: DeFiActions.createUniqueIdentifier()
        )
        
        // Test component info
        let info = source.getComponentInfo()
        log("Component Type: ".concat(info.name))
        log("Component Description: ".concat(info.description))
        log("Version: ".concat(info.version))
        
        // Test source-specific info
        log("Source Type: ".concat(source.getSourceType().identifier))
        log("Available: ".concat(source.minimumAvailable().toString()))
    }
}