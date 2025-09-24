// 7. emergency-withdraw.cdc
// Emergency withdrawal transaction

import ActionRouter from 0x79f5b5b0f95a160b

transaction(amount: UFix64, recipient: Address) {
    prepare(admin: &Account) {
        let adminRef = admin.storage.borrow<&ActionRouter.Admin>(from: ActionRouter.AdminStoragePath)
            ?? panic("Could not borrow admin reference")
        
        adminRef.emergencyWithdraw(amount: amount, recipient: recipient)
        
        log("Emergency withdrawal of ".concat(amount.toString()).concat(" FLOW to ").concat(recipient.toString()))
    }
}