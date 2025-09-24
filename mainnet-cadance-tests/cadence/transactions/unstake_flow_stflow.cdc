import FungibleToken from 0xf233dcee88fe0abe
import Staking from 0x1b77ba4b414de352
import stFlowToken from 0xd6f80565193ad727

import SwapFactory from 0xb063c16cac85dbd1
import SwapInterfaces from 0xb78ef7afa52ff906
import SwapConfig from 0xb78ef7afa52ff906

transaction(farmPoolId: UInt64, lpTokenAmount: UFix64) {
    let userCertificate: &Staking.UserCertificate
    let stakingCollectionRef: &{Staking.PoolCollectionPublic}
    let flowReceiver: &{FungibleToken.Receiver}
    let stFlowReceiver: &{FungibleToken.Receiver}

    prepare(signer: auth(Storage) &Account) {
        self.userCertificate = signer.storage.borrow<&Staking.UserCertificate>(from: Staking.UserCertificateStoragePath) ?? panic("No UserCertificate")
        self.flowReceiver = signer.capabilities.borrow<&{FungibleToken.Receiver}>(/public/flowTokenReceiver) ?? panic("No FLOW receiver")
        self.stFlowReceiver = signer.capabilities.borrow<&{FungibleToken.Receiver}>(/public/stFlowTokenReceiver) ?? panic("No stFLOW receiver")
        
        let stakingAccount = getAccount(0x1b77ba4b414de352)
        self.stakingCollectionRef = stakingAccount.capabilities.borrow<&{Staking.PoolCollectionPublic}>(Staking.CollectionPublicPath) ?? panic("No staking collection")
    }

    execute {
        // 1. Unstake LP tokens from the farm
        let poolRef = self.stakingCollectionRef.getPool(pid: farmPoolId)
        let lpTokens <- poolRef.unstake(userCertificate: self.userCertificate, amount: lpTokenAmount)

        // 2. Get the pair contract to remove liquidity from
        let token0Key = "A.1654653399040a61.FlowToken"
        let token1Key = "A.d6f80565193ad727.stFlowToken"
        let pairAddress = SwapFactory.getPairAddress(token0Key: token0Key, token1Key: token1Key) ?? panic("Pair not found")
        let pairRef = getAccount(pairAddress).capabilities.borrow<&{SwapInterfaces.PairPublic}>(SwapConfig.PairPublicPath) ?? panic("Could not get pair ref")

        // 3. Remove liquidity to get the underlying tokens back
        let underlyingVaults <- pairRef.removeLiquidity(from: <-lpTokens)
        let flowVault <- underlyingVaults.remove(at: 0)
        let stFlowVault <- underlyingVaults.remove(at: 0)
        destroy underlyingVaults

        // 4. Deposit the tokens back into the user's account
        self.flowReceiver.deposit(from: <-flowVault)
        self.stFlowReceiver.deposit(from: <-stFlowVault)
        log("Successfully unstaked and withdrew funds from FLOW-stFlow pool ".concat(farmPoolId.toString()))
    }
}