// cadence/scripts/get_all_pool_types.cdc
import Staking from 0x1b77ba4b414de352

access(all) struct PoolType {
    access(all) let pid: UInt64
    access(all) let acceptTokenKey: String
    access(all) let totalStaking: UFix64
    access(all) let poolCategory: String  // "LP" or "SINGLE"
    access(all) let tokenPair: String     // "FLOW-stFlow", "LOPPY-SINGLE", etc.
    access(all) let status: String
    access(all) let isActive: Bool
    
    init(
        pid: UInt64,
        acceptTokenKey: String,
        totalStaking: UFix64,
        poolCategory: String,
        tokenPair: String,
        status: String,
        isActive: Bool
    ) {
        self.pid = pid
        self.acceptTokenKey = acceptTokenKey
        self.totalStaking = totalStaking
        self.poolCategory = poolCategory
        self.tokenPair = tokenPair
        self.status = status
        self.isActive = isActive
    }
}

// Function to categorize pools based on accept token key
access(all) fun categorizePool(acceptTokenKey: String): {String: String} {
    let result: {String: String} = {}
    
    // Check for LP tokens (SwapPair contracts)
    if acceptTokenKey.contains("SwapPair") {
        result["category"] = "LP"
        
        // Known LP pairs
        if acceptTokenKey.contains("396c0cda3302d8c5") {
            result["pair"] = "FLOW-stFlow"
        } else if acceptTokenKey.contains("fa82796435e15832") {
            result["pair"] = "FLOW-USDC"
        } else if acceptTokenKey.contains("6155398610a02093") {
            result["pair"] = "SDM-FLOW"
        } else {
            result["pair"] = "UNKNOWN-LP"
        }
    } else {
        result["category"] = "SINGLE"
        
        // Single token staking
        if acceptTokenKey.contains("stFlowToken") {
            result["pair"] = "stFlow-SINGLE"
        } else if acceptTokenKey.contains("FlowToken") {
            result["pair"] = "FLOW-SINGLE"
        } else if acceptTokenKey.contains("LOPPY") {
            result["pair"] = "LOPPY-SINGLE"
        } else if acceptTokenKey.contains("MVP") {
            result["pair"] = "MVP-SINGLE"
        } else {
            result["pair"] = "UNKNOWN-SINGLE"
        }
    }
    
    return result
}

access(all) fun main(): [PoolType] {
    let stakingAccount = getAccount(0x1b77ba4b414de352)
    let collectionRef = stakingAccount.capabilities.borrow<&{Staking.PoolCollectionPublic}>(
        Staking.CollectionPublicPath
    ) ?? panic("Could not borrow staking collection")
    
    let poolCount = collectionRef.getCollectionLength()
    let allPools: [PoolType] = []
    let currentTime = getCurrentBlock().timestamp
    
    var i = 0
    while i < poolCount {
        let poolRef = collectionRef.getPool(pid: UInt64(i))
        let poolInfo = poolRef.getPoolInfo()
        
        // Categorize the pool
        let poolCategory = categorizePool(acceptTokenKey: poolInfo.acceptTokenKey)
        
        // Check if pool is active
        let isActive = poolInfo.status == "2" && 
                      currentTime >= poolInfo.startTime && 
                      currentTime <= poolInfo.endTime
        
        let poolType = PoolType(
            pid: poolInfo.pid,
            acceptTokenKey: poolInfo.acceptTokenKey,
            totalStaking: poolInfo.totalStaking,
            poolCategory: poolCategory["category"] ?? "UNKNOWN",
            tokenPair: poolCategory["pair"] ?? "UNKNOWN",
            status: poolInfo.status,
            isActive: isActive
        )
        
        allPools.append(poolType)
        i = i + 1
    }
    
    return allPools
}