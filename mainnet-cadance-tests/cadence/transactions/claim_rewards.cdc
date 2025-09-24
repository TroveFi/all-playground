import FungibleToken from 0xf233dcee88fe0abe
import Staking from 0x1b77ba4b414de352

transaction(farmPoolId: UInt64) {
    let userCertificate: &Staking.UserCertificate
    let stakingCollectionRef: &{Staking.PoolCollectionPublic}
    let flowReceiver: &{FungibleToken.Receiver}

    prepare(signer: auth(Storage) &Account) {
        self.userCertificate = signer.storage.borrow<&Staking.UserCertificate>(from: Staking.UserCertificateStoragePath) ?? panic("No UserCertificate")
        self.flowReceiver = signer.capabilities.borrow<&{FungibleToken.Receiver}>(/public/flowTokenReceiver) ?? panic("No FLOW receiver")
        let stakingAccount = getAccount(0x1b77ba4b414de352)
        self.stakingCollectionRef = stakingAccount.capabilities.borrow<&{Staking.PoolCollectionPublic}>(Staking.CollectionPublicPath) ?? panic("No staking collection")
    }
    
    execute {
        let poolRef = self.stakingCollectionRef.getPool(pid: farmPoolId)
        let rewards <- poolRef.claimRewards(userCertificate: self.userCertificate)
        
        for key in rewards.keys {
            let vault <- rewards.remove(key: key)!
            log("Claimed ".concat(vault.balance.toString()).concat(" of ").concat(key))
            // This example only deposits FLOW and destroys other reward tokens.
            if key.contains("FlowToken") {
                self.flowReceiver.deposit(from: <-vault)
            } else {
                destroy vault
            }
        }
        destroy rewards
    }
}