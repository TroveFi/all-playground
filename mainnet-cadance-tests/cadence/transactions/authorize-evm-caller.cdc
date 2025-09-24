// authorize-evm-caller-v3.cdc  
// This transaction authorizes an EVM address to call ActionRouterV3

import ActionRouterV3 from 0x79f5b5b0f95a160b

transaction(evmAddress: String) {
    prepare(admin: auth(Storage) &Account) {
        let adminRef = admin.storage.borrow<&ActionRouterV3.Admin>(from: ActionRouterV3.AdminStoragePath)
            ?? panic("Could not borrow admin reference")
        
        adminRef.authorizeEVMCaller(caller: evmAddress)
        
        log("EVM caller authorized in ActionRouterV3: ".concat(evmAddress))
    }
}