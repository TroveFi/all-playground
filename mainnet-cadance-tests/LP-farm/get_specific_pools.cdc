// cadence/scripts/get_specific_pools.cdc
import Staking from 0x1b77ba4b414de352

access(all) struct SafePoolInfo {
    access(all) let pid: UInt64
    access(all) let exists: Bool
    access(all) let status: String
    access(all) let acceptTokenKey: String
    access(all) let totalStaking: UFix64
    access(all) let limitAmount: UFix64
    access(all) let capacity: UFix64
    access(all) let hasRewards: Bool
    access(all) let rewardTokens: [String]
    
    init(pid: UInt64, exists: Bool, status: String, acceptTokenKey: String, totalStaking: UFix64, 
         limitAmount: UFix64, capacity: UFix64, hasRewards: Bool, rewardTokens: [String]) {
        self.pid = pid
        self.exists = exists
        self.status = status
        self.acceptTokenKey = acceptTokenKey
        self.totalStaking = totalStaking
        self.limitAmount = limitAmount
        self.capacity = capacity
        self.hasRewards = hasRewards
        self.rewardTokens = rewardTokens
    }
}

access(all) fun main(): [SafePoolInfo] {
    let stakingAccount = getAccount(0x1b77ba4b414de352)
    let collectionRef = stakingAccount.capabilities.borrow<&{Staking.PoolCollectionPublic}>(
        Staking.CollectionPublicPath
    ) ?? panic("Could not borrow staking collection")
    
    let allPools: [SafePoolInfo] = []
    
    // First get all pools in the known working range (0-30)
    var i: UInt64 = 0
    while i <= 30 {
        let poolRef = collectionRef.getPool(pid: i)
        let poolInfo = poolRef.getPoolInfo()
        let rewardInfo = poolRef.getRewardInfo()
        
        let capacity = poolInfo.limitAmount > poolInfo.totalStaking ? poolInfo.limitAmount - poolInfo.totalStaking : 0.0
        let rewardTokens: [String] = rewardInfo.keys
        let hasRewards = rewardTokens.length > 0
        
        allPools.append(SafePoolInfo(
            pid: poolInfo.pid,
            exists: true,
            status: poolInfo.status,
            acceptTokenKey: poolInfo.acceptTokenKey,
            totalStaking: poolInfo.totalStaking,
            limitAmount: poolInfo.limitAmount,
            capacity: capacity,
            hasRewards: hasRewards,
            rewardTokens: rewardTokens
        ))
        
        i = i + 1
    }
    
    // Now try to get the specific high-numbered pools from the website
    let websitePools: [UInt64] = [204, 205, 206]
    
    for poolId in websitePools {
        let poolRef = collectionRef.getPool(pid: poolId)
        let poolInfo = poolRef.getPoolInfo()
        let rewardInfo = poolRef.getRewardInfo()
        
        let capacity = poolInfo.limitAmount > poolInfo.totalStaking ? poolInfo.limitAmount - poolInfo.totalStaking : 0.0
        let rewardTokens: [String] = rewardInfo.keys
        let hasRewards = rewardTokens.length > 0
        
        allPools.append(SafePoolInfo(
            pid: poolInfo.pid,
            exists: true,
            status: poolInfo.status,
            acceptTokenKey: poolInfo.acceptTokenKey,
            totalStaking: poolInfo.totalStaking,
            limitAmount: poolInfo.limitAmount,
            capacity: capacity,
            hasRewards: hasRewards,
            rewardTokens: rewardTokens
        ))
    }
    
    return allPools
}