import FungibleToken from 0xf233dcee88fe0abe
import FlowToken from 0x1654653399040a61
import stFlowToken from 0xd6f80565193ad727
import LiquidStaking from 0xd6f80565193ad727
import LendingInterfaces from 0x2df970b6cdee5735
import LendingComptroller from 0xf80cb737bfe7c792
import LendingPoolFlow from 0x7492e2f9b4acea9a
import LendingPoolStFlow from 0x44fe3d9157770b2d

transaction(initialStake: UFix64) {
    prepare(acct: AuthAccount) {
        // 1. Stake FLOW -> get stFLOW
        let flowVault = acct.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)
            ?? panic("missing Flow vault")
        let staked <- flowVault.withdraw(amount: initialStake)
        let stFlowVault <- LiquidStaking.stakeFlow(<-staked)
        
        log("Staked initial FLOW, got stFLOW: ".concat(stFlowVault.balance.toString()))

        // 2. Deposit stFLOW as collateral
        let stFlowCollCap = getAccount(0x44fe3d9157770b2d)
            .getCapability<&{LendingInterfaces.LendingPoolPublic}>(/public/lendingPool)
            .borrow() ?? panic("could not borrow stFlow LendingPool")
        stFlowCollCap.depositCollateral(vault: <-stFlowVault)
        log("Deposited stFLOW as collateral")

        // 3. Borrow FLOW against stFLOW
        let flowBorrowCap = getAccount(0x7492e2f9b4acea9a)
            .getCapability<&{LendingInterfaces.LendingPoolPublic}>(/public/lendingPool)
            .borrow() ?? panic("could not borrow Flow LendingPool")
        let borrowedFlow <- flowBorrowCap.borrow(amount: initialStake * 0.7) 
        log("Borrowed FLOW: ".concat(borrowedFlow.balance.toString()))

        // 4. Restake borrowed FLOW
        let stFlowVault2 <- LiquidStaking.stakeFlow(<-borrowedFlow)
        log("Restaked borrowed FLOW, got stFLOW: ".concat(stFlowVault2.balance.toString()))

        // 5. Deposit the new stFLOW back as collateral
        stFlowCollCap.depositCollateral(vault: <-stFlowVault2)
        log("Deposited 2nd stFLOW as collateral")
    }
}
