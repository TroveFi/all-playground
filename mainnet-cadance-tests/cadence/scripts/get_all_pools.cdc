import Staking from 0x1b77ba4b414de352

// A more detailed struct to hold all necessary info for the bot
access(all) struct DetailedFarmPoolInfo {
    access(all) let pid: UInt64
    access(all) let acceptTokenKey: String
    access(all) let totalStaking: UFix64
    access(all) let rewards: {String: UFix64}

    init(pid: UInt64, acceptTokenKey: String, totalStaking: UFix64, rewards: {String: UFix64}) {
        self.pid = pid
        self.acceptTokenKey = acceptTokenKey
        self.totalStaking = totalStaking
        self.rewards = rewards
    }
}

access(all) fun main(): [DetailedFarmPoolInfo] {
    let collectionRef = getAccount(0x1b77ba4b414de352).capabilities
        .borrow<&{Staking.PoolCollectionPublic}>(Staking.CollectionPublicPath)
        ?? panic("Could not borrow staking collection")

    let poolCount = collectionRef.getCollectionLength()
    var pools: [DetailedFarmPoolInfo] = []
    var i = 0
    while i < poolCount {
        let poolRef = collectionRef.getPool(pid: UInt64(i))
        let poolInfo = poolRef.getPoolInfo()
        
        if poolInfo.status == "2" { // "2" means RUNNING
            let rewardInfo = poolRef.getRewardInfo()
            let rewards: {String: UFix64} = {}
            
            for key in rewardInfo.keys {
                rewards[key] = rewardInfo[key]!.rewardPerSeed
            }

            pools.append(DetailedFarmPoolInfo(
                pid: poolInfo.pid,
                acceptTokenKey: poolInfo.acceptTokenKey,
                totalStaking: poolInfo.totalStaking,
                rewards: rewards
            ))
        }
        i = i + 1
    }
    return pools
}