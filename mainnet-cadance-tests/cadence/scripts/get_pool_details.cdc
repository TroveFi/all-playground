// cadence/scripts/get_pool_details.cdc
import Staking from 0x1b77ba4b414de352

access(all) struct PoolDetails {
    access(all) let pid: UInt64
    access(all) let status: String
    access(all) let acceptTokenKey: String
    access(all) let totalStaking: UFix64
    access(all) let limitAmount: UFix64
    access(all) let startTime: UFix64
    access(all) let endTime: UFix64
    access(all) let rewardInfo: {String: RewardDetails}
    
    init(
        pid: UInt64,
        status: String,
        acceptTokenKey: String,
        totalStaking: UFix64,
        limitAmount: UFix64,
        startTime: UFix64,
        endTime: UFix64,
        rewardInfo: {String: RewardDetails}
    ) {
        self.pid = pid
        self.status = status
        self.acceptTokenKey = acceptTokenKey
        self.totalStaking = totalStaking
        self.limitAmount = limitAmount
        self.startTime = startTime
        self.endTime = endTime
        self.rewardInfo = rewardInfo
    }
}

access(all) struct RewardDetails {
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

access(all) fun main(poolId: UInt64): PoolDetails {
    let stakingAccount = getAccount(0x1b77ba4b414de352)
    let collectionRef = stakingAccount.capabilities.borrow<&{Staking.PoolCollectionPublic}>(
        Staking.CollectionPublicPath
    ) ?? panic("Could not borrow staking collection")
    
    let poolRef = collectionRef.getPool(pid: poolId)
    let poolInfo = poolRef.getPoolInfo()
    let rewardInfo = poolRef.getRewardInfo()
    
    let rewardDetails: {String: RewardDetails} = {}
    for tokenKey in rewardInfo.keys {
        let reward = rewardInfo[tokenKey]!
        rewardDetails[tokenKey] = RewardDetails(
            tokenKey: tokenKey,
            rewardPerSeed: reward.rewardPerSeed,
            totalRewards: reward.totalRewards,
            distributedRewards: reward.distributedRewards
        )
    }
    
    return PoolDetails(
        pid: poolInfo.pid,
        status: poolInfo.status,
        acceptTokenKey: poolInfo.acceptTokenKey,
        totalStaking: poolInfo.totalStaking,
        limitAmount: poolInfo.limitAmount,
        startTime: poolInfo.startTime,
        endTime: poolInfo.endTime,
        rewardInfo: rewardDetails
    )
}