import FungibleToken from 0xf233dcee88fe0abe
import FlowToken from 0x1654653399040a61
import stFlowToken from 0xd6f80565193ad727
import EVM from 0xe467b9dd11fa00df
import VaultCore from 0x79f5b5b0f95a160b
import IncrementStakingStrategy from 0x79f5b5b0f95a160b
import IncrementLoopingStrategy from 0x79f5b5b0f95a160b
import IncrementLendingStrategy from 0x79f5b5b0f95a160b
import IncrementFarmingStrategy from 0x79f5b5b0f95a160b
import SwapStrategy from 0x79f5b5b0f95a160b

/// AgentManager2 - Fresh deployment for orchestrating strategies and managing EVM bridge
access(all) contract AgentManager2 {
    
    // ====================================================================
    // PATHS
    // ====================================================================
    access(all) let AgentStoragePath: StoragePath
    access(all) let AgentPublicPath: PublicPath
    
    // ====================================================================
    // EVM CONTRACT ADDRESSES
    // ====================================================================
    access(all) let EVM_VAULT_CORE: String
    access(all) let EVM_STRATEGY_MANAGER: String
    
    // ====================================================================
    // EVENTS
    // ====================================================================
    access(all) event StrategyExecuted(strategy: String, amount: UFix64, result: String)
    access(all) event FundsBridgedToEVM(amount: UFix64, evmAddress: String)
    access(all) event FundsBridgedFromEVM(amount: UFix64)
    access(all) event YieldHarvested(strategy: String, amount: UFix64)
    
    // ====================================================================
    // STATE
    // ====================================================================
    access(self) var totalBridgedToEVM: UFix64
    access(self) var totalBridgedFromEVM: UFix64
    
    // ====================================================================
    // AGENT RESOURCE
    // ====================================================================
    access(all) resource Agent {
        access(self) let vaultRef: &VaultCore.Vault
        access(self) let coa: auth(EVM.Call, EVM.Withdraw) &EVM.CadenceOwnedAccount
        
        // Strategy resources
        access(self) let stakingStrategy: @IncrementStakingStrategy.Strategy
        access(self) let loopingStrategy: @IncrementLoopingStrategy.Strategy
        access(self) let lendingStrategy: @IncrementLendingStrategy.Strategy
        access(self) let farmingStrategy: @IncrementFarmingStrategy.Strategy
        access(self) let swapStrategy: @SwapStrategy.Strategy
        
        init(
            vaultRef: &VaultCore.Vault,
            coa: auth(EVM.Call, EVM.Withdraw) &EVM.CadenceOwnedAccount
        ) {
            self.vaultRef = vaultRef
            self.coa = coa
            
            // Initialize all strategy resources
            self.stakingStrategy <- IncrementStakingStrategy.createStrategy()
            self.loopingStrategy <- IncrementLoopingStrategy.createStrategy()
            self.lendingStrategy <- IncrementLendingStrategy.createStrategy()
            self.farmingStrategy <- IncrementFarmingStrategy.createStrategy()
            self.swapStrategy <- SwapStrategy.createStrategy()
        }
        
        // ====================================================================
        // STRATEGY EXECUTION
        // ====================================================================
        
        /// Execute staking strategy
        access(all) fun executeStaking(amount: UFix64): UFix64 {
            let flowVault <- self.vaultRef.withdrawForStrategy(
                assetType: VaultCore.AssetType.flow,
                amount: amount
            ) as! @FlowToken.Vault
            
            let stFlowVault <- self.stakingStrategy.executeStrategy(from: <-flowVault)
            let received = stFlowVault.balance
            
            self.vaultRef.depositFromStrategy(
                assetType: VaultCore.AssetType.stflow,
                from: <-stFlowVault
            )
            
            emit StrategyExecuted(strategy: "Staking", amount: amount, result: received.toString())
            return received
        }
        
        /// Execute looping strategy
        access(all) fun executeLooping(amount: UFix64, numLoops: UInt8): UFix64 {
            let flowVault <- self.vaultRef.withdrawForStrategy(
                assetType: VaultCore.AssetType.flow,
                amount: amount
            ) as! @FlowToken.Vault
            
            let stFlowVault <- self.loopingStrategy.executeStrategy(from: <-flowVault, numLoops: numLoops)
            let received = stFlowVault.balance
            
            self.vaultRef.depositFromStrategy(
                assetType: VaultCore.AssetType.stflow,
                from: <-stFlowVault
            )
            
            emit StrategyExecuted(strategy: "Looping", amount: amount, result: received.toString())
            return received
        }
        
        /// Supply to lending market
        access(all) fun supplyToLending(asset: String, amount: UFix64) {
            if asset == "FLOW" {
                let vault <- self.vaultRef.withdrawForStrategy(
                    assetType: VaultCore.AssetType.flow,
                    amount: amount
                ) as! @FlowToken.Vault
                
                self.lendingStrategy.depositFlow(vault: <-vault)
                self.lendingStrategy.supplyFlow(amount: amount)
                
            } else if asset == "stFLOW" {
                let vault <- self.vaultRef.withdrawForStrategy(
                    assetType: VaultCore.AssetType.stflow,
                    amount: amount
                ) as! @stFlowToken.Vault
                
                self.lendingStrategy.depositStFlow(vault: <-vault)
                self.lendingStrategy.supplyStFlow(amount: amount)
            }
            
            emit StrategyExecuted(strategy: "Lending-Supply", amount: amount, result: "Success")
        }
        
        /// Stake in farming pool
        access(all) fun stakeInFarm(poolId: UInt64, amount: UFix64, tokenType: String) {
            if tokenType == "FLOW" {
                let vault <- self.vaultRef.withdrawForStrategy(
                    assetType: VaultCore.AssetType.flow,
                    amount: amount
                ) as! @FlowToken.Vault
                
                let success = self.farmingStrategy.executeStrategy(poolId: poolId, from: <-vault)
                let resultStr = success ? "true" : "false"
                emit StrategyExecuted(strategy: "Farming", amount: amount, result: resultStr)
                
            } else if tokenType == "stFLOW" {
                let vault <- self.vaultRef.withdrawForStrategy(
                    assetType: VaultCore.AssetType.stflow,
                    amount: amount
                ) as! @stFlowToken.Vault
                
                let success = self.farmingStrategy.executeStrategy(poolId: poolId, from: <-vault)
                let resultStr = success ? "true" : "false"
                emit StrategyExecuted(strategy: "Farming", amount: amount, result: resultStr)
            }
        }
        
        /// Harvest farming rewards
        access(all) fun harvestFarmingRewards(poolId: UInt64) {
            let rewards <- self.farmingStrategy.harvestPool(poolId: poolId)
            
            var totalHarvested: UFix64 = 0.0
            
            for tokenKey in rewards.keys {
                let rewardVault <- rewards.remove(key: tokenKey)!
                totalHarvested = totalHarvested + rewardVault.balance
                
                if tokenKey.slice(from: tokenKey.length - 9, upTo: tokenKey.length) == "FlowToken" {
                    self.vaultRef.depositFromStrategy(
                        assetType: VaultCore.AssetType.flow,
                        from: <-rewardVault
                    )
                } else if tokenKey.slice(from: tokenKey.length - 11, upTo: tokenKey.length) == "stFlowToken" {
                    self.vaultRef.depositFromStrategy(
                        assetType: VaultCore.AssetType.stflow,
                        from: <-rewardVault
                    )
                } else {
                    destroy rewardVault
                }
            }
            
            destroy rewards
            
            self.vaultRef.recordYieldHarvest(assetType: VaultCore.AssetType.flow, amount: totalHarvested)
            emit YieldHarvested(strategy: "Farming", amount: totalHarvested)
        }
        
        // ====================================================================
        // EVM BRIDGE FUNCTIONS
        // ====================================================================
        
        /// Bridge FLOW to EVM (becomes WFLOW)
        access(all) fun bridgeToEVM(amount: UFix64): Bool {
            let flowVault <- self.vaultRef.withdrawForEVMBridge(
                assetType: VaultCore.AssetType.flow,
                amount: amount
            ) as! @FlowToken.Vault
            
            self.coa.deposit(from: <-flowVault)
            
            AgentManager2.totalBridgedToEVM = AgentManager2.totalBridgedToEVM + amount
            
            emit FundsBridgedToEVM(
                amount: amount,
                evmAddress: self.coa.address().toString()
            )
            
            return true
        }
        
        /// Bridge FLOW back from EVM (unwraps WFLOW)
        access(all) fun bridgeFromEVM(amount: UFix64): Bool {
            let scaledAmount = amount * 1000000000.0
            let amountUInt = UInt(scaledAmount) * 1000000000
            let balance = EVM.Balance(attoflow: amountUInt)
            
            let flowVault <- self.coa.withdraw(balance: balance) as! @FlowToken.Vault
            let actualAmount = flowVault.balance
            
            self.vaultRef.depositFromEVMBridge(from: <-flowVault)
            
            AgentManager2.totalBridgedFromEVM = AgentManager2.totalBridgedFromEVM + actualAmount
            
            emit FundsBridgedFromEVM(amount: actualAmount)
            
            return true
        }
        
        /// Call EVM strategy contract
        access(all) fun executeEVMStrategy(
            contractAddress: String,
            calldata: [UInt8],
            value: UFix64
        ): EVM.Result {
            let scaledValue = value * 1000000000.0
            let amountUInt = UInt(scaledValue) * 1000000000
            let balance = EVM.Balance(attoflow: amountUInt)
            
            let addressBytes = contractAddress.decodeHex()
            assert(addressBytes.length == 20, message: "Invalid EVM address length, expected 20 bytes")
            
            let fixedBytes: [UInt8; 20] = [
                addressBytes[0], addressBytes[1], addressBytes[2], addressBytes[3], addressBytes[4],
                addressBytes[5], addressBytes[6], addressBytes[7], addressBytes[8], addressBytes[9],
                addressBytes[10], addressBytes[11], addressBytes[12], addressBytes[13], addressBytes[14],
                addressBytes[15], addressBytes[16], addressBytes[17], addressBytes[18], addressBytes[19]
            ]
            
            let evmAddress = EVM.EVMAddress(bytes: fixedBytes)
            
            let result = self.coa.call(
                to: evmAddress,
                data: calldata,
                gasLimit: 10_000_000,
                value: balance
            )
            
            return result
        }
        
        // ====================================================================
        // VIEW FUNCTIONS
        // ====================================================================
        
        access(all) fun getStrategyBalances(): {String: {String: UFix64}} {
            return {
                "staking": self.stakingStrategy.getBalances(),
                "looping": self.loopingStrategy.getBalances(),
                "lending": self.lendingStrategy.getBalances(),
                "farming": self.farmingStrategy.getBalances(),
                "swap": self.swapStrategy.getBalances()
            }
        }
        
        access(all) fun getFarmingPositions(): {UInt64: {String: UFix64}} {
            return self.farmingStrategy.getPositions()
        }
        
        access(all) fun getLendingPosition(): IncrementLendingStrategy.UserPosition {
            return self.lendingStrategy.getPositions()
        }
        
        access(all) fun getLoopingHealth(): {String: UFix64} {
            return self.loopingStrategy.getHealthMetrics()
        }
        
        access(all) fun getCOAAddress(): String {
            return self.coa.address().toString()
        }
        
        access(all) fun getCOABalance(): UFix64 {
            let balanceAttoflow = self.coa.balance().attoflow
            let scaledDown = UFix64(balanceAttoflow / 1000000000)
            return scaledDown / 1000000000.0
        }
    }
    
    // ====================================================================
    // CONTRACT FUNCTIONS
    // ====================================================================
    
    access(all) fun createAgent(
        vaultRef: &VaultCore.Vault,
        coa: auth(EVM.Call, EVM.Withdraw) &EVM.CadenceOwnedAccount
    ): @Agent {
        return <- create Agent(vaultRef: vaultRef, coa: coa)
    }
    
    access(all) fun getMetrics(): {String: UFix64} {
        return {
            "totalBridgedToEVM": self.totalBridgedToEVM,
            "totalBridgedFromEVM": self.totalBridgedFromEVM
        }
    }
    
    // ====================================================================
    // INITIALIZATION
    // ====================================================================
    
    init() {
        self.AgentStoragePath = /storage/AgentManager2
        self.AgentPublicPath = /public/AgentManager2
        
        self.EVM_VAULT_CORE = "0xc0F67510F9E8974345f7fE8b8981C780F94BFbf9"
        self.EVM_STRATEGY_MANAGER = "0x915537401B7BC088d54a58e55b488B821508A55f"
        
        self.totalBridgedToEVM = 0.0
        self.totalBridgedFromEVM = 0.0
    }
}