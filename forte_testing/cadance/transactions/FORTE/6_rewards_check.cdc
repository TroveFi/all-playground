import IncrementFiStakingConnectors from 0x49bae091e5ea16b5

// Script to check available rewards for a staker in a specific pool
access(all) fun main(staker: Address, pid: UInt64): UFix64 {
    log("Checking rewards for address: ".concat(staker.toString()))
    log("Pool ID: ".concat(pid.toString()))
    
    // Get rewards using the connector
    let rewards = IncrementFiStakingConnectors.getAvailableRewards(
        address: staker,
        pid: pid
    )
    
    log("Available rewards: ".concat(rewards.toString()))
    
    return rewards
}