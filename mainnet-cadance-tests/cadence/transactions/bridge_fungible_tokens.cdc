// cadence/transactions/bridge_fungible_tokens.cdc
// Advanced Cross-VM Bridge for Fungible Tokens (including FLOW)
import FungibleToken from 0xf233dcee88fe0abe
import FlowToken from 0x1654653399040a61
import EVM from 0xe467b9dd11fa00df
import FlowEVMBridge from 0x1e4aa0b87d10b141
import FlowEVMBridgeConfig from 0x1e4aa0b87d10b141

// Bridge fungible tokens from Cadence to EVM using the Cross-VM Bridge
transaction(amount: UFix64, recipientEVMAddressHex: String, tokenTypeIdentifier: String) {
    let coa: auth(EVM.Owner) &EVM.CadenceOwnedAccount
    let tokenVault: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}

    prepare(signer: auth(BorrowValue, Storage) &Account) {
        // Get or create COA
        if signer.storage.borrow<&EVM.CadenceOwnedAccount>(from: /storage/evm) == nil {
            let coa <- EVM.createCadenceOwnedAccount()
            signer.storage.save(<-coa, to: /storage/evm)
        }

        self.coa = signer.storage.borrow<auth(EVM.Owner) &EVM.CadenceOwnedAccount>(
            from: /storage/evm
        ) ?? panic("Could not borrow COA")

        // Determine token vault path based on type
        var vaultPath: StoragePath = /storage/flowTokenVault
        
        if tokenTypeIdentifier == "A.1654653399040a61.FlowToken.Vault" {
            vaultPath = /storage/flowTokenVault
        } else if tokenTypeIdentifier.contains("stFlowToken") {
            vaultPath = /storage/stFlowTokenVault
        }
        // Add more token types as needed

        self.tokenVault = signer.storage.borrow<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(
            from: vaultPath
        ) ?? panic("Could not borrow token vault")
    }

    execute {
        // Convert hex address to EVM.EVMAddress
        let addressBytes = recipientEVMAddressHex.decodeHex()
        let recipientEVMAddress = EVM.EVMAddress(bytes: addressBytes)

        // Withdraw tokens to bridge
        let tokensToTransfer <- self.tokenVault.withdraw(amount: amount)

        // Bridge tokens to EVM
        FlowEVMBridge.bridgeTokensToEVM(
            tokens: <-tokensToTransfer,
            to: recipientEVMAddress,
            feeProvider: self.coa
        )

        log("Successfully bridged ".concat(amount.toString()).concat(" tokens to EVM address ").concat(recipientEVMAddressHex))
    }
}