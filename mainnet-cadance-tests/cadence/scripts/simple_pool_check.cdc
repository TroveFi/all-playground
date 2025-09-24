// cadence/scripts/simple_pool_check.cdc
import Staking from 0x1b77ba4b414de352

access(all) struct SimplePoolInfo {
    access(all) let pid: UInt64
    access(all) let status: String
    access(all) let totalStaking: UFix64
    access(all) let limitAmount: UFix64
    access(all) let acceptTokenKey: String
    
    init(pid: UInt64, status: String, totalStaking: UFix64, limitAmount: UFix64, acceptTokenKey: String) {
        self.pid = pid
        self.status = status
        self.totalStaking = totalStaking
        self.limitAmount = limitAmount
        self.acceptTokenKey = acceptTokenKey
    }
}

access(all) fun main(poolId: UInt64): SimplePoolInfo? {
    let stakingAccount = getAccount(0x1b77ba4b414de352)
    let collectionRef = stakingAccount.capabilities.borrow<&{Staking.PoolCollectionPublic}>(
        Staking.CollectionPublicPath
    ) ?? panic("Could not borrow staking collection")
    
    let poolRef = collectionRef.getPool(pid: poolId)
    let poolInfo = poolRef.getPoolInfo()
    
    return SimplePoolInfo(
        pid: poolInfo.pid,
        status: poolInfo.status,
        totalStaking: poolInfo.totalStaking,
        limitAmount: poolInfo.limitAmount,
        acceptTokenKey: poolInfo.acceptTokenKey
    )
}