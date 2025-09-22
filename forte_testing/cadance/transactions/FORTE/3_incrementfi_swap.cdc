import FungibleToken from 0x9a0766d93b6608b7
import FlowToken from 0x7e60df042a9c0868
import IncrementFiSwapConnectors from 0x49bae091e5ea16b5
import SwapConnectors from 0xaddd594cf410166a
import FungibleTokenConnectors from 0x5a7b9cee9aaf4e4e
import DeFiActions from 0x4c2ff9dd03ab442f

// Transaction to test IncrementFi single-hop swap
transaction(inAmount: UFix64) {
    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController) &Account) {
        pre {
            inAmount > 0.0: "Input amount must be positive"
            inAmount <= 1.0: "Keep test amounts small (max 1.0 FLOW)"
        }
        
        log("Starting IncrementFi swap test")
        
        let vaultRef = signer.storage.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)!
        let initialBalance = vaultRef.balance
        
        log("Initial balance: ".concat(initialBalance.toString()))
        log("Swap amount: ".concat(inAmount.toString()))
        
        let operationID = DeFiActions.createUniqueIdentifier()
        
        // Create source
        let withdrawCap = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
            /storage/flowTokenVault
        )
        
        let source = FungibleTokenConnectors.VaultSource(
            min: 2.0,  // Keep minimum balance for gas
            withdrawVault: withdrawCap,
            uniqueID: operationID
        )
        
        // Create IncrementFi swapper (FLOW -> stableswap token if available)
        let swapper = IncrementFiSwapConnectors.Swapper(
            tokenInType: Type<@FlowToken.Vault>(),
            tokenOutType: Type<@FlowToken.Vault>(),  // Self-swap for testing
            poolID: 0,  // Use default pool
            uniqueID: operationID
        )
        
        // Create sink for output
        let depositCap = getAccount(signer.address).capabilities.get<&{FungibleToken.Vault}>(
            /public/flowTokenReceiver
        )
        
        let sink = FungibleTokenConnectors.VaultSink(
            max: nil,
            depositVault: depositCap,
            uniqueID: operationID
        )
        
        // Get quote for minimum output (slippage protection)
        let quote = swapper.quote(input: inAmount)
        let minOut = quote.output * 0.95  // 5% slippage tolerance
        
        log("Expected output: ".concat(quote.output.toString()))
        log("Minimum output: ".concat(minOut.toString()))
        
        // Execute swap pipeline: Source -> Swapper -> Sink
        let swapSource = SwapConnectors.SwapSource(
            source: source,
            swapper: swapper,
            sink: sink,
            uniqueID: operationID
        )
        
        let result = swapSource.swap(input: inAmount, minOutput: minOut)
        
        log("Swap result output: ".concat(result.output.toString()))
        
        post {
            result.output > 0.0: "Swap must produce positive output"
            result.output >= minOut: "Output must meet minimum threshold"
        }
        
        let finalBalance = vaultRef.balance
        log("Final balance: ".concat(finalBalance.toString()))
        
        log("IncrementFi swap test completed successfully")
    }
}