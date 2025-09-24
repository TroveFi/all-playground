// cadence/scripts/scan_all_pools.cdc
import Staking from 0x1b77ba4b414de352

access(all) struct ComprehensivePoolInfo {
    access(all) let pid: UInt64
    access(all) let status: String
    access(all) let acceptTokenKey: String
    access(all) let totalStaking: UFix64
    access(all) let limitAmount: UFix64
    access(all) let capacity: UFix64
    access(all) let hasRewards: Bool
    access(all) let rewardTokens: [String]
    access(all) let rewardRates: {String: UFix64}
    
    init(pid: UInt64, status: String, acceptTokenKey: String, totalStaking: UFix64, 
         limitAmount: UFix64, capacity: UFix64, hasRewards: Bool, rewardTokens: [String], rewardRates: {String: UFix64}) {
        self.pid = pid
        self.status = status
        self.acceptTokenKey = acceptTokenKey
        self.totalStaking = totalStaking
        self.limitAmount = limitAmount
        self.capacity = capacity
        self.hasRewards = hasRewards
        self.rewardTokens = rewardTokens
        self.rewardRates = rewardRates
    }
}

access(all) fun main(maxPoolId: UInt64): [ComprehensivePoolInfo] {
    let stakingAccount = getAccount(0x1b77ba4b414de352)
    let collectionRef = stakingAccount.capabilities.borrow<&{Staking.PoolCollectionPublic}>(
        Staking.CollectionPublicPath
    ) ?? panic("Could not borrow staking collection")
    
    let allPools: [ComprehensivePoolInfo] = []
    
    var i: UInt64 = 0
    while i <= maxPoolId {
        let poolRef = collectionRef.getPool(pid: i)
        let poolInfo = poolRef.getPoolInfo()
        let rewardInfo = poolRef.getRewardInfo()
        
        let capacity = poolInfo.limitAmount > poolInfo.totalStaking ? poolInfo.limitAmount - poolInfo.totalStaking : 0.0
        let rewardTokens: [String] = rewardInfo.keys
        let hasRewards = rewardTokens.length > 0
        
        let rewardRates: {String: UFix64} = {}
        for tokenKey in rewardInfo.keys {
            let reward = rewardInfo[tokenKey]!
            rewardRates[tokenKey] = reward.rewardPerSeed
        }
        
        // Include ALL pools regardless of status - let the bot decide what's stakeable
        allPools.append(ComprehensivePoolInfo(
            pid: poolInfo.pid,
            status: poolInfo.status,
            acceptTokenKey: poolInfo.acceptTokenKey,
            totalStaking: poolInfo.totalStaking,
            limitAmount: poolInfo.limitAmount,
            capacity: capacity,
            hasRewards: hasRewards,
            rewardTokens: rewardTokens,
            rewardRates: rewardRates
        ))
        
        i = i + 1
    }
    
    return allPools
}