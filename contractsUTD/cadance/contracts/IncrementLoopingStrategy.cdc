import FungibleToken from 0xf233dcee88fe0abe
import FlowToken from 0x1654653399040a61
import stFlowToken from 0xd6f80565193ad727
import LiquidStaking from 0xd6f80565193ad727
import LendingInterfaces from 0x2df970b6cdee5735
import LendingComptroller from 0xf80cb737bfe7c792
import LendingConfig from 0x2df970b6cdee5735

/// Increment Fi looping strategy
access(all) contract IncrementLoopingStrategy {
    
    access(all) let STFLOW_POOL_ADDRESS: Address
    access(all) let FLOW_POOL_ADDRESS: Address
    access(all) let BORROW_FACTOR: UFix64
    
    access(all) event LoopExecuted(loopNumber: UInt8, flowStaked: UFix64, stFlowReceived: UFix64, flowBorrowed: UFix64)
    access(all) event PositionUnwound(stFlowWithdrawn: UFix64, flowRepaid: UFix64)
    access(all) event HealthFactorWarning(message: String)
    
    access(self) var totalFlowStaked: UFix64
    access(self) var totalStFlowReceived: UFix64
    access(self) var totalFlowBorrowed: UFix64
    access(self) var totalLoops: UInt64
    
    access(all) resource Strategy {
        access(self) let userCertificate: @{LendingInterfaces.IdentityCertificate}
        access(self) let flowVault: @FlowToken.Vault
        access(self) let stFlowVault: @stFlowToken.Vault
        
        access(self) var loopCount: UInt8
        access(self) var totalStaked: UFix64
        access(self) var totalBorrowed: UFix64
        
        init() {
            self.userCertificate <- LendingComptroller.IssueUserCertificate()
            self.flowVault <- FlowToken.createEmptyVault(vaultType: Type<@FlowToken.Vault>()) as! @FlowToken.Vault
            self.stFlowVault <- stFlowToken.createEmptyVault(vaultType: Type<@stFlowToken.Vault>()) as! @stFlowToken.Vault
            
            self.loopCount = 0
            self.totalStaked = 0.0
            self.totalBorrowed = 0.0
        }
        
        /// Execute looping strategy with specified number of loops
        access(all) fun executeStrategy(from: @FlowToken.Vault, numLoops: UInt8): @stFlowToken.Vault {
            pre {
                from.balance > 0.0: "Cannot stake zero FLOW"
                numLoops >= 1 && numLoops <= 3: "Loops must be 1-3"
            }
            
            let initialAmount = from.balance
            
            // Store initial FLOW
            self.flowVault.deposit(from: <-from)
            
            // Execute loops
            var currentLoop: UInt8 = 0
            while currentLoop < numLoops {
                let availableFlow = self.flowVault.balance
                if availableFlow == 0.0 {
                    break
                }
                
                // Withdraw FLOW for this loop
                let flowToStake <- self.flowVault.withdraw(amount: availableFlow) as! @FlowToken.Vault
                
                let borrowedAmount = self.executeSingleLoop(
                    flowVault: <-flowToStake,
                    loopNumber: currentLoop + 1
                )
                
                currentLoop = currentLoop + 1
                
                if borrowedAmount == 0.0 {
                    break
                }
            }
            
            // Final stake of any remaining borrowed FLOW
            let remainingFlow = self.flowVault.balance
            if remainingFlow > 0.0 {
                let finalFlow <- self.flowVault.withdraw(amount: remainingFlow) as! @FlowToken.Vault
                let finalStFlow <- LiquidStaking.stake(flowVault: <-finalFlow)
                self.stFlowVault.deposit(from: <-finalStFlow)
            }
            
            // Return all accumulated stFLOW
            let totalStFlow = self.stFlowVault.balance
            let result <- self.stFlowVault.withdraw(amount: totalStFlow) as! @stFlowToken.Vault
            
            return <- result
        }
        
        /// Execute a single loop iteration
        access(self) fun executeSingleLoop(flowVault: @FlowToken.Vault, loopNumber: UInt8): UFix64 {
            let flowAmount = flowVault.balance
            
            // STEP 1: Stake FLOW -> stFLOW
            let stFlowVault <- LiquidStaking.stake(flowVault: <-flowVault)
            let stFlowReceived = stFlowVault.balance
            
            self.totalStaked = self.totalStaked + flowAmount
            
            // STEP 2: Supply stFLOW to Increment lending pool
            let stFlowPool = getAccount(IncrementLoopingStrategy.STFLOW_POOL_ADDRESS)
                .capabilities
                .borrow<&{LendingInterfaces.PoolPublic}>(LendingConfig.PoolPublicPublicPath)
                ?? panic("Cannot access stFLOW pool")
            
            stFlowPool.supply(
                supplierAddr: self.userCertificate.owner!.address,
                inUnderlyingVault: <-stFlowVault
            )
            
            // STEP 3: Check borrowing capacity
            let comptroller = getAccount(0xf80cb737bfe7c792)
                .capabilities
                .borrow<&{LendingInterfaces.ComptrollerPublic}>(LendingConfig.ComptrollerPublicPath)
                ?? panic("Cannot access comptroller")
            
            let liquidity = comptroller.getUserCrossMarketLiquidity(
                userAddr: self.userCertificate.owner!.address
            )
            
            // liquidity returns [availableBorrow, totalBorrow, totalCollateral] as Strings
            let availableToBorrowStr = liquidity[0] as! String
            let availableToBorrow = LendingConfig.ScaledUInt256ToUFix64(UInt256.fromString(availableToBorrowStr)!)
            
            if availableToBorrow < 0.01 {
                emit LoopExecuted(
                    loopNumber: loopNumber,
                    flowStaked: flowAmount,
                    stFlowReceived: stFlowReceived,
                    flowBorrowed: 0.0
                )
                return 0.0
            }
            
            // STEP 4: Borrow FLOW (use borrow factor for safety)
            let flowToBorrow = availableToBorrow * IncrementLoopingStrategy.BORROW_FACTOR
            
            let flowPool = getAccount(IncrementLoopingStrategy.FLOW_POOL_ADDRESS)
                .capabilities
                .borrow<&{LendingInterfaces.PoolPublic}>(LendingConfig.PoolPublicPublicPath)
                ?? panic("Cannot access FLOW pool")
            
            let borrowedFlow <- flowPool.borrow(
                userCertificate: &self.userCertificate as &{LendingInterfaces.IdentityCertificate},
                borrowAmount: flowToBorrow
            ) as! @FlowToken.Vault
            
            let borrowedAmount = borrowedFlow.balance
            self.totalBorrowed = self.totalBorrowed + borrowedAmount
            
            // Store borrowed FLOW for next loop
            self.flowVault.deposit(from: <-borrowedFlow)
            
            IncrementLoopingStrategy.totalFlowStaked = IncrementLoopingStrategy.totalFlowStaked + flowAmount
            IncrementLoopingStrategy.totalStFlowReceived = IncrementLoopingStrategy.totalStFlowReceived + stFlowReceived
            IncrementLoopingStrategy.totalFlowBorrowed = IncrementLoopingStrategy.totalFlowBorrowed + borrowedAmount
            IncrementLoopingStrategy.totalLoops = IncrementLoopingStrategy.totalLoops + 1
            
            emit LoopExecuted(
                loopNumber: loopNumber,
                flowStaked: flowAmount,
                stFlowReceived: stFlowReceived,
                flowBorrowed: borrowedAmount
            )
            
            return borrowedAmount
        }
        
        /// Get health metrics
        access(all) fun getHealthMetrics(): {String: UFix64} {
            let comptroller = getAccount(0xf80cb737bfe7c792)
                .capabilities
                .borrow<&{LendingInterfaces.ComptrollerPublic}>(LendingConfig.ComptrollerPublicPath)
                ?? panic("Cannot access comptroller")
            
            let liquidity = comptroller.getUserCrossMarketLiquidity(
                userAddr: self.userCertificate.owner!.address
            )
            
            let totalCollateralStr = liquidity[2] as! String
            let totalBorrowStr = liquidity[1] as! String
            
            let totalCollateral = LendingConfig.ScaledUInt256ToUFix64(UInt256.fromString(totalCollateralStr)!)
            let totalBorrow = LendingConfig.ScaledUInt256ToUFix64(UInt256.fromString(totalBorrowStr)!)
            
            let healthFactor = totalBorrow > 0.0 ? totalCollateral / totalBorrow : 999.0
            let leverage = self.totalStaked > 0.0 && self.totalBorrowed > 0.0
                ? self.totalStaked / (self.totalStaked - self.totalBorrowed)
                : 1.0
            
            return {
                "totalCollateral": totalCollateral,
                "totalBorrow": totalBorrow,
                "healthFactor": healthFactor,
                "leverage": leverage,
                "totalStaked": self.totalStaked,
                "totalBorrowed": self.totalBorrowed
            }
        }
        
        access(all) fun harvest(): @stFlowToken.Vault {
            return <- stFlowToken.createEmptyVault(vaultType: Type<@stFlowToken.Vault>()) as! @stFlowToken.Vault
        }
        
        access(all) fun emergencyExit(): @stFlowToken.Vault {
            emit HealthFactorWarning(message: "Emergency exit initiated - manual intervention required")
            return <- stFlowToken.createEmptyVault(vaultType: Type<@stFlowToken.Vault>()) as! @stFlowToken.Vault
        }
        
        access(all) fun getBalances(): {String: UFix64} {
            return {
                "flow": self.flowVault.balance,
                "stflow": self.stFlowVault.balance,
                "totalStaked": self.totalStaked,
                "totalBorrowed": self.totalBorrowed,
                "loopCount": UFix64(self.loopCount)
            }
        }
    }
    
    access(all) fun createStrategy(): @Strategy {
        return <- create Strategy()
    }
    
    access(all) fun getMetrics(): {String: UFix64} {
        return {
            "totalFlowStaked": self.totalFlowStaked,
            "totalStFlowReceived": self.totalStFlowReceived,
            "totalFlowBorrowed": self.totalFlowBorrowed,
            "totalLoops": UFix64(self.totalLoops),
            "avgLeverage": self.totalFlowStaked > 0.0 && self.totalFlowBorrowed > 0.0
                ? self.totalFlowStaked / (self.totalFlowStaked - self.totalFlowBorrowed)
                : 1.0
        }
    }
    
    init() {
        self.STFLOW_POOL_ADDRESS = 0x44fe3d9157770b2d
        self.FLOW_POOL_ADDRESS = 0x7492e2f9b4acea9a
        self.BORROW_FACTOR = 0.7
        
        self.totalFlowStaked = 0.0
        self.totalStFlowReceived = 0.0
        self.totalFlowBorrowed = 0.0
        self.totalLoops = 0
    }
}