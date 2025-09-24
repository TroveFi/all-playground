import FungibleToken from 0xf233dcee88fe0abe
import FlowToken from 0x1654653399040a61
import stFlowToken from 0xd6f80565193ad727
import Staking from 0x1b77ba4b414de352

transaction() {
    
    let userCertificate: &Staking.UserCertificate
    let stakingCollection: &{Staking.PoolCollectionPublic}
    let flowReceiver: &{FungibleToken.Receiver}
    let stFlowReceiver: &{FungibleToken.Receiver}
    
    prepare(signer: auth(Storage) &Account) {
        // Get user certificate
        self.userCertificate = signer.storage.borrow<&Staking.UserCertificate>(
            from: Staking.UserCertificateStoragePath
        ) ?? panic("User certificate not found")
        
        // Get staking collection
        let stakingAccount = getAccount(0x1b77ba4b414de352)
        self.stakingCollection = stakingAccount.capabilities.borrow<&{Staking.PoolCollectionPublic}>(
            Staking.CollectionPublicPath
        ) ?? panic("Could not borrow staking collection")
        
        // Get receivers for rewards
        self.flowReceiver = signer.capabilities.get<&{FungibleToken.Receiver}>(/public/flowTokenReceiver).borrow()
            ?? panic("Could not borrow Flow receiver")
        
        self.stFlowReceiver = signer.capabilities.get<&{FungibleToken.Receiver}>(/public/stFlowTokenReceiver).borrow()
            ?? panic("Could not borrow stFlow receiver")
    }
    
    execute {
        // Get all user's staking pool IDs
        let userAddress = self.userCertificate.owner!.address
        let stakingPoolIds = Staking.getUserStakingIds(address: userAddress)
        
        var totalRewardsClaimed: UFix64 = 0.0
        var poolsClaimed: Int = 0
        
        for poolId in stakingPoolIds {
            let poolRef = self.stakingCollection.getPool(pid: poolId)
            let userInfo = poolRef.getUserInfo(address: userAddress)
            
            // Only claim from pools where user has staked tokens
            if userInfo != nil && userInfo!.stakingAmount > 0.0 {
                let rewards <- poolRef.claimRewards(userCertificate: self.userCertificate)
                
                // Deposit each reward token to appropriate vault
                for tokenKey in rewards.keys {
                    let rewardVault <- rewards.remove(key: tokenKey)!
                    let amount = rewardVault.balance
                    
                    if tokenKey.contains("FlowToken") {
                        self.flowReceiver.deposit(from: <-rewardVault)
                        log("Claimed ".concat(amount.toString()).concat(" FLOW from pool ").concat(poolId.toString()))
                    } else if tokenKey.contains("stFlowToken") {
                        self.stFlowReceiver.deposit(from: <-rewardVault)
                        log("Claimed ".concat(amount.toString()).concat(" stFLOW from pool ").concat(poolId.toString()))
                    } else {
                        // For other tokens, would need specific handling
                        log("Received ".concat(amount.toString()).concat(" of ").concat(tokenKey).concat(" from pool ").concat(poolId.toString()))
                        destroy rewardVault
                    }
                    
                    totalRewardsClaimed = totalRewardsClaimed + amount
                }
                
                destroy rewards
                poolsClaimed = poolsClaimed + 1
            }
        }
        
        log("Successfully claimed rewards from ".concat(poolsClaimed.toString()).concat(" pools"))
        log("Total rewards value: ".concat(totalRewardsClaimed.toString()))
    }
}
