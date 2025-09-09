import FlowToken from 0x1654653399040a61
import stFlowToken from 0xd6f80565193ad727
import LiquidStaking from 0xd6f80565193ad727 // Placeholder???
import FungibleToken from 0xf233dcee88fe0abe

access(all) contract ActionRouterV2 {
    
    access(all) let AdminStoragePath: StoragePath
    access(all) let FlowVaultStoragePath: StoragePath
    access(all) let StFlowVaultStoragePath: StoragePath
    
    // Changed: Store Ethereum addresses as strings instead of Flow addresses
    access(self) var authorizedEVMCallers: {String: Bool}
    access(self) var isActive: Bool
    access(self) var minStakeAmount: UFix64
    access(self) var maxStakeAmount: UFix64
    access(self) var maxOperationsPerBlock: UInt64
    access(self) var currentBlockOperations: UInt64
    access(self) var lastBlockHeight: UInt64
    
    access(all) var totalStakeOperations: UInt64
    access(all) var totalUnstakeOperations: UInt64
    access(all) var totalFlowStaked: UFix64
    access(all) var totalStFlowMinted: UFix64
    
    // Updated events to use String for EVM addresses
    access(all) event StakeExecuted(amount: UFix64, recipient: String, stFlowReceived: UFix64, exchangeRate: UFix64, requestId: String)
    access(all) event UnstakeExecuted(amount: UFix64, recipient: String, flowReceived: UFix64, requestId: String)
    access(all) event EVMCallerAuthorized(caller: String)
    access(all) event EVMCallerRevoked(caller: String)
    access(all) event RouterConfigUpdated(minStake: UFix64, maxStake: UFix64)
    
    // Struct definitions moved inside the contract
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
    
    init() {
        self.AdminStoragePath = /storage/ActionRouterV2Admin
        self.FlowVaultStoragePath = /storage/ActionRouterV2FlowVault
        self.StFlowVaultStoragePath = /storage/ActionRouterV2StFlowVault
        
        self.authorizedEVMCallers = {}
        self.isActive = true
        self.minStakeAmount = 1.0
        self.maxStakeAmount = 10000.0
        self.maxOperationsPerBlock = 10
        self.currentBlockOperations = 0
        self.lastBlockHeight = getCurrentBlock().height
        
        self.totalStakeOperations = 0
        self.totalUnstakeOperations = 0
        self.totalFlowStaked = 0.0
        self.totalStFlowMinted = 0.0
        
        let admin <- create Admin()
        self.account.storage.save(<-admin, to: self.AdminStoragePath)
        
        let flowVault <- FlowToken.createEmptyVault(vaultType: Type<@FlowToken.Vault>())
        self.account.storage.save(<-flowVault, to: self.FlowVaultStoragePath)
        
        // Only create the capability if it doesn't already exist
        if self.account.capabilities.get<&{FungibleToken.Receiver}>(/public/flowTokenReceiver).check() == false {
            let flowReceiverCap = self.account.capabilities.storage.issue<&{FungibleToken.Receiver}>(self.FlowVaultStoragePath)
            self.account.capabilities.publish(flowReceiverCap, at: /public/flowTokenReceiver)
        }
    }
    
    access(all) resource Admin {
        
        // Updated: Accept Ethereum address as string
        access(all) fun authorizeEVMCaller(caller: String) {
            pre {
                caller.length > 0: "Caller address cannot be empty"
                caller.slice(from: 0, upTo: 2) == "0x": "Caller must be a valid Ethereum address starting with 0x"
                caller.length == 42: "Ethereum address must be 42 characters long"
            }
            ActionRouterV2.authorizedEVMCallers[caller] = true
            emit EVMCallerAuthorized(caller: caller)
        }
        
        access(all) fun revokeEVMCaller(caller: String) {
            ActionRouterV2.authorizedEVMCallers.remove(key: caller)
            emit EVMCallerRevoked(caller: caller)
        }
        
        access(all) fun setActive(active: Bool) {
            ActionRouterV2.isActive = active
        }
        
        access(all) fun updateLimits(minStake: UFix64, maxStake: UFix64, maxOpsPerBlock: UInt64) {
            pre {
                minStake > 0.0: "Minimum stake must be positive"
                maxStake >= minStake: "Maximum stake must be >= minimum"
                maxOpsPerBlock > 0: "Max operations per block must be positive"
            }
            ActionRouterV2.minStakeAmount = minStake
            ActionRouterV2.maxStakeAmount = maxStake
            ActionRouterV2.maxOperationsPerBlock = maxOpsPerBlock
            emit RouterConfigUpdated(minStake: minStake, maxStake: maxStake)
        }
        
        access(all) fun emergencyWithdraw(amount: UFix64, recipient: Address) {
            pre {
                amount > 0.0: "Amount must be positive"
            }
            
            let flowVaultRef = ActionRouterV2.account.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(from: ActionRouterV2.FlowVaultStoragePath)
                ?? panic("Could not borrow FlowToken vault")
            
            let withdrawnFlow <- flowVaultRef.withdraw(amount: amount)
            
            let recipientAccount = getAccount(recipient)
            let recipientFlowVault = recipientAccount.capabilities.get<&{FungibleToken.Receiver}>(/public/flowTokenReceiver).borrow()
                ?? panic("Could not borrow recipient FlowToken receiver")
            
            recipientFlowVault.deposit(from: <-withdrawnFlow)
        }
    }
    
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
    
    // Updated: Accept Ethereum address as string
    access(all) fun stakeFlow(amount: UFix64, recipient: String, requestId: String): StakeResult {
        pre {
            self.isActive: "Router is not active"
            self.authorizedEVMCallers[recipient] == true: "Caller not authorized"
            amount >= self.minStakeAmount: "Amount below minimum"
            amount <= self.maxStakeAmount: "Amount above maximum"
        }
        
        self.checkRateLimit()
        
        let flowVaultRef = self.account.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(from: self.FlowVaultStoragePath)
            ?? panic("Could not borrow FlowToken vault")
        
        assert(flowVaultRef.balance >= amount, message: "Insufficient FLOW balance in router")
        
        let flowToStake <- flowVaultRef.withdraw(amount: amount) as! @FlowToken.Vault
        let exchangeRateBefore = 1.0 // Placeholder
        let stFlowVault <- LiquidStaking.stake(flowVault: <-flowToStake)
        let stFlowAmount = stFlowVault.balance
        let exchangeRateAfter = 1.0 // Placeholder
        
        let existingStFlowVaultRef = self.account.storage.borrow<&stFlowToken.Vault>(from: self.StFlowVaultStoragePath)
        if existingStFlowVaultRef != nil {
            existingStFlowVaultRef!.deposit(from: <-stFlowVault)
        } else {
            self.account.storage.save(<-stFlowVault, to: self.StFlowVaultStoragePath)
        }
        
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
    
    // Updated: Accept Ethereum address as string
    access(all) fun unstakeFlow(stFlowAmount: UFix64, recipient: String, requestId: String): UnstakeResult {
        pre {
            self.isActive: "Router is not active"
            self.authorizedEVMCallers[recipient] == true: "Caller not authorized"
            stFlowAmount > 0.0: "Amount must be positive"
        }
        
        self.checkRateLimit()
        
        let stFlowVaultRef = self.account.storage.borrow<auth(FungibleToken.Withdraw) &stFlowToken.Vault>(from: self.StFlowVaultStoragePath)
            ?? panic("Could not borrow stFlowToken vault")
        
        assert(stFlowVaultRef.balance >= stFlowAmount, message: "Insufficient stFLOW balance")
        
        let stFlowToUnstake <- stFlowVaultRef.withdraw(amount: stFlowAmount) as! @stFlowToken.Vault
        let withdrawVoucher <- LiquidStaking.unstake(stFlowVault: <-stFlowToUnstake)
        
        let flowAmount = 0.0 // Placeholder
        destroy withdrawVoucher
        
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
    
    access(all) view fun getExchangeRate(): UFix64 {
        return 1.0 // Placeholder
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
    
    access(all) fun getStats(): RouterStats {
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
    
    // Updated: Accept Ethereum address as string
    access(all) view fun isAuthorized(caller: String): Bool {
        return self.authorizedEVMCallers[caller] == true
    }
}