// cadence/transactions/setup_coa.cdc
import EVM from 0xe467b9dd11fa00df

// Setup a Cadence Owned Account (COA) for cross-VM operations
transaction() {
    prepare(signer: auth(BorrowValue, SaveValue, IssueStorageCapabilityController, PublishCapability) &Account) {
        // Check if COA already exists
        if signer.storage.borrow<&EVM.CadenceOwnedAccount>(from: /storage/evm) != nil {
            log("COA already exists")
            return
        }

        // Create a new COA
        let coa <- EVM.createCadenceOwnedAccount()
        
        // Save COA to storage
        signer.storage.save(<-coa, to: /storage/evm)
        
        // Create and publish a capability for the COA
        let coaCapability = signer.capabilities.storage.issue<&EVM.CadenceOwnedAccount>(/storage/evm)
        signer.capabilities.publish(coaCapability, at: /public/evm)

        // Get the COA reference to log the EVM address
        let coaRef = signer.storage.borrow<&EVM.CadenceOwnedAccount>(from: /storage/evm)!
        let evmAddress = coaRef.address()

        log("COA created successfully!")
        log("Cadence Address: ".concat(signer.address.toString()))
        log("EVM Address: 0x".concat(evmAddress.toString()))
    }
}