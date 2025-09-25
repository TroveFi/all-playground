import FungibleToken from 0x9a0766d93b6608b7
import FlowToken from 0x7e60df042a9c0868
import EVMNativeFLOWConnectors from 0xb88ba0e976146cd1
import DeFiActions from 0x4c2ff9dd03ab442f

// Transaction to test EVM Native FLOW Source/Sink round-trip
transaction(amount: UFix64) {
    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController) &Account) {
        pre {
            amount > 0.0: "Amount must be positive"
            amount <= 0.1: "Keep EVM test amounts tiny (max 0.1 FLOW)"
        }
        
        log("Starting EVM Native FLOW round-trip test")
        log("Amount: ".concat(amount.toString()))
        
        let vaultRef = signer.storage.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)!
        let initialBalance = vaultRef.balance
        
        log("Initial Cadence balance: ".concat(initialBalance.toString()))
        
        let operationID = DeFiActions.createUniqueIdentifier()
        
        // Create EVM FLOW source (wraps/bridges FLOW to EVM)
        let evmSource = EVMNativeFLOWConnectors.EVMFLOWSource(
            cadenceVault: vaultRef,
            uniqueID: operationID
        )
        
        // Bridge FLOW to EVM
        let evmFlowVault <- evmSource.withdrawToEVM(amount: amount)
        log("Bridged to EVM: ".concat(evmFlowVault.balance.toString()))
        
        // Create EVM FLOW sink (unwraps/bridges FLOW back to Cadence)
        let evmSink = EVMNativeFLOWConnectors.EVMFLOWSink(
            cadenceReceiver: getAccount(signer.address).capabilities.get<&{FungibleToken.Vault}>(
                /public/flowTokenReceiver
            ),
            uniqueID: operationID
        )
        
        // Bridge FLOW back to Cadence
        evmSink.depositFromEVM(vault: <-evmFlowVault)
        
        let finalBalance = vaultRef.balance
        log("Final Cadence balance: ".concat(finalBalance.toString()))
        
        // Account for bridge fees
        let bridgeFee: UFix64 = 0.001  // Estimated bridge fee
        
        post {
            finalBalance >= initialBalance - bridgeFee: "No unexpected loss beyond bridge fees"
        }
        
        log("EVM Native FLOW round-trip test completed")
        log("Bridge fee impact: ".concat((initialBalance - finalBalance).toString()))
    }
}