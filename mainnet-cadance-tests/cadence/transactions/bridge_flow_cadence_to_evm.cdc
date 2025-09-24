// cadence/transactions/bridge_flow_cadence_to_evm.cdc
import FungibleToken from 0xf233dcee88fe0abe
import FlowToken from 0x1654653399040a61
import EVM from 0xe467b9dd11fa00df

// Transfer FLOW from Cadence to EVM using built-in COA functionality
transaction(amount: UFix64, recipientEVMAddressHex: String) {
    let coa: auth(EVM.Owner) &EVM.CadenceOwnedAccount
    let flowVault: auth(FungibleToken.Withdraw) &FlowToken.Vault

    prepare(signer: auth(BorrowValue) &Account) {
        // Borrow the COA from storage
        self.coa = signer.storage.borrow<auth(EVM.Owner) &EVM.CadenceOwnedAccount>(
            from: /storage/evm
        ) ?? panic("Could not borrow COA from provided gateway address")

        // Get FLOW vault
        self.flowVault = signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
            from: /storage/flowTokenVault
        ) ?? panic("Could not borrow FLOW vault")
    }

    execute {
        // Convert hex address to EVM.EVMAddress
        let addressBytes = recipientEVMAddressHex.decodeHex()
        let recipientEVMAddress = EVM.EVMAddress(bytes: addressBytes)

        // Withdraw FLOW from Cadence vault
        let flowToTransfer <- self.flowVault.withdraw(amount: amount)

        // Use COA's built-in FLOW deposit (this is built into COA)
        self.coa.deposit(from: <-flowToTransfer)

        // Transfer from COA to recipient EVM address
        let transferResult = self.coa.call(
            to: recipientEVMAddress,
            data: [],
            gasLimit: 21000,
            value: EVM.Balance(attoflow: amount * 1000000000000000000)
        )

        assert(transferResult.status == EVM.Status.successful, message: "EVM transfer failed")

        log("Successfully bridged ".concat(amount.toString()).concat(" FLOW from Cadence to EVM address ").concat(recipientEVMAddressHex))
    }
}