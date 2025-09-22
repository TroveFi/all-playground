import FungibleToken from 0x9a0766d93b6608b7
import FlowToken from 0x7e60df042a9c0868
import SwapConnectors from 0xaddd594cf410166a
import FungibleTokenConnectors from 0x5a7b9cee9aaf4e4e
import DeFiActions from 0x4c2ff9dd03ab442f

// Transaction to test generic SwapConnectors composition (without IncrementFi)
transaction(inAmount: UFix64) {
    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController) &Account) {
        pre {
            inAmount > 0.0: "Input amount must be positive"
            inAmount <= 0.5: "Keep test amounts small"
        }
        
        log("Starting generic SwapConnectors composition test")
        log("Input amount: ".concat(inAmount.toString()))
        
        let operationID = DeFiActions.createUniqueIdentifier()
        
        // Create source
        let withdrawCap = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
            /storage/flowTokenVault
        )
        
        let source = FungibleTokenConnectors.VaultSource(
            min: 2.0,
            withdrawVault: withdrawCap,
            uniqueID: operationID
        )
        
        // Create generic swapper adapter
        let swapper = SwapConnectors.GenericSwapper(
            tokenInType: Type<@FlowToken.Vault>(),
            tokenOutType: Type<@FlowToken.Vault>(),
            path: ["FLOW", "FLOW"],  // Self-swap for testing
            uniqueID: operationID
        )
        
        // Create sink
        let depositCap = getAccount(signer.address).capabilities.get<&{FungibleToken.Vault}>(
            /public/flowTokenReceiver
        )
        
        let sink = FungibleTokenConnectors.VaultSink(
            max: nil,
            depositVault: depositCap,
            uniqueID: operationID
        )
        
        // Get quote
        let quote = swapper.quote(input: inAmount)
        let minOut = quote.output * 0.95  // 5% slippage
        
        log("Expected output: ".concat(quote.output.toString()))
        log("Minimum output: ".concat(minOut.toString()))
        
        // Execute swap: A → B
        let swapSource = SwapConnectors.SwapSource(
            source: source,
            swapper: swapper,
            sink: sink,
            uniqueID: operationID
        )
        
        let result = swapSource.swap(input: inAmount, minOutput: minOut)
        
        log("Swap output: ".concat(result.output.toString()))
        
        post {
            result.output > 0.0: "Must produce positive output"
            result.output >= minOut: "Output must meet minimum threshold"
        }
        
        log("Generic SwapConnectors composition test completed")
    }
}