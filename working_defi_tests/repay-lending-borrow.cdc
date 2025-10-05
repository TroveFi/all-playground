import FungibleToken from 0xf233dcee88fe0abe
import FlowToken from 0x1654653399040a61
import LendingInterfaces from 0x2df970b6cdee5735
import LendingConfig from 0x2df970b6cdee5735

transaction(poolAddress: Address, repayAmount: UFix64) {
    let vault: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}
    
    prepare(acct: auth(Storage, Capabilities) &Account) {
        if poolAddress == 0x7492e2f9b4acea9a { // FLOW pool
            self.vault = acct.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(from: /storage/flowTokenVault)
                ?? panic("Missing FLOW vault")
        } else {
            panic("Unsupported pool")
        }
    }
    
    execute {
        let poolPublic = getAccount(poolAddress).capabilities
            .borrow<&{LendingInterfaces.PoolPublic}>(LendingConfig.PoolPublicPublicPath)
            ?? panic("Cannot access lending pool")
        
        let repayVault <- self.vault.withdraw(amount: repayAmount)
        let remaining <- poolPublic.repayBorrow(borrower: self.vault.owner!.address, repayUnderlyingVault: <-repayVault)
        
        if remaining != nil {
            self.vault.deposit(from: <-remaining!)
        } else {
            destroy remaining
        }
        
        log("Repaid ".concat(repayAmount.toString()).concat(" to pool ").concat(poolAddress.toString()))
    }
}