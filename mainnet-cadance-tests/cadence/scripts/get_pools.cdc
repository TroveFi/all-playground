import Staking from 0x1b77ba4b414de352

access(all) struct FarmPoolInfo {
    access(all) let pid: UInt64
    access(all) let acceptTokenKey: String
    access(all) let totalStaking: UFix64

    init(pid: UInt64, acceptTokenKey: String, totalStaking: UFix64) {
        self.pid = pid
        self.acceptTokenKey = acceptTokenKey
        self.totalStaking = totalStaking
    }
}

access(all) fun main(): [FarmPoolInfo] {
    let collectionRef = getAccount(0x1b77ba4b414de352).capabilities
        .borrow<&{Staking.PoolCollectionPublic}>(Staking.CollectionPublicPath)
        ?? panic("Could not borrow staking collection")

    let poolCount = collectionRef.getCollectionLength()
    var pools: [FarmPoolInfo] = []
    var i = 0
    while i < poolCount {
        let poolRef = collectionRef.getPool(pid: UInt64(i))
        let poolInfo = poolRef.getPoolInfo()
        if poolInfo.status == "2" { // "2" means RUNNING
            pools.append(FarmPoolInfo(
                pid: poolInfo.pid,
                acceptTokenKey: poolInfo.acceptTokenKey,
                totalStaking: poolInfo.totalStaking
            ))
        }
        i = i + 1
    }
    return pools
}