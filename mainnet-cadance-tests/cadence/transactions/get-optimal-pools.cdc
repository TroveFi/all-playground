import Staking from 0x1b77ba4b414de352

access(all) struct OptimalPool {
    access(all) let pid: UInt64
    access(all) let acceptTokenKey: String
    access(all) let totalStaking: UFix64
    access(all) let estimatedAPR: UFix64
    access(all) let utilization: UFix64
    access(all) let rewardTokens: [String]
    access(all) let capacity: UFix64
    
    init(
        pid: UInt64,
        acceptTokenKey: String,
        totalStaking: UFix64,
        estimatedAPR: UFix64,
        utilization: UFix64,
        rewardTokens: [String],
        capacity: UFix64
    ) {
        self.pid = pid
        self.acceptTokenKey = acceptTokenKey
        self.totalStaking = totalStaking
        self.estimatedAPR = estimatedAPR
        self.utilization = utilization
        self.rewardTokens = rewardTokens
        self.capacity = capacity
    }
}

access(all) fun main(
    minTVL: UFix64,
    maxUtilization: UFix64,
    minCapacity: UFix64
): [OptimalPool] {
    
    let stakingAccount = getAccount(0x1b77ba4b414de352)
    let collectionRef = stakingAccount.capabilities.borrow<&{Staking.PoolCollectionPublic}>(
        Staking.CollectionPublicPath
    ) ?? panic("Could not borrow staking collection")
    
    let poolCount = collectionRef.getCollectionLength()
    let optimalPools: [OptimalPool] = []
    
    var i = 0
    while i < poolCount {
        let poolRef = collectionRef.getPool(pid: UInt64(i))
        let poolInfo = poolRef.getPoolInfo()
        
        // Only include active pools
        if poolInfo.status == "2" {  // RUNNING status
            let utilization = (poolInfo.totalStaking / poolInfo.limitAmount) * 100.0
            let capacity = poolInfo.limitAmount - poolInfo.totalStaking
            
            // Apply filters
            if poolInfo.totalStaking >= minTVL && 
               utilization <= maxUtilization && 
               capacity >= minCapacity {
                
                let rewardInfo = poolRef.getRewardInfo()
                let rewardTokens: [String] = []
                var totalRPS: UFix64 = 0.0
                
                for tokenKey in rewardInfo.keys {
                    rewardTokens.append(tokenKey)
                    totalRPS = totalRPS + rewardInfo[tokenKey]!.rewardPerSeed
                }
                
                // Simple APR estimation (would need token prices for accuracy)
                let estimatedAPR = totalRPS * 365.0 * 24.0 * 60.0 * 60.0 * 100.0
                
                let optimalPool = OptimalPool(
                    pid: poolInfo.pid,
                    acceptTokenKey: poolInfo.acceptTokenKey,
                    totalStaking: poolInfo.totalStaking,
                    estimatedAPR: estimatedAPR,
                    utilization: utilization,
                    rewardTokens: rewardTokens,
                    capacity: capacity
                )
                
                optimalPools.append(optimalPool)
            }
        }
        
        i = i + 1
    }
    
    return optimalPools
}