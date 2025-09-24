// cadence/scripts/check_staking_eligibility.cdc
import Staking from 0x1b77ba4b414de352

access(all) struct StakingEligibility {
    access(all) let poolId: UInt64
    access(all) let isEligible: Bool
    access(all) let reason: String
    access(all) let currentTime: UFix64
    access(all) let startTime: UFix64
    access(all) let endTime: UFix64
    access(all) let remainingCapacity: UFix64
    
    init(poolId: UInt64, isEligible: Bool, reason: String, currentTime: UFix64, 
         startTime: UFix64, endTime: UFix64, remainingCapacity: UFix64) {
        self.poolId = poolId
        self.isEligible = isEligible
        self.reason = reason
        self.currentTime = currentTime
        self.startTime = startTime
        self.endTime = endTime
        self.remainingCapacity = remainingCapacity
    }
}

access(all) fun main(poolId: UInt64): StakingEligibility {
    let stakingAccount = getAccount(0x1b77ba4b414de352)
    let collectionRef = stakingAccount.capabilities.borrow<&{Staking.PoolCollectionPublic}>(
        Staking.CollectionPublicPath
    ) ?? panic("Could not borrow staking collection")
    
    let poolRef = collectionRef.getPool(pid: poolId)
    let poolInfo = poolRef.getPoolInfo()
    let currentTime = getCurrentBlock().timestamp
    
    var isEligible = true
    var reason = "Pool is eligible for staking"
    
    let remainingCapacity = poolInfo.limitAmount - poolInfo.totalStaking
    
    if poolInfo.status != "2" {
        isEligible = false
        reason = "Pool is not running (status: ".concat(poolInfo.status).concat(")")
    } else if currentTime < poolInfo.startTime {
        isEligible = false
        reason = "Staking has not started yet"
    } else if currentTime > poolInfo.endTime {
        isEligible = false
        reason = "Staking period has ended"
    } else if remainingCapacity <= 0.0 {
        isEligible = false
        reason = "Pool has reached maximum capacity"
    }
    
    return StakingEligibility(
        poolId: poolId,
        isEligible: isEligible,
        reason: reason,
        currentTime: currentTime,
        startTime: poolInfo.startTime,
        endTime: poolInfo.endTime,
        remainingCapacity: remainingCapacity
    )
}