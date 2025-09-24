// cadence/transactions/setup_staking.cdc  
import Staking from 0x1b77ba4b414de352

transaction {
    prepare(signer: auth(Storage, Capabilities) &Account) {
        
        // Check if UserCertificate already exists
        if signer.storage.borrow<&Staking.UserCertificate>(from: Staking.UserCertificateStoragePath) == nil {
            // Create and save UserCertificate
            signer.storage.save(<-Staking.createUserCertificate(), to: Staking.UserCertificateStoragePath)
            
            // Publish capability
            signer.capabilities.publish(
                signer.capabilities.storage.issue<&{Staking.UserCertificatePublic}>(Staking.UserCertificateStoragePath),
                at: Staking.UserCertificatePublicPath
            )
            
            log("UserCertificate created and configured successfully")
        } else {
            log("UserCertificate already exists")
        }
    }
}