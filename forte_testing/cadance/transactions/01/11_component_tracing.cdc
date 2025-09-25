import FungibleToken from 0x9a0766d93b6608b7
import FlowToken from 0x7e60df042a9c0868
import DeFiActionsUtils from 0x4c2ff9dd03ab442f
import SwapConnectors from 0xaddd594cf410166a
import FungibleTokenConnectors from 0x5a7b9cee9aaf4e4e
import IncrementFiSwapConnectors from 0x49bae091e5ea16b5
import DeFiActions from 0x4c2ff9dd03ab442f

// Transaction to test component tracing with UniqueIdentifier and events
transaction(uid: String) {
    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController) &Account) {
        log("Starting component tracing test with UID: ".concat(uid))
        
        // Create unique identifier for tracking
        let operationID = DeFiActionsUtils.UniqueIdentifier(uid)
        
        // Emit tracing event
        emit ComponentWorkflowStarted(uid: uid, operation: "Source->Swapper->Sink")
        
        let vaultRef = signer.storage.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)!
        let initialBalance = vaultRef.balance
        
        log("Initial balance: ".concat(initialBalance.toString()))
        
        // Create source with tracing
        let withdrawCap = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
            /storage/flowTokenVault
        )
        
        let source = FungibleTokenConnectors.VaultSource(
            min: 2.0,
            withdrawVault: withdrawCap,
            uniqueID: operationID
        )
        
        emit ComponentCreated(uid: uid, componentType: "VaultSource", stage: "source")
        
        // Create swapper with tracing
        let swapper = IncrementFiSwapConnectors.Swapper(
            tokenInType: Type<@FlowToken.Vault>(),
            tokenOutType: Type<@FlowToken.Vault>(),
            poolID: 0,
            uniqueID: operationID
        )
        
        emit ComponentCreated(uid: uid, componentType: "IncrementFiSwapper", stage: "swapper")
        
        // Create sink with tracing
        let depositCap = getAccount(signer.address).capabilities.get<&{FungibleToken.Vault}>(
            /public/flowTokenReceiver
        )
        
        let sink = FungibleTokenConnectors.VaultSink(
            max: nil,
            depositVault: depositCap,
            uniqueID: operationID
        )
        
        emit ComponentCreated(uid: uid, componentType: "VaultSink", stage: "sink")
        
        // Execute workflow with tracing
        let swapSource = SwapConnectors.SwapSource(
            source: source,
            swapper: swapper,
            sink: sink,
            uniqueID: operationID
        )
        
        let testAmount: UFix64 = 0.001
        let quote = swapper.quote(input: testAmount)
        
        emit WorkflowStep(uid: uid, step: "quote", input: testAmount, expectedOutput: quote.output)
        
        let result = swapSource.swap(input: testAmount, minOutput: quote.output * 0.95)
        
        emit WorkflowStep(uid: uid, step: "execution", input: testAmount, actualOutput: result.output)
        
        let finalBalance = vaultRef.balance
        log("Final balance: ".concat(finalBalance.toString()))
        
        emit ComponentWorkflowCompleted(uid: uid, success: true, finalOutput: result.output)
        
        log("Component tracing test completed with UID: ".concat(uid))
    }
}

// Events for tracing
access(all) event ComponentWorkflowStarted(uid: String, operation: String)
access(all) event ComponentCreated(uid: String, componentType: String, stage: String)
access(all) event WorkflowStep(uid: String, step: String, input: UFix64, expectedOutput: UFix64?)
access(all) event WorkflowStep(uid: String, step: String, input: UFix64, actualOutput: UFix64)
access(all) event ComponentWorkflowCompleted(uid: String, success: Bool, finalOutput: UFix64)