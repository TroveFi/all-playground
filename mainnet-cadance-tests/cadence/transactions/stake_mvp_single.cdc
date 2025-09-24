// cadence/transactions/stake_mvp_single.cdc
import FungibleToken from 0xf233dcee88fe0abe
import Staking from 0x1b77ba4b414de352

// Transaction for staking MVP tokens in single-token staking pool
transaction(farmPoolId: UInt64, mvpAmount: UFix64) {
    
    let userCertificate: &Staking.UserCertificate
    let stakingCollectionRef: &{Staking.PoolCollectionPublic}
    let mvpVault: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}
    
    prepare(signer: auth(Storage, Capabilities) &Account) {
        self.userCertificate = signer.storage.borrow<&Staking.UserCertificate>(
            from: Staking.UserCertificateStoragePath
        ) ?? panic("Could not borrow UserCertificate")
        
        let stakingAccount = getAccount(0x1b77ba4b414de352)
        self.stakingCollectionRef = stakingAccount.capabilities.borrow<&{Staking.PoolCollectionPublic}>(
            Staking.CollectionPublicPath
        ) ?? panic("Could not borrow staking collection")
        
        // Get MVP vault - replace with actual MVP token storage path
        self.mvpVault = signer.storage.borrow<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(
            from: /storage/mvpTokenVault
        ) ?? panic("Could not borrow MVP token vault")
    }
    
    execute {
        // Get the specific pool
        let poolRef = self.stakingCollectionRef.getPool(pid: farmPoolId)
        
        // Withdraw MVP tokens to stake
        let mvpTokensToStake <- self.mvpVault.withdraw(amount: mvpAmount)
        
        // Stake the MVP tokens
        poolRef.stake(staker: self.userCertificate.owner!.address, stakingToken: <-mvpTokensToStake)
        
        log("Successfully staked ".concat(mvpAmount.toString()).concat(" MVP tokens in pool ").concat(farmPoolId.toString()))
    }
}