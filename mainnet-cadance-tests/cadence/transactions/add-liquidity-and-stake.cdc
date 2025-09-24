import FungibleToken from 0xf233dcee88fe0abe
import FlowToken from 0x1654653399040a61
import SwapRouter from 0xa6850776a94e6551
import Staking from 0x1b77ba4b414de352
import FiatToken from 0xb19436aae4d94622 // USDC

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

        if signer.storage.borrow<&FiatToken.Vault>(from: /storage/usdcVault) == nil {
            signer.storage.save(<-FiatToken.createEmptyVault(), to: /storage/usdcVault)
            signer.capabilities.publish(signer.capabilities.storage.issue<&FiatToken.Vault{FungibleToken.Receiver}>(/storage/usdcVault), at: /public/usdcReceiver)
        }
    }

    execute {
        let totalFlow <- self.flowVault.withdraw(amount: flowAmount)
        let halfFlow <- totalFlow.withdraw(amount: flowAmount / 2.0)
        
        let tokenOutVault <- SwapRouter.swapExactTokensForTokens(
            fromToken: <-halfFlow,
            tokenOutType: Type<FiatToken>(),
            path: [Type<FlowToken>()],
            minAmountOut: 0.0
        )

        let lpTokens <- SwapRouter.addLiquidity(
            token0: <-totalFlow,
            token1: <-tokenOutVault,
            minToken0Amount: 0.0,
            minToken1Amount: 0.0
        )

        let poolRef = self.stakingCollectionRef.getPool(pid: farmPoolId)
        poolRef.stake(staker: self.userCertificate.owner!.address, stakingToken: <-lpTokens)
        
        log("Successfully staked in pool ".concat(farmPoolId.toString()))
    }
}