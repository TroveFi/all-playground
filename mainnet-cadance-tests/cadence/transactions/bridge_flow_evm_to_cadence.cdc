// cadence/transactions/bridge_flow_evm_to_cadence.cdc
import FungibleToken from 0xf233dcee88fe0abe
import FlowToken from 0x1654653399040a61
import EVM from 0xe467b9dd11fa00df

// Transfer FLOW from EVM to Cadence using built-in COA functionality
transaction(amount: UFix64, evmAddressHex: String) {
    let coa: auth(EVM.Owner) &EVM.CadenceOwnedAccount
    let flowReceiver: &{FungibleToken.Receiver}

    prepare(signer: auth(BorrowValue) &Account) {
        // Borrow the COA from storage
        self.coa = signer.storage.borrow<auth(EVM.Owner) &EVM.CadenceOwnedAccount>(
            from: /storage/evm
        ) ?? panic("Could not borrow COA from provided gateway address")

        // Get FLOW token receiver
        self.flowReceiver = signer.capabilities.get<&{FungibleToken.Receiver}>(/public/flowTokenReceiver).borrow()
            ?? panic("Could not borrow FLOW receiver")
    }

    execute {
        // Convert hex address to EVM.EVMAddress
        let addressBytes = evmAddressHex.decodeHex()
        let evmAddress = EVM.EVMAddress(bytes: addressBytes)

        // Use COA's built-in FLOW withdrawal (this is built into COA)
        let flowVault <- self.coa.withdraw(balance: EVM.Balance(attoflow: amount * 1000000000000000000))

        // Deposit to Cadence FLOW vault
        self.flowReceiver.deposit(from: <-flowVault)

        log("Successfully bridged ".concat(amount.toString()).concat(" FLOW from EVM to Cadence"))
    }
}