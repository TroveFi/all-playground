// File: cadence/transactions/fixed_portfolio_rebalancing.cdc
import FungibleToken from 0x9a0766d93b6608b7
import FlowToken from 0x7e60df042a9c0868
import FungibleTokenConnectors from 0x5a7b9cee9aaf4e4e
import DeFiActions from 0x4c2ff9dd03ab442f

transaction(targetFlowAllocation: UFix64, targetStakingAllocation: UFix64) {
    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController) &Account) {
        log("=== SCHEDULED: Weekly Portfolio Rebalancing ===")
        log("Target FLOW allocation: ".concat(targetFlowAllocation.toString()))
        log("Target staking allocation: ".concat(targetStakingAllocation.toString()))
        
        let operationID = DeFiActions.createUniqueIdentifier()
        let vaultRef = signer.storage.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)!
        let currentBalance = vaultRef.balance
        
        log("Current total balance: ".concat(currentBalance.toString()))
        
        // Calculate current allocations (simplified - assume all balance is liquid FLOW)
        let currentFlowAllocation = currentBalance * 0.7  // 70% in liquid FLOW
        let currentStakingAllocation = currentBalance * 0.3  // 30% in staking
        
        log("Current FLOW allocation: ".concat(currentFlowAllocation.toString()))
        log("Current staking allocation: ".concat(currentStakingAllocation.toString()))
        
        // Calculate absolute differences using conditional logic
        var flowDifferenceAbs: UFix64 = 0.0
        var stakingDifferenceAbs: UFix64 = 0.0
        var needsRebalancing = false
        
        if targetFlowAllocation > currentFlowAllocation {
            flowDifferenceAbs = targetFlowAllocation - currentFlowAllocation
            log("Need to increase FLOW allocation by: ".concat(flowDifferenceAbs.toString()))
        } else if currentFlowAllocation > targetFlowAllocation {
            flowDifferenceAbs = currentFlowAllocation - targetFlowAllocation
            log("Need to decrease FLOW allocation by: ".concat(flowDifferenceAbs.toString()))
        }
        
        if targetStakingAllocation > currentStakingAllocation {
            stakingDifferenceAbs = targetStakingAllocation - currentStakingAllocation
            log("Need to increase staking allocation by: ".concat(stakingDifferenceAbs.toString()))
        } else if currentStakingAllocation > targetStakingAllocation {
            stakingDifferenceAbs = currentStakingAllocation - targetStakingAllocation
            log("Need to decrease staking allocation by: ".concat(stakingDifferenceAbs.toString()))
        }
        
        // Check if rebalancing is needed (threshold: 0.5 FLOW)
        if flowDifferenceAbs > 0.5 || stakingDifferenceAbs > 0.5 {
            needsRebalancing = true
            log("Rebalancing threshold exceeded - executing rebalancing...")
            
            // Create rebalancing components
            let withdrawCap = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
                /storage/flowTokenVault
            )
            
            let rebalanceSource = FungibleTokenConnectors.VaultSource(
                min: 2.0,  // Keep minimum for gas
                withdrawVault: withdrawCap,
                uniqueID: operationID
            )
            
            let depositCap = getAccount(signer.address).capabilities.get<&{FungibleToken.Vault}>(
                /public/flowTokenReceiver
            )
            
            let rebalanceSink = FungibleTokenConnectors.VaultSink(
                max: nil,
                depositVault: depositCap,
                uniqueID: operationID
            )
            
            // Use the larger difference for rebalancing amount
            let rebalanceAmount = flowDifferenceAbs > stakingDifferenceAbs ? flowDifferenceAbs : stakingDifferenceAbs
            
            if rebalanceAmount > 0.0 && rebalanceAmount <= rebalanceSource.minimumAvailable() {
                let rebalanceTokens <- rebalanceSource.withdrawAvailable(maxAmount: rebalanceAmount)
                log("Rebalancing ".concat(rebalanceTokens.balance.toString()).concat(" FLOW"))
                
                // Simulate moving to different allocation
                if targetFlowAllocation > currentFlowAllocation {
                    log("Increasing FLOW allocation (reducing staking positions)")
                } else {
                    log("Decreasing FLOW allocation (increasing staking positions)")
                }
                
                rebalanceSink.depositCapacity(from: &rebalanceTokens as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
                
                if rebalanceTokens.balance > 0.0 {
                    vaultRef.deposit(from: <-rebalanceTokens)
                } else {
                    destroy rebalanceTokens
                }
                
                log("Portfolio rebalancing completed")
            } else {
                log("Rebalancing amount exceeds available balance or too small")
            }
            
        } else {
            log("Portfolio within rebalancing thresholds - no action needed")
            log("FLOW difference: ".concat(flowDifferenceAbs.toString()).concat(" (threshold: 0.5)"))
            log("Staking difference: ".concat(stakingDifferenceAbs.toString()).concat(" (threshold: 0.5)"))
        }
        
        let finalBalance = vaultRef.balance
        log("Final balance: ".concat(finalBalance.toString()))
        log("=== NEXT SCHEDULED EXECUTION: Next Sunday ===")
    }
}