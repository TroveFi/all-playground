// cadence/transactions/stake_single_token.cdc
import FungibleToken from 0xf233dcee88fe0abe
import Staking from 0x1b77ba4b414de352
import FlowToken from 0x1654653399040a61
import stFlowToken from 0xd6f80565193ad727

// Transaction for staking single tokens (LOPPY, MVP, etc.)
transaction(farmPoolId: UInt64, tokenAmount: UFix64) {
    
    let userCertificate: &Staking.UserCertificate
    let stakingCollectionRef: &{Staking.PoolCollectionPublic}
    let signer: auth(Storage, Capabilities) &Account
    
    prepare(signer: auth(Storage, Capabilities) &Account) {
        self.signer = signer
        
        self.userCertificate = signer.storage.borrow<&Staking.UserCertificate>(
            from: Staking.UserCertificateStoragePath
        ) ?? panic("Could not borrow UserCertificate")
        
        let stakingAccount = getAccount(0x1b77ba4b414de352)
        self.stakingCollectionRef = stakingAccount.capabilities.borrow<&{Staking.PoolCollectionPublic}>(
            Staking.CollectionPublicPath
        ) ?? panic("Could not borrow staking collection")
    }
    
    execute {
        let poolRef = self.stakingCollectionRef.getPool(pid: farmPoolId)
        let poolInfo = poolRef.getPoolInfo()
        
        var tokenVault: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}? = nil
        
        // Determine token type and get appropriate vault
        if poolInfo.acceptTokenKey.contains("FlowToken") {
            tokenVault = self.signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
                from: /storage/flowTokenVault
            )
        } else if poolInfo.acceptTokenKey.contains("stFlowToken") {
            tokenVault = self.signer.storage.borrow<auth(FungibleToken.Withdraw) &stFlowToken.Vault>(
                from: /storage/stFlowTokenVault
            )
        } else {
            // For other tokens like LOPPY, MVP, etc., use generic path
            tokenVault = self.signer.storage.borrow<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(
                from: /storage/genericTokenVault // Would need token-specific paths
            )
        }
        
        if tokenVault == nil {
            panic("Could not borrow token vault for token: ".concat(poolInfo.acceptTokenKey))
        }
        
        let tokensToStake <- tokenVault!.withdraw(amount: tokenAmount)
        
        poolRef.stake(staker: self.userCertificate.owner!.address, stakingToken: <-tokensToStake)
        
        log("Successfully staked ".concat(tokenAmount.toString()).concat(" tokens in single-token pool ").concat(farmPoolId.toString()))
    }
}