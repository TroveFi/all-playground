import FungibleToken from 0xf233dcee88fe0abe
import FlowToken from 0x1654653399040a61
import stFlowToken from 0xd6f80565193ad727

import SwapRouter from 0xa6850776a94e6551

transaction(flowIn: UFix64) {
    let flowVault: auth(FungibleToken.Withdraw) &FlowToken.Vault
    let stFlowReceiver: &{FungibleToken.Receiver}

    prepare(signer: auth(Storage, Capabilities) &Account) {
        self.flowVault = signer.storage
            .borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(from: /storage/flowTokenVault)
            ?? panic("Missing /storage/flowTokenVault")

        if signer.storage.borrow<&stFlowToken.Vault>(from: /storage/stFlowTokenVault) == nil {
            signer.storage.save(<-stFlowToken.createEmptyVault(vaultType: Type<@stFlowToken.Vault>()), to: /storage/stFlowTokenVault)
            signer.capabilities.publish(
                signer.capabilities.storage.issue<&{FungibleToken.Receiver}>(/storage/stFlowTokenVault),
                at: /public/stFlowTokenReceiver
            )
        }
        self.stFlowReceiver = signer.capabilities
            .borrow<&{FungibleToken.Receiver}>(/public/stFlowTokenReceiver)
            ?? panic("Missing /public/stFlowTokenReceiver")
    }

    execute {
        let deadline = getCurrentBlock().timestamp + 300.0
        let flow <- self.flowVault.withdraw(amount: flowIn)

        let stflow <- SwapRouter.swapExactTokensForTokens(
            exactVaultIn: <-flow,
            amountOutMin: 0.0,
            tokenKeyPath: [
                "A.1654653399040a61.FlowToken",
                "A.d6f80565193ad727.stFlowToken"
            ],
            deadline: deadline
        )
        self.stFlowReceiver.deposit(from: <-stflow)
        log("Swapped ".concat(flowIn.toString()).concat(" FLOW -> stFLOW and deposited."))
    }
}
