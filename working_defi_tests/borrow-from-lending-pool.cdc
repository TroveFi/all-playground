import FungibleToken from 0xf233dcee88fe0abe
import FlowToken from 0x1654653399040a61
import stFlowToken from 0xd6f80565193ad727
import LendingInterfaces from 0x2df970b6cdee5735
import LendingComptroller from 0xf80cb737bfe7c792
import LendingConfig from 0x2df970b6cdee5735

transaction(poolAddress: Address, borrowAmount: UFix64) {
    prepare(acct: auth(Storage, Capabilities) &Account) {
        if acct.storage.borrow<&{LendingInterfaces.IdentityCertificate}>(from: LendingConfig.UserCertificateStoragePath) == nil {
            acct.storage.save(<-LendingComptroller.IssueUserCertificate(), to: LendingConfig.UserCertificateStoragePath)
        }
        let userCertificate = acct.storage.borrow<&{LendingInterfaces.IdentityCertificate}>(from: LendingConfig.UserCertificateStoragePath)!
        
        let poolPublic = getAccount(poolAddress).capabilities
            .borrow<&{LendingInterfaces.PoolPublic}>(LendingConfig.PoolPublicPublicPath)
            ?? panic("Cannot access lending pool")
        
        let borrowedVault <- poolPublic.borrow(userCertificate: userCertificate, borrowAmount: borrowAmount)
        
        if poolAddress == 0x7492e2f9b4acea9a {
            let vault = acct.storage.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)!
            vault.deposit(from: <-borrowedVault)
        } else if poolAddress == 0x44fe3d9157770b2d {
            if acct.storage.borrow<&stFlowToken.Vault>(from: stFlowToken.tokenVaultPath) == nil {
                acct.storage.save(<-stFlowToken.createEmptyVault(vaultType: Type<@stFlowToken.Vault>()), to: stFlowToken.tokenVaultPath)
            }
            let vault = acct.storage.borrow<&stFlowToken.Vault>(from: stFlowToken.tokenVaultPath)!
            vault.deposit(from: <-borrowedVault)
        } else {
            destroy borrowedVault
            panic("Unsupported pool")
        }
        
        log("Borrowed ".concat(borrowAmount.toString()).concat(" from pool ").concat(poolAddress.toString()))
    }
}