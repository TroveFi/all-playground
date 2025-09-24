// cadence/transactions/stake_pool_dynamic.cdc
import FungibleToken from 0xf233dcee88fe0abe
import FlowToken from 0x1654653399040a61
import stFlowToken from 0xd6f80565193ad727
import Staking from 0x1b77ba4b414de352

// DEX Contracts
import SwapRouter from 0xa6850776a94e6551
import SwapFactory from 0xb063c16cac85dbd1
import SwapInterfaces from 0xb78ef7afa52ff906
import SwapConfig from 0xb78ef7afa52ff906

// Dynamic staking transaction that works with any FLOW-based pool
transaction(farmPoolId: UInt64, flowAmount: UFix64) {
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

        // Get the pool's accept token key to determine what kind of LP token it needs
        let poolRef = self.stakingCollectionRef.getPool(pid: farmPoolId)
        let poolInfo = poolRef.getPoolInfo()
        let acceptTokenKey = poolInfo.acceptTokenKey
        
        log("Pool accepts token: ".concat(acceptTokenKey))

        if acceptTokenKey == "A.c353b9d685ec427d.SwapPair" {
            // This is the FLOW-stFlow pool #204 - create the correct LP tokens
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

            // Get the SPECIFIC pair for pool #204
            let pairAddress = Address(0xc353b9d685ec427d) // The exact address from acceptTokenKey
            let pairRef = getAccount(pairAddress).capabilities
                .borrow<&{SwapInterfaces.PairPublic}>(SwapConfig.PairPublicPath)
                ?? panic("Could not borrow reference to the specific pair contract")

            let lpTokens <- pairRef.addLiquidity(
                tokenAVault: <-totalFlow,
                tokenBVault: <-stFlowVault
            )

            // Stake the LP tokens
            poolRef.stake(staker: self.userCertificate.owner!.address, stakingToken: <-lpTokens)
            log("Successfully staked in FLOW-stFlow pool #204")
            
        } else if acceptTokenKey == "A.396c0cda3302d8c5.SwapPair" {
            // This is the older FLOW-stFlow pools - use the original pair
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

            let pairAddress = Address(0x396c0cda3302d8c5)
            let pairRef = getAccount(pairAddress).capabilities
                .borrow<&{SwapInterfaces.PairPublic}>(SwapConfig.PairPublicPath)
                ?? panic("Could not borrow reference to the original FLOW-stFlow pair")

            let lpTokens <- pairRef.addLiquidity(
                tokenAVault: <-totalFlow,
                tokenBVault: <-stFlowVault
            )

            poolRef.stake(staker: self.userCertificate.owner!.address, stakingToken: <-lpTokens)
            log("Successfully staked in older FLOW-stFlow pool")
            
        } else {
            panic("Pool type not supported yet: ".concat(acceptTokenKey))
        }
    }
}