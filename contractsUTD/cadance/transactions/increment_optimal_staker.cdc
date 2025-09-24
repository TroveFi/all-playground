import FungibleToken from 0xf233dcee88fe0abe
import FlowToken from 0x1654653399040a61
import stFlowToken from 0xd6f80565193ad727
import LiquidStaking from 0xd6f80565193ad727

// CRITICAL OPPORTUNITY: Pool 14 has 1805.87 RPS with 0 total staking
// This means you'd get 100% of the massive reward rate
// Risk: This might be too good to be true - could be a bug or exploit

transaction(inputAmount: UFix64) {
    let flowVault: auth(FungibleToken.Withdraw) &FlowToken.Vault
    let stFlowReceiver: &{FungibleToken.Receiver}

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
    }

    execute {
        log("🚀 EXECUTING POOL 14 STRATEGY - 1805.87 RPS, 0 total staking!")
        log("⚠️  WARNING: This yield seems too good to be true - test with small amount first")
        
        // Pool 14 accepts "A.fa82796435e15832.SwapPair" 
        // This is an LP token, so we need to:
        // 1. Create FLOW-stFLOW LP tokens
        // 2. Stake those LP tokens in Pool 14
        
        // Split FLOW for LP creation (50/50)
        let flowForLP = inputAmount * 0.5
        let flowForStaking = inputAmount * 0.5
        
        log("Splitting ".concat(inputAmount.toString()).concat(" FLOW: ").concat(flowForLP.toString()).concat(" + ").concat(flowForStaking.toString()))
        
        // Create stFLOW from half
        let flowVault1 <- self.flowVault.withdraw(amount: flowForStaking) as! @FlowToken.Vault
        let stFlowVault <- LiquidStaking.stake(flowVault: <-flowVault1)
        log("Staked ".concat(flowForStaking.toString()).concat(" FLOW → ").concat(stFlowVault.balance.toString()).concat(" stFLOW"))
        
        // Keep other half as FLOW
        let flowVault2 <- self.flowVault.withdraw(amount: flowForLP) as! @FlowToken.Vault
        
        // TODO: Add liquidity to FLOW-stFLOW pair to get LP tokens
        // This requires calling the SwapPair contract at 0xfa82796435e15832
        log("Would add liquidity: ".concat(flowForLP.toString()).concat(" FLOW + ").concat(stFlowVault.balance.toString()).concat(" stFLOW"))
        log("Expected LP tokens: ~".concat((flowForLP + stFlowVault.balance * 1.3).toString())) // Rough estimate
        
        // TODO: Stake LP tokens in Pool 14
        // This requires calling Staking.stake(pid: 14, amount: lpTokenAmount)
        log("Would stake LP tokens in Pool 14 for 1805.87 stFLOW per second!")
        
        // Calculate potential rewards
        let rewardPerSecond = 1805.87
        let rewardPerHour = rewardPerSecond * 3600.0
        let rewardPerDay = rewardPerHour * 24.0
        
        log("Potential rewards:")
        log("- Per hour: ".concat(rewardPerHour.toString()).concat(" stFLOW (~$").concat((rewardPerHour * 0.465).toString()).concat(")"))
        log("- Per day: ".concat(rewardPerDay.toString()).concat(" stFLOW (~$").concat((rewardPerDay * 0.465).toString()).concat(")"))
        
        // Safety warning
        log("⚠️  RISK ASSESSMENT:")
        log("- This pool has 0 total staking despite massive rewards")
        log("- Could indicate a bug, exploit, or hidden requirements") 
        log("- Recommend testing with <$50 first")
        log("- Monitor position closely for any issues")
        
        // For now, deposit tokens back (until we implement the actual LP creation)
        self.stFlowReceiver.deposit(from: <-stFlowVault)
        self.flowVault.deposit(from: <-flowVault2)
        
        log("✅ Strategy planned - implement LP creation to execute")
    }
}
