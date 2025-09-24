// cadence/scripts/check_known_pools.cdc
import Staking from 0x1b77ba4b414de352

access(all) struct KnownPoolCheck {
    access(all) let pid: UInt64
    access(all) let exists: Bool
    access(all) let status: String
    access(all) let acceptTokenKey: String
    access(all) let totalStaking: UFix64
    access(all) let limitAmount: UFix64
    access(all) let hasRewards: Bool
    access(all) let errorMsg: String
    
    init(pid: UInt64, exists: Bool, status: String, acceptTokenKey: String, 
         totalStaking: UFix64, limitAmount: UFix64, hasRewards: Bool, errorMsg: String) {
        self.pid = pid
        self.exists = exists
        self.status = status
        self.acceptTokenKey = acceptTokenKey
        self.totalStaking = totalStaking
        self.limitAmount = limitAmount
        self.hasRewards = hasRewards
        self.errorMsg = errorMsg
    }
}

access(all) fun main(): [KnownPoolCheck] {
    let stakingAccount = getAccount(0x1b77ba4b414de352)
    let collectionRef = stakingAccount.capabilities.borrow<&{Staking.PoolCollectionPublic}>(
        Staking.CollectionPublicPath
    ) ?? panic("Could not borrow staking collection")
    
    // Check the pools mentioned on Increment Fi website
    let knownPoolIds: [UInt64] = [204, 205, 206, 20, 14]
    let results: [KnownPoolCheck] = []
    
    for poolId in knownPoolIds {
        var exists = true
        var status = ""
        var acceptTokenKey = ""
        var totalStaking: UFix64 = 0.0
        var limitAmount: UFix64 = 0.0
        var hasRewards = false
        var errorMsg = ""
        
        // Try to get pool info - the error handling was wrong before
        let poolRef = collectionRef.getPool(pid: poolId)
        let poolInfo = poolRef.getPoolInfo()
        let rewardInfo = poolRef.getRewardInfo()
        
        status = poolInfo.status
        acceptTokenKey = poolInfo.acceptTokenKey
        totalStaking = poolInfo.totalStaking
        limitAmount = poolInfo.limitAmount
        hasRewards = rewardInfo.keys.length > 0
        
        results.append(KnownPoolCheck(
            pid: poolId,
            exists: exists,
            status: status,
            acceptTokenKey: acceptTokenKey,
            totalStaking: totalStaking,
            limitAmount: limitAmount,
            hasRewards: hasRewards,
            errorMsg: errorMsg
        ))
    }
    
    return results
}