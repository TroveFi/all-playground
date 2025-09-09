
import FlowToken from 0x1654653399040a61
import stFlowToken from 0xd6f80565193ad727
import LiquidStaking from 0xd6f80565193ad727
import LiquidStakingError from 0xd6f80565193ad727
import PublicPriceOracle from 0xec67451f8a58216a

access(all) contract ActionRouter {
    
    // Storage paths
    access(all) let AdminStoragePath: StoragePath
    access(all) let RouterStoragePath: StoragePath
    access(all) let FlowVaultStoragePath: StoragePath
    access(all) let StFlowVaultStoragePath: StoragePath
    
    // Access control
    access(self) var authorizedEVMCallers: {Address: Bool}
    access(self) var isActive: Bool
    
    // Configuration
    access(self) var minStakeAmount: UFix64
    access(self) var maxStakeAmount: UFix64
    access(self) var maxOperationsPerBlock: UInt64
    access(self) var currentBlockOperations: UInt64
    access(self) var lastBlockHeight: UInt64
    
    // Stats tracking
    access(all) var totalStakeOperations: UInt64
    access(all) var totalUnstakeOperations: UInt64
    access(all) var totalFlowStaked: UFix64
    access(all) var totalStFlowMinted: UFix64
    
    // Events
    access(all) event StakeExecuted(
        amount: UFix64,
        recipient: Address,
        stFlowReceived: UFix64,
        exchangeRate: UFix64,
        requestId: String
    )
    
    access(all) event UnstakeExecuted(
        amount: UFix64,
        recipient: Address,
        flowReceived: UFix64,
        requestId: String
    )
    
    access(all) event EVMCallerAuthorized(caller: Address)
    access(all) event EVMCallerRevoked(caller: Address)
    access(all) event RouterConfigUpdated(minStake: UFix64, maxStake: UFix64)
    
    init() {
        self.AdminStoragePath = /storage/ActionRouterAdmin
        self.RouterStoragePath = /storage/ActionRouter
        self.FlowVaultStoragePath = /storage/ActionRouterFlowVault
        self.StFlowVaultStoragePath = /storage/ActionRouterStFlowVault
        
        self.authorizedEVMCallers = {}
        self.isActive = true
        
        // Set conservative limits
        self.minStakeAmount = 1.0
        self.maxStakeAmount = 10000.0
        self.maxOperationsPerBlock = 10
        self.currentBlockOperations = 0
        self.lastBlockHeight = getCurrentBlock().height
        
        // Initialize stats
        self.totalStakeOperations = 0
        self.totalUnstakeOperations = 0
        self.totalFlowStaked = 0.0
        self.totalStFlowMinted = 0.0
        
        // Create and store admin resource
        let admin <- create Admin()
        self.account.storage.save(<-admin, to: self.AdminStoragePath)
        
        // Create and store empty FLOW vault
        let flowVault <- FlowToken.createEmptyVault(vaultType: Type<@FlowToken.Vault>())
        self.account.storage.save(<-flowVault, to: self.FlowVaultStoragePath)
        
        // Link public capability for FLOW deposits
        let flowReceiverCap = self.account.capabilities.storage.issue<&{FlowToken.Receiver}>(self.FlowVaultStoragePath)
        self.account.capabilities.publish(flowReceiverCap, at: /public/flowTokenReceiver)
    }
    
    // Admin resource for managing the router
    access(all) resource Admin {
        
        access(all) fun authorizeEVMCaller(caller: Address) {
            ActionRouter.authorizedEVMCallers[caller] = true
            emit EVMCallerAuthorized(caller: caller)
        }
        
        access(all) fun revokeEVMCaller(caller: Address) {
            ActionRouter.authorizedEVMCallers.remove(key: caller)
            emit EVMCallerRevoked(caller: caller)
        }
        
        access(all) fun setActive(active: Bool) {
            ActionRouter.isActive = active
        }
        
        access(all) fun updateLimits(minStake: UFix64, maxStake: UFix64, maxOpsPerBlock: UInt64) {
            pre {
                minStake > 0.0: "Minimum stake must be positive"
                maxStake >= minStake: "Maximum stake must be >= minimum"
                maxOpsPerBlock > 0: "Max operations per block must be positive"
            }
            ActionRouter.minStakeAmount = minStake
            ActionRouter.maxStakeAmount = maxStake
            ActionRouter.maxOperationsPerBlock = maxOpsPerBlock
            emit RouterConfigUpdated(minStake: minStake, maxStake: maxStake)
        }
        
        access(all) fun emergencyWithdraw(amount: UFix64, recipient: Address) {
            pre {
                amount > 0.0: "Amount must be positive"
            }
            
            let flowVaultRef = ActionRouter.account.storage.borrow<&FlowToken.Vault>(from: ActionRouter.FlowVaultStoragePath)
                ?? panic("Could not borrow FlowToken vault")
            
            let withdrawnFlow <- flowVaultRef.withdraw(amount: amount)
            
            let recipientAccount = getAccount(recipient)
            let recipientFlowVault = recipientAccount.capabilities.get<&{FlowToken.Receiver}>(/public/flowTokenReceiver).borrow()
                ?? panic("Could not borrow recipient FlowToken receiver")
            
            recipientFlowVault.deposit(from: <-withdrawnFlow)
        }
    }
    
    // Rate limiting function
    access(self) fun checkRateLimit() {
        let currentBlock = getCurrentBlock().height
        
        if currentBlock > self.lastBlockHeight {
            self.currentBlockOperations = 0
            self.lastBlockHeight = currentBlock
        }
        
        assert(
            self.currentBlockOperations < self.maxOperationsPerBlock,
            message: "Rate limit exceeded for this block"
        )
        
        self.currentBlockOperations = self.currentBlockOperations + 1
    }
    
    // Main staking function callable by authorized EVM addresses
    access(all) fun stakeFlow(amount: UFix64, recipient: Address, requestId: String): StakeResult {
        pre {
            self.isActive: "Router is not active"
            self.authorizedEVMCallers[recipient] == true: "Caller not authorized"
            amount >= self.minStakeAmount: "Amount below minimum"
            amount <= self.maxStakeAmount: "Amount above maximum"
        }
        
        self.checkRateLimit()
        
        // Get FLOW from contract's vault
        let flowVaultRef = self.account.storage.borrow<&FlowToken.Vault>(from: self.FlowVaultStoragePath)
            ?? panic("Could not borrow FlowToken vault")
        
        assert(flowVaultRef.balance >= amount, message: "Insufficient FLOW balance in router")
        
        // Withdraw FLOW for staking
        let flowToStake <- flowVaultRef.withdraw(amount: amount)
        
        // Get current exchange rate before staking
        let exchangeRateBefore = LiquidStaking.getExchangeRate()
        
        // Execute staking through Increment's LiquidStaking
        let stFlowVault <- LiquidStaking.stake(flowVault: <-flowToStake)
        let stFlowAmount = stFlowVault.balance
        
        // Get updated exchange rate
        let exchangeRateAfter = LiquidStaking.getExchangeRate()
        
        // Store stFLOW in contract
        let existingStFlowVaultRef = self.account.storage.borrow<&stFlowToken.Vault>(from: self.StFlowVaultStoragePath)
        if existingStFlowVaultRef != nil {
            existingStFlowVaultRef!.deposit(from: <-stFlowVault)
        } else {
            self.account.storage.save(<-stFlowVault, to: self.StFlowVaultStoragePath)
        }
        
        // Update stats
        self.totalStakeOperations = self.totalStakeOperations + 1
        self.totalFlowStaked = self.totalFlowStaked + amount
        self.totalStFlowMinted = self.totalStFlowMinted + stFlowAmount
        
        emit StakeExecuted(
            amount: amount,
            recipient: recipient,
            stFlowReceived: stFlowAmount,
            exchangeRate: exchangeRateAfter,
            requestId: requestId
        )
        
        return StakeResult(
            flowAmount: amount,
            stFlowReceived: stFlowAmount,
            exchangeRate: exchangeRateAfter,
            requestId: requestId,
            success: true
        )
    }
    
    // Main unstaking function
    access(all) fun unstakeFlow(stFlowAmount: UFix64, recipient: Address, requestId: String): UnstakeResult {
        pre {
            self.isActive: "Router is not active"
            self.authorizedEVMCallers[recipient] == true: "Caller not authorized"
            stFlowAmount > 0.0: "Amount must be positive"
        }
        
        self.checkRateLimit()
        
        // Get stFLOW vault
        let stFlowVaultRef = self.account.storage.borrow<&stFlowToken.Vault>(from: self.StFlowVaultStoragePath)
            ?? panic("Could not borrow stFlowToken vault")
        
        assert(stFlowVaultRef.balance >= stFlowAmount, message: "Insufficient stFLOW balance")
        
        // Withdraw stFLOW for unstaking
        let stFlowToUnstake <- stFlowVaultRef.withdraw(amount: stFlowAmount)
        
        // Execute unstaking through Increment's LiquidStaking
        let flowVault <- LiquidStaking.unstake(stFlowVault: <-stFlowToUnstake)
        let flowAmount = flowVault.balance
        
        // Store FLOW back in contract vault
        let existingFlowVaultRef = self.account.storage.borrow<&FlowToken.Vault>(from: self.FlowVaultStoragePath)
        if existingFlowVaultRef != nil {
            existingFlowVaultRef!.deposit(from: <-flowVault)
        } else {
            self.account.storage.save(<-flowVault, to: self.FlowVaultStoragePath)
        }
        
        // Update stats
        self.totalUnstakeOperations = self.totalUnstakeOperations + 1
        
        emit UnstakeExecuted(
            amount: stFlowAmount,
            recipient: recipient,
            flowReceived: flowAmount,
            requestId: requestId
        )
        
        return UnstakeResult(
            stFlowAmount: stFlowAmount,
            flowReceived: flowAmount,
            requestId: requestId,
            success: true
        )
    }
    
    // Query functions for EVM integration
    access(all) view fun getExchangeRate(): UFix64 {
        return LiquidStaking.getExchangeRate()
    }
    
    access(all) view fun getStFlowBalance(): UFix64 {
        let stFlowVaultRef = self.account.storage.borrow<&stFlowToken.Vault>(from: self.StFlowVaultStoragePath)
        if stFlowVaultRef != nil {
            return stFlowVaultRef!.balance
        }
        return 0.0
    }
    
    access(all) view fun getFlowBalance(): UFix64 {
        let flowVaultRef = self.account.storage.borrow<&FlowToken.Vault>(from: self.FlowVaultStoragePath)
        if flowVaultRef != nil {
            return flowVaultRef!.balance
        }
        return 0.0
    }
    
    access(all) view fun getStats(): RouterStats {
        return RouterStats(
            totalStakeOps: self.totalStakeOperations,
            totalUnstakeOps: self.totalUnstakeOperations,
            totalFlowStaked: self.totalFlowStaked,
            totalStFlowMinted: self.totalStFlowMinted,
            currentFlowBalance: self.getFlowBalance(),
            currentStFlowBalance: self.getStFlowBalance(),
            isActive: self.isActive
        )
    }
    
    access(all) view fun isAuthorized(caller: Address): Bool {
        return self.authorizedEVMCallers[caller] == true
    }
    
    // Price oracle integration
    access(all) view fun getStFlowPrice(): UFix64? {
        let priceData = PublicPriceOracle.getPrice(oracleAddr: 0x031dabc5ba1d2932)
        return priceData?.price
    }
    
    access(all) view fun getFlowPrice(): UFix64? {
        let priceData = PublicPriceOracle.getPrice(oracleAddr: 0xe385412159992e11)
        return priceData?.price
    }
}

