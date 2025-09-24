import FungibleToken from 0xf233dcee88fe0abe
import FlowToken from 0x1654653399040a61
import Staking from 0x1b77ba4b414de352
import stFlowToken from 0xd6f80565193ad727

// DEX Contracts
import SwapRouter from 0xa6850776a94e6551
import SwapFactory from 0xb063c16cac85dbd1
import SwapInterfaces from 0xb78ef7afa52ff906
import SwapConfig from 0xb78ef7afa52ff906

// This transaction is specifically for staking into a FLOW-stFlow pool
transaction(flowAmount: UFix64, farmPoolId: UInt64) {
    let flowVault: auth(FungibleToken.Withdraw) &FlowToken.Vault
    let userCertificate: &Staking.UserCertificate
    let stakingCollectionRef: &{Staking.PoolCollectionPublic}

    prepare(signer: auth(Storage, Capabilities) &Account) {
        self.flowVault = signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(from: /storage/flowTokenVault)
            ?? panic("Could not borrow FlowToken vault")
        
        self.userCertificate = signer.storage.borrow<&Staking.UserCertificate>(from: Staking.UserCertificateStoragePath)
            ?? panic("Could not borrow UserCertificate.")
        
        let stakingAccount = getAccount(0x1b77ba4b414de352)
        self.stakingCollectionRef = stakingAccount.capabilities.borrow<&{Staking.PoolCollectionPublic}>(Staking.CollectionPublicPath)
            ?? panic("Could not borrow staking collection")

        // Check for and create a stFlowToken vault if one does not exist.
        if signer.storage.borrow<&stFlowToken.Vault>(from: /storage/stFlowTokenVault) == nil {
            // FIX: createEmptyVault() for stFlowToken also requires a `vaultType` argument.
            signer.storage.save(<-stFlowToken.createEmptyVault(vaultType: Type<@stFlowToken.Vault>()), to: /storage/stFlowTokenVault)
            signer.capabilities.publish(signer.capabilities.storage.issue<&{FungibleToken.Receiver}>(/storage/stFlowTokenVault), at: /public/stFlowTokenReceiver)
        }
    }

    execute {
        let deadline = getCurrentBlock().timestamp + 60.0 

        let totalFlow <- self.flowVault.withdraw(amount: flowAmount)
        let halfFlow <- totalFlow.withdraw(amount: flowAmount / 2.0)
        
        let stFlowVault <- SwapRouter.swapExactTokensForTokens(
            exactVaultIn: <-halfFlow,
            amountOutMin: 0.0,
            tokenKeyPath: [
                "A.1654653399040a61.FlowToken",
                "A.d6f80565193ad727.stFlowToken"
            ],
            deadline: deadline
        )

        let token0Key = "A.1654653399040a61.FlowToken"
        let token1Key = "A.d6f80565193ad727.stFlowToken"
        let pairAddress = SwapFactory.getPairAddress(token0Key: token0Key, token1Key: token1Key)
            ?? panic("FLOW-stFlow pair does not exist.")

        let pairRef = getAccount(pairAddress).capabilities
            .borrow<&{SwapInterfaces.PairPublic}>(SwapConfig.PairPublicPath)
            ?? panic("Could not borrow reference to Pair contract")

        let lpTokens <- pairRef.addLiquidity(
            tokenAVault: <-totalFlow,
            tokenBVault: <-stFlowVault
        )

        let poolRef = self.stakingCollectionRef.getPool(pid: farmPoolId)
        poolRef.stake(staker: self.userCertificate.owner!.address, stakingToken: <-lpTokens)
        
        log("Transaction SUCCEEDED: Staked in FLOW-stFlow pool ".concat(farmPoolId.toString()))
    }
}