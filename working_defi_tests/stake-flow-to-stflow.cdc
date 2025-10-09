import FungibleToken from 0xf233dcee88fe0abe
import FlowToken from 0x1654653399040a61
import stFlowToken from 0xd6f80565193ad727
import LiquidStaking from 0xd6f80565193ad727
import SwapInterfaces from 0xb78ef7afa52ff906

// Uses LiquidStaking and DEX swaps, not Staking farming pools

transaction(flowAmount: UFix64) {
    let flowVault: auth(FungibleToken.Withdraw) &FlowToken.Vault
    let stFlowVaultRef: &stFlowToken.Vault

    prepare(acct: auth(Storage, Capabilities) &Account) {
        self.flowVault =
            acct.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(from: /storage/flowTokenVault)
            ?? panic("Missing /storage/flowTokenVault")

        if acct.storage.borrow<&stFlowToken.Vault>(from: stFlowToken.tokenVaultPath) == nil {
            acct.storage.save(<-stFlowToken.createEmptyVault(vaultType: Type<@stFlowToken.Vault>()), to: stFlowToken.tokenVaultPath)
            acct.capabilities.unpublish(stFlowToken.tokenReceiverPath)
            acct.capabilities.unpublish(stFlowToken.tokenBalancePath)
            acct.capabilities.publish(
                acct.capabilities.storage.issue<&{FungibleToken.Receiver}>(stFlowToken.tokenVaultPath),
                at: stFlowToken.tokenReceiverPath
            )
            acct.capabilities.publish(
                acct.capabilities.storage.issue<&{FungibleToken.Balance}>(stFlowToken.tokenVaultPath),
                at: stFlowToken.tokenBalancePath
            )
        }
        self.stFlowVaultRef = acct.storage.borrow<&stFlowToken.Vault>(from: stFlowToken.tokenVaultPath)!
    }

    execute {
        let vaultIn <- self.flowVault.withdraw(amount: flowAmount) as! @FlowToken.Vault

        let pairV1 = getAccount(0x396c0cda3302d8c5).capabilities
            .borrow<&{SwapInterfaces.PairPublic}>(/public/increment_swap_pair)
            ?? panic("Missing v1 pair public")
        let pairStable = getAccount(0xc353b9d685ec427d).capabilities
            .borrow<&{SwapInterfaces.PairPublic}>(/public/increment_swap_pair)
            ?? panic("Missing stable pair public")

        let estStake = LiquidStaking.calcStFlowFromFlow(flowAmount: flowAmount)
        let estV1 = pairV1.getAmountOut(amountIn: flowAmount, tokenInKey: "A.1654653399040a61.FlowToken")
        let estStable = pairStable.getAmountOut(amountIn: flowAmount, tokenInKey: "A.1654653399040a61.FlowToken")

        let bestSwapOut = estStable > estV1 ? estStable : estV1
        let bestPair = estStable > estV1 ? pairStable : pairV1

        if estStake > bestSwapOut {
            let out <- LiquidStaking.stake(flowVault: <-vaultIn)
            self.stFlowVaultRef.deposit(from: <-out)
            log("ROUTE: staked via LiquidStaking")
        } else {
            let out <- bestPair.swap(vaultIn: <-vaultIn, exactAmountOut: nil)
            self.stFlowVaultRef.deposit(from: <-out)
            log("ROUTE: swapped via DEX")
        }
    }
}
