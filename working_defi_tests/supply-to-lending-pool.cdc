import FungibleToken from 0xf233dcee88fe0abe
import FlowToken from 0x1654653399040a61
import stFlowToken from 0xd6f80565193ad727
import LendingInterfaces from 0x2df970b6cdee5735
import LendingConfig from 0x2df970b6cdee5735

transaction(poolAddress: Address, amount: UFix64) {
    prepare(acct: auth(Storage, Capabilities) &Account) {
        let poolPublic = getAccount(poolAddress).capabilities
            .borrow<&{LendingInterfaces.PoolPublic}>(LendingConfig.PoolPublicPublicPath)
            ?? panic("Cannot access lending pool")
        
        if poolAddress == 0x7492e2f9b4acea9a {
            let vault = acct.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(from: /storage/flowTokenVault)
                ?? panic("Missing FLOW vault")
            let suppliedVault <- vault.withdraw(amount: amount)
            poolPublic.supply(supplierAddr: acct.address, inUnderlyingVault: <-suppliedVault)
        } else if poolAddress == 0x44fe3d9157770b2d {
            let vault = acct.storage.borrow<auth(FungibleToken.Withdraw) &stFlowToken.Vault>(from: stFlowToken.tokenVaultPath)
                ?? panic("Missing stFLOW vault")
            let suppliedVault <- vault.withdraw(amount: amount)
            poolPublic.supply(supplierAddr: acct.address, inUnderlyingVault: <-suppliedVault)
        } else {
            panic("Unsupported pool")
        }
        
        log("Supplied ".concat(amount.toString()).concat(" to pool ").concat(poolAddress.toString()))
    }
}