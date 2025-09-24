// cadence/scripts/get_vault_status.cdc
import IncrementVault from 0x__CONTRACT_ADDRESS__

access(all) fun main(userAddress: Address): {String: AnyStruct}? {
    let account = getAccount(userAddress)
    
    if let vaultRef = account.capabilities.borrow<&{IncrementVault.VaultPublic}>(
        IncrementVault.VaultPublicPath
    ) {
        let balances = vaultRef.getBalances()
        let positions = vaultRef.getPositions()
        let stats = vaultRef.getTotalStats()
        let coaAddress = vaultRef.getCOAAddress()
        
        return {
            "balances": balances,
            "positions": positions,
            "stats": stats,
            "coaAddress": coaAddress,
            "hasVault": true
        }
    }
    
    return {"hasVault": false}
}

// =====================================

// cadence/scripts/get_vault_positions.cdc
import IncrementVault from 0x__CONTRACT_ADDRESS__

access(all) fun main(userAddress: Address): [IncrementVault.Position] {
    let account = getAccount(userAddress)
    
    if let vaultRef = account.capabilities.borrow<&{IncrementVault.VaultPublic}>(
        IncrementVault.VaultPublicPath
    ) {
        return vaultRef.getPositions()
    }
    
    return []
}

// =====================================

// cadence/scripts/estimate_lp_rewards.cdc
import Staking from 0x1b77ba4b414de352

access(all) struct RewardEstimate {
    access(all) let poolId: UInt64
    access(all) let stakingAmount: UFix64
    access(all) let pendingRewards: {String: UFix64}
    access(all) let rewardTokenKeys: [String]
    access(all) let poolStatus: String
    
    init(poolId: UInt64, stakingAmount: UFix64, pendingRewards: {String: UFix64}, 
         rewardTokenKeys: [String], poolStatus: String) {
        self.poolId = poolId
        self.stakingAmount = stakingAmount
        self.pendingRewards = pendingRewards
        self.rewardTokenKeys = rewardTokenKeys
        self.poolStatus = poolStatus
    }
}

access(all) fun main(userAddress: Address): [RewardEstimate] {
    let stakingIds = Staking.getUserStakingIds(address: userAddress)
    let results: [RewardEstimate] = []
    
    if stakingIds.length == 0 { 
        return results 
    }

    let collectionRef = getAccount(0x1b77ba4b414de352).capabilities
        .borrow<&{Staking.PoolCollectionPublic}>(Staking.CollectionPublicPath)
        ?? panic("Could not borrow staking collection")

    for poolId in stakingIds {
        let poolRef = collectionRef.getPool(pid: poolId)
        let poolInfo = poolRef.getPoolInfo()
        
        if let userInfo = poolRef.getUserInfo(address: userAddress) {
            if userInfo.stakingAmount > 0.0 {
                let rewardInfo = poolRef.getRewardInfo()
                var pendingRewards: {String: UFix64} = {}
                
                // Calculate pending rewards (simplified)
                for tokenKey in rewardInfo.keys {
                    pendingRewards[tokenKey] = userInfo.stakingAmount * 0.001 // Placeholder calculation
                }
                
                results.append(RewardEstimate(
                    poolId: poolId,
                    stakingAmount: userInfo.stakingAmount,
                    pendingRewards: pendingRewards,
                    rewardTokenKeys: rewardInfo.keys,
                    poolStatus: poolInfo.status
                ))
            }
        }
    }
    
    return results
}

// =====================================

// cadence/scripts/get_increment_pool_info.cdc
import Staking from 0x1b77ba4b414de352

access(all) struct PoolDetails {
    access(all) let pid: UInt64
    access(all) let status: String
    access(all) let acceptTokenKey: String
    access(all) let totalStaking: UFix64
    access(all) let limitAmount: UFix64
    access(all) let capacity: UFix64
    access(all) let rewardTokens: [String]
    access(all) let apr: UFix64? // Estimated APR
    
    init(pid: UInt64, status: String, acceptTokenKey: String, totalStaking: UFix64,
         limitAmount: UFix64, capacity: UFix64, rewardTokens: [String], apr: UFix64?) {
        self.pid = pid
        self.status = status
        self.acceptTokenKey = acceptTokenKey
        self.totalStaking = totalStaking
        self.limitAmount = limitAmount
        self.capacity = capacity
        self.rewardTokens = rewardTokens
        self.apr = apr
    }
}

access(all) fun main(): [PoolDetails] {
    let collectionRef = getAccount(0x1b77ba4b414de352).capabilities
        .borrow<&{Staking.PoolCollectionPublic}>(Staking.CollectionPublicPath)
        ?? panic("Could not borrow staking collection")
    
    let activePoolIds: [UInt64] = [204, 205, 206, 20, 14, 6] // Known active pools
    let results: [PoolDetails] = []
    
    for poolId in activePoolIds {
        let poolRef = collectionRef.getPool(pid: poolId)
        let poolInfo = poolRef.getPoolInfo()
        let rewardInfo = poolRef.getRewardInfo()
        
        // Only include active pools
        if poolInfo.status == "2" { // Running status
            let capacity = poolInfo.limitAmount > poolInfo.totalStaking 
                ? poolInfo.limitAmount - poolInfo.totalStaking 
                : 0.0
            
            // Rough APR estimation (would need more complex calculation in reality)
            var estimatedAPR: UFix64? = nil
            if poolInfo.totalStaking > 0.0 && rewardInfo.keys.length > 0 {
                estimatedAPR = 15.0 // Placeholder - would calculate from reward rates
            }
            
            results.append(PoolDetails(
                pid: poolInfo.pid,
                status: poolInfo.status,
                acceptTokenKey: poolInfo.acceptTokenKey,
                totalStaking: poolInfo.totalStaking,
                limitAmount: poolInfo.limitAmount,
                capacity: capacity,
                rewardTokens: rewardInfo.keys,
                apr: estimatedAPR
            ))
        }
    }
    
    return results
}