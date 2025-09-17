
// Transaction to stake LP tokens in a farming pool

import FungibleToken from 0xf233dcee88fe0abe
import Staking from 0x1b77ba4b414de352

transaction(farmPoolId: UInt64, lpTokenAmount: UFix64) {
    
    let userCertificate: &Staking.UserCertificate
    let lpTokenVault: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}
    let stakingCollectionRef: &{Staking.PoolCollectionPublic}
    
    prepare(signer: auth(Storage) &Account) {
        // Get user certificate
        self.userCertificate = signer.storage.borrow<&Staking.UserCertificate>(
            from: Staking.UserCertificateStoragePath
        ) ?? panic("Could not borrow UserCertificate")
        
        // Get staking collection reference
        let stakingAccount = getAccount(0x1b77ba4b414de352)
        self.stakingCollectionRef = stakingAccount.capabilities.borrow<&{Staking.PoolCollectionPublic}>(
            Staking.CollectionPublicPath
        ) ?? panic("Could not borrow staking collection")
        
        // This is a placeholder - in reality, you'd need to determine the correct
        // LP token vault path based on the specific LP token type
        // For now, assuming it's a generic vault path
        self.lpTokenVault = signer.storage.borrow<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(
            from: /storage/lpTokenVault  // This would need to be the actual LP token vault path
        ) ?? panic("Could not borrow LP token vault")
    }
    
    execute {
        // Get the specific pool
        let poolRef = self.stakingCollectionRef.getPool(pid: farmPoolId)
        
        // Withdraw LP tokens to stake
        let lpTokensToStake <- self.lpTokenVault.withdraw(amount: lpTokenAmount)
        
        // Stake the LP tokens
        poolRef.stake(staker: self.userCertificate.owner!.address, stakingToken: <-lpTokensToStake)
        
        log("Successfully staked ".concat(lpTokenAmount.toString()).concat(" LP tokens in pool ").concat(farmPoolId.toString()))
    }
}

// ==========================================

// unstake-from-farm.cdc
// Transaction to unstake LP tokens from a farming pool

import FungibleToken from 0xf233dcee88fe0abe
import Staking from 0x1b77ba4b414de352

transaction(farmPoolId: UInt64, amount: UFix64) {
    
    let userCertificate: &Staking.UserCertificate
    let stakingCollectionRef: &{Staking.PoolCollectionPublic}
    
    prepare(signer: auth(Storage) &Account) {
        // Get user certificate
        self.userCertificate = signer.storage.borrow<&Staking.UserCertificate>(
            from: Staking.UserCertificateStoragePath
        ) ?? panic("Could not borrow UserCertificate")
        
        // Get staking collection reference
        let stakingAccount = getAccount(0x1b77ba4b414de352)
        self.stakingCollectionRef = stakingAccount.capabilities.borrow<&{Staking.PoolCollectionPublic}>(
            Staking.CollectionPublicPath
        ) ?? panic("Could not borrow staking collection")
    }
    
    execute {
        // Get the specific pool
        let poolRef = self.stakingCollectionRef.getPool(pid: farmPoolId)
        
        // Unstake tokens
        let unstakedTokens <- poolRef.unstake(userCertificate: self.userCertificate, amount: amount)
        
        // Store the unstaked tokens back in user's vault
        // This would need to determine the correct vault path based on token type
        let userAccount = self.userCertificate.owner!
        
        // Placeholder - would need to get the correct receiver capability
        // based on the specific LP token type
        let receiverCap = userAccount.capabilities.get<&{FungibleToken.Receiver}>(/public/lpTokenReceiver)
        let receiverRef = receiverCap.borrow() ?? panic("Could not borrow receiver")
        
        receiverRef.deposit(from: <-unstakedTokens)
        
        log("Successfully unstaked ".concat(amount.toString()).concat(" tokens from pool ").concat(farmPoolId.toString()))
    }
}

// ==========================================

// claim-farm-rewards.cdc
// Transaction to claim rewards from a farming pool

import FungibleToken from 0xf233dcee88fe0abe
import Staking from 0x1b77ba4b414de352

