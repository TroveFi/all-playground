// cadence/transactions/stake_loppy_single.cdc
import FungibleToken from 0xf233dcee88fe0abe
import Staking from 0x1b77ba4b414de352

// Transaction for staking LOPPY tokens in single-token staking pool
transaction(farmPoolId: UInt64, loppyAmount: UFix64) {
    
    let userCertificate: &Staking.UserCertificate
    let stakingCollectionRef: &{Staking.PoolCollectionPublic}
    let loppyVault: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}
    
    prepare(signer: auth(Storage, Capabilities) &Account) {
        self.userCertificate = signer.storage.borrow<&Staking.UserCertificate>(
            from: Staking.UserCertificateStoragePath
        ) ?? panic("Could not borrow UserCertificate")
        
        let stakingAccount = getAccount(0x1b77ba4b414de352)
        self.stakingCollectionRef = stakingAccount.capabilities.borrow<&{Staking.PoolCollectionPublic}>(
            Staking.CollectionPublicPath
        ) ?? panic("Could not borrow staking collection")
        
        // Get LOPPY vault - replace with actual LOPPY token storage path
        self.loppyVault = signer.storage.borrow<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(
            from: /storage/loppyTokenVault
        ) ?? panic("Could not borrow LOPPY token vault")
    }
    
    execute {
        // Get the specific pool
        let poolRef = self.stakingCollectionRef.getPool(pid: farmPoolId)
        
        // Withdraw LOPPY tokens to stake
        let loppyTokensToStake <- self.loppyVault.withdraw(amount: loppyAmount)
        
        // Stake the LOPPY tokens
        poolRef.stake(staker: self.userCertificate.owner!.address, stakingToken: <-loppyTokensToStake)
        
        log("Successfully staked ".concat(loppyAmount.toString()).concat(" LOPPY tokens in pool ").concat(farmPoolId.toString()))
    }
}