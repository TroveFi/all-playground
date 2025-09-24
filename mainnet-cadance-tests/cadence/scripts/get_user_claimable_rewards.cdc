// cadence/scripts/get_user_claimable_rewards.cdc
import Staking from 0x1b77ba4b414de352

access(all) struct ClaimableRewards {
    access(all) let poolId: UInt64
    access(all) let rewards: {String: UFix64}
    access(all) let totalValue: UFix64
    
    init(poolId: UInt64, rewards: {String: UFix64}, totalValue: UFix64) {
        self.poolId = poolId
        self.rewards = rewards
        self.totalValue = totalValue
    }
}

access(all) fun main(userAddress: Address): [ClaimableRewards] {
    let stakingAccount = getAccount(0x1b77ba4b414de352)
    let collectionRef = stakingAccount.capabilities.borrow<&{Staking.PoolCollectionPublic}>(
        Staking.CollectionPublicPath
    ) ?? panic("Could not borrow staking collection")
    
    let stakingIds = Staking.getUserStakingIds(address: userAddress)
    let claimableRewards: [ClaimableRewards] = []
    
    for poolId in stakingIds {
        let poolRef = collectionRef.getPool(pid: poolId)
        
        if let userInfo = poolRef.getUserInfo(address: userAddress) {
            if userInfo.stakingAmount > 0.0 {
                // This would need to calculate actual claimable rewards
                // For now, return placeholder structure
                let rewards: {String: UFix64} = {}
                let rewardInfo = poolRef.getRewardInfo()
                
                for tokenKey in rewardInfo.keys {
                    // Simplified calculation - in reality would need to track time
                    let reward = rewardInfo[tokenKey]!
                    let claimable = userInfo.stakingAmount * reward.rewardPerSeed * 3600.0 // 1 hour worth
                    rewards[tokenKey] = claimable
                }
                
                claimableRewards.append(ClaimableRewards(
                    poolId: poolId,
                    rewards: rewards,
                    totalValue: 0.0 // Would calculate based on token prices
                ))
            }
        }
    }
    
    return claimableRewards
}