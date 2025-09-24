// cadence/contracts/AutoYieldVault.cdc
import FungibleToken from 0xf233dcee88fe0abe
import FlowToken from 0x1654653399040a61
import stFlowToken from 0xd6f80565193ad727
import Staking from 0x1b77ba4b414de352

// DEX Contracts for LP farming
import SwapRouter from 0xa6850776a94e6551
import SwapFactory from 0xb063c16cac85dbd1
import SwapInterfaces from 0xb78ef7afa52ff906
import SwapConfig from 0xb78ef7afa52ff906

access(all) contract AutoYieldVault {
    
    // Storage paths
    access(all) let VaultStoragePath: StoragePath
    access(all) let VaultPublicPath: PublicPath
    access(all) let VaultPrivatePath: PrivatePath

    // Events
    access(all) event FundsDeposited(amount: UFix64, strategy: String)
    access(all) event FundsWithdrawn(amount: UFix64, recipient: Address)
    access(all) event LPTokensCreated(flowAmount: UFix64, stFlowAmount: UFix64, lpAmount: UFix64)
    access(all) event StakedInPool(poolId: UInt64, amount: UFix64)
    access(all) event RewardsClaimed(poolId: UInt64, rewards: {String: UFix64})
    access(all) event StrategyExecuted(strategy: String, amount: UFix64)

    // Strategy enum
    access(all) enum Strategy: UInt8 {
        access(all) case FlowStFlowLP      // Create FLOW-stFlow LP and stake
        access(all) case StFlowStaking     // Direct stFlow staking
        access(all) case OptimalYield      // AI-selected optimal strategy
    }

    // User position tracking
    access(all) struct UserPosition {
        access(all) let owner: Address
        access(all) var totalDeposited: UFix64
        access(all) var currentBalance: UFix64
        access(all) var activeStrategies: {Strategy: UFix64}
        access(all) var stakingPositions: {UInt64: UFix64}  // poolId -> amount
        access(all) var lastActivity: UFix64
        access(all) var totalYieldEarned: UFix64

        init(owner: Address) {
            self.owner = owner
            self.totalDeposited = 0.0
            self.currentBalance = 0.0
            self.activeStrategies = {}
            self.stakingPositions = {}
            self.lastActivity = getCurrentBlock().timestamp
            self.totalYieldEarned = 0.0
        }

        access(contract) fun addDeposit(amount: UFix64) {
            self.totalDeposited = self.totalDeposited + amount
            self.currentBalance = self.currentBalance + amount
            self.lastActivity = getCurrentBlock().timestamp
        }

        access(contract) fun recordWithdrawal(amount: UFix64) {
            self.currentBalance = self.currentBalance - amount
            self.lastActivity = getCurrentBlock().timestamp
        }

        access(contract) fun updateStrategy(strategy: Strategy, amount: UFix64) {
            if self.activeStrategies[strategy] == nil {
                self.activeStrategies[strategy] = amount
            } else {
                self.activeStrategies[strategy] = self.activeStrategies[strategy]! + amount
            }
        }

        access(contract) fun recordStaking(poolId: UInt64, amount: UFix64) {
            self.stakingPositions[poolId] = amount
        }

        access(contract) fun addYield(amount: UFix64) {
            self.totalYieldEarned = self.totalYieldEarned + amount
            self.currentBalance = self.currentBalance + amount
        }
    }

    // Vault resource
    access(all) resource Vault {
        access(self) var flowVault: @FlowToken.Vault
        access(self) var stFlowVault: @stFlowToken.Vault
        access(self) var userPositions: {Address: UserPosition}
        access(self) var totalValueLocked: UFix64
        access(self) var userCertificate: @Staking.UserCertificate

        init() {
            self.flowVault <- FlowToken.createEmptyVault(vaultType: Type<@FlowToken.Vault>())
            self.stFlowVault <- stFlowToken.createEmptyVault(vaultType: Type<@stFlowToken.Vault>())
            self.userPositions = {}
            self.totalValueLocked = 0.0
            self.userCertificate <- Staking.createUserCertificate()
        }

        // Deposit function - automatically executes yield strategy
        access(all) fun deposit(
            flowVault: @FlowToken.Vault, 
            strategy: Strategy, 
            owner: Address
        ) {
            let amount = flowVault.balance
            require(amount > 0.0, message: "Deposit amount must be greater than 0")

            // Update user position
            if self.userPositions[owner] == nil {
                self.userPositions[owner] = UserPosition(owner: owner)
            }
            self.userPositions[owner]!.addDeposit(amount: amount)

            // Store the FLOW temporarily
            self.flowVault.deposit(from: <-flowVault)
            self.totalValueLocked = self.totalValueLocked + amount

            emit FundsDeposited(amount: amount, strategy: strategy.rawValue.toString())

            // Execute the selected strategy
            self.executeStrategy(strategy: strategy, amount: amount, owner: owner)
        }

        // Execute yield farming strategy
        access(self) fun executeStrategy(strategy: Strategy, amount: UFix64, owner: Address) {
            switch strategy {
                case Strategy.FlowStFlowLP:
                    self.executeFlowStFlowLP(amount: amount, owner: owner)
                case Strategy.StFlowStaking:
                    self.executeStFlowStaking(amount: amount, owner: owner)
                case Strategy.OptimalYield:
                    self.executeOptimalStrategy(amount: amount, owner: owner)
            }
        }

        // Strategy 1: FLOW-stFlow LP farming
        access(self) fun executeFlowStFlowLP(amount: UFix64, owner: Address) {
            let flowToUse = amount
            let halfFlow <- self.flowVault.withdraw(amount: flowToUse / 2.0)
            let remainingFlow <- self.flowVault.withdraw(amount: flowToUse / 2.0)

            // Swap half FLOW for stFlow
            let deadline = getCurrentBlock().timestamp + 300.0
            let stFlowVault <- SwapRouter.swapExactTokensForTokens(
                exactVaultIn: <-halfFlow,
                amountOutMin: 0.0,
                tokenKeyPath: [
                    "A.1654653399040a61.FlowToken",
                    "A.d6f80565193ad727.stFlowToken"
                ],
                deadline: deadline
            )

            let stFlowAmount = stFlowVault.balance

            // Create LP tokens - use the most active FLOW-stFlow pair
            let pairAddress = SwapFactory.getPairAddress(
                token0Key: "A.1654653399040a61.FlowToken",
                token1Key: "A.d6f80565193ad727.stFlowToken"
            ) ?? panic("FLOW-stFlow pair not found")

            let pairRef = getAccount(pairAddress).capabilities
                .borrow<&{SwapInterfaces.PairPublic}>(SwapConfig.PairPublicPath)
                ?? panic("Could not borrow pair reference")

            let lpTokens <- pairRef.addLiquidity(
                tokenAVault: <-remainingFlow,
                tokenBVault: <-stFlowVault
            )

            let lpAmount = lpTokens.balance
            emit LPTokensCreated(flowAmount: flowToUse / 2.0, stFlowAmount: stFlowAmount, lpAmount: lpAmount)

            // Find best FLOW-stFlow staking pool and stake
            let optimalPoolId = self.findOptimalStakingPool(acceptTokenKey: pairAddress.toString())
            if optimalPoolId != nil {
                self.stakeInPool(poolId: optimalPoolId!, lpTokens: <-lpTokens, owner: owner)
            } else {
                // If no staking pool available, just hold the LP tokens
                destroy lpTokens
            }

            // Update user position
            self.userPositions[owner]!.updateStrategy(strategy: Strategy.FlowStFlowLP, amount: amount)

            emit StrategyExecuted(strategy: "FlowStFlowLP", amount: amount)
        }

        // Strategy 2: Direct stFlow staking
        access(self) fun executeStFlowStaking(amount: UFix64, owner: Address) {
            let flowToSwap <- self.flowVault.withdraw(amount: amount)

            // Swap all FLOW to stFlow
            let deadline = getCurrentBlock().timestamp + 300.0
            let stFlowVault <- SwapRouter.swapExactTokensForTokens(
                exactVaultIn: <-flowToSwap,
                amountOutMin: 0.0,
                tokenKeyPath: [
                    "A.1654653399040a61.FlowToken",
                    "A.d6f80565193ad727.stFlowToken"
                ],
                deadline: deadline
            )

            let stFlowAmount = stFlowVault.balance
            self.stFlowVault.deposit(from: <-stFlowVault)

            // Find optimal stFlow staking pool
            let optimalPoolId = self.findOptimalStakingPool(acceptTokenKey: "A.d6f80565193ad727.stFlowToken")
            if optimalPoolId != nil {
                let tokensToStake <- self.stFlowVault.withdraw(amount: stFlowAmount)
                self.stakeInPool(poolId: optimalPoolId!, lpTokens: <-tokensToStake, owner: owner)
            }

            self.userPositions[owner]!.updateStrategy(strategy: Strategy.StFlowStaking, amount: amount)
            emit StrategyExecuted(strategy: "StFlowStaking", amount: amount)
        }

        // Strategy 3: AI-selected optimal yield
        access(self) fun executeOptimalStrategy(amount: UFix64, owner: Address) {
            // This would implement your bot's optimal pool selection logic
            // For now, default to FLOW-stFlow LP as it had good results
            self.executeFlowStFlowLP(amount: amount, owner: owner)
        }

        // Find optimal staking pool for a given token type
        access(self) fun findOptimalStakingPool(acceptTokenKey: String): UInt64? {
            let stakingAccount = getAccount(0x1b77ba4b414de352)
            let collectionRef = stakingAccount.capabilities.borrow<&{Staking.PoolCollectionPublic}>(
                Staking.CollectionPublicPath
            ) ?? panic("Could not borrow staking collection")

            let poolCount = collectionRef.getCollectionLength()
            var bestPool: UInt64? = nil
            var bestAPY: UFix64 = 0.0

            var i: UInt64 = 0
            while i < poolCount {
                let poolRef = collectionRef.getPool(pid: i)
                let poolInfo = poolRef.getPoolInfo()

                // Check if pool matches our token type and is running
                if poolInfo.acceptTokenKey.contains(acceptTokenKey) && poolInfo.status == "2" {
                    let rewardInfo = poolRef.getRewardInfo()
                    var dailyRewards: UFix64 = 0.0
                    
                    for tokenKey in rewardInfo.keys {
                        let reward = rewardInfo[tokenKey]!
                        dailyRewards = dailyRewards + reward.rewardPerSeed * 86400.0
                    }

                    // Simple APY estimation
                    if poolInfo.totalStaking > 0.0 {
                        let estimatedAPY = (dailyRewards * 365.0 * 100.0) / poolInfo.totalStaking
                        if estimatedAPY > bestAPY {
                            bestAPY = estimatedAPY
                            bestPool = i
                        }
                    }
                }
                i = i + 1
            }

            return bestPool
        }

        // Stake tokens in a specific pool
        access(self) fun stakeInPool(poolId: UInt64, lpTokens: @{FungibleToken.Vault}, owner: Address) {
            let stakingAccount = getAccount(0x1b77ba4b414de352)
            let collectionRef = stakingAccount.capabilities.borrow<&{Staking.PoolCollectionPublic}>(
                Staking.CollectionPublicPath
            ) ?? panic("Could not borrow staking collection")

            let poolRef = collectionRef.getPool(pid: poolId)
            let amount = lpTokens.balance

            // Stake the tokens
            poolRef.stake(staker: self.userCertificate.owner!.address, stakingToken: <-lpTokens)

            // Update user position
            self.userPositions[owner]!.recordStaking(poolId: poolId, amount: amount)

            emit StakedInPool(poolId: poolId, amount: amount)
        }

        // Claim rewards from all positions
        access(all) fun harvestRewards(owner: Address) {
            let stakingAccount = getAccount(0x1b77ba4b414de352)
            let collectionRef = stakingAccount.capabilities.borrow<&{Staking.PoolCollectionPublic}>(
                Staking.CollectionPublicPath
            ) ?? panic("Could not borrow staking collection")

            let userPosition = self.userPositions[owner]!
            var totalYieldEarned: UFix64 = 0.0

            for poolId in userPosition.stakingPositions.keys {
                let poolRef = collectionRef.getPool(pid: poolId)
                let rewards <- poolRef.claimRewards(userCertificate: self.userCertificate)

                var poolRewards: {String: UFix64} = {}
                
                for tokenKey in rewards.keys {
                    let rewardVault <- rewards.remove(key: tokenKey)!
                    let rewardAmount = rewardVault.balance
                    poolRewards[tokenKey] = rewardAmount

                    // Deposit rewards back into appropriate vaults
                    if tokenKey.contains("FlowToken") {
                        self.flowVault.deposit(from: <-rewardVault)
                        totalYieldEarned = totalYieldEarned + rewardAmount
                    } else if tokenKey.contains("stFlowToken") {
                        self.stFlowVault.deposit(from: <-rewardVault)
                        totalYieldEarned = totalYieldEarned + rewardAmount
                    } else {
                        // For other reward tokens, could implement specific handling
                        destroy rewardVault
                    }
                }

                destroy rewards
                emit RewardsClaimed(poolId: poolId, rewards: poolRewards)
            }

            // Update user yield tracking
            self.userPositions[owner]!.addYield(amount: totalYieldEarned)
            self.totalValueLocked = self.totalValueLocked + totalYieldEarned
        }

        // Withdraw funds (including earned yield)
        access(all) fun withdraw(amount: UFix64, owner: Address): @FlowToken.Vault {
            require(self.userPositions[owner] != nil, message: "No position found")
            let userPosition = self.userPositions[owner]!
            require(userPosition.currentBalance >= amount, message: "Insufficient balance")

            // For simplicity, withdraw from FLOW vault first
            // In a production system, you'd unstake from positions as needed
            let withdrawVault <- self.flowVault.withdraw(amount: amount)

            self.userPositions[owner]!.recordWithdrawal(amount: amount)
            self.totalValueLocked = self.totalValueLocked - amount

            emit FundsWithdrawn(amount: amount, recipient: owner)

            return <-withdrawVault
        }

        // View functions
        access(all) fun getUserPosition(owner: Address): UserPosition? {
            return self.userPositions[owner]
        }

        access(all) fun getTotalValueLocked(): UFix64 {
            return self.totalValueLocked
        }

        access(all) fun getFlowBalance(): UFix64 {
            return self.flowVault.balance
        }

        access(all) fun getStFlowBalance(): UFix64 {
            return self.stFlowVault.balance
        }
    }

    // Public interfaces
    access(all) resource interface VaultPublic {
        access(all) fun deposit(flowVault: @FlowToken.Vault, strategy: Strategy, owner: Address)
        access(all) fun getUserPosition(owner: Address): UserPosition?
        access(all) fun getTotalValueLocked(): UFix64
    }

    // Create a new vault
    access(all) fun createVault(): @Vault {
        return <-create Vault()
    }

    init() {
        self.VaultStoragePath = /storage/AutoYieldVault
        self.VaultPublicPath = /public/AutoYieldVault
        self.VaultPrivatePath = /private/AutoYieldVault
    }
}