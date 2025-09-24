import Staking from 0x1b77ba4b414de352

transaction() {
    
    prepare(signer: auth(Storage) &Account) {
        // Check if user certificate already exists
        if signer.storage.borrow<&Staking.UserCertificate>(from: Staking.UserCertificateStoragePath) == nil {
            // Create and store user certificate
            let userCertificate <- Staking.setupUser()
            signer.storage.save(<-userCertificate, to: Staking.UserCertificateStoragePath)
            
            log("User certificate created and stored")
        } else {
            log("User certificate already exists")
        }
    }
    
    execute {
        log("User certificate setup completed")
    }
}