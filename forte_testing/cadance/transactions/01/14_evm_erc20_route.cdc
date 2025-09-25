import FungibleToken from 0x9a0766d93b6608b7
import EVMTokenConnectors from 0xb88ba0e976146cd1
import DeFiActions from 0x4c2ff9dd03ab442f

// Transaction to test EVM ERC-20 Source/Sink (approve + deposit + withdraw)
transaction(amount: UFix64) {
    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController) &Account) {
        pre {
            amount > 0.0: "Amount must be positive"
            amount <= 1.0: "Keep EVM ERC-20 test amounts small"
        }
        
        log("Starting EVM ERC-20 round-trip test")
        log("Amount: ".concat(amount.toString()))
        
        let operationID = DeFiActions.createUniqueIdentifier()
        
        // Placeholder ERC-20 contract address on Flow EVM testnet
        let erc20Address = "0x1234567890abcdef1234567890abcdef12345678"  // EVM_ERC20_ADDRESS placeholder
        
        // Create EVM token source
        let evmTokenSource = EVMTokenConnectors.ERC20Source(
            tokenAddress: erc20Address,
            holderAddress: signer.address,
            uniqueID: operationID
        )
        
        // Get initial EVM balance
        let initialEVMBalance = evmTokenSource.getBalance()
        log("Initial EVM balance: ".concat(initialEVMBalance.toString()))
        
        if initialEVMBalance >= amount {
            // Approve token spending
            evmTokenSource.approve(spender: erc20Address, amount: amount)
            log("Approved spending: ".concat(amount.toString()))
            
            // Create EVM token sink
            let evmTokenSink = EVMTokenConnectors.ERC20Sink(
                tokenAddress: erc20Address,
                recipientAddress: signer.address,
                uniqueID: operationID
            )
            
            // Withdraw from EVM source
            let tokenVault <- evmTokenSource.withdraw(amount: amount)
            log("Withdrawn from EVM: ".concat(tokenVault.balance.toString()))
            
            // Deposit to EVM sink (round-trip)
            evmTokenSink.deposit(vault: <-tokenVault)
            log("Deposited back to EVM")
            
            // Check final EVM balance
            let finalEVMBalance = evmTokenSource.getBalance()
            log("Final EVM balance: ".concat(finalEVMBalance.toString()))
            
            // Account for gas fees
            let gasFee: UFix64 = 0.01  // Estimated gas fees
            
            post {
                finalEVMBalance >= initialEVMBalance - gasFee: "No unexpected loss beyond gas fees"
            }
            
            log("EVM ERC-20 round-trip completed successfully")
            
        } else {
            log("Insufficient EVM token balance for test")
            log("Required: ".concat(amount.toString()).concat(", Available: ").concat(initialEVMBalance.toString()))
        }
    }
}