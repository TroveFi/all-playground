import FungibleToken from 0xf233dcee88fe0abe
import FlowToken from 0x1654653399040a61
import stFlowToken from 0xd6f80565193ad727
import LiquidStaking from 0xd6f80565193ad727
import LendingInterfaces from 0x2df970b6cdee5735
import LendingComptroller from 0xf80cb737bfe7c792
import LendingConfig from 0x2df970b6cdee5735

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
        // Get pool references once
        let stFlowPool = getAccount(0x44fe3d9157770b2d).capabilities
            .borrow<&{LendingInterfaces.PoolPublic}>(LendingConfig.PoolPublicPublicPath)
            ?? panic("Cannot access stFlow lending pool")
        
        let flowPool = getAccount(0x7492e2f9b4acea9a).capabilities
            .borrow<&{LendingInterfaces.PoolPublic}>(LendingConfig.PoolPublicPublicPath)
            ?? panic("Cannot access FLOW lending pool")

        // ROUND 1: Initial stake and borrow
        log("=== ROUND 1: Initial Stake ===")
        
        let flowVault1 <- self.flowVault.withdraw(amount: initialStake) as! @FlowToken.Vault
        let stFlowVault1 <- LiquidStaking.stake(flowVault: <-flowVault1)
        log("Staked ".concat(initialStake.toString()).concat(" FLOW into ").concat(stFlowVault1.balance.toString()).concat(" stFlow"))

        stFlowPool.supply(supplierAddr: self.userCertificate.owner!.address, inUnderlyingVault: <-stFlowVault1)
        log("Deposited stFlow as collateral")

        let borrowAmount1 = initialStake * 0.7
        let borrowedFlow1 <- flowPool.borrow(userCertificate: self.userCertificate, borrowAmount: borrowAmount1)
        log("Borrowed ".concat(borrowAmount1.toString()).concat(" FLOW"))

        // ROUND 2: First leverage loop
        log("=== ROUND 2: First Leverage Loop ===")
        
        let borrowedFlowTyped1 <- borrowedFlow1 as! @FlowToken.Vault
        let stFlowVault2 <- LiquidStaking.stake(flowVault: <-borrowedFlowTyped1)
        log("Restaked ".concat(borrowAmount1.toString()).concat(" FLOW into ").concat(stFlowVault2.balance.toString()).concat(" stFlow"))

        stFlowPool.supply(supplierAddr: self.userCertificate.owner!.address, inUnderlyingVault: <-stFlowVault2)
        log("Deposited second stFlow batch as collateral")

        let borrowAmount2 = borrowAmount1 * 0.7
        let borrowedFlow2 <- flowPool.borrow(userCertificate: self.userCertificate, borrowAmount: borrowAmount2)
        log("Second borrow: ".concat(borrowAmount2.toString()).concat(" FLOW"))

        // ROUND 3: Second leverage loop
        log("=== ROUND 3: Second Leverage Loop ===")
        
        let borrowedFlowTyped2 <- borrowedFlow2 as! @FlowToken.Vault
        let stFlowVault3 <- LiquidStaking.stake(flowVault: <-borrowedFlowTyped2)
        log("Restaked ".concat(borrowAmount2.toString()).concat(" FLOW into ").concat(stFlowVault3.balance.toString()).concat(" stFlow"))

        stFlowPool.supply(supplierAddr: self.userCertificate.owner!.address, inUnderlyingVault: <-stFlowVault3)
        log("Deposited third stFlow batch as collateral")

        let borrowAmount3 = borrowAmount2 * 0.7
        let borrowedFlow3 <- flowPool.borrow(userCertificate: self.userCertificate, borrowAmount: borrowAmount3)
        log("Third borrow: ".concat(borrowAmount3.toString()).concat(" FLOW"))

        // FINAL: Stake final borrowed amount and deposit to wallet
        log("=== FINAL: Stake Final Amount ===")
        
        let borrowedFlowTyped3 <- borrowedFlow3 as! @FlowToken.Vault
        let stFlowVault4 <- LiquidStaking.stake(flowVault: <-borrowedFlowTyped3)
        log("Final stake: ".concat(borrowAmount3.toString()).concat(" FLOW into ").concat(stFlowVault4.balance.toString()).concat(" stFlow"))

        self.stFlowVaultRef.deposit(from: <-stFlowVault4)
        log("Deposited final stFlow to user wallet")

        // Summary
        let totalBorrowed = borrowAmount1 + borrowAmount2 + borrowAmount3
        let totalExposure = initialStake + totalBorrowed
        let leverageRatio = totalExposure / initialStake
        
        log("=== SUMMARY ===")
        log("Initial FLOW: ".concat(initialStake.toString()))
        log("Total borrowed: ".concat(totalBorrowed.toString()))
        log("Total FLOW exposure: ".concat(totalExposure.toString()))
        log("Leverage ratio: ".concat(leverageRatio.toString()).concat("x"))
        log("⚠️  WARNING: High leverage position - monitor closely for liquidation risk")
    }
}