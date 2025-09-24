// cadence/scripts/check_pool_range.cdc
import Staking from 0x1b77ba4b414de352

access(all) struct PoolRangeCheck {
    access(all) let pid: UInt64
    access(all) let exists: Bool
    access(all) let status: String
    access(all) let acceptTokenKey: String
    access(all) let totalStaking: UFix64
    access(all) let hasRewards: Bool
    access(all) let rewardCount: Int
    
    init(pid: UInt64, exists: Bool, status: String, acceptTokenKey: String, 
         totalStaking: UFix64, hasRewards: Bool, rewardCount: Int) {
        self.pid = pid
        self.exists = exists
        self.status = status
        self.acceptTokenKey = acceptTokenKey
        self.totalStaking = totalStaking
        self.hasRewards = hasRewards
        self.rewardCount = rewardCount
    }
}

access(all) fun main(): [PoolRangeCheck] {
    let stakingAccount = getAccount(0x1b77ba4b414de352)
    let collectionRef = stakingAccount.capabilities.borrow<&{Staking.PoolCollectionPublic}>(
        Staking.CollectionPublicPath
    ) ?? panic("Could not borrow staking collection")
    
    let results: [PoolRangeCheck] = []
    
    // Check pools 200-210 (where Increment Fi shows active pools)
    let poolRanges: [UInt64] = [200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210]
    
    for poolId in poolRanges {
        var exists = false
        var status = ""
        var acceptTokenKey = ""
        var totalStaking: UFix64 = 0.0
        var hasRewards = false
        var rewardCount = 0
        
        // Try to access the pool - if it fails, it doesn't exist
        let poolRef = collectionRef.getPool(pid: poolId)
        if poolRef != nil {
            exists = true
            let poolInfo = poolRef.getPoolInfo()
            let rewardInfo = poolRef.getRewardInfo()
            
            status = poolInfo.status
            acceptTokenKey = poolInfo.acceptTokenKey
            totalStaking = poolInfo.totalStaking
            rewardCount = rewardInfo.keys.length
            hasRewards = rewardCount > 0
        }
        
        results.append(PoolRangeCheck(
            pid: poolId,
            exists: exists,
            status: status,
            acceptTokenKey: acceptTokenKey,
            totalStaking: totalStaking,
            hasRewards: hasRewards,
            rewardCount: rewardCount
        ))
    }
    
    return results
}