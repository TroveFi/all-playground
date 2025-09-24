// cadence/transactions/stake_stflow_mvp.cdc
import FungibleToken from 0xf233dcee88fe0abe
import stFlowToken from 0xd6f80565193ad727
import Staking from 0x1b77ba4b414de352

// DEX Contracts
import SwapRouter from 0xa6850776a94e6551
import SwapFactory from 0xb063c16cac85dbd1
import SwapInterfaces from 0xb78ef7afa52ff906
import SwapConfig from 0xb78ef7afa52ff906

// Transaction for creating stFlow-MVP LP tokens and staking them
transaction(stFlowAmount: UFix64, mvpAmount: UFix64, farmPoolId: UInt64) {
    let stFlowVault: auth(FungibleToken.Withdraw) &stFlowToken.Vault
    let userCertificate: &Staking.UserCertificate
    let stakingCollectionRef: &{Staking.PoolCollectionPublic}

    prepare(signer: auth(Storage, Capabilities) &Account) {
        self.stFlowVault = signer.storage.borrow<auth(FungibleToken.Withdraw) &stFlowToken.Vault>(from: /storage/stFlowTokenVault)
            ?? panic("Could not borrow stFlowToken vault")
        
        self.userCertificate = signer.storage.borrow<&Staking.UserCertificate>(from: Staking.UserCertificateStoragePath)
            ?? panic("Could not borrow UserCertificate")
        
        let stakingAccount = getAccount(0x1b77ba4b414de352)
        self.stakingCollectionRef = stakingAccount.capabilities.borrow<&{Staking.PoolCollectionPublic}>(Staking.CollectionPublicPath)
            ?? panic("Could not borrow staking collection")
    }

    execute {
        let deadline = getCurrentBlock().timestamp + 60.0

        // Get stFlow tokens
        let stFlowTokens <- self.stFlowVault.withdraw(amount: stFlowAmount)
        
        // Get MVP tokens (assuming user has them)
        let mvpVault = signer.storage.borrow<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(
            from: /storage/mvpTokenVault
        ) ?? panic("Could not borrow MVP token vault")
        
        let mvpTokens <- mvpVault.withdraw(amount: mvpAmount)

        // Get the stFlow-MVP pair
        let token0Key = "A.d6f80565193ad727.stFlowToken"
        let token1Key = "A.MVP_CONTRACT_ADDRESS.MVP" // Replace with actual MVP contract
        let pairAddress = SwapFactory.getPairAddress(token0Key: token0Key, token1Key: token1Key)
            ?? panic("stFlow-MVP pair does not exist")

        let pairRef = getAccount(pairAddress).capabilities
            .borrow<&{SwapInterfaces.PairPublic}>(SwapConfig.PairPublicPath)
            ?? panic("Could not borrow reference to Pair contract")

        // Add liquidity to get LP tokens
        let lpTokens <- pairRef.addLiquidity(
            tokenAVault: <-stFlowTokens,
            tokenBVault: <-mvpTokens
        )

        // Stake the LP tokens
        let poolRef = self.stakingCollectionRef.getPool(pid: farmPoolId)
        poolRef.stake(staker: self.userCertificate.owner!.address, stakingToken: <-lpTokens)
        
        log("Successfully staked stFlow-MVP LP tokens in pool ".concat(farmPoolId.toString()))
    }
}