// cadence/transactions/create_and_stake_lp.cdc
import FungibleToken from 0xf233dcee88fe0abe
import FlowToken from 0x1654653399040a61
import stFlowToken from 0xd6f80565193ad727
import Staking from 0x1b77ba4b414de352

// DEX Contracts
import SwapRouter from 0xa6850776a94e6551
import SwapFactory from 0xb063c16cac85dbd1
import SwapInterfaces from 0xb78ef7afa52ff906
import SwapConfig from 0xb78ef7afa52ff906

// This transaction creates LP tokens and stakes them in one go
transaction(farmPoolId: UInt64, flowAmount: UFix64, secondTokenAmount: UFix64, poolType: String) {
    let flowVault: auth(FungibleToken.Withdraw) &FlowToken.Vault
    let userCertificate: &Staking.UserCertificate
    let stakingCollectionRef: &{Staking.PoolCollectionPublic}
    let signer: auth(Storage, Capabilities) &Account

    prepare(signer: auth(Storage, Capabilities) &Account) {
        self.signer = signer
        
        self.flowVault = signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(from: /storage/flowTokenVault)
            ?? panic("Could not borrow FlowToken vault")
        
        self.userCertificate = signer.storage.borrow<&Staking.UserCertificate>(from: Staking.UserCertificateStoragePath)
            ?? panic("Could not borrow UserCertificate")
        
        let stakingAccount = getAccount(0x1b77ba4b414de352)
        self.stakingCollectionRef = stakingAccount.capabilities.borrow<&{Staking.PoolCollectionPublic}>(Staking.CollectionPublicPath)
            ?? panic("Could not borrow staking collection")

        // Ensure stFlow vault exists
        if signer.storage.borrow<&stFlowToken.Vault>(from: /storage/stFlowTokenVault) == nil {
            signer.storage.save(<-stFlowToken.createEmptyVault(vaultType: Type<@stFlowToken.Vault>()), to: /storage/stFlowTokenVault)
            signer.capabilities.publish(signer.capabilities.storage.issue<&{FungibleToken.Receiver}>(/storage/stFlowTokenVault), at: /public/stFlowTokenReceiver)
        }
    }

    execute {
        let deadline = getCurrentBlock().timestamp + 300.0 // 5 minutes

        if poolType == "FLOW-stFlow" {
            // Create FLOW-stFlow LP tokens
            let totalFlow <- self.flowVault.withdraw(amount: flowAmount)
            let halfFlow <- totalFlow.withdraw(amount: flowAmount / 2.0)
            
            // Swap half FLOW for stFlow
            let stFlowVault <- SwapRouter.swapExactTokensForTokens(
                exactVaultIn: <-halfFlow,
                amountOutMin: 0.0,
                tokenKeyPath: [
                    "A.1654653399040a61.FlowToken",
                    "A.d6f80565193ad727.stFlowToken"
                ],
                deadline: deadline
            )

            // Get pair and add liquidity
            let token0Key = "A.1654653399040a61.FlowToken"
            let token1Key = "A.d6f80565193ad727.stFlowToken"
            let pairAddress = SwapFactory.getPairAddress(token0Key: token0Key, token1Key: token1Key)
                ?? panic("FLOW-stFlow pair does not exist")

            let pairRef = getAccount(pairAddress).capabilities
                .borrow<&{SwapInterfaces.PairPublic}>(SwapConfig.PairPublicPath)
                ?? panic("Could not borrow reference to Pair contract")

            let lpTokens <- pairRef.addLiquidity(
                tokenAVault: <-totalFlow,
                tokenBVault: <-stFlowVault
            )

            // Stake the LP tokens
            let poolRef = self.stakingCollectionRef.getPool(pid: farmPoolId)
            poolRef.stake(staker: self.userCertificate.owner!.address, stakingToken: <-lpTokens)
            
        } else {
            panic("Pool type not supported yet: ".concat(poolType))
        }
        
        log("Successfully created and staked LP tokens in pool ".concat(farmPoolId.toString()))
    }
}