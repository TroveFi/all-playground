import FungibleToken from 0x9a0766d93b6608b7
import FlowToken from 0x7e60df042a9c0868
import IncrementFiFlashloanConnectors from 0x49bae091e5ea16b5
import DeFiActions from 0x4c2ff9dd03ab442f

// Transaction to test IncrementFi flashloan (borrow & repay within callback)
transaction(amount: UFix64) {
    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController) &Account) {
        pre {
            amount > 0.0: "Amount must be positive"
            amount <= 10.0: "Keep flashloan test amounts small"
        }
        
        log("Starting IncrementFi flashloan dry-run test")
        log("Flashloan amount: ".concat(amount.toString()))
        
        let operationID = DeFiActions.createUniqueIdentifier()
        
        // Create flashloan connector
        let flasher = IncrementFiFlashloanConnectors.Flasher(
            tokenType: Type<@FlowToken.Vault>(),
            poolID: 0,  // Use default pool
            uniqueID: operationID
        )
        
        // Check flashloan availability
        let maxAvailable = flasher.getMaxFlashloanAmount()
        log("Max available flashloan: ".concat(maxAvailable.toString()))
        
        assert(amount <= maxAvailable, message: "Requested amount exceeds flashloan capacity")
        
        // Create flashloan callback executor
        let executor = FlashloanCallback()
        
        // Execute flashloan - borrow, execute callback, repay
        let result = flasher.executeFlashloan(
            amount: amount,
            executor: executor,
            data: {"test": "dry-run", "operationID": operationID.toString()}
        )
        
        log("Flashloan executed successfully")
        log("Callback result: ".concat(result.success.toString()))
        log("Fees paid: ".concat(result.fees.toString()))
        
        post {
            result.success: "Flashloan must complete successfully"
            result.fees >= 0.0: "Fees must be non-negative"
        }
        
        log("IncrementFi flashloan dry-run completed successfully")
    }
}

// Flashloan callback executor
access(all) struct FlashloanCallback: IncrementFiFlashloanConnectors.FlashloanCallback {
    
    access(all) fun executeCallback(
        borrowed: @{FungibleToken.Vault},
        data: {String: AnyStruct}
    ): @{FungibleToken.Vault} {
        
        log("=== FLASHLOAN CALLBACK STARTED ===")
        log("Borrowed amount: ".concat(borrowed.balance.toString()))
        log("Callback data: ".concat(data.keys.toString()))
        
        // Perform flashloan logic here (currently just logging)
        // In a real scenario, this would be arbitrage, liquidation, etc.
        
        log("Flashloan callback logic executed")
        log("=== FLASHLOAN CALLBACK COMPLETED ===")
        
        // Return the borrowed amount plus fees for repayment
        return <-borrowed
    }
}