// Result structs
access(all) struct StakeResult {
    access(all) let flowAmount: UFix64
    access(all) let stFlowReceived: UFix64
    access(all) let exchangeRate: UFix64
    access(all) let requestId: String
    access(all) let success: Bool
    
    init(flowAmount: UFix64, stFlowReceived: UFix64, exchangeRate: UFix64, requestId: String, success: Bool) {
        self.flowAmount = flowAmount
        self.stFlowReceived = stFlowReceived
        self.exchangeRate = exchangeRate
        self.requestId = requestId
        self.success = success
    }
}

access(all) struct UnstakeResult {
    access(all) let stFlowAmount: UFix64
    access(all) let flowReceived: UFix64
    access(all) let requestId: String
    access(all) let success: Bool
    
    init(stFlowAmount: UFix64, flowReceived: UFix64, requestId: String, success: Bool) {
        self.stFlowAmount = stFlowAmount
        self.flowReceived = flowReceived
        self.requestId = requestId
        self.success = success
    }
}

access(all) struct RouterStats {
    access(all) let totalStakeOps: UInt64
    access(all) let totalUnstakeOps: UInt64
    access(all) let totalFlowStaked: UFix64
    access(all) let totalStFlowMinted: UFix64
    access(all) let currentFlowBalance: UFix64
    access(all) let currentStFlowBalance: UFix64
    access(all) let isActive: Bool
    
    init(
        totalStakeOps: UInt64,
        totalUnstakeOps: UInt64,
        totalFlowStaked: UFix64,
        totalStFlowMinted: UFix64,
        currentFlowBalance: UFix64,
        currentStFlowBalance: UFix64,
        isActive: Bool
    ) {
        self.totalStakeOps = totalStakeOps
        self.totalUnstakeOps = totalUnstakeOps
        self.totalFlowStaked = totalFlowStaked
        self.totalStFlowMinted = totalStFlowMinted
        self.currentFlowBalance = currentFlowBalance
        self.currentStFlowBalance = currentStFlowBalance
        self.isActive = isActive
    }
}