transaction(farmPoolId: UInt64) {
    
    let userCertificate: &Staking.UserCertificate
    let stakingCollectionRef: &{Staking.PoolCollectionPublic}
    
    prepare(signer: auth(Storage) &Account) {
        // Get user certificate
        self.userCertificate = signer.storage.borrow<&Staking.UserCertificate>(
            from: Staking.UserCertificateStoragePath
        ) ?? panic("Could not borrow UserCertificate")
        
        // Get staking collection reference
        let stakingAccount = getAccount(0x1b77ba4b414de352)
        self.stakingCollectionRef = stakingAccount.capabilities.borrow<&{Staking.PoolCollectionPublic}>(
            Staking.CollectionPublicPath
        ) ?? panic("Could not borrow staking collection")
    }
    
    execute {
        // Get the specific pool
        let poolRef = self.stakingCollectionRef.getPool(pid: farmPoolId)
        
        // Claim rewards
        let claimedRewards <- poolRef.claimRewards(userCertificate: self.userCertificate)
        
        var totalClaimedValue: UFix64 = 0.0
        
        // Deposit each reward token to user's appropriate vault
        for tokenKey in claimedRewards.keys {
            let rewardVault <- claimedRewards.remove(key: tokenKey)!
            let amount = rewardVault.balance
            totalClaimedValue = totalClaimedValue + amount
            
            // This would need logic to determine the correct receiver path for each token type
            // For now, simplified placeholder
            
            if tokenKey.contains("FlowToken") {
                // Deposit FLOW tokens
                let flowReceiver = self.userCertificate.owner!.capabilities.get<&{FungibleToken.Receiver}>(/public/flowTokenReceiver).borrow()
                    ?? panic("Could not borrow FLOW receiver")
                flowReceiver.deposit(from: <-rewardVault)
            } else if tokenKey.contains("stFlowToken") {
                // Deposit stFLOW tokens
                let stFlowReceiver = self.userCertificate.owner!.capabilities.get<&{FungibleToken.Receiver}>(/public/stFlowTokenReceiver).borrow()
                    ?? panic("Could not borrow stFLOW receiver")
                stFlowReceiver.deposit(from: <-rewardVault)
            } else {
                // For other tokens, would need specific handling
                // For now, just destroy (not recommended in production)
                destroy rewardVault
            }
            
            log("Claimed ".concat(amount.toString()).concat(" of ").concat(tokenKey))
        }
        
        // Destroy empty collection
        destroy claimedRewards
        
        log("Successfully claimed rewards from pool ".concat(farmPoolId.toString()))
    }
}

// ==========================================

// setup-user-certificate.cdc
// Transaction to set up user certificate for farming

import Staking from 0x1b77ba4b414de352

transaction() {
    
    prepare(signer: auth(Storage) &Account) {
        // Check if user certificate already exists
        if signer.storage.borrow<&Staking.UserCertificate>(from: Staking.UserCertificateStoragePath) == nil {
            // Create and store user certificate
            let userCertificate <- Staking.setupUser()
            signer.storage.save(<-userCertificate, to: Staking.UserCertificateStoragePath)
            
            log("User certificate created and stored")
        } else {
            log("User certificate already exists")
        }
    }
    
    execute {
        log("User certificate setup completed")
    }
}

// ==========================================

// batch-farm-operations.cdc
// Transaction to perform multiple farming operations in one transaction

import FungibleToken from 0xf233dcee88fe0abe
import Staking from 0x1b77ba4b414de352

    access(all) let poolId: UInt64
    access(all) let amount: UFix64?
    
    init(operationType: String, poolId: UInt64, amount: UFix64?) {
        self.operationType = operationType
        self.poolId = poolId
        self.amount = amount
    }
}

transaction(operations: [FarmOperation]) {
    
    let userCertificate: &Staking.UserCertificate
    let stakingCollectionRef: &{Staking.PoolCollectionPublic}
    
    prepare(signer: auth(Storage) &Account) {
        // Get user certificate
        self.userCertificate = signer.storage.borrow<&Staking.UserCertificate>(
            from: Staking.UserCertificateStoragePath
        ) ?? panic("Could not borrow UserCertificate")
        
        // Get staking collection reference
        let stakingAccount = getAccount(0x1b77ba4b414de352)
        self.stakingCollectionRef = stakingAccount.capabilities.borrow<&{Staking.PoolCollectionPublic}>(
            Staking.CollectionPublicPath
        ) ?? panic("Could not borrow staking collection")
    }
    
    execute {
        var operationsExecuted = 0
        
        for operation in operations {
            let poolRef = self.stakingCollectionRef.getPool(pid: operation.poolId)
            
            switch operation.operationType {
                case "claim":
                    let rewards <- poolRef.claimRewards(userCertificate: self.userCertificate)
                    // Handle reward distribution (simplified)
                    destroy rewards
                    operationsExecuted = operationsExecuted + 1
                    
                case "unstake":
                    if operation.amount != nil {
                        let unstaked <- poolRef.unstake(
                            userCertificate: self.userCertificate, 
                            amount: operation.amount!
                        )
                        // Handle unstaked tokens (simplified)
                        destroy unstaked
                        operationsExecuted = operationsExecuted + 1
                    }
                    
                case "stake":
                    // Staking would require accessing LP token vaults
                    // This is more complex and depends on token types
                    log("Stake operation requires LP tokens - implement based on specific needs")
                    
                default:
                    log("Unknown operation type: ".concat(operation.operationType))
            }
        }
        
        log("Batch operations completed: ".concat(operationsExecuted.toString()).concat(" operations"))
    }
}

// ==========================================

// get-optimal-pools.cdc
// Script to get optimal farming pools based on criteria

import Staking from 0x1b77ba4b414de352

