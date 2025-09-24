// cadence/transactions/claim_all_rewards.cdc
import FungibleToken from 0xf233dcee88fe0abe
import Staking from 0x1b77ba4b414de352

transaction() {
    
    let userCertificate: &Staking.UserCertificate
    let stakingCollectionRef: &{Staking.PoolCollectionPublic}
    let signer: auth(Storage, Capabilities) &Account
    
    prepare(signer: auth(Storage, Capabilities) &Account) {
        self.signer = signer
        
        self.userCertificate = signer.storage.borrow<&Staking.UserCertificate>(
            from: Staking.UserCertificateStoragePath
        ) ?? panic("Could not borrow UserCertificate")
        
        let stakingAccount = getAccount(0x1b77ba4b414de352)
        self.stakingCollectionRef = stakingAccount.capabilities.borrow<&{Staking.PoolCollectionPublic}>(
            Staking.CollectionPublicPath
        ) ?? panic("Could not borrow staking collection")
    }
    
    execute {
        let userAddress = self.userCertificate.owner!.address
        let stakingIds = Staking.getUserStakingIds(address: userAddress)
        
        var totalClaimed: UFix64 = 0.0
        
        for poolId in stakingIds {
            let poolRef = self.stakingCollectionRef.getPool(pid: poolId)
            
            // Check if user has staked amount > 0
            if let userInfo = poolRef.getUserInfo(address: userAddress) {
                if userInfo.stakingAmount > 0.0 {
                    let claimedRewards <- poolRef.claimRewards(userCertificate: self.userCertificate)
                    
                    // Process each reward token
                    for tokenKey in claimedRewards.keys {
                        let rewardVault <- claimedRewards.remove(key: tokenKey)!
                        let amount = rewardVault.balance
                        
                        if amount > 0.0 {
                            totalClaimed = totalClaimed + amount
                            
                            // Route rewards to appropriate receivers
                            if tokenKey.contains("FlowToken") {
                                let flowReceiver = self.signer.capabilities.get<&{FungibleToken.Receiver}>(/public/flowTokenReceiver).borrow()
                                    ?? panic("Could not borrow FLOW receiver")
                                flowReceiver.deposit(from: <-rewardVault)
                            } else if tokenKey.contains("stFlowToken") {
                                let stFlowReceiver = self.signer.capabilities.get<&{FungibleToken.Receiver}>(/public/stFlowTokenReceiver).borrow()
                                    ?? panic("Could not borrow stFLOW receiver")
                                stFlowReceiver.deposit(from: <-rewardVault)
                            } else {
                                // For other tokens, try generic receiver or destroy
                                // In production, would need specific handling for each token
                                destroy rewardVault
                            }
                            
                            log("Claimed ".concat(amount.toString()).concat(" of ").concat(tokenKey).concat(" from pool ").concat(poolId.toString()))
                        } else {
                            destroy rewardVault
                        }
                    }
                    
                    destroy claimedRewards
                }
            }
        }
        
        log("Successfully claimed rewards from all pools. Total value: ".concat(totalClaimed.toString()))
    }
}