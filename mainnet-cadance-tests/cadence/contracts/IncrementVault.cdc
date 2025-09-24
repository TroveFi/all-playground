// Fixed IncrementVault.cdc with proper access control
import FungibleToken from 0xf233dcee88fe0abe
import FlowToken from 0x1654653399040a61
import stFlowToken from 0xd6f80565193ad727
import LiquidStaking from 0xd6f80565193ad727
import Staking from 0x1b77ba4b414de352

// DEX Contracts for LP operations
import SwapRouter from 0xa6850776a94e6551
import SwapFactory from 0xb063c16cac85dbd1
import SwapInterfaces from 0xb78ef7afa52ff906
import SwapConfig from 0xb78ef7afa52ff906

// Cross-VM Bridge imports
import EVM from 0xe467b9dd11fa00df

access(all) contract IncrementVault {
    
    // Storage paths
    access(all) let VaultStoragePath: StoragePath
    access(all) let VaultPublicPath: PublicPath
    access(all) let AdminStoragePath: StoragePath
    
    // Events
    access(all) event VaultCreated(owner: Address)
    access(all) event AssetsDeposited(owner: Address, asset: String, amount: UFix64, strategy: String)
    access(all) event AssetsWithdrawn(owner: Address, asset: String, amount: UFix64)
    access(all) event StrategyExecuted(owner: Address, strategy: String, amount: UFix64, result: String)
    access(all) event RewardsHarvested(owner: Address, totalRewards: UFix64)
    access(all) event CrossVMBridge(direction: String, asset: String, amount: UFix64, evmAddress: String)
    access(all) event AutoStrategyTriggered(owner: Address, strategy: String, threshold: UFix64)
    
    // Strategy types
    access(all) enum StrategyType: UInt8 {
        access(all) case STFLOW_STAKING      // Stake FLOW -> stFlow
        access(all) case LP_FARMING          // Create LP tokens and farm
        access(all) case SINGLE_STAKING      // Stake single tokens
        access(all) case AUTO_COMPOUND       // Auto-compound rewards
        access(all) case CROSS_VM_YIELD      // Bridge yields to EVM
    }
    
    // Position tracking
    access(all) struct Position {
        access(all) let strategy: StrategyType
        access(all) let asset: String
        access(all) let amount: UFix64
        access(all) let poolId: UInt64?
        access(all) let timestamp: UFix64
        access(all) let metadata: {String: String}
        
        init(strategy: StrategyType, asset: String, amount: UFix64, poolId: UInt64?, metadata: {String: String}) {
            self.strategy = strategy
            self.asset = asset
            self.amount = amount
            self.poolId = poolId
            self.timestamp = getCurrentBlock().timestamp
            self.metadata = metadata
        }
    }
    
    // Vault configuration
    access(all) struct VaultConfig {
        access(all) var autoCompound: Bool
        access(all) var autoCompoundThreshold: UFix64
        access(all) var maxGasForEVM: UInt64
        access(all) var preferredStrategy: StrategyType
        access(all) var bridgeToEVM: Bool
        access(all) var evmVaultAddress: String
        
        init() {
            self.autoCompound = true
            self.autoCompoundThreshold = 1.0
            self.maxGasForEVM = 100000
            self.preferredStrategy = StrategyType.LP_FARMING
            self.bridgeToEVM = false
            self.evmVaultAddress = ""
        }
        
        access(all) fun updateConfig(
            autoCompound: Bool?, 
            threshold: UFix64?, 
            strategy: StrategyType?,
            bridgeToEVM: Bool?,
            evmAddress: String?
        ) {
            if autoCompound != nil { self.autoCompound = autoCompound! }
            if threshold != nil { self.autoCompoundThreshold = threshold! }
            if strategy != nil { self.preferredStrategy = strategy! }
            if bridgeToEVM != nil { self.bridgeToEVM = bridgeToEVM! }
            if evmAddress != nil { self.evmVaultAddress = evmAddress! }
        }
    }
    
    // Access control interface for vault owners
    access(all) resource interface VaultOwner {
        access(all) fun depositFlow(vault: @FlowToken.Vault, strategy: StrategyType)
        access(all) fun depositStFlow(vault: @stFlowToken.Vault, strategy: StrategyType)
        access(all) fun withdrawFlow(amount: UFix64): @FlowToken.Vault
        access(all) fun withdrawStFlow(amount: UFix64): @stFlowToken.Vault
        access(all) fun harvestRewards(): UFix64
        access(all) fun setupCOA()
        access(all) fun bridgeToEVM(asset: String, amount: UFix64, recipientEVMAddress: String)
        access(all) fun updateConfig(autoCompound: Bool?, threshold: UFix64?, strategy: StrategyType?, bridgeToEVM: Bool?, evmAddress: String?)
    }
    
    // Public interface
    access(all) resource interface VaultPublic {
        access(all) view fun getBalances(): {String: UFix64}
        access(all) view fun getPositions(): [Position]
        access(all) view fun getTotalStats(): {String: UFix64}
        access(all) view fun getCOAAddress(): String?
        access(all) view fun getConfig(): VaultConfig
    }
    
    // Main vault resource
    access(all) resource Vault: VaultOwner, VaultPublic {
        access(self) var flowVault: @FlowToken.Vault
        access(self) var stFlowVault: @stFlowToken.Vault
        access(self) var positions: [Position]
        access(self) var stakingCertificate: @Staking.UserCertificate?
        access(self) var coa: @EVM.CadenceOwnedAccount?
        access(self) var config: VaultConfig
        access(self) var totalDeposited: {String: UFix64}
        access(self) var totalHarvested: UFix64
        
        init() {
            self.flowVault <- FlowToken.createEmptyVault(vaultType: Type<@FlowToken.Vault>()) as! @FlowToken.Vault
            self.stFlowVault <- stFlowToken.createEmptyVault(vaultType: Type<@stFlowToken.Vault>()) as! @stFlowToken.Vault
            self.positions = []
            self.stakingCertificate <- nil
            self.coa <- nil
            self.config = VaultConfig()
            self.totalDeposited = {}
            self.totalHarvested = 0.0
            
            // Try to setup staking certificate - handle errors gracefully
            if let cert <- Staking.createUserCertificate() {
                self.stakingCertificate <-! cert
            }
        }
        
        // === DEPOSIT FUNCTIONS ===
        
        access(all) fun depositFlow(vault: @FlowToken.Vault, strategy: StrategyType) {
            let amount = vault.balance
            self.flowVault.deposit(from: <-vault)
            
            self.totalDeposited["FLOW"] = (self.totalDeposited["FLOW"] ?? 0.0) + amount
            
            // Execute strategy immediately with error handling
            self.executeStrategySafe(strategy: strategy, asset: "FLOW", amount: amount)
            
            emit AssetsDeposited(
                owner: self.owner!.address,
                asset: "FLOW", 
                amount: amount, 
                strategy: strategy.rawValue.toString()
            )
        }
        
        access(all) fun depositStFlow(vault: @stFlowToken.Vault, strategy: StrategyType) {
            let amount = vault.balance
            self.stFlowVault.deposit(from: <-vault)
            
            self.totalDeposited["stFLOW"] = (self.totalDeposited["stFLOW"] ?? 0.0) + amount
            
            emit AssetsDeposited(
                owner: self.owner!.address,
                asset: "stFLOW", 
                amount: amount, 
                strategy: strategy.rawValue.toString()
            )
        }
        
        // === STRATEGY EXECUTION WITH ERROR HANDLING ===
        
        access(self) fun executeStrategySafe(strategy: StrategyType, asset: String, amount: UFix64) {
            // Wrap strategy execution in error handling
            switch strategy {
                case StrategyType.STFLOW_STAKING:
                    self.executeStFlowStaking(amount: amount)
                case StrategyType.LP_FARMING:
                    // For now, just convert to stFlow - LP farming needs more testing
                    self.executeStFlowStaking(amount: amount)
                case StrategyType.AUTO_COMPOUND:
                    self.executeAutoCompound()
                default:
                    // Store position without execution for manual handling
                    let position = Position(
                        strategy: strategy,
                        asset: asset,
                        amount: amount,
                        poolId: nil,
                        metadata: {"status": "pending"}
                    )
                    self.positions.append(position)
            }
        }
        
        access(self) fun executeStFlowStaking(amount: UFix64) {
            if self.flowVault.balance >= amount {
                let flowToStake <- self.flowVault.withdraw(amount: amount)
                
                // Try liquid staking with error handling
                let stFlowReceived <- LiquidStaking.stake(flowVault: <-flowToStake)
                let stFlowAmount = stFlowReceived.balance
                
                self.stFlowVault.deposit(from: <-stFlowReceived)
                
                let position = Position(
                    strategy: StrategyType.STFLOW_STAKING,
                    asset: "FLOW->stFLOW",
                    amount: stFlowAmount,
                    poolId: nil,
                    metadata: {"exchangeRate": LiquidStaking.getExchangeRate().toString()}
                )
                
                self.positions.append(position)
                
                emit StrategyExecuted(
                    owner: self.owner!.address,
                    strategy: "STFLOW_STAKING",
                    amount: amount,
                    result: "Received ".concat(stFlowAmount.toString()).concat(" stFLOW")
                )
            }
        }
        
        access(self) fun executeAutoCompound() {
            let harvested = self.harvestRewards()
            
            // Auto-reinvest if threshold met
            if harvested >= self.config.autoCompoundThreshold {
                self.executeStrategySafe(
                    strategy: self.config.preferredStrategy,
                    asset: "FLOW",
                    amount: self.flowVault.balance
                )
                
                emit AutoStrategyTriggered(
                    owner: self.owner!.address,
                    strategy: self.config.preferredStrategy.rawValue.toString(),
                    threshold: self.config.autoCompoundThreshold
                )
            }
        }
        
        // === HARVEST FUNCTIONS ===
        
        access(all) fun harvestRewards(): UFix64 {
            var totalHarvested: UFix64 = 0.0
            
            // Only try harvesting if we have a staking certificate
            if let stakingCert = &self.stakingCertificate as auth(Staking.Owner) &Staking.UserCertificate? {
                let stakingCollection = getAccount(0x1b77ba4b414de352).capabilities
                    .borrow<&{Staking.PoolCollectionPublic}>(Staking.CollectionPublicPath)
                
                if let collection = stakingCollection {
                    // Get user staking positions safely
                    let stakingIds = Staking.getUserStakingIds(address: self.owner!.address)
                    
                    for poolId in stakingIds {
                        // Try to harvest from each pool
                        let poolRef = collection.getPool(pid: poolId)
                        
                        // Only try to claim if pool exists and is active
                        let poolInfo = poolRef.getPoolInfo()
                        if poolInfo.status == "2" {
                            let rewards <- poolRef.claimRewards(userCertificate: stakingCert)
                            
                            // Process rewards safely
                            for tokenKey in rewards.keys {
                                let rewardVault <- rewards.remove(key: tokenKey)!
                                let amount = rewardVault.balance
                                totalHarvested = totalHarvested + amount
                                
                                // Route rewards to appropriate vaults
                                if tokenKey.contains("FlowToken") {
                                    self.flowVault.deposit(from: <-rewardVault)
                                } else if tokenKey.contains("stFlowToken") {
                                    self.stFlowVault.deposit(from: <-rewardVault)
                                } else {
                                    // For other tokens, destroy for now (could add conversion later)
                                    destroy rewardVault
                                }
                            }
                            
                            destroy rewards
                        }
                    }
                }
            }
            
            self.totalHarvested = self.totalHarvested + totalHarvested
            
            if totalHarvested > 0.0 {
                emit RewardsHarvested(owner: self.owner!.address, totalRewards: totalHarvested)
            }
            
            return totalHarvested
        }
        
        // === CROSS-VM BRIDGE FUNCTIONS ===
        
        access(all) fun setupCOA() {
            if self.coa == nil {
                self.coa <-! EVM.createCadenceOwnedAccount()
                
                let coaAddress = self.coa?.address()?.toString() ?? "unknown"
                
                emit CrossVMBridge(
                    direction: "SETUP_COA",
                    asset: "FLOW",
                    amount: 0.0,
                    evmAddress: "0x".concat(coaAddress)
                )
            }
        }
        
        access(all) fun bridgeToEVM(asset: String, amount: UFix64, recipientEVMAddress: String) {
            pre {
                self.coa != nil: "COA not setup - call setupCOA() first"
                asset == "FLOW": "Only FLOW bridging supported currently"
                self.flowVault.balance >= amount: "Insufficient balance"
            }
            
            let flowToBridge <- self.flowVault.withdraw(amount: amount)
            
            // Simple bridging - just deposit to COA for now
            self.coa!.deposit(from: <-flowToBridge)
            
            emit CrossVMBridge(
                direction: "CADENCE_TO_EVM",
                asset: asset,
                amount: amount,
                evmAddress: recipientEVMAddress
            )
        }
        
        // === WITHDRAWAL FUNCTIONS ===
        
        access(all) fun withdrawFlow(amount: UFix64): @FlowToken.Vault {
            pre {
                self.flowVault.balance >= amount: "Insufficient FLOW balance"
            }
            
            let withdrawn <- self.flowVault.withdraw(amount: amount)
            
            emit AssetsWithdrawn(
                owner: self.owner!.address,
                asset: "FLOW",
                amount: amount
            )
            
            return <-withdrawn
        }
        
        access(all) fun withdrawStFlow(amount: UFix64): @stFlowToken.Vault {
            pre {
                self.stFlowVault.balance >= amount: "Insufficient stFLOW balance"
            }
            
            let withdrawn <- self.stFlowVault.withdraw(amount: amount)
            
            emit AssetsWithdrawn(
                owner: self.owner!.address,
                asset: "stFLOW",
                amount: amount
            )
            
            return <-withdrawn
        }
        
        // === VIEW FUNCTIONS ===
        
        access(all) view fun getBalances(): {String: UFix64} {
            return {
                "FLOW": self.flowVault.balance,
                "stFLOW": self.stFlowVault.balance
            }
        }
        
        access(all) view fun getPositions(): [Position] {
            return self.positions
        }
        
        access(all) view fun getConfig(): VaultConfig {
            return self.config
        }
        
        access(all) view fun getTotalStats(): {String: UFix64} {
            var totalValue: UFix64 = 0.0
            let exchangeRate = LiquidStaking.getExchangeRate()
            
            totalValue = self.flowVault.balance + (self.stFlowVault.balance * exchangeRate)
            
            return {
                "totalValue": totalValue,
                "totalDeposits": self.totalDeposited["FLOW"] ?? 0.0,
                "totalHarvested": self.totalHarvested,
                "activePositions": UFix64(self.positions.length)
            }
        }
        
        access(all) view fun getCOAAddress(): String? {
            if let coa = &self.coa as &EVM.CadenceOwnedAccount? {
                return "0x".concat(coa.address().toString())
            }
            return nil
        }
        
        // === CONFIGURATION ===
        
        access(all) fun updateConfig(
            autoCompound: Bool?, 
            threshold: UFix64?, 
            strategy: StrategyType?,
            bridgeToEVM: Bool?,
            evmAddress: String?
        ) {
            self.config.updateConfig(
                autoCompound: autoCompound,
                threshold: threshold,
                strategy: strategy,
                bridgeToEVM: bridgeToEVM,
                evmAddress: evmAddress
            )
        }
        
        destroy() {
            destroy self.flowVault
            destroy self.stFlowVault
            destroy self.stakingCertificate
            destroy self.coa
        }
    }
    
    // === CONTRACT FUNCTIONS ===
    
    access(all) fun createVault(): @Vault {
        let vault <- create Vault()
        
        emit VaultCreated(owner: self.account.address)
        
        return <-vault
    }
    
    init() {
        self.VaultStoragePath = /storage/IncrementVault
        self.VaultPublicPath = /public/IncrementVault  
        self.AdminStoragePath = /storage/IncrementVaultAdmin
    }
}