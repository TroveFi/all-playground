
import FungibleToken from 0xf233dcee88fe0abe
import Staking from 0x1b77ba4b414de352

transaction(farmPoolId: UInt64, amount: UFix64) {
    
    let userCertificate: &Staking.UserCertificate
    let stakingCollectionRef: &{Staking.PoolCollectionPublic}
    
    prepare(signer: auth(Storage) &Account) {
        // Get user certificate
        self.userCertificate = signer.storage.borrow<&Staking.UserCertificate>(
            from: Staking.UserCertificateStoragePath
        ) ?? panic("Could not borrow UserCertificate")
        
        // Get staking collection reference
        let stakingAccount = getAccount(0x1b77ba4b414de352)
        self.stakingCollectionRef = stakingAccount.capabilities.borrow<&{Staking.PoolCollectionPublic}>(
            Staking.CollectionPublicPath
        ) ?? panic("Could not borrow staking collection")
    }
    
    execute {
        // Get the specific pool
        let poolRef = self.stakingCollectionRef.getPool(pid: farmPoolId)
        
        // Unstake tokens
        let unstakedTokens <- poolRef.unstake(userCertificate: self.userCertificate, amount: amount)
        
        // Store the unstaked tokens back in user's vault
        // This would need to determine the correct vault path based on token type
        let userAccount = self.userCertificate.owner!
        
        // Placeholder - would need to get the correct receiver capability
        // based on the specific LP token type
        let receiverCap = userAccount.capabilities.get<&{FungibleToken.Receiver}>(/public/lpTokenReceiver)
        let receiverRef = receiverCap.borrow() ?? panic("Could not borrow receiver")
        
        receiverRef.deposit(from: <-unstakedTokens)
        
        log("Successfully unstaked ".concat(amount.toString()).concat(" tokens from pool ").concat(farmPoolId.toString()))
    }
}
