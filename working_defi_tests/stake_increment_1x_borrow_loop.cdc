import FungibleToken from 0xf233dcee88fe0abe
import FlowToken from 0x1654653399040a61
import stFlowToken from 0xd6f80565193ad727
import LiquidStaking from 0xd6f80565193ad727
import LendingInterfaces from 0x2df970b6cdee5735
import LendingComptroller from 0xf80cb737bfe7c792
import LendingConfig from 0x2df970b6cdee5735

// Lending Loop Uses LendingInterfaces for leverage

transaction(initialStake: UFix64) {
    let flowVault: auth(FungibleToken.Withdraw) &FlowToken.Vault
    let stFlowVaultRef: &stFlowToken.Vault
    let userCertificate: &{LendingInterfaces.IdentityCertificate}

    prepare(acct: auth(Storage, Capabilities) &Account) {
        // Get reference to FLOW vault
        self.flowVault = acct.storage
            .borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(from: /storage/flowTokenVault)
            ?? panic("Missing /storage/flowTokenVault")

        // Setup stFLOW vault if it doesn't exist
        if acct.storage.borrow<&stFlowToken.Vault>(from: stFlowToken.tokenVaultPath) == nil {
            acct.storage.save(<-stFlowToken.createEmptyVault(vaultType: Type<@stFlowToken.Vault>()), to: stFlowToken.tokenVaultPath)
            acct.capabilities.unpublish(stFlowToken.tokenReceiverPath)
            acct.capabilities.unpublish(stFlowToken.tokenBalancePath)
            acct.capabilities.publish(
                acct.capabilities.storage.issue<&{FungibleToken.Receiver}>(stFlowToken.tokenVaultPath),
                at: stFlowToken.tokenReceiverPath
            )
            acct.capabilities.publish(
                acct.capabilities.storage.issue<&{FungibleToken.Balance}>(stFlowToken.tokenVaultPath),
                at: stFlowToken.tokenBalancePath
            )
        }
        self.stFlowVaultRef = acct.storage.borrow<&stFlowToken.Vault>(from: stFlowToken.tokenVaultPath)!

        // Get or create user certificate for lending
        if acct.storage.borrow<&{LendingInterfaces.IdentityCertificate}>(from: LendingConfig.UserCertificateStoragePath) == nil {
            acct.storage.save(<-LendingComptroller.IssueUserCertificate(), to: LendingConfig.UserCertificateStoragePath)
        }
        self.userCertificate = acct.storage.borrow<&{LendingInterfaces.IdentityCertificate}>(from: LendingConfig.UserCertificateStoragePath)!
    }

    execute {
        log("=== 1x LEVERAGE LOOP ===")
        
        // 1. Stake initial FLOW → stFlow
        let flowVault1 <- self.flowVault.withdraw(amount: initialStake) as! @FlowToken.Vault
        let stFlowVault1 <- LiquidStaking.stake(flowVault: <-flowVault1)
        log("Staked ".concat(initialStake.toString()).concat(" FLOW into ").concat(stFlowVault1.balance.toString()).concat(" stFlow"))

        // 2. Deposit stFlow as collateral using stFlow pool
        let stFlowPool = getAccount(0x44fe3d9157770b2d).capabilities
            .borrow<&{LendingInterfaces.PoolPublic}>(LendingConfig.PoolPublicPublicPath)
            ?? panic("Cannot access stFlow lending pool")
        
        stFlowPool.supply(supplierAddr: self.userCertificate.owner!.address, inUnderlyingVault: <-stFlowVault1)
        log("Deposited stFlow as collateral")

        // 3. Borrow FLOW using FLOW pool
        let flowPool = getAccount(0x7492e2f9b4acea9a).capabilities
            .borrow<&{LendingInterfaces.PoolPublic}>(LendingConfig.PoolPublicPublicPath)
            ?? panic("Cannot access FLOW lending pool")

        let borrowAmount = initialStake * 0.7
        let borrowedFlow <- flowPool.borrow(userCertificate: self.userCertificate, borrowAmount: borrowAmount)
        log("Borrowed ".concat(borrowAmount.toString()).concat(" FLOW"))

        // 4. Stake borrowed FLOW → stFlow and deposit to wallet
        let borrowedFlowTyped <- borrowedFlow as! @FlowToken.Vault
        let stFlowVault2 <- LiquidStaking.stake(flowVault: <-borrowedFlowTyped)
        log("Staked borrowed ".concat(borrowAmount.toString()).concat(" FLOW into ").concat(stFlowVault2.balance.toString()).concat(" stFlow"))

        // 5. Deposit final stFlow to user's wallet
        self.stFlowVaultRef.deposit(from: <-stFlowVault2)
        log("Deposited final stFlow to user wallet")

        // Summary
        let totalBorrowed = borrowAmount
        let totalExposure = initialStake + totalBorrowed
        let leverageRatio = totalExposure / initialStake
        
        log("=== SUMMARY ===")
        log("Initial FLOW: ".concat(initialStake.toString()))
        log("Total borrowed: ".concat(totalBorrowed.toString()))
        log("Total FLOW exposure: ".concat(totalExposure.toString()))
        log("Leverage ratio: ".concat(leverageRatio.toString()).concat("x"))
    }
}