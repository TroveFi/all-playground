// cadence/scripts/get_pool_rewards.cdc
import Staking from 0x1b77ba4b414de352

access(all) struct RewardInfo {
    access(all) let tokenKey: String
    access(all) let rewardPerSeed: UFix64
    access(all) let totalRewards: UFix64
    access(all) let distributedRewards: UFix64
    
    init(tokenKey: String, rewardPerSeed: UFix64, totalRewards: UFix64, distributedRewards: UFix64) {
        self.tokenKey = tokenKey
        self.rewardPerSeed = rewardPerSeed
        self.totalRewards = totalRewards
        self.distributedRewards = distributedRewards
    }
}

access(all) fun main(poolId: UInt64): [RewardInfo] {
    let stakingAccount = getAccount(0x1b77ba4b414de352)
    let collectionRef = stakingAccount.capabilities.borrow<&{Staking.PoolCollectionPublic}>(
        Staking.CollectionPublicPath
    ) ?? panic("Could not borrow staking collection")
    
    let poolRef = collectionRef.getPool(pid: poolId)
    let rewardInfo = poolRef.getRewardInfo()
    
    let rewards: [RewardInfo] = []
    for tokenKey in rewardInfo.keys {
        let reward = rewardInfo[tokenKey]!
        rewards.append(RewardInfo(
            tokenKey: tokenKey,
            rewardPerSeed: reward.rewardPerSeed,
            totalRewards: reward.totalRewards,
            distributedRewards: reward.distributedRewards
        ))
    }
    
    return rewards
}