access(all) struct OptimalPool {
    access(all) let pid: UInt64
    access(all) let acceptTokenKey: String
    access(all) let totalStaking: UFix64
    access(all) let estimatedAPR: UFix64
    access(all) let utilization: UFix64
    access(all) let rewardTokens: [String]
    access(all) let capacity: UFix64
    
    init(
        pid: UInt64,
        acceptTokenKey: String,
        totalStaking: UFix64,
        estimatedAPR: UFix64,
        utilization: UFix64,
        rewardTokens: [String],
        capacity: UFix64
    ) {
        self.pid = pid
        self.acceptTokenKey = acceptTokenKey
        self.totalStaking = totalStaking
        self.estimatedAPR = estimatedAPR
        self.utilization = utilization
        self.rewardTokens = rewardTokens
        self.capacity = capacity
    }
}

access(all) fun main(
    minTVL: UFix64,
    maxUtilization: UFix64,
    minCapacity: UFix64
): [OptimalPool] {
    
    let stakingAccount = getAccount(0x1b77ba4b414de352)
    let collectionRef = stakingAccount.capabilities.borrow<&{Staking.PoolCollectionPublic}>(
        Staking.CollectionPublicPath
    ) ?? panic("Could not borrow staking collection")
    
    let poolCount = collectionRef.getCollectionLength()
    let optimalPools: [OptimalPool] = []
    
    var i = 0
    while i < poolCount {
        let poolRef = collectionRef.getPool(pid: UInt64(i))
        let poolInfo = poolRef.getPoolInfo()
        
        // Only include active pools
        if poolInfo.status == "2" {  // RUNNING status
            let utilization = (poolInfo.totalStaking / poolInfo.limitAmount) * 100.0
            let capacity = poolInfo.limitAmount - poolInfo.totalStaking
            
            // Apply filters
            if poolInfo.totalStaking >= minTVL && 
               utilization <= maxUtilization && 
               capacity >= minCapacity {
                
                let rewardInfo = poolRef.getRewardInfo()
                let rewardTokens: [String] = []
                var totalRPS: UFix64 = 0.0
                
                for tokenKey in rewardInfo.keys {
                    rewardTokens.append(tokenKey)
                    totalRPS = totalRPS + rewardInfo[tokenKey]!.rewardPerSeed
                }
                
                // Simple APR estimation (would need token prices for accuracy)
                let estimatedAPR = totalRPS * 365.0 * 24.0 * 60.0 * 60.0 * 100.0
                
                let optimalPool = OptimalPool(
                    pid: poolInfo.pid,
                    acceptTokenKey: poolInfo.acceptTokenKey,
                    totalStaking: poolInfo.totalStaking,
                    estimatedAPR: estimatedAPR,
                    utilization: utilization,
                    rewardTokens: rewardTokens,
                    capacity: capacity
                )
                
                optimalPools.append(optimalPool)
            }
        }
        
        i = i + 1
    }
    
    return optimalPools
}

// ==========================================

// add-liquidity-and-stake.cdc
// Transaction to add liquidity to a pair and stake the LP tokens in one go

import FungibleToken from 0xf233dcee88fe0abe
import FlowToken from 0x1654653399040a61
import SwapRouter from 0xa6850776a94e6551
import Staking from 0x1b77ba4b414de352

transaction(
    token0Amount: UFix64,
    token1Amount: UFix64,
    minToken0Amount: UFix64,
    minToken1Amount: UFix64,
    farmPoolId: UInt64,
    deadline: UFix64
) {
    
    let userCertificate: &Staking.UserCertificate
    let stakingCollectionRef: &{Staking.PoolCollectionPublic}
    let flowVault: auth(FungibleToken.Withdraw) &FlowToken.Vault
    
    prepare(signer: auth(Storage) &Account) {
        // Get user certificate
        self.userCertificate = signer.storage.borrow<&Staking.UserCertificate>(
            from: Staking.UserCertificateStoragePath
        ) ?? panic("Could not borrow UserCertificate")
        
        // Get staking collection reference
        let stakingAccount = getAccount(0x1b77ba4b414de352)
        self.stakingCollectionRef = stakingAccount.capabilities.borrow<&{Staking.PoolCollectionPublic}>(
            Staking.CollectionPublicPath
        ) ?? panic("Could not borrow staking collection")
        
        // Get Flow vault
        self.flowVault = signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
            from: /storage/flowTokenVault
        ) ?? panic("Could not borrow FlowToken vault")
        
        // Verify deadline
        assert(getCurrentBlock().timestamp <= deadline, message: "Transaction deadline exceeded")
    }
    
    execute {
        // This is a simplified version - in reality, you'd need to:
        // 1. Determine which tokens are needed for the LP pair
        // 2. Add liquidity to the correct pair
        // 3. Receive LP tokens
        // 4. Stake those LP tokens in the farm
        
        // For now, this is a template that would need to be customized
        // based on the specific token pair and LP requirements
        
        log("Add liquidity and stake operation template - needs customization for specific pairs")
        
        // Placeholder for actual implementation:
        // let lpTokens <- SwapRouter.addLiquidity(...)
        // poolRef.stake(staker: signer.address, stakingToken: <-lpTokens)
    }
}