import "FungibleToken"
import "FlowToken"
import "EVM"

/// Simple bridge of FLOW from Cadence to EVM
/// FLOW becomes WFLOW in EVM
transaction(amount: UFix64) {
    let coa: auth(EVM.Call) &EVM.CadenceOwnedAccount
    let vault: @FlowToken.Vault

    prepare(signer: auth(BorrowValue, Storage) &Account) {
        // Get COA
        self.coa = signer.storage.borrow<auth(EVM.Call) &EVM.CadenceOwnedAccount>(from: /storage/evm)
            ?? panic("No COA found")

        // Withdraw FLOW
        let flowVault = signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
            from: /storage/flowTokenVault
        ) ?? panic("No FlowToken vault")
        
        self.vault <- flowVault.withdraw(amount: amount) as! @FlowToken.Vault
    }

    execute {
        // Deposit directly to COA (becomes WFLOW in EVM)
        self.coa.deposit(from: <-self.vault)
        log("Bridged ".concat(amount.toString()).concat(" FLOW to EVM"))
    }
}