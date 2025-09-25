import FungibleToken from 0x9a0766d93b6608b7
import FlowToken from 0x7e60df042a9c0868
import IncrementFiSwapConnectors from 0x49bae091e5ea16b5
import SwapConnectors from 0xaddd594cf410166a
import FungibleTokenConnectors from 0x5a7b9cee9aaf4e4e
import DeFiActions from 0x4c2ff9dd03ab442f

// Transaction to test IncrementFi swap components (simplified)
transaction(testAmount: UFix64) {
    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController) &Account) {
        pre {
            testAmount > 0.0: "Test amount must be positive"
            testAmount <= 0.1: "Keep test amounts very small (max 0.1 FLOW)"
        }
        
        log("Starting IncrementFi connector test")
        
        let vaultRef = signer.storage.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)!
        let initialBalance = vaultRef.balance
        
        log("Initial balance: ".concat(initialBalance.toString()))
        log("Test amount: ".concat(testAmount.toString()))
        
        let operationID = DeFiActions.createUniqueIdentifier()
        
        // Test 1: Create and test VaultSource
        let withdrawCap = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(
            /storage/flowTokenVault
        )
        
        let source = FungibleTokenConnectors.VaultSource(
            min: 2.0,  // Keep minimum balance for gas
            withdrawVault: withdrawCap,
            uniqueID: operationID
        )
        
        log("VaultSource created successfully")
        log("Available from source: ".concat(source.minimumAvailable().toString()))
        
        // Test 2: Create BasicQuote to test SwapConnectors
        let basicQuote = SwapConnectors.BasicQuote(
            inType: Type<@FlowToken.Vault>(),
            outType: Type<@FlowToken.Vault>(),
            inAmount: testAmount,
            outAmount: testAmount * 0.98  // Simulate small slippage
        )
        
        log("BasicQuote created - inAmount: ".concat(basicQuote.inAmount.toString()))
        log("BasicQuote created - outAmount: ".concat(basicQuote.outAmount.toString()))
        
        // Test 3: Try to create IncrementFi Swapper (may fail if no valid pairs exist)
        // Note: This requires valid token pairs that actually exist
        // For now, just test that we can access the connector contract
        let swapperType = Type<IncrementFiSwapConnectors.Swapper>()
        log("IncrementFi Swapper type available: ".concat(swapperType.identifier))
        
        // Test 4: Create VaultSink
        let depositCap = getAccount(signer.address).capabilities.get<&{FungibleToken.Vault}>(
            /public/flowTokenReceiver
        )
        
        let sink = FungibleTokenConnectors.VaultSink(
            max: nil,
            depositVault: depositCap,
            uniqueID: operationID
        )
        
        log("VaultSink created successfully")
        log("Sink capacity: ".concat(sink.minimumCapacity().toString()))
        
        let finalBalance = vaultRef.balance
        log("Final balance: ".concat(finalBalance.toString()))
        
        // Since we didn't actually move funds, balance should be unchanged
        assert(finalBalance == initialBalance, message: "Balance should be unchanged in connector test")
        
        log("IncrementFi connector test completed successfully")
    }
}