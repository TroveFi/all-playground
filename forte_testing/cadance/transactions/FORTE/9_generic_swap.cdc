import FungibleToken from 0x9a0766d93b6608b7
import FlowToken from 0x7e60df042a9c0868
import FungibleTokenConnectors from 0x5a7b9cee9aaf4e4e
import DeFiActions from 0x4c2ff9dd03ab442f

// Transaction to test FungibleToken connectors (simplified without SwapConnectors)
transaction(testAmount: UFix64, minBalance: UFix64) {
    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController) &Account) {
        pre {
            testAmount > 0.0: "Test amount must be positive"
            testAmount <= 0.1: "Keep test amounts small"
            minBalance > 0.0: "Minimum balance must be positive"
        }
        
        log("Starting FungibleToken connectors test")
        log("Test amount: ".concat(testAmount.toString()))
        log("Minimum balance: ".concat(minBalance.toString()))
        
        let operationID = DeFiActions.createUniqueIdentifier()
        
        // Get initial balance
        let vaultRef = signer.storage.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)!
        let initialBalance = vaultRef.balance
        log("Initial balance: ".concat(initialBalance.toString()))
        
        // Create source with minimum balance protection
        let withdrawCap = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(
            /storage/flowTokenVault
        )
        
        let source = FungibleTokenConnectors.VaultSource(
            min: minBalance,
            withdrawVault: withdrawCap,
            uniqueID: operationID
        )
        
        // Check available funds
        let available = source.minimumAvailable()
        log("Available for test: ".concat(available.toString()))
        
        let actualAmount = testAmount < available ? testAmount : available
        log("Using amount: ".concat(actualAmount.toString()))
        
        if actualAmount > 0.0 {
            // Withdraw from source
            let withdrawnVault <- source.withdrawAvailable(maxAmount: actualAmount)
            log("Withdrawn: ".concat(withdrawnVault.balance.toString()))
            
            // Create sink for deposit back
            let depositCap = getAccount(signer.address).capabilities.get<&{FungibleToken.Vault}>(
                /public/flowTokenReceiver
            )!
            
            let sink = FungibleTokenConnectors.VaultSink(
                max: nil,
                depositVault: depositCap,
                uniqueID: operationID
            )
            
            // Deposit back through sink
            sink.depositCapacity(from: &withdrawnVault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
            
            // Handle any remaining balance
            if withdrawnVault.balance > 0.0 {
                vaultRef.deposit(from: <-withdrawnVault)
            } else {
                destroy withdrawnVault
            }
            
            let finalBalance = vaultRef.balance
            log("Final balance: ".concat(finalBalance.toString()))
            
            // Verify balance constraints
            assert(finalBalance >= minBalance, message: "Minimum balance constraint violated")
            assert(finalBalance >= initialBalance - 0.001, message: "Unexpected balance loss")
        } else {
            log("No funds available for testing")
        }
        
        log("FungibleToken connectors test completed")
    }
}