import FungibleToken from 0xf233dcee88fe0abe
import FlowToken from 0x1654653399040a61
import Staking from 0x1b77ba4b414de352

// --- CORRECTED USDC CONTRACT ---
// Using the official Usdc contract bridged by Wormhole, as FiatToken is non-functional.
import Usdc from 0x3f1a2377f8425154

// Contracts for DEX interaction
import SwapRouter from 0xa6850776a94e6551
import SwapFactory from 0xb063c16cac85dbd1
import SwapInterfaces from 0xb78ef7afa52ff906
import SwapConfig from 0xb78ef7afa52ff906

transaction(flowAmount: UFix64, farmPoolId: UInt64) {
    let flowVault: auth(FungibleToken.Withdraw) &FlowToken.Vault
    let userCertificate: &Staking.UserCertificate
    let stakingCollectionRef: &{Staking.PoolCollectionPublic}

    prepare(signer: auth(Storage, Capabilities) &Account) {
        self.flowVault = signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(from: /storage/flowTokenVault)
            ?? panic("Could not borrow FlowToken vault")
        
        self.userCertificate = signer.storage.borrow<&Staking.UserCertificate>(from: Staking.UserCertificateStoragePath)
            ?? panic("Could not borrow UserCertificate. Please run a setup transaction first.")
        
        let stakingAccount = getAccount(0x1b77ba4b414de352)
        self.stakingCollectionRef = stakingAccount.capabilities.borrow<&{Staking.PoolCollectionPublic}>(Staking.CollectionPublicPath)
            ?? panic("Could not borrow staking collection")

        // Check for and create a Usdc vault if one does not exist.
        if signer.storage.borrow<&Usdc.Vault>(from: /storage/usdcVault) == nil {
            signer.storage.save(<-Usdc.createEmptyVault(), to: /storage/usdcVault)
            signer.capabilities.publish(signer.capabilities.storage.issue<&{FungibleToken.Receiver}>(/storage/usdcVault), at: /public/usdcReceiver)
        }
    }

    execute {
        let deadline = getCurrentBlock().timestamp + 60.0 

        let totalFlow <- self.flowVault.withdraw(amount: flowAmount)
        let halfFlow <- totalFlow.withdraw(amount: flowAmount / 2.0)
        
        // Swap FLOW for the correct Usdc token.
        let usdcVault <- SwapRouter.swapExactTokensForTokens(
            exactVaultIn: <-halfFlow,
            amountOutMin: 0.0,
            tokenKeyPath: [
                "A.1654653399040a61.FlowToken",
                "A.3f1a2377f8425154.Usdc" // Using correct Usdc token key
            ],
            deadline: deadline
        )

        // Use the correct token keys for the pair.
        let token0Key = "A.1654653399040a61.FlowToken"
        let token1Key = "A.3f1a2377f8425154.Usdc"
        let pairAddress = SwapFactory.getPairAddress(token0Key: token0Key, token1Key: token1Key)
            ?? panic("FLOW-USDC pair does not exist for the functional Usdc contract.")

        let pairRef = getAccount(pairAddress).capabilities
            .borrow<&{SwapInterfaces.PairPublic}>(SwapConfig.PairPublicPath)
            ?? panic("Could not borrow reference to Pair contract")

        let lpTokens <- pairRef.addLiquidity(
            tokenAVault: <-totalFlow,
            tokenBVault: <-usdcVault
        )

        let poolRef = self.stakingCollectionRef.getPool(pid: farmPoolId)
        poolRef.stake(staker: self.userCertificate.owner!.address, stakingToken: <-lpTokens)
        
        log("Transaction SUCCEEDED: Staked in pool ".concat(farmPoolId.toString()))
    }
}