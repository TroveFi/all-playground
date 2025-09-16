import FlowToken from 0x1654653399040a61
import stFlowToken from 0xd6f80565193ad727
import LiquidStaking from 0xd6f80565193ad727
import FungibleToken from 0xf233dcee88fe0abe

access(all) contract ActionRouterV3 {
    
    access(all) let AdminStoragePath: StoragePath
    access(all) let FlowVaultStoragePath: StoragePath
    access(all) let StFlowVaultStoragePath: StoragePath
    
    access(self) var authorizedEVMCallers: {String: Bool}
    access(self) var isActive: Bool
    access(self) var minStakeAmount: UFix64
    access(self) var maxStakeAmount: UFix64
    access(self) var maxOperationsPerBlock: UInt64
    access(self) var currentBlockOperations: UInt64
    access(self) var lastBlockHeight: UInt64
    access(self) var pausedOperations: {String: Bool}
    access(self) var protocolFeeRate: UFix64 // New fee mechanism
    
    access(all) var totalStakeOperations: UInt64
    access(all) var totalUnstakeOperations: UInt64
    access(all) var totalFlowStaked: UFix64
    access(all) var totalStFlowMinted: UFix64
    access(all) var accumulatedFees: UFix64
    access(all) var contractVersion: String
    
    // Enhanced events with more context
    access(all) event StakeExecuted(
        amount: UFix64, 
        recipient: String, 
        stFlowReceived: UFix64, 
        exchangeRate: UFix64, 
        requestId: String,
        blockHeight: UInt64,
        timestamp: UFix64,
        protocolFee: UFix64
    )
    access(all) event UnstakeExecuted(
        amount: UFix64, 
        recipient: String, 
        flowReceived: UFix64, 
        requestId: String,
        blockHeight: UInt64,
        timestamp: UFix64,
        protocolFee: UFix64
    )
    access(all) event EVMCallerAuthorized(caller: String, authorizedBy: Address)
    access(all) event EVMCallerRevoked(caller: String, revokedBy: Address)
    access(all) event RouterConfigUpdated(
        minStake: UFix64, 
        maxStake: UFix64, 
        maxOpsPerBlock: UInt64,
        protocolFeeRate: UFix64,
        updatedBy: Address
    )
    access(all) event RouterPaused(operation: String, pausedBy: Address)
    access(all) event RouterUnpaused(operation: String, unpausedBy: Address)
    access(all) event EmergencyWithdraw(
        amount: UFix64, 
        recipient: Address, 
        reason: String, 
        executedBy: Address
    )
    access(all) event BatchOperationExecuted(
        operationType: String,
        requestCount: Int,
        successCount: Int,
        totalAmount: UFix64
    )
    
    // Error codes for better error handling
    access(all) enum ErrorCode: UInt8 {
        access(all) case SUCCESS
        access(all) case ROUTER_INACTIVE
        access(all) case UNAUTHORIZED_CALLER
        access(all) case AMOUNT_OUT_OF_BOUNDS
        access(all) case RATE_LIMIT_EXCEEDED
        access(all) case INSUFFICIENT_BALANCE
        access(all) case OPERATION_PAUSED
        access(all) case INVALID_REQUEST_ID
        access(all) case LIQUIDSTAKING_ERROR
        access(all) case PROTOCOL_FEE_ERROR
    }
    
    access(all) struct StakeResult {
        access(all) let flowAmount: UFix64
        access(all) let stFlowReceived: UFix64
        access(all) let exchangeRate: UFix64
        access(all) let protocolFee: UFix64
        access(all) let requestId: String
        access(all) let success: Bool
        access(all) let errorCode: ErrorCode
        access(all) let timestamp: UFix64
        access(all) let blockHeight: UInt64
        
        init(
            flowAmount: UFix64, 
            stFlowReceived: UFix64, 
            exchangeRate: UFix64, 
            protocolFee: UFix64,
            requestId: String, 
            success: Bool,
            errorCode: ErrorCode,
            timestamp: UFix64,
            blockHeight: UInt64
        ) {
            self.flowAmount = flowAmount
            self.stFlowReceived = stFlowReceived
            self.exchangeRate = exchangeRate
            self.protocolFee = protocolFee
            self.requestId = requestId
            self.success = success
            self.errorCode = errorCode
            self.timestamp = timestamp
            self.blockHeight = blockHeight
        }
    }

    access(all) struct UnstakeResult {
        access(all) let stFlowAmount: UFix64
        access(all) let flowReceived: UFix64
        access(all) let protocolFee: UFix64
        access(all) let requestId: String
        access(all) let success: Bool
        access(all) let errorCode: ErrorCode
        access(all) let timestamp: UFix64
        access(all) let blockHeight: UInt64
        
        init(
            stFlowAmount: UFix64, 
            flowReceived: UFix64, 
            protocolFee: UFix64,
            requestId: String, 
            success: Bool,
            errorCode: ErrorCode,
            timestamp: UFix64,
            blockHeight: UInt64
        ) {
            self.stFlowAmount = stFlowAmount
            self.flowReceived = flowReceived
            self.protocolFee = protocolFee
            self.requestId = requestId
            self.success = success
            self.errorCode = errorCode
            self.timestamp = timestamp
            self.blockHeight = blockHeight
        }
    }

    access(all) struct RouterStats {
        access(all) let totalStakeOps: UInt64
        access(all) let totalUnstakeOps: UInt64
        access(all) let totalFlowStaked: UFix64
        access(all) let totalStFlowMinted: UFix64
        access(all) let currentFlowBalance: UFix64
        access(all) let currentStFlowBalance: UFix64
        access(all) let accumulatedFees: UFix64
        access(all) let exchangeRate: UFix64
        access(all) let protocolFeeRate: UFix64
        access(all) let isActive: Bool
        access(all) let rateLimitStatus: UInt64
        access(all) let version: String
        access(all) let blockHeight: UInt64
        access(all) let timestamp: UFix64
        
        init(
            totalStakeOps: UInt64,
            totalUnstakeOps: UInt64,
            totalFlowStaked: UFix64,
            totalStFlowMinted: UFix64,
            currentFlowBalance: UFix64,
            currentStFlowBalance: UFix64,
            accumulatedFees: UFix64,
            exchangeRate: UFix64,
            protocolFeeRate: UFix64,
            isActive: Bool,
            rateLimitStatus: UInt64,
            version: String,
            blockHeight: UInt64,
            timestamp: UFix64
        ) {
            self.totalStakeOps = totalStakeOps
            self.totalUnstakeOps = totalUnstakeOps
            self.totalFlowStaked = totalFlowStaked
            self.totalStFlowMinted = totalStFlowMinted
            self.currentFlowBalance = currentFlowBalance
            self.currentStFlowBalance = currentStFlowBalance
            self.accumulatedFees = accumulatedFees
            self.exchangeRate = exchangeRate
            self.protocolFeeRate = protocolFeeRate
            self.isActive = isActive
            self.rateLimitStatus = rateLimitStatus
            self.version = version
            self.blockHeight = blockHeight
            self.timestamp = timestamp
        }
    }
    
    access(all) struct RouterConfig {
        access(all) let minStakeAmount: UFix64
        access(all) let maxStakeAmount: UFix64
        access(all) let maxOperationsPerBlock: UInt64
        access(all) let protocolFeeRate: UFix64
        access(all) let isActive: Bool
        access(all) let authorizedCallersCount: Int
        access(all) let pausedOperations: [String]
        access(all) let version: String
        
        init(
            minStakeAmount: UFix64,
            maxStakeAmount: UFix64,
            maxOperationsPerBlock: UInt64,
            protocolFeeRate: UFix64,
            isActive: Bool,
            authorizedCallersCount: Int,
            pausedOperations: [String],
            version: String
        ) {
            self.minStakeAmount = minStakeAmount
            self.maxStakeAmount = maxStakeAmount
            self.maxOperationsPerBlock = maxOperationsPerBlock
            self.protocolFeeRate = protocolFeeRate
            self.isActive = isActive
            self.authorizedCallersCount = authorizedCallersCount
            self.pausedOperations = pausedOperations
            self.version = version
        }
    }

    access(all) struct BatchStakeRequest {
        access(all) let amount: UFix64
        access(all) let recipient: String
        access(all) let requestId: String
        
        init(amount: UFix64, recipient: String, requestId: String) {
            self.amount = amount
            self.recipient = recipient
            self.requestId = requestId
        }
    }

    access(all) struct BatchUnstakeRequest {
        access(all) let stFlowAmount: UFix64
        access(all) let recipient: String
        access(all) let requestId: String
        
        init(stFlowAmount: UFix64, recipient: String, requestId: String) {
            self.stFlowAmount = stFlowAmount
            self.recipient = recipient
            self.requestId = requestId
        }
    }
    
    init() {
        self.AdminStoragePath = /storage/ActionRouterV3Admin
        self.FlowVaultStoragePath = /storage/ActionRouterV3FlowVault
        self.StFlowVaultStoragePath = /storage/ActionRouterV3StFlowVault
        
        self.authorizedEVMCallers = {}
        self.pausedOperations = {}
        self.isActive = true
        self.minStakeAmount = 1.0
        self.maxStakeAmount = 10000.0
        self.maxOperationsPerBlock = 25 // Increased for V3
        self.currentBlockOperations = 0
        self.lastBlockHeight = getCurrentBlock().height
        self.protocolFeeRate = 0.001 // 0.1% protocol fee
        
        self.totalStakeOperations = 0
        self.totalUnstakeOperations = 0
        self.totalFlowStaked = 0.0
        self.totalStFlowMinted = 0.0
        self.accumulatedFees = 0.0
        self.contractVersion = "3.0.0"
        
        let admin <- create Admin()
        self.account.storage.save(<-admin, to: self.AdminStoragePath)
        
        let flowVault <- FlowToken.createEmptyVault(vaultType: Type<@FlowToken.Vault>())
        self.account.storage.save(<-flowVault, to: self.FlowVaultStoragePath)
        
        // Ensure proper capability setup
        if self.account.capabilities.get<&{FungibleToken.Receiver}>(/public/flowTokenReceiver).check() == false {
            let flowReceiverCap = self.account.capabilities.storage.issue<&{FungibleToken.Receiver}>(self.FlowVaultStoragePath)
            self.account.capabilities.publish(flowReceiverCap, at: /public/flowTokenReceiver)
        }
    }
    
    access(all) resource Admin {
        
        access(all) fun authorizeEVMCaller(caller: String) {
            pre {
                caller.length > 0: "Caller address cannot be empty"
                caller.slice(from: 0, upTo: 2) == "0x": "Caller must be a valid Ethereum address starting with 0x"
                caller.length == 42: "Ethereum address must be 42 characters long"
            }
            ActionRouterV3.authorizedEVMCallers[caller] = true
            emit EVMCallerAuthorized(caller: caller, authorizedBy: self.owner!.address)
        }
        
        access(all) fun revokeEVMCaller(caller: String) {
            ActionRouterV3.authorizedEVMCallers.remove(key: caller)
            emit EVMCallerRevoked(caller: caller, revokedBy: self.owner!.address)
        }
        
        access(all) fun setActive(active: Bool) {
            ActionRouterV3.isActive = active
        }
        
        access(all) fun pauseOperation(operation: String) {
            pre {
                operation == "stake" || operation == "unstake" || operation == "batch": "Invalid operation type"
            }
            ActionRouterV3.pausedOperations[operation] = true
            emit RouterPaused(operation: operation, pausedBy: self.owner!.address)
        }
        
        access(all) fun unpauseOperation(operation: String) {
            pre {
                operation == "stake" || operation == "unstake" || operation == "batch": "Invalid operation type"
            }
            ActionRouterV3.pausedOperations.remove(key: operation)
            emit RouterUnpaused(operation: operation, unpausedBy: self.owner!.address)
        }
        
        access(all) fun updateLimits(
            minStake: UFix64, 
            maxStake: UFix64, 
            maxOpsPerBlock: UInt64,
            protocolFeeRate: UFix64
        ) {
            pre {
                minStake > 0.0: "Minimum stake must be positive"
                maxStake >= minStake: "Maximum stake must be >= minimum"
                maxOpsPerBlock > 0: "Max operations per block must be positive"
                protocolFeeRate >= 0.0 && protocolFeeRate <= 0.01: "Protocol fee must be between 0% and 1%"
            }
            ActionRouterV3.minStakeAmount = minStake
            ActionRouterV3.maxStakeAmount = maxStake
            ActionRouterV3.maxOperationsPerBlock = maxOpsPerBlock
            ActionRouterV3.protocolFeeRate = protocolFeeRate
            emit RouterConfigUpdated(
                minStake: minStake, 
                maxStake: maxStake, 
                maxOpsPerBlock: maxOpsPerBlock,
                protocolFeeRate: protocolFeeRate,
                updatedBy: self.owner!.address
            )
        }
        
        access(all) fun emergencyWithdraw(amount: UFix64, recipient: Address, reason: String) {
            pre {
                amount > 0.0: "Amount must be positive"
                reason.length > 0: "Emergency reason required"
            }
            
            let flowVaultRef = ActionRouterV3.account.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(from: ActionRouterV3.FlowVaultStoragePath)
                ?? panic("Could not borrow FlowToken vault")
            
            assert(flowVaultRef.balance >= amount, message: "Insufficient balance for emergency withdrawal")
            
            let withdrawnFlow <- flowVaultRef.withdraw(amount: amount)
            
            let recipientAccount = getAccount(recipient)
            let recipientFlowVault = recipientAccount.capabilities.get<&{FungibleToken.Receiver}>(/public/flowTokenReceiver).borrow()
                ?? panic("Could not borrow recipient FlowToken receiver")
            
            recipientFlowVault.deposit(from: <-withdrawnFlow)
            emit EmergencyWithdraw(
                amount: amount, 
                recipient: recipient, 
                reason: reason,
                executedBy: self.owner!.address
            )
        }
        
        access(all) fun resetRateLimit() {
            ActionRouterV3.currentBlockOperations = 0
        }

        access(all) fun withdrawAccumulatedFees(recipient: Address) {
            let feesToWithdraw = ActionRouterV3.accumulatedFees
            if feesToWithdraw > 0.0 {
                let flowVaultRef = ActionRouterV3.account.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(from: ActionRouterV3.FlowVaultStoragePath)
                    ?? panic("Could not borrow FlowToken vault")
                
                if flowVaultRef.balance >= feesToWithdraw {
                    let feeVault <- flowVaultRef.withdraw(amount: feesToWithdraw)
                    let recipientAccount = getAccount(recipient)
                    let recipientFlowVault = recipientAccount.capabilities.get<&{FungibleToken.Receiver}>(/public/flowTokenReceiver).borrow()
                        ?? panic("Could not borrow recipient FlowToken receiver")
                    
                    recipientFlowVault.deposit(from: <-feeVault)
                    ActionRouterV3.accumulatedFees = 0.0
                }
            }
        }
    }
    
    access(self) fun checkRateLimit(): Bool {
        let currentBlock = getCurrentBlock().height
        
        if currentBlock > self.lastBlockHeight {
            self.currentBlockOperations = 0
            self.lastBlockHeight = currentBlock
        }
        
        if self.currentBlockOperations >= self.maxOperationsPerBlock {
            return false
        }
        
        self.currentBlockOperations = self.currentBlockOperations + 1
        return true
    }
    
    access(self) fun validateRequestId(_ requestId: String): Bool {
        return requestId.length > 0 && requestId.length <= 128
    }
    
    access(self) fun validateEthereumAddress(_ address: String): Bool {
        return address.length == 42 && address.slice(from: 0, upTo: 2) == "0x"
    }

    access(self) fun calculateProtocolFee(_ amount: UFix64): UFix64 {
        return amount * self.protocolFeeRate
    }
    
    access(all) fun stakeFlow(amount: UFix64, recipient: String, requestId: String): StakeResult {
        let timestamp = getCurrentBlock().timestamp
        let blockHeight = getCurrentBlock().height
        
        // Validate inputs
        if !self.validateRequestId(requestId) {
            return StakeResult(
                flowAmount: amount, stFlowReceived: 0.0, exchangeRate: 0.0, protocolFee: 0.0,
                requestId: requestId, success: false, errorCode: ErrorCode.INVALID_REQUEST_ID,
                timestamp: timestamp, blockHeight: blockHeight
            )
        }
        
        if !self.validateEthereumAddress(recipient) {
            return StakeResult(
                flowAmount: amount, stFlowReceived: 0.0, exchangeRate: 0.0, protocolFee: 0.0,
                requestId: requestId, success: false, errorCode: ErrorCode.UNAUTHORIZED_CALLER,
                timestamp: timestamp, blockHeight: blockHeight
            )
        }
        
        if !self.isActive {
            return StakeResult(
                flowAmount: amount, stFlowReceived: 0.0, exchangeRate: 0.0, protocolFee: 0.0,
                requestId: requestId, success: false, errorCode: ErrorCode.ROUTER_INACTIVE,
                timestamp: timestamp, blockHeight: blockHeight
            )
        }
        
        if self.pausedOperations["stake"] == true {
            return StakeResult(
                flowAmount: amount, stFlowReceived: 0.0, exchangeRate: 0.0, protocolFee: 0.0,
                requestId: requestId, success: false, errorCode: ErrorCode.OPERATION_PAUSED,
                timestamp: timestamp, blockHeight: blockHeight
            )
        }
        
        if self.authorizedEVMCallers[recipient] != true {
            return StakeResult(
                flowAmount: amount, stFlowReceived: 0.0, exchangeRate: 0.0, protocolFee: 0.0,
                requestId: requestId, success: false, errorCode: ErrorCode.UNAUTHORIZED_CALLER,
                timestamp: timestamp, blockHeight: blockHeight
            )
        }
        
        if amount < self.minStakeAmount || amount > self.maxStakeAmount {
            return StakeResult(
                flowAmount: amount, stFlowReceived: 0.0, exchangeRate: 0.0, protocolFee: 0.0,
                requestId: requestId, success: false, errorCode: ErrorCode.AMOUNT_OUT_OF_BOUNDS,
                timestamp: timestamp, blockHeight: blockHeight
            )
        }
        
        if !self.checkRateLimit() {
            return StakeResult(
                flowAmount: amount, stFlowReceived: 0.0, exchangeRate: 0.0, protocolFee: 0.0,
                requestId: requestId, success: false, errorCode: ErrorCode.RATE_LIMIT_EXCEEDED,
                timestamp: timestamp, blockHeight: blockHeight
            )
        }
        
        let flowVaultRef = self.account.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(from: self.FlowVaultStoragePath)
            ?? panic("Could not borrow FlowToken vault")
        
        if flowVaultRef.balance < amount {
            return StakeResult(
                flowAmount: amount, stFlowReceived: 0.0, exchangeRate: 0.0, protocolFee: 0.0,
                requestId: requestId, success: false, errorCode: ErrorCode.INSUFFICIENT_BALANCE,
                timestamp: timestamp, blockHeight: blockHeight
            )
        }
        
        // Calculate protocol fee
        let protocolFee = self.calculateProtocolFee(amount)
        let amountAfterFee = amount - protocolFee
        
        let flowToStake <- flowVaultRef.withdraw(amount: amountAfterFee) as! @FlowToken.Vault
        
        // Execute the actual staking
        let exchangeRateAfter = LiquidStaking.getExchangeRate()
        let stFlowVault <- LiquidStaking.stake(flowVault: <-flowToStake)
        let stFlowAmount = stFlowVault.balance
        
        // Store the received stFLOW
        let existingStFlowVaultRef = self.account.storage.borrow<&stFlowToken.Vault>(from: self.StFlowVaultStoragePath)
        if existingStFlowVaultRef != nil {
            existingStFlowVaultRef!.deposit(from: <-stFlowVault)
        } else {
            self.account.storage.save(<-stFlowVault, to: self.StFlowVaultStoragePath)
        }
        
        // Update statistics and accumulate fees
        self.totalStakeOperations = self.totalStakeOperations + 1
        self.totalFlowStaked = self.totalFlowStaked + amount
        self.totalStFlowMinted = self.totalStFlowMinted + stFlowAmount
        self.accumulatedFees = self.accumulatedFees + protocolFee
        
        emit StakeExecuted(
            amount: amount, recipient: recipient, stFlowReceived: stFlowAmount,
            exchangeRate: exchangeRateAfter, requestId: requestId, blockHeight: blockHeight,
            timestamp: timestamp, protocolFee: protocolFee
        )
        
        return StakeResult(
            flowAmount: amount, stFlowReceived: stFlowAmount, exchangeRate: exchangeRateAfter,
            protocolFee: protocolFee, requestId: requestId, success: true,
            errorCode: ErrorCode.SUCCESS, timestamp: timestamp, blockHeight: blockHeight
        )
    }
    
    access(all) fun unstakeFlow(stFlowAmount: UFix64, recipient: String, requestId: String): UnstakeResult {
        let timestamp = getCurrentBlock().timestamp
        let blockHeight = getCurrentBlock().height
        
        // Validate inputs (similar to stakeFlow)
        if !self.validateRequestId(requestId) {
            return UnstakeResult(
                stFlowAmount: stFlowAmount, flowReceived: 0.0, protocolFee: 0.0,
                requestId: requestId, success: false, errorCode: ErrorCode.INVALID_REQUEST_ID,
                timestamp: timestamp, blockHeight: blockHeight
            )
        }
        
        if !self.validateEthereumAddress(recipient) {
            return UnstakeResult(
                stFlowAmount: stFlowAmount, flowReceived: 0.0, protocolFee: 0.0,
                requestId: requestId, success: false, errorCode: ErrorCode.UNAUTHORIZED_CALLER,
                timestamp: timestamp, blockHeight: blockHeight
            )
        }
        
        if !self.isActive {
            return UnstakeResult(
                stFlowAmount: stFlowAmount, flowReceived: 0.0, protocolFee: 0.0,
                requestId: requestId, success: false, errorCode: ErrorCode.ROUTER_INACTIVE,
                timestamp: timestamp, blockHeight: blockHeight
            )
        }
        
        if self.pausedOperations["unstake"] == true {
            return UnstakeResult(
                stFlowAmount: stFlowAmount, flowReceived: 0.0, protocolFee: 0.0,
                requestId: requestId, success: false, errorCode: ErrorCode.OPERATION_PAUSED,
                timestamp: timestamp, blockHeight: blockHeight
            )
        }
        
        if self.authorizedEVMCallers[recipient] != true {
            return UnstakeResult(
                stFlowAmount: stFlowAmount, flowReceived: 0.0, protocolFee: 0.0,
                requestId: requestId, success: false, errorCode: ErrorCode.UNAUTHORIZED_CALLER,
                timestamp: timestamp, blockHeight: blockHeight
            )
        }
        
        if stFlowAmount <= 0.0 {
            return UnstakeResult(
                stFlowAmount: stFlowAmount, flowReceived: 0.0, protocolFee: 0.0,
                requestId: requestId, success: false, errorCode: ErrorCode.AMOUNT_OUT_OF_BOUNDS,
                timestamp: timestamp, blockHeight: blockHeight
            )
        }
        
        if !self.checkRateLimit() {
            return UnstakeResult(
                stFlowAmount: stFlowAmount, flowReceived: 0.0, protocolFee: 0.0,
                requestId: requestId, success: false, errorCode: ErrorCode.RATE_LIMIT_EXCEEDED,
                timestamp: timestamp, blockHeight: blockHeight
            )
        }
        
        let stFlowVaultRef = self.account.storage.borrow<auth(FungibleToken.Withdraw) &stFlowToken.Vault>(from: self.StFlowVaultStoragePath)
            ?? panic("Could not borrow stFlowToken vault")
        
        if stFlowVaultRef.balance < stFlowAmount {
            return UnstakeResult(
                stFlowAmount: stFlowAmount, flowReceived: 0.0, protocolFee: 0.0,
                requestId: requestId, success: false, errorCode: ErrorCode.INSUFFICIENT_BALANCE,
                timestamp: timestamp, blockHeight: blockHeight
            )
        }
        
        let stFlowToUnstake <- stFlowVaultRef.withdraw(amount: stFlowAmount) as! @stFlowToken.Vault
        
        // Execute the actual unstaking
        let withdrawVoucher <- LiquidStaking.unstake(stFlowVault: <-stFlowToUnstake)
        let flowVault <- LiquidStaking.redeemVoucher(voucher: <-withdrawVoucher)
        let flowAmount = flowVault.balance
        
        // Calculate protocol fee on received FLOW
        let protocolFee = self.calculateProtocolFee(flowAmount)
        let amountAfterFee = flowAmount - protocolFee
        
        // Withdraw fee amount before storing
        let feeVault <- flowVault.withdraw(amount: protocolFee)
        destroy feeVault // In production, you might want to store this instead
        
        // Store the remaining FLOW
        let existingFlowVaultRef = self.account.storage.borrow<&FlowToken.Vault>(from: self.FlowVaultStoragePath)
        if existingFlowVaultRef != nil {
            existingFlowVaultRef!.deposit(from: <-flowVault)
        } else {
            self.account.storage.save(<-flowVault, to: self.FlowVaultStoragePath)
        }
        
        // Update statistics
        self.totalUnstakeOperations = self.totalUnstakeOperations + 1
        self.accumulatedFees = self.accumulatedFees + protocolFee
        
        emit UnstakeExecuted(
            amount: stFlowAmount, recipient: recipient, flowReceived: amountAfterFee,
            requestId: requestId, blockHeight: blockHeight, timestamp: timestamp,
            protocolFee: protocolFee
        )
        
        return UnstakeResult(
            stFlowAmount: stFlowAmount, flowReceived: amountAfterFee, protocolFee: protocolFee,
            requestId: requestId, success: true, errorCode: ErrorCode.SUCCESS,
            timestamp: timestamp, blockHeight: blockHeight
        )
    }
    
    // Enhanced batch operations
    access(all) fun batchStakeFlow(requests: [BatchStakeRequest]): [StakeResult] {
        pre {
            requests.length > 0: "No requests provided"
            requests.length <= 20: "Too many batch requests"
            self.pausedOperations["batch"] != true: "Batch operations are paused"
        }
        
        let results: [StakeResult] = []
        var totalAmount: UFix64 = 0.0
        var successCount = 0
        
        for request in requests {
            let result = self.stakeFlow(
                amount: request.amount, 
                recipient: request.recipient, 
                requestId: request.requestId
            )
            results.append(result)
            
            if result.success {
                successCount = successCount + 1
                totalAmount = totalAmount + result.flowAmount
            }
        }
        
        emit BatchOperationExecuted(
            operationType: "stake",
            requestCount: requests.length,
            successCount: successCount,
            totalAmount: totalAmount
        )
        
        return results
    }

    access(all) fun batchUnstakeFlow(requests: [BatchUnstakeRequest]): [UnstakeResult] {
        pre {
            requests.length > 0: "No requests provided"
            requests.length <= 20: "Too many batch requests"
            self.pausedOperations["batch"] != true: "Batch operations are paused"
        }
        
        let results: [UnstakeResult] = []
        var totalAmount: UFix64 = 0.0
        var successCount = 0
        
        for request in requests {
            let result = self.unstakeFlow(
                stFlowAmount: request.stFlowAmount, 
                recipient: request.recipient, 
                requestId: request.requestId
            )
            results.append(result)
            
            if result.success {
                successCount = successCount + 1
                totalAmount = totalAmount + result.stFlowAmount
            }
        }
        
        emit BatchOperationExecuted(
            operationType: "unstake",
            requestCount: requests.length,
            successCount: successCount,
            totalAmount: totalAmount
        )
        
        return results
    }
    
    // View functions for querying state
    access(all) view fun getExchangeRate(): UFix64 {
        return LiquidStaking.getExchangeRate()
    }
    
    access(all) view fun getStFlowBalance(): UFix64 {
        let stFlowVaultRef = self.account.storage.borrow<&stFlowToken.Vault>(from: self.StFlowVaultStoragePath)
        return stFlowVaultRef?.balance ?? 0.0
    }
    
    access(all) view fun getFlowBalance(): UFix64 {
        let flowVaultRef = self.account.storage.borrow<&FlowToken.Vault>(from: self.FlowVaultStoragePath)
        return flowVaultRef?.balance ?? 0.0
    }
    
    access(all) view fun getConfig(): RouterConfig {
        let pausedOps: [String] = []
        for operation in self.pausedOperations.keys {
            if self.pausedOperations[operation] == true {
                pausedOps.append(operation)
            }
        }
        
        return RouterConfig(
            minStakeAmount: self.minStakeAmount,
            maxStakeAmount: self.maxStakeAmount,
            maxOperationsPerBlock: self.maxOperationsPerBlock,
            protocolFeeRate: self.protocolFeeRate,
            isActive: self.isActive,
            authorizedCallersCount: self.authorizedEVMCallers.length,
            pausedOperations: pausedOps,
            version: self.contractVersion
        )
    }
    
    access(all) fun getStats(): RouterStats {
        let currentBlock = getCurrentBlock()
        return RouterStats(
            totalStakeOps: self.totalStakeOperations,
            totalUnstakeOps: self.totalUnstakeOperations,
            totalFlowStaked: self.totalFlowStaked,
            totalStFlowMinted: self.totalStFlowMinted,
            currentFlowBalance: self.getFlowBalance(),
            currentStFlowBalance: self.getStFlowBalance(),
            accumulatedFees: self.accumulatedFees,
            exchangeRate: self.getExchangeRate(),
            protocolFeeRate: self.protocolFeeRate,
            isActive: self.isActive,
            rateLimitStatus: self.currentBlockOperations,
            version: self.contractVersion,
            blockHeight: currentBlock.height,
            timestamp: currentBlock.timestamp
        )
    }
    
    access(all) view fun isAuthorized(caller: String): Bool {
        return self.authorizedEVMCallers[caller] == true
    }
    
    access(all) view fun isOperationPaused(operation: String): Bool {
        return self.pausedOperations[operation] == true
    }
    
    access(all) view fun getAuthorizedCallers(): [String] {
        return self.authorizedEVMCallers.keys
    }
    
    access(all) view fun getRateLimitInfo(): {String: UInt64} {
        return {
            "currentOperations": self.currentBlockOperations,
            "maxOperations": self.maxOperationsPerBlock,
            "remaining": self.maxOperationsPerBlock - self.currentBlockOperations,
            "blockHeight": self.lastBlockHeight
        }
    }
    
    // Health check function for monitoring
    access(all) view fun healthCheck(): {String: AnyStruct} {
        let currentBlock = getCurrentBlock()
        return {
            "isActive": self.isActive,
            "flowBalance": self.getFlowBalance(),
            "stFlowBalance": self.getStFlowBalance(),
            "exchangeRate": self.getExchangeRate(),
            "rateLimitRemaining": self.maxOperationsPerBlock - self.currentBlockOperations,
            "blockHeight": currentBlock.height,
            "timestamp": currentBlock.timestamp,
            "version": self.contractVersion,
            "protocolFeeRate": self.protocolFeeRate,
            "accumulatedFees": self.accumulatedFees,
            "pausedOperations": self.pausedOperations.keys,
            "totalOperations": self.totalStakeOperations + self.totalUnstakeOperations
        }
    }

    // Utility functions for calculations
    access(all) view fun calculateStakeOutput(flowAmount: UFix64): {String: UFix64} {
        let protocolFee = self.calculateProtocolFee(flowAmount)
        let amountAfterFee = flowAmount - protocolFee
        let exchangeRate = self.getExchangeRate()
        let estimatedStFlow = amountAfterFee / exchangeRate
        
        return {
            "inputFlow": flowAmount,
            "protocolFee": protocolFee,
            "flowAfterFee": amountAfterFee,
            "estimatedStFlow": estimatedStFlow,
            "exchangeRate": exchangeRate
        }
    }

    access(all) view fun calculateUnstakeOutput(stFlowAmount: UFix64): {String: UFix64} {
        let exchangeRate = self.getExchangeRate()
        let flowBeforeFee = stFlowAmount * exchangeRate
        let protocolFee = self.calculateProtocolFee(flowBeforeFee)
        let estimatedFlow = flowBeforeFee - protocolFee
        
        return {
            "inputStFlow": stFlowAmount,
            "flowBeforeFee": flowBeforeFee,
            "protocolFee": protocolFee,
            "estimatedFlow": estimatedFlow,
            "exchangeRate": exchangeRate
        }
    }
}