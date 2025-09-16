// fund-router.cdc
// This transaction sends FLOW tokens to the ActionRouter contract account

import FungibleToken from 0xf233dcee88fe0abe
import FlowToken from 0x1654653399040a61

transaction(amount: UFix64, routerAddress: Address) {
    prepare(signer: auth(Storage) &Account) {
        // Get signer's Flow vault with proper authorization
        let flowVault = signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
            from: /storage/flowTokenVault
        ) ?? panic("Could not borrow Flow vault")
        
        // Withdraw the specified amount
        let tokens <- flowVault.withdraw(amount: amount)
        
        // Get the router's Flow receiver capability
        let routerAccount = getAccount(routerAddress)
        let routerReceiver = routerAccount.capabilities.get<&{FungibleToken.Receiver}>(/public/flowTokenReceiver).borrow()
            ?? panic("Could not borrow router's Flow receiver")
        
        // Deposit tokens to the router
        routerReceiver.deposit(from: <-tokens)
        
        log("Funded ActionRouter with ".concat(amount.toString()).concat(" FLOW"))
    }
}