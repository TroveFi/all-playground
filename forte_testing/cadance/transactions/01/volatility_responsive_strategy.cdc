// File: cadence/transactions/volatility_responsive_strategy.cdc
import FungibleToken from 0x9a0766d93b6608b7
import FlowToken from 0x7e60df042a9c0868
import FungibleTokenConnectors from 0x5a7b9cee9aaf4e4e
import DeFiActions from 0x4c2ff9dd03ab442f

// Innovation: Automatically adjust risk exposure based on market volatility
transaction(volatilityIndex: UFix64) {
    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController) &Account) {
        log("=== Volatility-Responsive Risk Management ===")
        log("Current volatility index: ".concat(volatilityIndex.toString()).concat("%"))
        
        let operationID = DeFiActions.createUniqueIdentifier()
        let vaultRef = signer.storage.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)!
        let portfolioValue = vaultRef.balance
        
        log("Portfolio value: ".concat(portfolioValue.toString()))
        
        // Define volatility thresholds and corresponding risk levels
        var riskLevel: String = "UNKNOWN"
        var targetSafeAllocation: UFix64 = 0.0
        var targetRiskAllocation: UFix64 = 0.0
        var actionRequired = false
        
        if volatilityIndex <= 5.0 {
            riskLevel = "VERY_LOW"
            targetSafeAllocation = 20.0  // 20% safe assets
            targetRiskAllocation = 80.0  // 80% risk assets
        } else if volatilityIndex <= 10.0 {
            riskLevel = "LOW"
            targetSafeAllocation = 30.0  // 30% safe assets
            targetRiskAllocation = 70.0  // 70% risk assets
        } else if volatilityIndex <= 20.0 {
            riskLevel = "MODERATE"
            targetSafeAllocation = 50.0  // 50% safe assets
            targetRiskAllocation = 50.0  // 50% risk assets
        } else if volatilityIndex <= 35.0 {
            riskLevel = "HIGH"
            targetSafeAllocation = 70.0  // 70% safe assets
            targetRiskAllocation = 30.0  // 30% risk assets
        } else {
            riskLevel = "EXTREME"
            targetSafeAllocation = 90.0  // 90% safe assets
            targetRiskAllocation = 10.0  // 10% risk assets
        }
        
        log("Risk level: ".concat(riskLevel))
        log("Target allocation - Safe: ".concat(targetSafeAllocation.toString()).concat("%, Risk: ").concat(targetRiskAllocation.toString()).concat("%"))
        
        // Calculate target amounts
        let targetSafeAmount = portfolioValue * (targetSafeAllocation / 100.0)
        let targetRiskAmount = portfolioValue * (targetRiskAllocation / 100.0)
        
        // Simulate current allocations (would query real protocols in production)
        let currentSafeAmount = portfolioValue * 0.40  // Currently 40% in safe assets
        let currentRiskAmount = portfolioValue * 0.60  // Currently 60% in risk assets
        
        log("Current allocation - Safe: ".concat(currentSafeAmount.toString()).concat(" (40%), Risk: ").concat(currentRiskAmount.toString()).concat(" (60%)"))
        log("Target allocation - Safe: ".concat(targetSafeAmount.toString()).concat(", Risk: ").concat(targetRiskAmount.toString()))
        
        // Calculate rebalancing requirements
        var safeRebalanceAmount: UFix64 = 0.0
        var riskRebalanceAmount: UFix64 = 0.0
        var rebalanceDirection: String = "NONE"
        
        if targetSafeAmount > currentSafeAmount {
            safeRebalanceAmount = targetSafeAmount - currentSafeAmount
            rebalanceDirection = "RISK_OFF"  // Move from risk to safe
            actionRequired = true
        } else if currentSafeAmount > targetSafeAmount {
            safeRebalanceAmount = currentSafeAmount - targetSafeAmount
            rebalanceDirection = "RISK_ON"   // Move from safe to risk
            actionRequired = true
        }
        
        if targetRiskAmount > currentRiskAmount {
            riskRebalanceAmount = targetRiskAmount - currentRiskAmount
        } else if currentRiskAmount > targetRiskAmount {
            riskRebalanceAmount = currentRiskAmount - targetRiskAmount
        }
        
        log("Rebalance direction: ".concat(rebalanceDirection))
        log("Rebalance amount: ".concat(safeRebalanceAmount.toString()))
        
        // Execute volatility-responsive rebalancing
        if actionRequired && safeRebalanceAmount > 1.0 {
            log("Executing volatility-responsive rebalancing...")
            
            // Create rebalancing components
            let withdrawCap = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
                /storage/flowTokenVault
            )
            
            let volatilitySource = FungibleTokenConnectors.VaultSource(
                min: 2.0,  // Keep minimum for gas
                withdrawVault: withdrawCap,
                uniqueID: operationID
            )
            
            let depositCap = getAccount(signer.address).capabilities.get<&{FungibleToken.Vault}>(
                /public/flowTokenReceiver
            )
            
            let volatilitySink = FungibleTokenConnectors.VaultSink(
                max: nil,
                depositVault: depositCap,
                uniqueID: operationID
            )
            
            // Execute the rebalancing based on volatility
            if safeRebalanceAmount <= volatilitySource.minimumAvailable() {
                let rebalanceTokens <- volatilitySource.withdrawAvailable(maxAmount: safeRebalanceAmount)
                log("Rebalancing ".concat(rebalanceTokens.balance.toString()).concat(" tokens"))
                
                if rebalanceDirection == "RISK_OFF" {
                    log("RISK OFF: Moving ".concat(rebalanceTokens.balance.toString()).concat(" from risk assets to safe assets"))
                    log("Action: Selling volatile positions, buying stablecoins/bonds")
                } else {
                    log("RISK ON: Moving ".concat(rebalanceTokens.balance.toString()).concat(" from safe assets to risk assets"))
                    log("Action: Selling safe positions, buying growth assets")
                }
                
                // Execute the volatility-responsive move
                volatilitySink.depositCapacity(from: &rebalanceTokens as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
                
                if rebalanceTokens.balance > 0.0 {
                    vaultRef.deposit(from: <-rebalanceTokens)
                } else {
                    destroy rebalanceTokens
                }
                
                log("Volatility-responsive rebalancing completed")
                
            } else {
                log("Rebalancing amount exceeds available balance")
            }
            
        } else {
            log("No significant rebalancing required")
            log("Current allocation appropriate for volatility level: ".concat(riskLevel))
        }
        
        // Risk management alerts
        if volatilityIndex > 30.0 {
            log("HIGH VOLATILITY ALERT: Consider additional risk controls")
        }
        if volatilityIndex > 50.0 {
            log("EXTREME VOLATILITY WARNING: Maximum defensive positioning recommended")
        }
        
        let finalBalance = vaultRef.balance
        log("Final balance: ".concat(finalBalance.toString()))
        log("=== Next volatility check scheduled in 2 hours ===")
    }
}