// File: cadence/transactions/working_yield_farming.cdc
import FungibleToken from 0x9a0766d93b6608b7
import FlowToken from 0x7e60df042a9c0868
import FungibleTokenConnectors from 0x5a7b9cee9aaf4e4e
import DeFiActions from 0x4c2ff9dd03ab442f

transaction(amount: UFix64) {
    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController) &Account) {
        log("=== DeFi Yield Farming Strategy Test ===")
        log("Amount to process: ".concat(amount.toString()))
        
        // Create operation ID for tracking
        let operationID = DeFiActions.createUniqueIdentifier()
        log("Operation ID created successfully")
        
        // Get current balance
        let vaultRef = signer.storage.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)!
        let currentBalance = vaultRef.balance
        log("Current balance: ".concat(currentBalance.toString()).concat(" FLOW"))
        
        if currentBalance >= amount + 2.0 {  // Keep 2 FLOW for gas
            // Create source with minimum balance protection
            let withdrawCap = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
                /storage/flowTokenVault
            )
            
            let tokenSource = FungibleTokenConnectors.VaultSource(
                min: 2.0,  // Keep 2 FLOW minimum for gas
                withdrawVault: withdrawCap,
                uniqueID: operationID
            )
            
            log("Available for farming: ".concat(tokenSource.minimumAvailable().toString()))
            
            // Withdraw tokens for yield farming
            let farmingTokens <- tokenSource.withdrawAvailable(maxAmount: amount)
            log("Tokens allocated for farming: ".concat(farmingTokens.balance.toString()))
            
            // Create sink (simulate farming pool deposit)
            let depositCap = getAccount(signer.address).capabilities.get<&{FungibleToken.Vault}>(
                /public/flowTokenReceiver
            )
            
            let farmingSink = FungibleTokenConnectors.VaultSink(
                max: nil,  // No limit for farming
                depositVault: depositCap,
                uniqueID: operationID
            )
            
            // Execute farming deposit
            log("Depositing to yield farming pool...")
            farmingSink.depositCapacity(from: &farmingTokens as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
            
            // Clean up remaining tokens
            if farmingTokens.balance > 0.0 {
                log("Returning unused tokens: ".concat(farmingTokens.balance.toString()))
                vaultRef.deposit(from: <-farmingTokens)
            } else {
                destroy farmingTokens
                log("All tokens deployed to farming pool")
            }
            
            log("Yield farming strategy executed successfully")
            
        } else {
            log("Insufficient balance for farming")
            log("Required: ".concat((amount + 2.0).toString()).concat(" FLOW (including gas reserve)"))
            log("Available: ".concat(currentBalance.toString()).concat(" FLOW"))
        }
        
        let finalBalance = vaultRef.balance
        log("Final balance: ".concat(finalBalance.toString()).concat(" FLOW"))
        log("=== Farming Strategy Complete ===")
        log("In production: This would run automatically via Scheduled Transactions")
    }
}