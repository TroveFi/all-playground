import FungibleToken from 0xf233dcee88fe0abe
import FlowToken from 0x1654653399040a61
import stFlowToken from 0xd6f80565193ad727
import LiquidStaking from 0xd6f80565193ad727

/// Simple staking transaction for delta neutral strategy
/// Stakes FLOW -> stFLOW without any leverage or looping
transaction(flowAmount: UFix64) {
    let flowVault: auth(FungibleToken.Withdraw) &FlowToken.Vault
    let stFlowVaultRef: &stFlowToken.Vault

    prepare(acct: auth(Storage, Capabilities) &Account) {
        // Get reference to FLOW vault
        self.flowVault = acct.storage
            .borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(from: /storage/flowTokenVault)
            ?? panic("Missing /storage/flowTokenVault")

        // Setup stFLOW vault if it doesn't exist
        if acct.storage.borrow<&stFlowToken.Vault>(from: stFlowToken.tokenVaultPath) == nil {
            acct.storage.save(
                <-stFlowToken.createEmptyVault(vaultType: Type<@stFlowToken.Vault>()), 
                to: stFlowToken.tokenVaultPath
            )
            
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
        log("=== DELTA NEUTRAL STAKING ===")
        
        // Withdraw FLOW
        let flowVault <- self.flowVault.withdraw(amount: flowAmount) as! @FlowToken.Vault
        log("Withdrew ".concat(flowAmount.toString()).concat(" FLOW from wallet"))
        
        // Stake FLOW -> stFLOW
        let stFlowVault <- LiquidStaking.stake(flowVault: <-flowVault)
        let stFlowReceived = stFlowVault.balance
        log("Staked ".concat(flowAmount.toString()).concat(" FLOW -> ").concat(stFlowReceived.toString()).concat(" stFLOW"))
        
        // Deposit stFLOW to wallet
        self.stFlowVaultRef.deposit(from: <-stFlowVault)
        log("Deposited stFLOW to wallet")
        
        // Log summary for external script to parse
        log("STAKE_COMPLETE:")
        log("FLOW_STAKED=".concat(flowAmount.toString()))
        log("STFLOW_RECEIVED=".concat(stFlowReceived.toString()))
        log("READY_FOR_HEDGE")
    }
}