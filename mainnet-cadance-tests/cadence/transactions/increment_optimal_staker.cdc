import FungibleToken from 0xf233dcee88fe0abe
import FlowToken from 0x1654653399040a61
import stFlowToken from 0xd6f80565193ad727
import SwapRouter from 0xa6850776a94e6551
import Staking from 0x1b77ba4b414de352

transaction(poolId: UInt64, inputAmount: UFix64) {
    let flowVault: auth(FungibleToken.Withdraw) &FlowToken.Vault
    let stFlowReceiver: &{FungibleToken.Receiver}
    let stakingCollection: &{Staking.PoolCollectionPublic}

    prepare(acct: auth(Storage, Capabilities) &Account) {
        self.flowVault = acct.storage
            .borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(from: /storage/flowTokenVault)
            ?? panic("Missing FLOW vault")

        // Setup stFLOW receiver  
        if acct.storage.borrow<&stFlowToken.Vault>(from: stFlowToken.tokenVaultPath) == nil {
            acct.storage.save(<-stFlowToken.createEmptyVault(vaultType: Type<@stFlowToken.Vault>()), to: stFlowToken.tokenVaultPath)
            acct.capabilities.unpublish(stFlowToken.tokenReceiverPath)
            acct.capabilities.publish(
                acct.capabilities.storage.issue<&{FungibleToken.Receiver}>(stFlowToken.tokenVaultPath),
                at: stFlowToken.tokenReceiverPath
            )
        }
        self.stFlowReceiver = acct.capabilities
            .borrow<&{FungibleToken.Receiver}>(stFlowToken.tokenReceiverPath)
            ?? panic("Missing stFLOW receiver")

        self.stakingCollection = getAccount(0x1b77ba4b414de352).capabilities
            .borrow<&{Staking.PoolCollectionPublic}>(Staking.CollectionPublicPath)
            ?? panic("Cannot access staking collection")
    }

    execute {
        log("Executing strategy for Pool ".concat(poolId.toString()).concat(" with ".concat(inputAmount.toString()).concat(" FLOW"))
        
        let poolRef = self.stakingCollection.getPool(pid: poolId)
        let poolInfo = poolRef.getPoolInfo()
        
        log("Pool status: ".concat(poolInfo.status))
        log("Total staking: ".concat(poolInfo.totalStaking.toString()))
        log("Accepts: ".concat(poolInfo.acceptTokenKey))
        
        // Only proceed if pool is active
        if poolInfo.status != "1" {
            panic("Pool is not active")
        }
        
        // For LP token pools, create FLOW-stFLOW LP
        if poolInfo.acceptTokenKey.contains("SwapPair") {
            log("Creating LP tokens for staking")
            
            // Use SwapRouter to create FLOW-stFLOW LP tokens
            let flowVault <- self.flowVault.withdraw(amount: inputAmount) as! @FlowToken.Vault
            
            // Swap to stFLOW through DEX (avoid direct staking due to auction period)
            let stFlowVault <- SwapRouter.swapExactTokensForTokens(
                exactVaultIn: <-flowVault,
                amountOutMin: 0.0,
                tokenKeyPath: [
                    "A.1654653399040a61.FlowToken",
                    "A.d6f80565193ad727.stFlowToken"
                ],
                deadline: getCurrentBlock().timestamp + 300.0
            )
            
            log("Swapped FLOW for ".concat(stFlowVault.balance.toString()).concat(" stFLOW via DEX"))
            
            // TODO: Add liquidity to create LP tokens
            // TODO: Stake LP tokens in the target pool
            
            log("Would create LP tokens and stake in Pool ".concat(poolId.toString()))
            
            // For now, deposit stFLOW to user wallet
            self.stFlowReceiver.deposit(from: <-stFlowVault)
            
        } else {
            log("Non-LP pool - would need different strategy")
        }
        
        log("Strategy executed for Pool ".concat(poolId.toString()))
    }
}