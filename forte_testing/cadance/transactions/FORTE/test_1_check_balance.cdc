// File: cadence/scripts/scheduled_defi_test_1_balance.cdc
import "FungibleToken" from 0x9a0766d93b6608b7
import "FlowToken" from 0x7e60df042a9c0868

access(all) fun main(address: Address): UFix64 {
    let account = getAccount(address)
    let vaultRef = account.capabilities.get<&{FungibleToken.Balance}>(/public/flowTokenBalance)
        .borrow()
        ?? panic("Could not borrow Balance capability")
    
    return vaultRef.balance
}

// Run with:
// flow scripts execute cadence/scripts/scheduled_defi_test_1_balance.cdc --args-json '[{"type":"Address","value":"0xbaD4374FeB7ec757027CF2186B6eb6f32412f723"}]' --network testnet