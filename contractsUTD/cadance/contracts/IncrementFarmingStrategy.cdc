import FungibleToken from 0xf233dcee88fe0abe
import FlowToken from 0x1654653399040a61
import stFlowToken from 0xd6f80565193ad727
import Staking from 0x1b77ba4b414de352

/// Increment Fi LP farming strategy
/// Stake LP tokens in farming pools to earn rewards
access(all) contract IncrementFarmingStrategy {
    
    // ====================================================================
    // EVENTS
    // ====================================================================
    access(all) event FarmDeposited(poolId: UInt64, amount: UFix64, tokenKey: String)
    access(all) event FarmWithdrawn(poolId: UInt64, amount: UFix64)
    access(all) event RewardsClaimed(poolId: UInt64, rewards: {String: UFix64})
    access(all) event StrategyExecuted(poolId: UInt64, amount: UFix64)
    
    // ====================================================================
    // STATE
    // ====================================================================
    access(self) var totalDeposited: {UInt64: UFix64}
    access(self) var totalRewardsClaimed: {String: UFix64}
    
    // ====================================================================
    // STRATEGY RESOURCE
    // ====================================================================
    access(all) resource Strategy {
        access(self) let flowVault: @FlowToken.Vault
        access(self) let stFlowVault: @stFlowToken.Vault
        access(self) let activePositions: {UInt64: Bool}
        access(self) let userCertificate: @Staking.UserCertificate
        
        init() {
            self.flowVault <- FlowToken.createEmptyVault(vaultType: Type<@FlowToken.Vault>()) as! @FlowToken.Vault
            self.stFlowVault <- stFlowToken.createEmptyVault(vaultType: Type<@stFlowToken.Vault>()) as! @stFlowToken.Vault
            self.activePositions = {}
            self.userCertificate <- Staking.setupUser()
        }
        
        /// Execute farming: deposit into specified pool
        access(all) fun executeStrategy(poolId: UInt64, from: @{FungibleToken.Vault}): Bool {
            pre {
                from.balance > 0.0: "Cannot deposit zero"
            }
            
            let amount = from.balance
            
            // Get staking pool collection
            let stakingCollection = getAccount(0x1b77ba4b414de352)
                .capabilities
                .borrow<&{Staking.PoolCollectionPublic}>(Staking.CollectionPublicPath)
                ?? panic("Cannot access staking collection")
            
            // Get specific pool
            let poolRef = stakingCollection.getPool(pid: poolId)
            let poolInfo = poolRef.getPoolInfo()
            
            // Verify pool is active (status "1" = RUNNING)
            assert(poolInfo.status == "1", message: "Pool is not active")
            
            // Stake tokens - signature: stake(staker: Address, stakingToken: @{FungibleToken.Vault})
            poolRef.stake(staker: self.owner!.address, stakingToken: <-from)
            
            // Track position
            self.activePositions[poolId] = true
            
            if IncrementFarmingStrategy.totalDeposited[poolId] == nil {
                IncrementFarmingStrategy.totalDeposited[poolId] = 0.0
            }
            IncrementFarmingStrategy.totalDeposited[poolId] = IncrementFarmingStrategy.totalDeposited[poolId]! + amount
            
            emit FarmDeposited(poolId: poolId, amount: amount, tokenKey: poolInfo.acceptTokenKey)
            emit StrategyExecuted(poolId: poolId, amount: amount)
            
            return true
        }
        
        /// Harvest rewards from a farming pool
        access(all) fun harvestPool(poolId: UInt64): @{String: {FungibleToken.Vault}} {
            pre {
                self.activePositions[poolId] ?? false: "No active position in this pool"
            }
            
            let stakingCollection = getAccount(0x1b77ba4b414de352)
                .capabilities
                .borrow<&{Staking.PoolCollectionPublic}>(Staking.CollectionPublicPath)
                ?? panic("Cannot access staking collection")
            
            let poolRef = stakingCollection.getPool(pid: poolId)
            
            // Get user info to see unclaimed rewards
            let userInfo = poolRef.getUserInfo(address: self.owner!.address)
            
            if userInfo != nil {
                let unclaimedRewards = userInfo!.unclaimedRewards
                
                // Claim rewards - signature: claimRewards(userCertificate: &{IdentityCertificate})
                let rewardVaults <- poolRef.claimRewards(
                    userCertificate: &self.userCertificate as &{Staking.IdentityCertificate}
                )
                
                // Track claimed rewards
                for tokenKey in unclaimedRewards.keys {
                    let rewardAmount = unclaimedRewards[tokenKey]!
                    
                    if IncrementFarmingStrategy.totalRewardsClaimed[tokenKey] == nil {
                        IncrementFarmingStrategy.totalRewardsClaimed[tokenKey] = 0.0
                    }
                    IncrementFarmingStrategy.totalRewardsClaimed[tokenKey] = 
                        IncrementFarmingStrategy.totalRewardsClaimed[tokenKey]! + rewardAmount
                }
                
                emit RewardsClaimed(poolId: poolId, rewards: unclaimedRewards)
                
                return <- rewardVaults
            } else {
                // Return empty dictionary if no user info
                let emptyVaults: @{String: {FungibleToken.Vault}} <- {}
                return <- emptyVaults
            }
        }
        
        /// Harvest all active positions
        access(all) fun harvestAll(): @{String: {FungibleToken.Vault}} {
            var allRewards: @{String: {FungibleToken.Vault}} <- {}
            
            for poolId in self.activePositions.keys {
                if self.activePositions[poolId]! {
                    let harvested <- self.harvestPool(poolId: poolId)
                    
                    // Merge harvested vaults into allRewards
                    for tokenKey in harvested.keys {
                        let rewardVault <- harvested.remove(key: tokenKey)!
                        
                        if allRewards.containsKey(tokenKey) {
                            let existingVault = &allRewards[tokenKey] as &{FungibleToken.Vault}?
                            existingVault!.deposit(from: <-rewardVault)
                        } else {
                            allRewards[tokenKey] <-! rewardVault
                        }
                    }
                    
                    destroy harvested
                }
            }
            
            return <- allRewards
        }
        
        /// Withdraw from a farming pool
        access(all) fun withdrawFromPool(poolId: UInt64, amount: UFix64): @{FungibleToken.Vault} {
            pre {
                self.activePositions[poolId] ?? false: "No active position in this pool"
                amount > 0.0: "Amount must be positive"
            }
            
            let stakingCollection = getAccount(0x1b77ba4b414de352)
                .capabilities
                .borrow<&{Staking.PoolCollectionPublic}>(Staking.CollectionPublicPath)
                ?? panic("Cannot access staking collection")
            
            let poolRef = stakingCollection.getPool(pid: poolId)
            
            // Unstake tokens - signature: unstake(userCertificate: &{IdentityCertificate}, amount: UFix64)
            let withdrawnVault <- poolRef.unstake(
                userCertificate: &self.userCertificate as &{Staking.IdentityCertificate},
                amount: amount
            )
            
            IncrementFarmingStrategy.totalDeposited[poolId] = IncrementFarmingStrategy.totalDeposited[poolId]! - amount
            
            if IncrementFarmingStrategy.totalDeposited[poolId]! <= 0.0 {
                self.activePositions[poolId] = false
            }
            
            emit FarmWithdrawn(poolId: poolId, amount: amount)
            
            return <- withdrawnVault
        }
        
        /// Emergency exit - withdraw all from all pools
        access(all) fun emergencyExit(): @{String: {FungibleToken.Vault}} {
            var allWithdrawn: @{String: {FungibleToken.Vault}} <- {}
            
            let stakingCollection = getAccount(0x1b77ba4b414de352)
                .capabilities
                .borrow<&{Staking.PoolCollectionPublic}>(Staking.CollectionPublicPath)
                ?? panic("Cannot access staking collection")
            
            for poolId in self.activePositions.keys {
                if self.activePositions[poolId]! {
                    let poolRef = stakingCollection.getPool(pid: poolId)
                    let userInfo = poolRef.getUserInfo(address: self.owner!.address)
                    
                    if userInfo != nil && userInfo!.stakingAmount > 0.0 {
                        let withdrawn <- poolRef.unstake(
                            userCertificate: &self.userCertificate as &{Staking.IdentityCertificate},
                            amount: userInfo!.stakingAmount
                        )
                        
                        let tokenKey = poolRef.getPoolInfo().acceptTokenKey
                        
                        if allWithdrawn.containsKey(tokenKey) {
                            let existingVault = &allWithdrawn[tokenKey] as &{FungibleToken.Vault}?
                            existingVault!.deposit(from: <-withdrawn)
                        } else {
                            allWithdrawn[tokenKey] <-! withdrawn
                        }
                        
                        self.activePositions[poolId] = false
                    }
                }
            }
            
            return <- allWithdrawn
        }
        
        /// Get positions info
        access(all) fun getPositions(): {UInt64: {String: UFix64}} {
            let positions: {UInt64: {String: UFix64}} = {}
            
            let stakingCollection = getAccount(0x1b77ba4b414de352)
                .capabilities
                .borrow<&{Staking.PoolCollectionPublic}>(Staking.CollectionPublicPath)
                ?? panic("Cannot access staking collection")
            
            for poolId in self.activePositions.keys {
                if self.activePositions[poolId]! {
                    let poolRef = stakingCollection.getPool(pid: poolId)
                    let userInfo = poolRef.getUserInfo(address: self.owner!.address)
                    
                    if userInfo != nil {
                        positions[poolId] = {
                            "stakingAmount": userInfo!.stakingAmount,
                            "isBlocked": userInfo!.isBlocked ? 1.0 : 0.0
                        }
                    }
                }
            }
            
            return positions
        }
        
        access(all) fun getBalances(): {String: UFix64} {
            return {
                "flow": self.flowVault.balance,
                "stflow": self.stFlowVault.balance
            }
        }
    }
    
    // ====================================================================
    // CONTRACT FUNCTIONS
    // ====================================================================
    access(all) fun createStrategy(): @Strategy {
        return <- create Strategy()
    }
    
    access(all) fun getMetrics(): {String: AnyStruct} {
        return {
            "totalDepositedByPool": self.totalDeposited,
            "totalRewardsClaimed": self.totalRewardsClaimed
        }
    }
    
    /// Query available farming pools
    access(all) fun getActivePools(): [{String: AnyStruct}] {
        let pools: [{String: AnyStruct}] = []
        
        let stakingCollection = getAccount(0x1b77ba4b414de352)
            .capabilities
            .borrow<&{Staking.PoolCollectionPublic}>(Staking.CollectionPublicPath)
        
        if stakingCollection != nil {
            let poolCount = stakingCollection!.getCollectionLength()
            var i: UInt64 = 0
            
            while i < UInt64(poolCount) && i < 20 {
                let poolRef = stakingCollection!.getPool(pid: i)
                let poolInfo = poolRef.getPoolInfo()
                
                if poolInfo.status == "1" {
                    pools.append({
                        "pid": poolInfo.pid,
                        "acceptTokenKey": poolInfo.acceptTokenKey,
                        "totalStaking": poolInfo.totalStaking,
                        "limitAmount": poolInfo.limitAmount,
                        "status": poolInfo.status
                    })
                }
                
                i = i + 1
            }
        }
        
        return pools
    }
    
    // ====================================================================
    // INITIALIZATION
    // ====================================================================
    init() {
        self.totalDeposited = {}
        self.totalRewardsClaimed = {}
    }
}