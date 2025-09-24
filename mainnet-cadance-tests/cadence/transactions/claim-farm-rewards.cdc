import FungibleToken from 0xf233dcee88fe0abe
import Staking from 0x1b77ba4b414de352

transaction(farmPoolId: UInt64) {
    
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
        
        // Claim rewards
        let claimedRewards <- poolRef.claimRewards(userCertificate: self.userCertificate)
        
        var totalClaimedValue: UFix64 = 0.0
        
        // Deposit each reward token to user's appropriate vault
        for tokenKey in claimedRewards.keys {
            let rewardVault <- claimedRewards.remove(key: tokenKey)!
            let amount = rewardVault.balance
            totalClaimedValue = totalClaimedValue + amount
            
            // This would need logic to determine the correct receiver path for each token type
            // For now, simplified placeholder
            
            if tokenKey.contains("FlowToken") {
                // Deposit FLOW tokens
                let flowReceiver = self.userCertificate.owner!.capabilities.get<&{FungibleToken.Receiver}>(/public/flowTokenReceiver).borrow()
                    ?? panic("Could not borrow FLOW receiver")
                flowReceiver.deposit(from: <-rewardVault)
            } else if tokenKey.contains("stFlowToken") {
                // Deposit stFLOW tokens
                let stFlowReceiver = self.userCertificate.owner!.capabilities.get<&{FungibleToken.Receiver}>(/public/stFlowTokenReceiver).borrow()
                    ?? panic("Could not borrow stFLOW receiver")
                stFlowReceiver.deposit(from: <-rewardVault)
            } else {
                // For other tokens, would need specific handling
                // For now, just destroy (not recommended in production)
                destroy rewardVault
            }
            
            log("Claimed ".concat(amount.toString()).concat(" of ").concat(tokenKey))
        }
        
        // Destroy empty collection
        destroy claimedRewards
        
        log("Successfully claimed rewards from pool ".concat(farmPoolId.toString()))
    }
}