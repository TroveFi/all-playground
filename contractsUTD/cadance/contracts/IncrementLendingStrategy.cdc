import FungibleToken from 0xf233dcee88fe0abe
import FlowToken from 0x1654653399040a61
import stFlowToken from 0xd6f80565193ad727
import LendingInterfaces from 0x2df970b6cdee5735
import LendingComptroller from 0xf80cb737bfe7c792
import LendingConfig from 0x2df970b6cdee5735

/// Increment Fi lending/borrowing strategy
/// Supply assets to earn interest, borrow against collateral
access(all) contract IncrementLendingStrategy {
    
    // ====================================================================
    // POOL ADDRESSES
    // ====================================================================
    access(all) let FLOW_POOL: Address       // 0x7492e2f9b4acea9a
    access(all) let STFLOW_POOL: Address     // 0x44fe3d9157770b2d
    
    // ====================================================================
    // EVENTS
    // ====================================================================
    access(all) event Supplied(poolAddress: Address, asset: String, amount: UFix64, supplier: Address)
    access(all) event Borrowed(poolAddress: Address, asset: String, amount: UFix64, borrower: Address)
    access(all) event Repaid(poolAddress: Address, asset: String, amount: UFix64, borrower: Address)
    access(all) event Redeemed(poolAddress: Address, asset: String, amount: UFix64, supplier: Address)
    access(all) event LiquidityChecked(availableBorrow: UFix64, totalBorrow: UFix64, totalCollateral: UFix64)
    
    // ====================================================================
    // STATE
    // ====================================================================
    access(self) var totalSupplied: {Address: UFix64}
    access(self) var totalBorrowed: {Address: UFix64}
    
    // ====================================================================
    // STRUCTS
    // ====================================================================
    access(all) struct UserPosition {
        access(all) let supplied: {Address: UFix64}
        access(all) let borrowed: {Address: UFix64}
        access(all) let availableBorrow: UFix64
        access(all) let totalCollateral: UFix64
        access(all) let healthFactor: UFix64
        
        init(
            supplied: {Address: UFix64},
            borrowed: {Address: UFix64},
            availableBorrow: UFix64,
            totalCollateral: UFix64,
            healthFactor: UFix64
        ) {
            self.supplied = supplied
            self.borrowed = borrowed
            self.availableBorrow = availableBorrow
            self.totalCollateral = totalCollateral
            self.healthFactor = healthFactor
        }
    }
    
    // ====================================================================
    // STRATEGY RESOURCE
    // ====================================================================
    access(all) resource Strategy {
        access(self) let userCertificate: @{LendingInterfaces.IdentityCertificate}
        access(self) let flowVault: @FlowToken.Vault
        access(self) let stFlowVault: @stFlowToken.Vault
        
        access(self) var suppliedPools: {Address: UFix64}
        access(self) var borrowedPools: {Address: UFix64}
        
        init() {
            self.userCertificate <- LendingComptroller.IssueUserCertificate()
            self.flowVault <- FlowToken.createEmptyVault(vaultType: Type<@FlowToken.Vault>()) as! @FlowToken.Vault
            self.stFlowVault <- stFlowToken.createEmptyVault(vaultType: Type<@stFlowToken.Vault>()) as! @stFlowToken.Vault
            
            self.suppliedPools = {}
            self.borrowedPools = {}
        }
        
        // ====================================================================
        // SUPPLY FUNCTIONS
        // ====================================================================
        
        /// Supply FLOW to lending pool
        access(all) fun supplyFlow(amount: UFix64) {
            pre {
                self.flowVault.balance >= amount: "Insufficient FLOW balance"
                amount > 0.0: "Amount must be positive"
            }
            
            let vault <- self.flowVault.withdraw(amount: amount) as! @FlowToken.Vault
            
            let poolPublic = getAccount(IncrementLendingStrategy.FLOW_POOL)
                .capabilities
                .borrow<&{LendingInterfaces.PoolPublic}>(LendingConfig.PoolPublicPublicPath)
                ?? panic("Cannot access FLOW pool")
            
            poolPublic.supply(
                supplierAddr: self.userCertificate.owner!.address,
                inUnderlyingVault: <-vault
            )
            
            let currentSupplied = self.suppliedPools[IncrementLendingStrategy.FLOW_POOL] ?? 0.0
            self.suppliedPools[IncrementLendingStrategy.FLOW_POOL] = currentSupplied + amount
            
            IncrementLendingStrategy.totalSupplied[IncrementLendingStrategy.FLOW_POOL] = 
                (IncrementLendingStrategy.totalSupplied[IncrementLendingStrategy.FLOW_POOL] ?? 0.0) + amount
            
            emit Supplied(
                poolAddress: IncrementLendingStrategy.FLOW_POOL,
                asset: "FLOW",
                amount: amount,
                supplier: self.userCertificate.owner!.address
            )
        }
        
        /// Supply stFLOW to lending pool
        access(all) fun supplyStFlow(amount: UFix64) {
            pre {
                self.stFlowVault.balance >= amount: "Insufficient stFLOW balance"
                amount > 0.0: "Amount must be positive"
            }
            
            let vault <- self.stFlowVault.withdraw(amount: amount) as! @stFlowToken.Vault
            
            let poolPublic = getAccount(IncrementLendingStrategy.STFLOW_POOL)
                .capabilities
                .borrow<&{LendingInterfaces.PoolPublic}>(LendingConfig.PoolPublicPublicPath)
                ?? panic("Cannot access stFLOW pool")
            
            poolPublic.supply(
                supplierAddr: self.userCertificate.owner!.address,
                inUnderlyingVault: <-vault
            )
            
            let currentSupplied = self.suppliedPools[IncrementLendingStrategy.STFLOW_POOL] ?? 0.0
            self.suppliedPools[IncrementLendingStrategy.STFLOW_POOL] = currentSupplied + amount
            
            IncrementLendingStrategy.totalSupplied[IncrementLendingStrategy.STFLOW_POOL] = 
                (IncrementLendingStrategy.totalSupplied[IncrementLendingStrategy.STFLOW_POOL] ?? 0.0) + amount
            
            emit Supplied(
                poolAddress: IncrementLendingStrategy.STFLOW_POOL,
                asset: "stFLOW",
                amount: amount,
                supplier: self.userCertificate.owner!.address
            )
        }
        
        // ====================================================================
        // BORROW FUNCTIONS
        // ====================================================================
        
        /// Borrow FLOW from lending pool
        access(all) fun borrowFlow(amount: UFix64): @FlowToken.Vault {
            pre {
                amount > 0.0: "Amount must be positive"
            }
            
            let poolPublic = getAccount(IncrementLendingStrategy.FLOW_POOL)
                .capabilities
                .borrow<&{LendingInterfaces.PoolPublic}>(LendingConfig.PoolPublicPublicPath)
                ?? panic("Cannot access FLOW pool")
            
            let borrowedVault <- poolPublic.borrow(
                userCertificate: &self.userCertificate as &{LendingInterfaces.IdentityCertificate},
                borrowAmount: amount
            ) as! @FlowToken.Vault
            
            let currentBorrowed = self.borrowedPools[IncrementLendingStrategy.FLOW_POOL] ?? 0.0
            self.borrowedPools[IncrementLendingStrategy.FLOW_POOL] = currentBorrowed + amount
            
            IncrementLendingStrategy.totalBorrowed[IncrementLendingStrategy.FLOW_POOL] = 
                (IncrementLendingStrategy.totalBorrowed[IncrementLendingStrategy.FLOW_POOL] ?? 0.0) + amount
            
            emit Borrowed(
                poolAddress: IncrementLendingStrategy.FLOW_POOL,
                asset: "FLOW",
                amount: amount,
                borrower: self.userCertificate.owner!.address
            )
            
            return <- borrowedVault
        }
        
        /// Borrow stFLOW from lending pool
        access(all) fun borrowStFlow(amount: UFix64): @stFlowToken.Vault {
            pre {
                amount > 0.0: "Amount must be positive"
            }
            
            let poolPublic = getAccount(IncrementLendingStrategy.STFLOW_POOL)
                .capabilities
                .borrow<&{LendingInterfaces.PoolPublic}>(LendingConfig.PoolPublicPublicPath)
                ?? panic("Cannot access stFLOW pool")
            
            let borrowedVault <- poolPublic.borrow(
                userCertificate: &self.userCertificate as &{LendingInterfaces.IdentityCertificate},
                borrowAmount: amount
            ) as! @stFlowToken.Vault
            
            let currentBorrowed = self.borrowedPools[IncrementLendingStrategy.STFLOW_POOL] ?? 0.0
            self.borrowedPools[IncrementLendingStrategy.STFLOW_POOL] = currentBorrowed + amount
            
            IncrementLendingStrategy.totalBorrowed[IncrementLendingStrategy.STFLOW_POOL] = 
                (IncrementLendingStrategy.totalBorrowed[IncrementLendingStrategy.STFLOW_POOL] ?? 0.0) + amount
            
            emit Borrowed(
                poolAddress: IncrementLendingStrategy.STFLOW_POOL,
                asset: "stFLOW",
                amount: amount,
                borrower: self.userCertificate.owner!.address
            )
            
            return <- borrowedVault
        }
        
        // ====================================================================
        // REPAY FUNCTIONS - Using repayBorrowBehalf (correct function)
        // ====================================================================
        
        /// Repay FLOW loan
        access(all) fun repayFlow(vault: @FlowToken.Vault) {
            pre {
                vault.balance > 0.0: "Cannot repay zero"
            }
            
            let amount = vault.balance
            
            let poolPublic = getAccount(IncrementLendingStrategy.FLOW_POOL)
                .capabilities
                .borrow<&{LendingInterfaces.PoolPublic}>(LendingConfig.PoolPublicPublicPath)
                ?? panic("Cannot access FLOW pool")
            
            // repayBorrow returns optional vault (excess/change)
            let excessVault <- poolPublic.repayBorrow(
                borrower: self.userCertificate.owner!.address,
                repayUnderlyingVault: <-vault
            )
            
            // Handle excess if any
            if excessVault != nil {
                self.flowVault.deposit(from: <-excessVault!)
            } else {
                destroy excessVault
            }
            
            let currentBorrowed = self.borrowedPools[IncrementLendingStrategy.FLOW_POOL] ?? 0.0
            self.borrowedPools[IncrementLendingStrategy.FLOW_POOL] = currentBorrowed > amount ? currentBorrowed - amount : 0.0
            
            emit Repaid(
                poolAddress: IncrementLendingStrategy.FLOW_POOL,
                asset: "FLOW",
                amount: amount,
                borrower: self.userCertificate.owner!.address
            )
        }
        
        /// Repay stFLOW loan
        access(all) fun repayStFlow(vault: @stFlowToken.Vault) {
            pre {
                vault.balance > 0.0: "Cannot repay zero"
            }
            
            let amount = vault.balance
            
            let poolPublic = getAccount(IncrementLendingStrategy.STFLOW_POOL)
                .capabilities
                .borrow<&{LendingInterfaces.PoolPublic}>(LendingConfig.PoolPublicPublicPath)
                ?? panic("Cannot access stFLOW pool")
            
            // repayBorrow returns optional vault (excess/change)
            let excessVault <- poolPublic.repayBorrow(
                borrower: self.userCertificate.owner!.address,
                repayUnderlyingVault: <-vault
            )
            
            // Handle excess if any
            if excessVault != nil {
                self.stFlowVault.deposit(from: <-excessVault!)
            } else {
                destroy excessVault
            }
            
            let currentBorrowed = self.borrowedPools[IncrementLendingStrategy.STFLOW_POOL] ?? 0.0
            self.borrowedPools[IncrementLendingStrategy.STFLOW_POOL] = currentBorrowed > amount ? currentBorrowed - amount : 0.0
            
            emit Repaid(
                poolAddress: IncrementLendingStrategy.STFLOW_POOL,
                asset: "stFLOW",
                amount: amount,
                borrower: self.userCertificate.owner!.address
            )
        }
        
        // ====================================================================
        // REDEEM FUNCTIONS - Using correct parameter name
        // ====================================================================
        
        /// Redeem (withdraw) FLOW from supply
        access(all) fun redeemFlow(amount: UFix64): @FlowToken.Vault {
            pre {
                amount > 0.0: "Amount must be positive"
            }
            
            let poolPublic = getAccount(IncrementLendingStrategy.FLOW_POOL)
                .capabilities
                .borrow<&{LendingInterfaces.PoolPublic}>(LendingConfig.PoolPublicPublicPath)
                ?? panic("Cannot access FLOW pool")
            
            // Use numLpTokenToRedeem parameter name
            let redeemedVault <- poolPublic.redeem(
                userCertificate: &self.userCertificate as &{LendingInterfaces.IdentityCertificate},
                numLpTokenToRedeem: amount
            ) as! @FlowToken.Vault
            
            let currentSupplied = self.suppliedPools[IncrementLendingStrategy.FLOW_POOL] ?? 0.0
            self.suppliedPools[IncrementLendingStrategy.FLOW_POOL] = currentSupplied > amount ? currentSupplied - amount : 0.0
            
            emit Redeemed(
                poolAddress: IncrementLendingStrategy.FLOW_POOL,
                asset: "FLOW",
                amount: amount,
                supplier: self.userCertificate.owner!.address
            )
            
            return <- redeemedVault
        }
        
        /// Redeem (withdraw) stFLOW from supply
        access(all) fun redeemStFlow(amount: UFix64): @stFlowToken.Vault {
            pre {
                amount > 0.0: "Amount must be positive"
            }
            
            let poolPublic = getAccount(IncrementLendingStrategy.STFLOW_POOL)
                .capabilities
                .borrow<&{LendingInterfaces.PoolPublic}>(LendingConfig.PoolPublicPublicPath)
                ?? panic("Cannot access stFLOW pool")
            
            // Use numLpTokenToRedeem parameter name
            let redeemedVault <- poolPublic.redeem(
                userCertificate: &self.userCertificate as &{LendingInterfaces.IdentityCertificate},
                numLpTokenToRedeem: amount
            ) as! @stFlowToken.Vault
            
            let currentSupplied = self.suppliedPools[IncrementLendingStrategy.STFLOW_POOL] ?? 0.0
            self.suppliedPools[IncrementLendingStrategy.STFLOW_POOL] = currentSupplied > amount ? currentSupplied - amount : 0.0
            
            emit Redeemed(
                poolAddress: IncrementLendingStrategy.STFLOW_POOL,
                asset: "stFLOW",
                amount: amount,
                supplier: self.userCertificate.owner!.address
            )
            
            return <- redeemedVault
        }
        
        // ====================================================================
        // LIQUIDITY & HEALTH CHECK
        // ====================================================================
        
        /// Get user's borrowing capacity and position health
        access(all) fun getLiquidityInfo(): {String: UFix64} {
            let comptroller = getAccount(0xf80cb737bfe7c792)
                .capabilities
                .borrow<&{LendingInterfaces.ComptrollerPublic}>(LendingConfig.ComptrollerPublicPath)
                ?? panic("Cannot access comptroller")
            
            let liquidity = comptroller.getUserCrossMarketLiquidity(
                userAddr: self.userCertificate.owner!.address
            )
            
            let availableBorrowStr = liquidity[0] as! String
            let totalBorrowStr = liquidity[1] as! String
            let totalCollateralStr = liquidity[2] as! String
            
            let availableBorrow = LendingConfig.ScaledUInt256ToUFix64(UInt256.fromString(availableBorrowStr)!)
            let totalBorrow = LendingConfig.ScaledUInt256ToUFix64(UInt256.fromString(totalBorrowStr)!)
            let totalCollateral = LendingConfig.ScaledUInt256ToUFix64(UInt256.fromString(totalCollateralStr)!)
            
            let healthFactor = totalBorrow > 0.0 ? totalCollateral / totalBorrow : 999.0
            let borrowUtilization = totalCollateral > 0.0 ? (totalBorrow / totalCollateral) * 100.0 : 0.0
            
            emit LiquidityChecked(
                availableBorrow: availableBorrow,
                totalBorrow: totalBorrow,
                totalCollateral: totalCollateral
            )
            
            return {
                "availableBorrow": availableBorrow,
                "totalBorrow": totalBorrow,
                "totalCollateral": totalCollateral,
                "healthFactor": healthFactor,
                "borrowUtilization": borrowUtilization
            }
        }
        
        // ====================================================================
        // VAULT MANAGEMENT
        // ====================================================================
        
        access(all) fun depositFlow(vault: @FlowToken.Vault) {
            self.flowVault.deposit(from: <-vault)
        }
        
        access(all) fun depositStFlow(vault: @stFlowToken.Vault) {
            self.stFlowVault.deposit(from: <-vault)
        }
        
        access(all) fun withdrawFlow(amount: UFix64): @FlowToken.Vault {
            return <- self.flowVault.withdraw(amount: amount) as! @FlowToken.Vault
        }
        
        access(all) fun withdrawStFlow(amount: UFix64): @stFlowToken.Vault {
            return <- self.stFlowVault.withdraw(amount: amount) as! @stFlowToken.Vault
        }
        
        // ====================================================================
        // VIEW FUNCTIONS
        // ====================================================================
        
        access(all) fun getBalances(): {String: UFix64} {
            return {
                "flow": self.flowVault.balance,
                "stflow": self.stFlowVault.balance
            }
        }
        
        access(all) fun getPositions(): UserPosition {
            let liquidityInfo = self.getLiquidityInfo()
            
            return UserPosition(
                supplied: self.suppliedPools,
                borrowed: self.borrowedPools,
                availableBorrow: liquidityInfo["availableBorrow"]!,
                totalCollateral: liquidityInfo["totalCollateral"]!,
                healthFactor: liquidityInfo["healthFactor"]!
            )
        }
    }
    
    // ====================================================================
    // CONTRACT FUNCTIONS
    // ====================================================================
    
    access(all) fun createStrategy(): @Strategy {
        return <- create Strategy()
    }
    
    access(all) fun getMetrics(): {String: AnyStruct} {
        return {
            "totalSuppliedByPool": self.totalSupplied,
            "totalBorrowedByPool": self.totalBorrowed
        }
    }
    
    // ====================================================================
    // INITIALIZATION
    // ====================================================================
    
    init() {
        self.FLOW_POOL = 0x7492e2f9b4acea9a
        self.STFLOW_POOL = 0x44fe3d9157770b2d
        
        self.totalSupplied = {}
        self.totalBorrowed = {}
    }
}