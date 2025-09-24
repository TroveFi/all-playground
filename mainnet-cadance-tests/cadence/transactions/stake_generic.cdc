// cadence/transactions/stake_generic.cdc
import FungibleToken from 0xf233dcee88fe0abe
import Staking from 0x1b77ba4b414de352

// Generic transaction for staking LP tokens that user already has
transaction(farmPoolId: UInt64, amount: UFix64) {
    
    let userCertificate: &Staking.UserCertificate
    let stakingCollectionRef: &{Staking.PoolCollectionPublic}
    let signer: auth(Storage) &Account
    
    prepare(signer: auth(Storage) &Account) {
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
        
        // Get the exact LP token vault path for this specific pool
        let acceptTokenKey = poolInfo.acceptTokenKey
        var vaultPath: StoragePath = /storage/lpTokenVault
        
        // Map specific accept token keys to their correct vault paths
        if acceptTokenKey == "A.396c0cda3302d8c5.SwapPair" {
            vaultPath = /storage/lpTokenVault396c0cda
        } else if acceptTokenKey == "A.c353b9d685ec427d.SwapPair" {
            vaultPath = /storage/lpTokenVaultc353b9d6
        } else if acceptTokenKey == "A.14bc0af67ad1c5ff.SwapPair" {
            vaultPath = /storage/lpTokenVault14bc0af6
        } else if acceptTokenKey == "A.1c502071c9ab3d84.SwapPair" {
            vaultPath = /storage/lpTokenVault1c502071
        } else if acceptTokenKey == "A.fa82796435e15832.SwapPair" {
            vaultPath = /storage/lpTokenVaultfa827964
        } else if acceptTokenKey == "A.6155398610a02093.SwapPair" {
            vaultPath = /storage/lpTokenVault61553986
        } else if acceptTokenKey.contains("stFlowToken") {
            vaultPath = /storage/stFlowTokenVault
        } else if acceptTokenKey.contains("FlowToken") {
            vaultPath = /storage/flowTokenVault
        }
        
        let tokenVault = self.signer.storage.borrow<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(
            from: vaultPath
        ) ?? panic("Could not borrow token vault from path: ".concat(vaultPath.toString()))
        
        let tokensToStake <- tokenVault.withdraw(amount: amount)
        
        poolRef.stake(staker: self.userCertificate.owner!.address, stakingToken: <-tokensToStake)
        
        log("Successfully staked ".concat(amount.toString()).concat(" tokens in pool ").concat(farmPoolId.toString()))
    }
}