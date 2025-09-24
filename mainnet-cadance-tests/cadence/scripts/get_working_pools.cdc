// cadence/scripts/get_working_pools.cdc
import Staking from 0x1b77ba4b414de352

access(all) struct WorkingPoolInfo {
    access(all) let pid: UInt64
    access(all) let status: String
    access(all) let acceptTokenKey: String
    access(all) let totalStaking: UFix64
    access(all) let limitAmount: UFix64
    access(all) let capacity: UFix64
    access(all) let utilization: UFix64
    access(all) let rewardTokens: [String]
    access(all) let estimatedDailyRewards: UFix64
    access(all) let canStake: Bool
    
    init(
        pid: UInt64, status: String, acceptTokenKey: String, totalStaking: UFix64,
        limitAmount: UFix64, capacity: UFix64, utilization: UFix64,
        rewardTokens: [String], estimatedDailyRewards: UFix64, canStake: Bool
    ) {
        self.pid = pid
        self.status = status
        self.acceptTokenKey = acceptTokenKey
        self.totalStaking = totalStaking
        self.limitAmount = limitAmount
        self.capacity = capacity
        self.utilization = utilization
        self.rewardTokens = rewardTokens
        self.estimatedDailyRewards = estimatedDailyRewards
        self.canStake = canStake
    }
}

access(all) fun main(): [WorkingPoolInfo] {
    let stakingAccount = getAccount(0x1b77ba4b414de352)
    let collectionRef = stakingAccount.capabilities.borrow<&{Staking.PoolCollectionPublic}>(
        Staking.CollectionPublicPath
    ) ?? panic("Could not borrow staking collection")
    
    let poolCount = collectionRef.getCollectionLength()
    let allPools: [WorkingPoolInfo] = []
    
    var i = 0
    while i < poolCount {
        let poolRef = collectionRef.getPool(pid: UInt64(i))
        let poolInfo = poolRef.getPoolInfo()
        
        let capacity = poolInfo.limitAmount - poolInfo.totalStaking
        let utilization = poolInfo.totalStaking / poolInfo.limitAmount * 100.0
        
        let rewardInfo = poolRef.getRewardInfo()
        let rewardTokens: [String] = rewardInfo.keys
        var totalDailyRewards: UFix64 = 0.0
        
        for tokenKey in rewardInfo.keys {
            let reward = rewardInfo[tokenKey]!
            totalDailyRewards = totalDailyRewards + reward.rewardPerSeed * 86400.0
        }
        
        // Very permissive check - just needs to be running and have rewards
        let hasRewards = totalDailyRewards > 0.0
        let canStake = poolInfo.status == "2" && hasRewards
        
        let workingPoolInfo = WorkingPoolInfo(
            pid: poolInfo.pid,
            status: poolInfo.status,
            acceptTokenKey: poolInfo.acceptTokenKey,
            totalStaking: poolInfo.totalStaking,
            limitAmount: poolInfo.limitAmount,
            capacity: capacity,
            utilization: utilization,
            rewardTokens: rewardTokens,
            estimatedDailyRewards: totalDailyRewards,
            canStake: canStake
        )
        
        allPools.append(workingPoolInfo)
        i = i + 1
    }
    
    return allPools
}