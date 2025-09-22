import IncrementFiStakingConnectors from 0x49bae091e5ea16b5

// Script to check available rewards for a staker in a specific pool
access(all) fun main(staker: Address, pid: UInt64): {String: AnyStruct} {
    log("Checking rewards for address: ".concat(staker.toString()))
    log("Pool ID: ".concat(pid.toString()))
    
    // Borrow the pool using the helper function from the contract
    let pool = IncrementFiStakingConnectors.borrowPool(pid: pid)
    
    if pool == nil {
        log("Pool not found or not accessible")
        return {
            "poolID": pid,
            "staker": staker.toString(),
            "error": "Pool not found or not accessible",
            "unclaimedRewards": {} as {String: UFix64},
            "stakingAmount": 0.0
        }
    }
    
    // Get user info from the pool
    let userInfo = pool!.getUserInfo(address: staker)
    
    if userInfo == nil {
        log("User has no staking position in this pool")
        return {
            "poolID": pid,
            "staker": staker.toString(),
            "unclaimedRewards": {} as {String: UFix64},
            "stakingAmount": 0.0,
            "message": "No staking position found"
        }
    }
    
    let result: {String: AnyStruct} = {
        "poolID": pid,
        "staker": staker.toString(),
        "stakingAmount": userInfo!.stakingAmount,
        "unclaimedRewards": userInfo!.unclaimedRewards,
        "timestamp": getCurrentBlock().timestamp
    }
    
    log("Staking amount: ".concat(userInfo!.stakingAmount.toString()))
    log("Unclaimed rewards: ".concat(userInfo!.unclaimedRewards.keys.length.toString()).concat(" token types"))
    
    return result
}