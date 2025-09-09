// authorize-evm-caller.cdc  
// This transaction authorizes an EVM address to call the router

import ActionRouterV2 from 0x79f5b5b0f95a160b

transaction(evmAddress: String) {
    prepare(admin: auth(Storage) &Account) {
        let adminRef = admin.storage.borrow<&ActionRouterV2.Admin>(from: ActionRouterV2.AdminStoragePath)
            ?? panic("Could not borrow admin reference")
        
        adminRef.authorizeEVMCaller(caller: evmAddress)
        
        log("EVM caller authorized: ".concat(evmAddress))
    }
}