
import FungibleToken from 0xf233dcee88fe0abe
import Staking from 0x1b77ba4b414de352

transaction(farmPoolId: UInt64, lpTokenAmount: UFix64) {
    
    let userCertificate: &Staking.UserCertificate
    let lpTokenVault: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}
    let stakingCollectionRef: &{Staking.PoolCollectionPublic}
    
    prepare(signer: auth(Storage) &Account) {
        // Get user certificate
        self.userCertificate = signer.storage.borrow<&Staking.UserCertificate>(
            from: Staking.UserCertificateStoragePath
        ) ?? panic("Could not borrow UserCertificate")
        
        // Get staking collection reference
        let stakingAccount = getAccount(0x1b77ba4b414de352)
        self.stakingCollectionRef = stakingAccount.capabilities.borrow<&{Staking.PoolCollectionPublic}>(
            Staking.CollectionPublicPath
        ) ?? panic("Could not borrow staking collection")
        
        // This is a placeholder - in reality, you'd need to determine the correct
        // LP token vault path based on the specific LP token type
        // For now, assuming it's a generic vault path
        self.lpTokenVault = signer.storage.borrow<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(
            from: /storage/lpTokenVault  // This would need to be the actual LP token vault path
        ) ?? panic("Could not borrow LP token vault")
    }
    
    execute {
        // Get the specific pool
        let poolRef = self.stakingCollectionRef.getPool(pid: farmPoolId)
        
        // Withdraw LP tokens to stake
        let lpTokensToStake <- self.lpTokenVault.withdraw(amount: lpTokenAmount)
        
        // Stake the LP tokens
        poolRef.stake(staker: self.userCertificate.owner!.address, stakingToken: <-lpTokensToStake)
        
        log("Successfully staked ".concat(lpTokenAmount.toString()).concat(" LP tokens in pool ").concat(farmPoolId.toString()))
    }
}
