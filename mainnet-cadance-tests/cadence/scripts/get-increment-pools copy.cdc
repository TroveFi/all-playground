import Staking from 0x1b77ba4b414de352

access(all) struct FarmPoolInfo {
    access(all) let pid: UInt64
    access(all) let status: String
    access(all) let acceptTokenKey: String
    access(all) let totalStaking: UFix64
    access(all) let limitAmount: UFix64
    access(all) let creator: Address
    access(all) let rewardTokens: [String]
    access(all) let rewardInfo: {String: String} // Simplified for now
    
    init(
        pid: UInt64,
        status: String,
        acceptTokenKey: String,
        totalStaking: UFix64,
        limitAmount: UFix64,
        creator: Address,
        rewardTokens: [String],
        rewardInfo: {String: String}
    ) {
        self.pid = pid
        self.status = status
        self.acceptTokenKey = acceptTokenKey
        self.totalStaking = totalStaking
        self.limitAmount = limitAmount
        self.creator = creator
        self.rewardTokens = rewardTokens
        self.rewardInfo = rewardInfo
    }
}

access(all) fun main(): [FarmPoolInfo] {
    let stakingAccount = getAccount(0x1b77ba4b414de352)
    let collectionRef = stakingAccount.capabilities.borrow<&{Staking.PoolCollectionPublic}>(Staking.CollectionPublicPath)
    
    if collectionRef == nil {
        return []
    }
    
    let poolCount = collectionRef!.getCollectionLength()
    let pools: [FarmPoolInfo] = []
    
    // Get all pools (limited to first 20 for testing)
    let maxPools = poolCount < 20 ? poolCount : 20
    var i = 0
    
    while i < maxPools {
        let poolRef = collectionRef!.getPool(pid: UInt64(i))
        let poolInfo = poolRef.getPoolInfo()
        let rewardInfo = poolRef.getRewardInfo()
        
        let rewardTokens: [String] = []
        let rewardDetails: {String: String} = {}
        
        for tokenKey in rewardInfo.keys {
            rewardTokens.append(tokenKey)
            let reward = rewardInfo[tokenKey]!
            rewardDetails[tokenKey] = "RPS: ".concat(reward.rewardPerSeed.toString())
        }
        
        let farmPool = FarmPoolInfo(
            pid: poolInfo.pid,
            status: poolInfo.status,
            acceptTokenKey: poolInfo.acceptTokenKey,
            totalStaking: poolInfo.totalStaking,
            limitAmount: poolInfo.limitAmount,
            creator: poolInfo.creator,
            rewardTokens: rewardTokens,
            rewardInfo: rewardDetails
        )
        
        pools.append(farmPool)
        i = i + 1
    }
    
    return pools
}