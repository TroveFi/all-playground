// cadence/scripts/enhanced_farm_info.cdc
import Staking from 0x1b77ba4b414de352

access(all) struct EnhancedFarmInfo {
    access(all) let pid: UInt64
    access(all) let status: String
    access(all) let acceptTokenKey: String
    access(all) let totalStaking: UFix64
    access(all) let limitAmount: UFix64
    access(all) let capacity: UFix64
    access(all) let utilization: UFix64
    access(all) let rewardTokens: [String]
    access(all) let rewardRates: {String: UFix64}
    access(all) let estimatedDailyRewards: UFix64
    access(all) let isViable: Bool
    access(all) let startTime: UFix64
    access(all) let endTime: UFix64
    access(all) let isActive: Bool
    
    init(
        pid: UInt64, status: String, acceptTokenKey: String, totalStaking: UFix64,
        limitAmount: UFix64, capacity: UFix64, utilization: UFix64,
        rewardTokens: [String], rewardRates: {String: UFix64},
        estimatedDailyRewards: UFix64, isViable: Bool,
        startTime: UFix64, endTime: UFix64, isActive: Bool
    ) {
        self.pid = pid
        self.status = status
        self.acceptTokenKey = acceptTokenKey
        self.totalStaking = totalStaking
        self.limitAmount = limitAmount
        self.capacity = capacity
        self.utilization = utilization
        self.rewardTokens = rewardTokens
        self.rewardRates = rewardRates
        self.estimatedDailyRewards = estimatedDailyRewards
        self.isViable = isViable
        self.startTime = startTime
        self.endTime = endTime
        self.isActive = isActive
    }
}

access(all) fun main(minCapacity: UFix64, maxUtilization: UFix64): [EnhancedFarmInfo] {
    let stakingAccount = getAccount(0x1b77ba4b414de352)
    let collectionRef = stakingAccount.capabilities.borrow<&{Staking.PoolCollectionPublic}>(
        Staking.CollectionPublicPath
    ) ?? panic("Could not borrow staking collection")
    
    let poolCount = collectionRef.getCollectionLength()
    let allPools: [EnhancedFarmInfo] = []
    let currentTime = getCurrentBlock().timestamp
    
    var i = 0
    while i < poolCount {
        let poolRef = collectionRef.getPool(pid: UInt64(i))
        let poolInfo = poolRef.getPoolInfo()
        
        let capacity = poolInfo.limitAmount - poolInfo.totalStaking
        let utilization = poolInfo.totalStaking / poolInfo.limitAmount * 100.0
        
        let rewardInfo = poolRef.getRewardInfo()
        let rewardTokens: [String] = rewardInfo.keys
        let rewardRates: {String: UFix64} = {}
        var totalDailyRewards: UFix64 = 0.0
        
        for tokenKey in rewardInfo.keys {
            let reward = rewardInfo[tokenKey]!
            rewardRates[tokenKey] = reward.rewardPerSeed
            totalDailyRewards = totalDailyRewards + reward.rewardPerSeed * 86400.0
        }
        
        // Check if pool is actually open for staking (not just running)
        let hasCapacity = capacity > 0.0
        let isRunning = poolInfo.status == "2"
        let isViable = hasCapacity && isRunning && totalDailyRewards > 0.0
        
        let farmInfo = EnhancedFarmInfo(
            pid: poolInfo.pid,
            status: poolInfo.status,
            acceptTokenKey: poolInfo.acceptTokenKey,
            totalStaking: poolInfo.totalStaking,
            limitAmount: poolInfo.limitAmount,
            capacity: capacity,
            utilization: utilization,
            rewardTokens: rewardTokens,
            rewardRates: rewardRates,
            estimatedDailyRewards: totalDailyRewards,
            isViable: isViable,
            startTime: 0.0,  // Not available in PoolInfo
            endTime: 0.0,    // Not available in PoolInfo
            isActive: isRunning
        )
        
        allPools.append(farmInfo)
        i = i + 1
    }
    
    return allPools
}