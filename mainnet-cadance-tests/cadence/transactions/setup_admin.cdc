import ArbitrageBotController from 0x2409dfbcc4c9d705

transaction() {
    prepare(signer: auth(BorrowValue, SaveValue) &Account) {
        // Check if Admin already exists
        if signer.storage.borrow<&ArbitrageBotController.Admin>(from: /storage/ArbitrageBotAdmin) != nil {
            log("Admin resource already exists")
            return
        }

        // The contract should have created the admin, but let's verify the public capability
        let publicCap = getAccount(0x2409dfbcc4c9d705)
            .capabilities.get<&ArbitrageBotController.Admin>(/public/ArbitrageBotAdmin)
        
        if publicCap.check() {
            log("Admin resource exists and is properly linked")
        } else {
            log("Admin resource needs to be set up")
            panic("Admin resource not found - contract may need redeployment")
        }
    }
}