import FungibleToken from 0xf233dcee88fe0abe
import FlowToken from 0x1654653399040a61
import stFlowToken from 0xd6f80565193ad727
import Staking from 0x1b77ba4b414de352

transaction() {
    prepare(signer: auth(Storage, Capabilities) &Account) {
        // 1. Setup user certificate if not exists
        if signer.storage.borrow<&Staking.UserCertificate>(from: Staking.UserCertificateStoragePath) == nil {
            let userCertificate <- Staking.setupUser()
            signer.storage.save(<-userCertificate, to: Staking.UserCertificateStoragePath)
        }
        
        // 2. Ensure Flow token receiver capability exists
        if !signer.capabilities.get<&{FungibleToken.Receiver}>(/public/flowTokenReceiver).check() {
            let flowCap = signer.capabilities.storage.issue<&{FungibleToken.Receiver}>(/storage/flowTokenVault)
            signer.capabilities.publish(flowCap, at: /public/flowTokenReceiver)
        }
        
        // 3. Ensure stFlow token vault and receiver capability exists
        if signer.storage.borrow<&stFlowToken.Vault>(from: /storage/stFlowTokenVault) == nil {
            let stFlowVault <- stFlowToken.createEmptyVault(vaultType: Type<@stFlowToken.Vault>())
            signer.storage.save(<-stFlowVault, to: /storage/stFlowTokenVault)
        }
        
        if !signer.capabilities.get<&{FungibleToken.Receiver}>(/public/stFlowTokenReceiver).check() {
            let stFlowCap = signer.capabilities.storage.issue<&{FungibleToken.Receiver}>(/storage/stFlowTokenVault)
            signer.capabilities.publish(stFlowCap, at: /public/stFlowTokenReceiver)
        }
        
        log("User setup completed for LP farming")
    }
}
