import FungibleToken from 0xf233dcee88fe0abe
import SwapRouter from 0xa6850776a94e6551
import Staking from 0x1b77ba4b414de352

transaction(farmPoolId: UInt64, lpTokenAmount: UFix64) {
    let userCertificate: &Staking.UserCertificate
    let stakingCollectionRef: &{Staking.PoolCollectionPublic}
    let flowReceiver: &{FungibleToken.Receiver}
    let usdcReceiver: &{FungibleToken.Receiver}

    prepare(signer: auth(Storage) &Account) {
        self.userCertificate = signer.storage.borrow<&Staking.UserCertificate>(from: Staking.UserCertificateStoragePath) ?? panic("No UserCertificate")
        self.flowReceiver = signer.capabilities.borrow<&{FungibleToken.Receiver}>(/public/flowTokenReceiver) ?? panic("No FLOW receiver")
        self.usdcReceiver = signer.capabilities.borrow<&{FungibleToken.Receiver}>(/public/usdcReceiver) ?? panic("No USDC receiver")
        let stakingAccount = getAccount(0x1b77ba4b414de352)
        self.stakingCollectionRef = stakingAccount.capabilities.borrow<&{Staking.PoolCollectionPublic}>(Staking.CollectionPublicPath) ?? panic("No staking collection")
    }

    execute {
        let poolRef = self.stakingCollectionRef.getPool(pid: farmPoolId)
        let lpTokens <- poolRef.unstake(userCertificate: self.userCertificate, amount: lpTokenAmount)

        let {token0, token1} <- SwapRouter.removeLiquidity(lpToken: <-lpTokens, minToken0Amount: 0.0, minToken1Amount: 0.0)

        self.flowReceiver.deposit(from: <-token0)
        self.usdcReceiver.deposit(from: <-token1)
        log("Successfully unstaked and withdrew funds from pool ".concat(farmPoolId.toString()))
    }
}