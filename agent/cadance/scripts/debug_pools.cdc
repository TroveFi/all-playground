// cadence/scripts/debug_pools.cdc
import Staking from 0x1b77ba4b414de352

access(all) struct DebugPoolInfo {
    access(all) let pid: UInt64
    access(all) let status: String
    access(all) let acceptTokenKey: String
    access(all) let totalStaking: UFix64
    access(all) let limitAmount: UFix64
    access(all) let capacity: UFix64
    access(all) let rewardTokenKeys: [String]
    access(all) let hasRewards: Bool
    
    init(pid: UInt64, status: String, acceptTokenKey: String, totalStaking: UFix64, limitAmount: UFix64, capacity: UFix64, rewardTokenKeys: [String], hasRewards: Bool) {
        self.pid = pid
        self.status = status
        self.acceptTokenKey = acceptTokenKey
        self.totalStaking = totalStaking
        self.limitAmount = limitAmount
        self.capacity = capacity
        self.rewardTokenKeys = rewardTokenKeys
        self.hasRewards = hasRewards
    }
}

access(all) fun main(): [DebugPoolInfo] {
    let stakingAccount = getAccount(0x1b77ba4b414de352)
    let collectionRef = stakingAccount.capabilities.borrow<&{Staking.PoolCollectionPublic}>(
        Staking.CollectionPublicPath
    ) ?? panic("Could not borrow staking collection")
    
    let poolCount = collectionRef.getCollectionLength()
    let debugPools: [DebugPoolInfo] = []
    
    var i = 0
    while i < poolCount {
        let poolRef = collectionRef.getPool(pid: UInt64(i))
        let poolInfo = poolRef.getPoolInfo()
        let rewardInfo = poolRef.getRewardInfo()
        
        let capacity = poolInfo.limitAmount - poolInfo.totalStaking
        let rewardTokenKeys: [String] = rewardInfo.keys
        let hasRewards = rewardTokenKeys.length > 0
        
        // Only include pools that are running and have some activity or rewards
        if poolInfo.status == "2" && (poolInfo.totalStaking > 0.0 || hasRewards) {
            debugPools.append(DebugPoolInfo(
                pid: poolInfo.pid,
                status: poolInfo.status,
                acceptTokenKey: poolInfo.acceptTokenKey,
                totalStaking: poolInfo.totalStaking,
                limitAmount: poolInfo.limitAmount,
                capacity: capacity,
                rewardTokenKeys: rewardTokenKeys,
                hasRewards: hasRewards
            ))
        }
        
        i = i + 1
    }
    
    return debugPools
}