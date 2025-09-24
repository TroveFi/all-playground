// 1. setup-action-router.cdc
// This transaction sets up the ActionRouter after deployment

import ActionRouter from 0x79f5b5b0f95a160b

transaction {
    prepare(admin: &Account) {
        let adminRef = admin.storage.borrow<&ActionRouter.Admin>(from: ActionRouter.AdminStoragePath)
            ?? panic("Could not borrow admin reference")
        
        // Set initial configuration
        adminRef.updateLimits(minStake: 1.0, maxStake: 10000.0, maxOpsPerBlock: 10)
        adminRef.setActive(active: true)
        
        log("ActionRouter configured successfully")
    }
}











