import "FungibleToken"
import "FlowToken"
import "EVM"

/// Simple bridge of FLOW from EVM back to Cadence
/// Unwraps WFLOW back to FLOW
transaction(amount: UInt256) {
    let coa: auth(EVM.Withdraw) &EVM.CadenceOwnedAccount
    let receiver: &FlowToken.Vault

    prepare(signer: auth(BorrowValue, Storage) &Account) {
        // Get COA
        self.coa = signer.storage.borrow<auth(EVM.Withdraw) &EVM.CadenceOwnedAccount>(from: /storage/evm)
            ?? panic("No COA found")

        // Get FLOW receiver
        self.receiver = signer.storage.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)
            ?? panic("No FlowToken vault")
    }

    execute {
        // Convert UInt256 to UInt
        let amountUInt = UInt(amount)
        
        // Withdraw from COA (unwraps WFLOW to FLOW)
        let balance = EVM.Balance(attoflow: amountUInt)
        let vault <- self.coa.withdraw(balance: balance) as! @FlowToken.Vault
        
        let flowAmount = vault.balance
        self.receiver.deposit(from: <-vault)
        
        log("Bridged ".concat(flowAmount.toString()).concat(" FLOW from EVM"))
    }
}