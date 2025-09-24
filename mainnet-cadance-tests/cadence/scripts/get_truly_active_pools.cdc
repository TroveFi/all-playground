// cadence/scripts/get_truly_active_pools.cdc
import Staking from 0x1b77ba4b414de352

access(all) struct TrulyActivePool {
    access(all) let pid: UInt64
    access(all) let status: String
    access(all) let acceptTokenKey: String
    access(all) let totalStaking: UFix64
    access(all) let limitAmount: UFix64
    access(all) let capacity: UFix64
    access(all) let hasRewards: Bool
    access(all) let rewardTokens: [String]
    
    init(pid: UInt64, status: String, acceptTokenKey: String, totalStaking: UFix64, 
         limitAmount: UFix64, capacity: UFix64, hasRewards: Bool, rewardTokens: [String]) {
        self.pid = pid
        self.status = status
        self.acceptTokenKey = acceptTokenKey
        self.totalStaking = totalStaking
        self.limitAmount = limitAmount
        self.capacity = capacity
        self.hasRewards = hasRewards
        self.rewardTokens = rewardTokens
    }
}

access(all) fun main(): [TrulyActivePool] {
    let stakingAccount = getAccount(0x1b77ba4b414de352)
    let collectionRef = stakingAccount.capabilities.borrow<&{Staking.PoolCollectionPublic}>(
        Staking.CollectionPublicPath
    ) ?? panic("Could not borrow staking collection")
    
    let activePools: [TrulyActivePool] = []
    
    // Check a reasonable range for active pools including known ones
    var i = 0
    while i <= 30 {  // Extended to include pool 20
        let poolRef = collectionRef.getPool(pid: UInt64(i))
        let poolInfo = poolRef.getPoolInfo()
        
        // Only include pools with status "2" (RUNNING)
        if poolInfo.status == "2" {
            let rewardInfo = poolRef.getRewardInfo()
            let rewardTokens: [String] = rewardInfo.keys
            let hasRewards = rewardTokens.length > 0
            
            let capacity = poolInfo.limitAmount - poolInfo.totalStaking
            
            let activePool = TrulyActivePool(
                pid: poolInfo.pid,
                status: poolInfo.status,
                acceptTokenKey: poolInfo.acceptTokenKey,
                totalStaking: poolInfo.totalStaking,
                limitAmount: poolInfo.limitAmount,
                capacity: capacity,
                hasRewards: hasRewards,
                rewardTokens: rewardTokens
            )
            
            activePools.append(activePool)
        }
        
        i = i + 1
    }
    
    return activePools
}