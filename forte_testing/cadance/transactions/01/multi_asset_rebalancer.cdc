import FungibleToken from 0x9a0766d93b6608b7
import FlowToken from 0x7e60df042a9c0868
import FungibleTokenConnectors from 0x5a7b9cee9aaf4e4e
import DeFiActions from 0x4c2ff9dd03ab442f

transaction(flowTarget: UFix64, stakingTarget: UFix64, lpTarget: UFix64, rebalanceThreshold: UFix64) {
    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController) &Account) {
        log("=== Multi-Asset Portfolio Rebalancer ===")
        log("Target allocations - FLOW: ".concat(flowTarget.toString()).concat("%, Staking: ").concat(stakingTarget.toString()).concat("%, LP: ").concat(lpTarget.toString()).concat("%"))
        
        let operationID = DeFiActions.createUniqueIdentifier()
        let vaultRef = signer.storage.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)!
        let totalValue = vaultRef.balance
        
        log("Total portfolio value: ".concat(totalValue.toString()))
        
        // Calculate target amounts
        let targetFlowAmount = totalValue * (flowTarget / 100.0)
        let targetStakingAmount = totalValue * (stakingTarget / 100.0)
        let targetLpAmount = totalValue * (lpTarget / 100.0)
        
        log("Target amounts - FLOW: ".concat(targetFlowAmount.toString()))
        log("Target amounts - Staking: ".concat(targetStakingAmount.toString()))
        log("Target amounts - LP: ".concat(targetLpAmount.toString()))
        
        // Simulate current allocations
        let currentFlowAmount = totalValue * 0.50  // 50% currently in FLOW
        let currentStakingAmount = totalValue * 0.30  // 30% currently staked
        let currentLpAmount = totalValue * 0.20  // 20% in LP tokens
        
        log("Current amounts - FLOW: ".concat(currentFlowAmount.toString()))
        log("Current amounts - Staking: ".concat(currentStakingAmount.toString()))
        log("Current amounts - LP: ".concat(currentLpAmount.toString()))
        
        // Calculate rebalancing needs
        var totalRebalanceNeeded: UFix64 = 0.0
        var rebalanceRequired = false
        
        // Check FLOW allocation
        var flowDifference: UFix64 = 0.0
        if targetFlowAmount > currentFlowAmount {
            flowDifference = targetFlowAmount - currentFlowAmount
            log("Need to increase FLOW by: ".concat(flowDifference.toString()))
        } else if currentFlowAmount > targetFlowAmount {
            flowDifference = currentFlowAmount - targetFlowAmount
            log("Need to decrease FLOW by: ".concat(flowDifference.toString()))
        }
        
        // Check staking allocation
        var stakingDifference: UFix64 = 0.0
        if targetStakingAmount > currentStakingAmount {
            stakingDifference = targetStakingAmount - currentStakingAmount
            log("Need to increase staking by: ".concat(stakingDifference.toString()))
        } else if currentStakingAmount > targetStakingAmount {
            stakingDifference = currentStakingAmount - targetStakingAmount
            log("Need to decrease staking by: ".concat(stakingDifference.toString()))
        }
        
        // Check LP allocation
        var lpDifference: UFix64 = 0.0
        if targetLpAmount > currentLpAmount {
            lpDifference = targetLpAmount - currentLpAmount
            log("Need to increase LP by: ".concat(lpDifference.toString()))
        } else if currentLpAmount > targetLpAmount {
            lpDifference = currentLpAmount - targetLpAmount
            log("Need to decrease LP by: ".concat(lpDifference.toString()))
        }
        
        // Calculate total rebalancing magnitude
        totalRebalanceNeeded = flowDifference + stakingDifference + lpDifference
        rebalanceRequired = totalRebalanceNeeded > rebalanceThreshold
        
        log("Total rebalancing needed: ".concat(totalRebalanceNeeded.toString()))
        log("Rebalancing threshold: ".concat(rebalanceThreshold.toString()))
        
        if rebalanceRequired {
            log("EXECUTING MULTI-ASSET REBALANCING")
            
            // Create rebalancing components
            let withdrawCap = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
                /storage/flowTokenVault
            )
            
            let rebalanceSource = FungibleTokenConnectors.VaultSource(
                min: 5.0,  // Keep minimum for gas and operations
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
            
            // Execute rebalancing for the largest imbalance first (FIXED: changed to var)
            var primaryRebalanceAmount = flowDifference
            if stakingDifference > primaryRebalanceAmount {
                primaryRebalanceAmount = stakingDifference
            }
            if lpDifference > primaryRebalanceAmount {
                primaryRebalanceAmount = lpDifference
            }
            
            if primaryRebalanceAmount > 0.0 && primaryRebalanceAmount <= rebalanceSource.minimumAvailable() {
                let rebalanceTokens <- rebalanceSource.withdrawAvailable(maxAmount: primaryRebalanceAmount)
                log("Rebalancing ".concat(rebalanceTokens.balance.toString()).concat(" tokens"))
                
                // Simulate complex rebalancing logic
                if flowDifference == primaryRebalanceAmount {
                    log("Primary rebalancing: Adjusting FLOW allocation")
                } else if stakingDifference == primaryRebalanceAmount {
                    log("Primary rebalancing: Adjusting staking allocation")
                } else {
                    log("Primary rebalancing: Adjusting LP allocation")
                }
                
                // Execute the rebalancing move
                rebalanceSink.depositCapacity(from: &rebalanceTokens as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
                
                if rebalanceTokens.balance > 0.0 {
                    vaultRef.deposit(from: <-rebalanceTokens)
                } else {
                    destroy rebalanceTokens
                }
                
                log("Multi-asset rebalancing completed successfully")
                
            } else {
                log("Cannot execute rebalancing - insufficient balance or amount too large")
            }
            
        } else {
            log("Portfolio within acceptable balance thresholds")
            log("No rebalancing required at this time")
        }
        
        let finalBalance = vaultRef.balance
        log("Final balance: ".concat(finalBalance.toString()))
        log("=== Next scheduled rebalancing check in 6 hours ===")
    }
}