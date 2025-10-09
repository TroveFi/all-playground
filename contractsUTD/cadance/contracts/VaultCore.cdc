import FungibleToken from 0xf233dcee88fe0abe
import FlowToken from 0x1654653399040a61
import stFlowToken from 0xd6f80565193ad727

/// Core vault contract for non-custodial yield aggregation
/// Users deposit funds, only they can withdraw their principal
/// Agent manages funds across strategies to maximize APY
access(all) contract VaultCore {
    
    // ====================================================================
    // PATHS
    // ====================================================================
    access(all) let VaultStoragePath: StoragePath
    access(all) let VaultPublicPath: PublicPath
    access(all) let AdminStoragePath: StoragePath
    access(all) let AgentStoragePath: StoragePath
    
    // ====================================================================
    // EVENTS
    // ====================================================================
    access(all) event VaultInitialized()
    access(all) event UserDeposited(user: Address, asset: String, amount: UFix64, shares: UFix64, riskLevel: UInt8)
    access(all) event WithdrawalRequested(user: Address, asset: String, amount: UFix64, requestId: UInt64)
    access(all) event WithdrawalProcessed(user: Address, requestId: UInt64, amount: UFix64)
    access(all) event StrategyExecuted(strategy: String, asset: String, amount: UFix64)
    access(all) event YieldHarvested(asset: String, amount: UFix64, fees: UFix64)
    access(all) event BridgedToEVM(asset: String, amount: UFix64)
    access(all) event BridgedFromEVM(asset: String, amount: UFix64)
    access(all) event EmergencyModeToggled(enabled: Bool)
    access(all) event YieldEligibilityChanged(user: Address, eligible: Bool)
    
    // ====================================================================
    // STATE VARIABLES
    // ====================================================================
    access(self) var totalValueLocked: UFix64
    access(self) var totalUsers: UInt64
    access(self) var totalPrincipal: UFix64
    access(self) var totalYieldGenerated: UFix64
    access(self) var totalShares: UFix64
    access(self) var currentEpoch: UInt64
    access(self) var lastEpochStart: UFix64
    access(self) var epochDuration: UFix64
    
    access(self) var depositsEnabled: Bool
    access(self) var withdrawalsEnabled: Bool
    access(self) var emergencyMode: Bool
    
    access(self) var totalBridgedToEVM: UFix64
    access(self) var totalBridgedFromEVM: UFix64
    
    access(self) var nextRequestId: UInt64
    
    // ====================================================================
    // ENUMS
    // ====================================================================
    access(all) enum RiskLevel: UInt8 {
        access(all) case conservative
        access(all) case normal
        access(all) case aggressive
    }
    
    access(all) enum AssetType: UInt8 {
        access(all) case flow
        access(all) case stflow
        access(all) case usdc
    }
    
    // ====================================================================
    // STRUCTS
    // ====================================================================
    access(all) struct UserPosition {
        access(all) let user: Address
        access(all) var totalShares: UFix64
        access(all) var flowDeposited: UFix64
        access(all) var stFlowDeposited: UFix64
        access(all) var lastDepositTime: UFix64
        access(all) var riskLevel: RiskLevel
        access(all) var yieldEligible: Bool
        access(all) var vrfMultiplier: UFix64
        access(all) var withdrawalRequests: [UInt64]
        
        init(user: Address, riskLevel: RiskLevel) {
            self.user = user
            self.totalShares = 0.0
            self.flowDeposited = 0.0
            self.stFlowDeposited = 0.0
            self.lastDepositTime = getCurrentBlock().timestamp
            self.riskLevel = riskLevel
            self.yieldEligible = true
            self.vrfMultiplier = 1.0
            self.withdrawalRequests = []
        }
        
        access(contract) fun addShares(amount: UFix64) {
            self.totalShares = self.totalShares + amount
        }
        
        access(contract) fun removeShares(amount: UFix64) {
            self.totalShares = self.totalShares - amount
        }
        
        access(contract) fun addFlowDeposit(amount: UFix64) {
            self.flowDeposited = self.flowDeposited + amount
            self.lastDepositTime = getCurrentBlock().timestamp
        }
        
        access(contract) fun addStFlowDeposit(amount: UFix64) {
            self.stFlowDeposited = self.stFlowDeposited + amount
            self.lastDepositTime = getCurrentBlock().timestamp
        }
        
        access(contract) fun removeFlowDeposit(amount: UFix64) {
            self.flowDeposited = self.flowDeposited - amount
        }
        
        access(contract) fun removeStFlowDeposit(amount: UFix64) {
            self.stFlowDeposited = self.stFlowDeposited - amount
        }
        
        access(contract) fun setYieldEligible(eligible: Bool) {
            self.yieldEligible = eligible
        }
        
        access(contract) fun setVRFMultiplier(multiplier: UFix64) {
            self.vrfMultiplier = multiplier
        }
        
        access(contract) fun addWithdrawalRequest(requestId: UInt64) {
            self.withdrawalRequests.append(requestId)
        }
    }
    
    access(all) struct WithdrawalRequest {
        access(all) let requestId: UInt64
        access(all) let user: Address
        access(all) let assetType: AssetType
        access(all) let amount: UFix64
        access(all) let requestTime: UFix64
        access(all) var processed: Bool
        
        init(requestId: UInt64, user: Address, assetType: AssetType, amount: UFix64) {
            self.requestId = requestId
            self.user = user
            self.assetType = assetType
            self.amount = amount
            self.requestTime = getCurrentBlock().timestamp
            self.processed = false
        }
        
        access(contract) fun markProcessed() {
            self.processed = true
        }
    }
    
    access(all) struct AssetBalance {
        access(all) var vaultBalance: UFix64
        access(all) var strategyBalance: UFix64
        access(all) var evmBalance: UFix64
        access(all) var totalBalance: UFix64
        access(all) var totalHarvested: UFix64
        access(all) var lastHarvestTime: UFix64
        
        init() {
            self.vaultBalance = 0.0
            self.strategyBalance = 0.0
            self.evmBalance = 0.0
            self.totalBalance = 0.0
            self.totalHarvested = 0.0
            self.lastHarvestTime = getCurrentBlock().timestamp
        }
        
        access(contract) fun addToVault(amount: UFix64) {
            self.vaultBalance = self.vaultBalance + amount
            self.totalBalance = self.totalBalance + amount
        }
        
        access(contract) fun removeFromVault(amount: UFix64) {
            self.vaultBalance = self.vaultBalance - amount
            self.totalBalance = self.totalBalance - amount
        }
        
        access(contract) fun moveToStrategy(amount: UFix64) {
            self.vaultBalance = self.vaultBalance - amount
            self.strategyBalance = self.strategyBalance + amount
        }
        
        access(contract) fun moveFromStrategy(amount: UFix64) {
            self.strategyBalance = self.strategyBalance - amount
            self.vaultBalance = self.vaultBalance + amount
        }
        
        access(contract) fun moveToEVM(amount: UFix64) {
            self.vaultBalance = self.vaultBalance - amount
            self.evmBalance = self.evmBalance + amount
        }
        
        access(contract) fun moveFromEVM(amount: UFix64) {
            self.evmBalance = self.evmBalance - amount
            self.vaultBalance = self.vaultBalance + amount
        }
        
        access(contract) fun recordHarvest(amount: UFix64) {
            self.totalHarvested = self.totalHarvested + amount
            self.lastHarvestTime = getCurrentBlock().timestamp
        }
    }
    
    access(all) struct VaultMetrics {
        access(all) let totalValueLocked: UFix64
        access(all) let totalUsers: UInt64
        access(all) let totalShares: UFix64
        access(all) let totalPrincipal: UFix64
        access(all) let totalYieldGenerated: UFix64
        access(all) let totalBridgedToEVM: UFix64
        access(all) let totalBridgedFromEVM: UFix64
        access(all) let currentEpoch: UInt64
        access(all) let depositsEnabled: Bool
        access(all) let withdrawalsEnabled: Bool
        access(all) let emergencyMode: Bool
        
        init(
            tvl: UFix64,
            users: UInt64,
            shares: UFix64,
            principal: UFix64,
            yieldGen: UFix64,
            bridgedTo: UFix64,
            bridgedFrom: UFix64,
            epoch: UInt64,
            deposits: Bool,
            withdrawals: Bool,
            emergency: Bool
        ) {
            self.totalValueLocked = tvl
            self.totalUsers = users
            self.totalShares = shares
            self.totalPrincipal = principal
            self.totalYieldGenerated = yieldGen
            self.totalBridgedToEVM = bridgedTo
            self.totalBridgedFromEVM = bridgedFrom
            self.currentEpoch = epoch
            self.depositsEnabled = deposits
            self.withdrawalsEnabled = withdrawals
            self.emergencyMode = emergency
        }
    }
    
    // ====================================================================
    // VAULT RESOURCE
    // ====================================================================
    access(all) resource Vault {
        // Asset storage
        access(self) let flowVault: @FlowToken.Vault
        access(self) let stFlowVault: @stFlowToken.Vault
        
        // User tracking
        access(self) let userPositions: {Address: UserPosition}
        access(self) let withdrawalRequests: {UInt64: WithdrawalRequest}
        
        // Asset balances
        access(self) let assetBalances: {AssetType: AssetBalance}
        
        // Strategy tracking
        access(self) let whitelistedStrategies: {String: Bool}
        
        init() {
            self.flowVault <- FlowToken.createEmptyVault(vaultType: Type<@FlowToken.Vault>()) as! @FlowToken.Vault
            self.stFlowVault <- stFlowToken.createEmptyVault(vaultType: Type<@stFlowToken.Vault>()) as! @stFlowToken.Vault
            
            self.userPositions = {}
            self.withdrawalRequests = {}
            
            self.assetBalances = {}
            self.assetBalances[AssetType.flow] = AssetBalance()
            self.assetBalances[AssetType.stflow] = AssetBalance()
            
            self.whitelistedStrategies = {}
        }
        
        // ====================================================================
        // DEPOSIT FUNCTIONS
        // ====================================================================
        access(all) fun depositFlow(from: @FlowToken.Vault, user: Address, riskLevel: RiskLevel): UFix64 {
            pre {
                VaultCore.depositsEnabled: "Deposits are disabled"
                !VaultCore.emergencyMode: "Emergency mode active"
                from.balance > 0.0: "Cannot deposit zero"
            }
            
            let amount = from.balance
            let shares = self.calculateShares(assetType: AssetType.flow, amount: amount)
            
            // Deposit funds
            self.flowVault.deposit(from: <-from)
            self.assetBalances[AssetType.flow]!.addToVault(amount: amount)
            
            // Update or create user position
            if self.userPositions[user] == nil {
                self.userPositions[user] = UserPosition(user: user, riskLevel: riskLevel)
                VaultCore.totalUsers = VaultCore.totalUsers + 1
            }
            
            self.userPositions[user]!.addShares(amount: shares)
            self.userPositions[user]!.addFlowDeposit(amount: amount)
            
            VaultCore.totalShares = VaultCore.totalShares + shares
            VaultCore.totalPrincipal = VaultCore.totalPrincipal + amount
            VaultCore.totalValueLocked = VaultCore.totalValueLocked + amount
            
            emit UserDeposited(
                user: user,
                asset: "FLOW",
                amount: amount,
                shares: shares,
                riskLevel: riskLevel.rawValue
            )
            
            return shares
        }
        
        access(all) fun depositStFlow(from: @stFlowToken.Vault, user: Address, riskLevel: RiskLevel): UFix64 {
            pre {
                VaultCore.depositsEnabled: "Deposits are disabled"
                !VaultCore.emergencyMode: "Emergency mode active"
                from.balance > 0.0: "Cannot deposit zero"
            }
            
            let amount = from.balance
            let shares = self.calculateShares(assetType: AssetType.stflow, amount: amount)
            
            self.stFlowVault.deposit(from: <-from)
            self.assetBalances[AssetType.stflow]!.addToVault(amount: amount)
            
            if self.userPositions[user] == nil {
                self.userPositions[user] = UserPosition(user: user, riskLevel: riskLevel)
                VaultCore.totalUsers = VaultCore.totalUsers + 1
            }
            
            self.userPositions[user]!.addShares(amount: shares)
            self.userPositions[user]!.addStFlowDeposit(amount: amount)
            
            VaultCore.totalShares = VaultCore.totalShares + shares
            VaultCore.totalPrincipal = VaultCore.totalPrincipal + amount
            VaultCore.totalValueLocked = VaultCore.totalValueLocked + amount
            
            emit UserDeposited(
                user: user,
                asset: "stFLOW",
                amount: amount,
                shares: shares,
                riskLevel: riskLevel.rawValue
            )
            
            return shares
        }
        
        // ====================================================================
        // WITHDRAWAL FUNCTIONS
        // ====================================================================
        access(all) fun requestWithdrawal(user: Address, assetType: AssetType, amount: UFix64): UInt64 {
            pre {
                self.userPositions[user] != nil: "No position found"
                amount > 0.0: "Amount must be positive"
            }
            
            let position = self.userPositions[user]!
            
            // Verify user has sufficient balance
            if assetType == AssetType.flow {
                assert(position.flowDeposited >= amount, message: "Insufficient FLOW balance")
            } else if assetType == AssetType.stflow {
                assert(position.stFlowDeposited >= amount, message: "Insufficient stFLOW balance")
            }
            
            let requestId = VaultCore.nextRequestId
            VaultCore.nextRequestId = requestId + 1
            
            let request = WithdrawalRequest(
                requestId: requestId,
                user: user,
                assetType: assetType,
                amount: amount
            )
            
            self.withdrawalRequests[requestId] = request
            self.userPositions[user]!.addWithdrawalRequest(requestId: requestId)
            
            emit WithdrawalRequested(
                user: user,
                asset: assetType == AssetType.flow ? "FLOW" : "stFLOW",
                amount: amount,
                requestId: requestId
            )
            
            return requestId
        }
        
        access(all) fun processWithdrawal(requestId: UInt64): @{FungibleToken.Vault} {
            pre {
                VaultCore.withdrawalsEnabled: "Withdrawals disabled"
                self.withdrawalRequests[requestId] != nil: "Invalid request"
                !self.withdrawalRequests[requestId]!.processed: "Already processed"
            }
            
            let request = self.withdrawalRequests[requestId]!
            let user = request.user
            let amount = request.amount
            let assetType = request.assetType
            
            // Mark as processed
            self.withdrawalRequests[requestId]!.markProcessed()
            
            // Calculate shares to burn
            let shares = self.calculateShares(assetType: assetType, amount: amount)
            
            // Update user position
            if assetType == AssetType.flow {
                self.userPositions[user]!.removeFlowDeposit(amount: amount)
                self.assetBalances[AssetType.flow]!.removeFromVault(amount: amount)
            } else if assetType == AssetType.stflow {
                self.userPositions[user]!.removeStFlowDeposit(amount: amount)
                self.assetBalances[AssetType.stflow]!.removeFromVault(amount: amount)
            }
            
            self.userPositions[user]!.removeShares(amount: shares)
            
            VaultCore.totalShares = VaultCore.totalShares - shares
            VaultCore.totalPrincipal = VaultCore.totalPrincipal - amount
            VaultCore.totalValueLocked = VaultCore.totalValueLocked - amount
            
            emit WithdrawalProcessed(user: user, requestId: requestId, amount: amount)
            
            // Return appropriate vault
            if assetType == AssetType.flow {
                return <- self.flowVault.withdraw(amount: amount)
            } else {
                return <- self.stFlowVault.withdraw(amount: amount)
            }
        }
        
        // ====================================================================
        // STRATEGY FUNCTIONS (AGENT ONLY)
        // ====================================================================
        access(all) fun withdrawForStrategy(assetType: AssetType, amount: UFix64): @{FungibleToken.Vault} {
            pre {
                amount > 0.0: "Amount must be positive"
            }
            
            self.assetBalances[assetType]!.moveToStrategy(amount: amount)
            
            if assetType == AssetType.flow {
                return <- self.flowVault.withdraw(amount: amount)
            } else {
                return <- self.stFlowVault.withdraw(amount: amount)
            }
        }
        
        access(all) fun depositFromStrategy(assetType: AssetType, from: @{FungibleToken.Vault}) {
            let amount = from.balance
            
            self.assetBalances[assetType]!.moveFromStrategy(amount: amount)
            
            if assetType == AssetType.flow {
                self.flowVault.deposit(from: <-from as! @FlowToken.Vault)
            } else {
                self.stFlowVault.deposit(from: <-from as! @stFlowToken.Vault)
            }
        }
        
        access(all) fun recordYieldHarvest(assetType: AssetType, amount: UFix64) {
            self.assetBalances[assetType]!.recordHarvest(amount: amount)
            VaultCore.totalYieldGenerated = VaultCore.totalYieldGenerated + amount
        }
        
        // ====================================================================
        // BRIDGING FUNCTIONS (AGENT ONLY)
        // ====================================================================
        access(all) fun withdrawForEVMBridge(assetType: AssetType, amount: UFix64): @{FungibleToken.Vault} {
            pre {
                assetType == AssetType.flow: "Only FLOW can be bridged"
                amount > 0.0: "Amount must be positive"
            }
            
            self.assetBalances[assetType]!.moveToEVM(amount: amount)
            VaultCore.totalBridgedToEVM = VaultCore.totalBridgedToEVM + amount
            
            emit BridgedToEVM(asset: "FLOW", amount: amount)
            
            return <- self.flowVault.withdraw(amount: amount)
        }
        
        access(all) fun depositFromEVMBridge(from: @FlowToken.Vault) {
            let amount = from.balance
            
            self.assetBalances[AssetType.flow]!.moveFromEVM(amount: amount)
            VaultCore.totalBridgedFromEVM = VaultCore.totalBridgedFromEVM + amount
            
            self.flowVault.deposit(from: <-from)
            
            emit BridgedFromEVM(asset: "FLOW", amount: amount)
        }
        
        // ====================================================================
        // ADMIN FUNCTIONS
        // ====================================================================
        access(all) fun whitelistStrategy(strategyName: String, status: Bool) {
            self.whitelistedStrategies[strategyName] = status
        }
        
        access(all) fun setUserYieldEligibility(user: Address, eligible: Bool) {
            pre {
                self.userPositions[user] != nil: "User not found"
            }
            
            self.userPositions[user]!.setYieldEligible(eligible: eligible)
            emit YieldEligibilityChanged(user: user, eligible: eligible)
        }
        
        access(all) fun setUserVRFMultiplier(user: Address, multiplier: UFix64) {
            pre {
                self.userPositions[user] != nil: "User not found"
                multiplier >= 1.0 && multiplier <= 100.0: "Invalid multiplier"
            }
            
            self.userPositions[user]!.setVRFMultiplier(multiplier: multiplier)
        }
        
        // ====================================================================
        // VIEW FUNCTIONS
        // ====================================================================
        access(all) fun getUserPosition(user: Address): UserPosition? {
            return self.userPositions[user]
        }
        
        access(all) fun getAssetBalance(assetType: AssetType): AssetBalance {
            return self.assetBalances[assetType]!
        }
        
        access(all) fun getWithdrawalRequest(requestId: UInt64): WithdrawalRequest? {
            return self.withdrawalRequests[requestId]
        }
        
        access(all) fun calculateShares(assetType: AssetType, amount: UFix64): UFix64 {
            if VaultCore.totalShares == 0.0 {
                return amount
            }
            
            let assetBalance = self.assetBalances[assetType]!
            let totalAssetValue = assetBalance.totalBalance
            
            if totalAssetValue == 0.0 {
                return amount
            }
            
            return (amount * VaultCore.totalShares) / VaultCore.totalValueLocked
        }
        
        access(all) fun isStrategyWhitelisted(strategyName: String): Bool {
            return self.whitelistedStrategies[strategyName] ?? false
        }
    }
    
    // ====================================================================
    // PUBLIC INTERFACE
    // ====================================================================
    access(all) resource interface VaultPublic {
        access(all) fun getUserPosition(user: Address): UserPosition?
        access(all) fun getAssetBalance(assetType: AssetType): AssetBalance
        access(all) fun getWithdrawalRequest(requestId: UInt64): WithdrawalRequest?
        access(all) fun getVaultMetrics(): VaultMetrics
    }
    
    // ====================================================================
    // ADMIN RESOURCE
    // ====================================================================
    access(all) resource Admin {
        access(all) fun toggleDeposits(enabled: Bool) {
            VaultCore.depositsEnabled = enabled
        }
        
        access(all) fun toggleWithdrawals(enabled: Bool) {
            VaultCore.withdrawalsEnabled = enabled
        }
        
        access(all) fun setEmergencyMode(enabled: Bool) {
            VaultCore.emergencyMode = enabled
            if enabled {
                VaultCore.depositsEnabled = false
            }
            emit EmergencyModeToggled(enabled: enabled)
        }
        
        access(all) fun advanceEpoch() {
            VaultCore.currentEpoch = VaultCore.currentEpoch + 1
            VaultCore.lastEpochStart = getCurrentBlock().timestamp
        }
        
        access(all) fun setEpochDuration(duration: UFix64) {
            VaultCore.epochDuration = duration
        }
    }
    
    // ====================================================================
    // CONTRACT FUNCTIONS
    // ====================================================================
    access(all) fun getVaultMetrics(): VaultMetrics {
        return VaultMetrics(
            tvl: self.totalValueLocked,
            users: self.totalUsers,
            shares: self.totalShares,
            principal: self.totalPrincipal,
            yieldGen: self.totalYieldGenerated,
            bridgedTo: self.totalBridgedToEVM,
            bridgedFrom: self.totalBridgedFromEVM,
            epoch: self.currentEpoch,
            deposits: self.depositsEnabled,
            withdrawals: self.withdrawalsEnabled,
            emergency: self.emergencyMode
        )
    }
    
    access(all) fun createEmptyVault(): @Vault {
        return <- create Vault()
    }
    
    // ====================================================================
    // INITIALIZATION
    // ====================================================================
    init() {
        self.VaultStoragePath = /storage/TrueMultiAssetVault
        self.VaultPublicPath = /public/TrueMultiAssetVault
        self.AdminStoragePath = /storage/VaultAdmin
        self.AgentStoragePath = /storage/VaultAgent
        
        self.totalValueLocked = 0.0
        self.totalUsers = 0
        self.totalPrincipal = 0.0
        self.totalYieldGenerated = 0.0
        self.totalShares = 0.0
        
        self.currentEpoch = 1
        self.lastEpochStart = getCurrentBlock().timestamp
        self.epochDuration = 604800.0 // 7 days in seconds
        
        self.depositsEnabled = true
        self.withdrawalsEnabled = true
        self.emergencyMode = false
        
        self.totalBridgedToEVM = 0.0
        self.totalBridgedFromEVM = 0.0
        
        self.nextRequestId = 0
        
        // Create admin resource
        self.account.storage.save(<-create Admin(), to: self.AdminStoragePath)
        
        emit VaultInitialized()
    }
}