// cadence/transactions/unstake_generic.cdc
import FungibleToken from 0xf233dcee88fe0abe
import Staking from 0x1b77ba4b414de352

transaction(farmPoolId: UInt64, amount: UFix64) {
    
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
        // Get the specific pool
        let poolRef = self.stakingCollectionRef.getPool(pid: farmPoolId)
        let poolInfo = poolRef.getPoolInfo()
        
        // Unstake tokens from the pool
        let unstakedTokens <- poolRef.unstake(userCertificate: self.userCertificate, amount: amount)
        
        // Determine appropriate receiver based on token type
        if poolInfo.acceptTokenKey.contains("FlowToken") {
            let flowReceiver = self.signer.capabilities.get<&{FungibleToken.Receiver}>(/public/flowTokenReceiver).borrow()
                ?? panic("Could not borrow FLOW receiver")
            flowReceiver.deposit(from: <-unstakedTokens)
        } else if poolInfo.acceptTokenKey.contains("stFlowToken") {
            let stFlowReceiver = self.signer.capabilities.get<&{FungibleToken.Receiver}>(/public/stFlowTokenReceiver).borrow()
                ?? panic("Could not borrow stFLOW receiver")
            stFlowReceiver.deposit(from: <-unstakedTokens)
        } else {
            // For LP tokens and other tokens, deposit to generic vault
            // This would need specific handling per token type
            let genericReceiver = self.signer.capabilities.get<&{FungibleToken.Receiver}>(/public/genericTokenReceiver).borrow()
                ?? panic("Could not borrow generic token receiver")
            genericReceiver.deposit(from: <-unstakedTokens)
        }
        
        log("Successfully unstaked ".concat(amount.toString()).concat(" tokens from pool ").concat(farmPoolId.toString()))
    }
}