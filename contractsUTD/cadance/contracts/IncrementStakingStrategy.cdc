import FungibleToken from 0xf233dcee88fe0abe
import FlowToken from 0x1654653399040a61
import stFlowToken from 0xd6f80565193ad727
import LiquidStaking from 0xd6f80565193ad727

/// Increment Fi liquid staking strategy
/// Stakes FLOW to receive stFLOW
access(all) contract IncrementStakingStrategy {
    
    access(all) event Staked(flowAmount: UFix64, stFlowReceived: UFix64)
    access(all) event Unstaked(stFlowAmount: UFix64, flowReceived: UFix64)
    access(all) event StrategyExecuted(amount: UFix64, result: UFix64)
    
    access(self) var totalFlowStaked: UFix64
    access(self) var totalStFlowReceived: UFix64
    
    access(all) resource Strategy {
        access(self) let flowVault: @FlowToken.Vault
        access(self) let stFlowVault: @stFlowToken.Vault
        
        init() {
            self.flowVault <- FlowToken.createEmptyVault(vaultType: Type<@FlowToken.Vault>()) as! @FlowToken.Vault
            self.stFlowVault <- stFlowToken.createEmptyVault(vaultType: Type<@stFlowToken.Vault>()) as! @stFlowToken.Vault
        }
        
        /// Execute staking: FLOW -> stFLOW
        access(all) fun executeStrategy(from: @FlowToken.Vault): @stFlowToken.Vault {
            pre {
                from.balance > 0.0: "Cannot stake zero FLOW"
            }
            
            let flowAmount = from.balance
            
            // Stake FLOW via LiquidStaking
            let stFlowVault <- LiquidStaking.stake(flowVault: <-from)
            let stFlowReceived = stFlowVault.balance
            
            IncrementStakingStrategy.totalFlowStaked = IncrementStakingStrategy.totalFlowStaked + flowAmount
            IncrementStakingStrategy.totalStFlowReceived = IncrementStakingStrategy.totalStFlowReceived + stFlowReceived
            
            emit Staked(flowAmount: flowAmount, stFlowReceived: stFlowReceived)
            emit StrategyExecuted(amount: flowAmount, result: stFlowReceived)
            
            return <- stFlowVault
        }
        
        /// Harvest any accrued stFLOW
        access(all) fun harvest(): @stFlowToken.Vault {
            let balance = self.stFlowVault.balance
            
            if balance > 0.0 {
                return <- self.stFlowVault.withdraw(amount: balance) as! @stFlowToken.Vault
            } else {
                return <- stFlowToken.createEmptyVault(vaultType: Type<@stFlowToken.Vault>()) as! @stFlowToken.Vault
            }
        }
        
        /// Emergency exit - return all stFLOW
        access(all) fun emergencyExit(): @stFlowToken.Vault {
            let balance = self.stFlowVault.balance
            
            if balance > 0.0 {
                return <- self.stFlowVault.withdraw(amount: balance) as! @stFlowToken.Vault
            } else {
                return <- stFlowToken.createEmptyVault(vaultType: Type<@stFlowToken.Vault>()) as! @stFlowToken.Vault
            }
        }
        
        /// Get current balances
        access(all) fun getBalances(): {String: UFix64} {
            return {
                "flow": self.flowVault.balance,
                "stflow": self.stFlowVault.balance
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
            "exchangeRate": self.totalFlowStaked > 0.0 ? self.totalStFlowReceived / self.totalFlowStaked : 1.0
        }
    }
    
    init() {
        self.totalFlowStaked = 0.0
        self.totalStFlowReceived = 0.0
    }
}