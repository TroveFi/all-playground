// cadence/scripts/check_specific_pool.cdc  
import Staking from 0x1b77ba4b414de352

access(all) struct SpecificPoolInfo {
    access(all) let pid: UInt64
    access(all) let status: String
    access(all) let acceptTokenKey: String
    access(all) let totalStaking: UFix64
    access(all) let limitAmount: UFix64
    access(all) let capacity: UFix64
    access(all) let rewardTokenKeys: [String]
    access(all) let canStakeReason: String
    
    init(pid: UInt64, status: String, acceptTokenKey: String, totalStaking: UFix64, 
         limitAmount: UFix64, capacity: UFix64, rewardTokenKeys: [String], canStakeReason: String) {
        self.pid = pid
        self.status = status
        self.acceptTokenKey = acceptTokenKey
        self.totalStaking = totalStaking
        self.limitAmount = limitAmount
        self.capacity = capacity
        self.rewardTokenKeys = rewardTokenKeys
        self.canStakeReason = canStakeReason
    }
}

access(all) fun main(poolId: UInt64): SpecificPoolInfo {
    let stakingAccount = getAccount(0x1b77ba4b414de352)
    let collectionRef = stakingAccount.capabilities.borrow<&{Staking.PoolCollectionPublic}>(
        Staking.CollectionPublicPath
    ) ?? panic("Could not borrow staking collection")
    
    let poolRef = collectionRef.getPool(pid: poolId)
    let poolInfo = poolRef.getPoolInfo()
    let rewardInfo = poolRef.getRewardInfo()
    
    let capacity = poolInfo.limitAmount - poolInfo.totalStaking
    let rewardTokenKeys: [String] = rewardInfo.keys
    
    var canStakeReason = "Pool can accept staking"
    
    if poolInfo.status != "2" {
        canStakeReason = "Pool status is not RUNNING (status: ".concat(poolInfo.status).concat(")")
    } else if capacity <= 0.0 {
        canStakeReason = "Pool has no remaining capacity (limit reached)"
    } else if poolInfo.limitAmount == 0.0 {
        canStakeReason = "Pool has no limit set (limitAmount is 0)"
    } else if rewardTokenKeys.length == 0 {
        canStakeReason = "Pool has no reward tokens configured"
    }
    
    return SpecificPoolInfo(
        pid: poolInfo.pid,
        status: poolInfo.status,
        acceptTokenKey: poolInfo.acceptTokenKey,
        totalStaking: poolInfo.totalStaking,
        limitAmount: poolInfo.limitAmount,
        capacity: capacity,
        rewardTokenKeys: rewardTokenKeys,
        canStakeReason: canStakeReason
    )
}