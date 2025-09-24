// cadence/transactions/tx_mainnet_stake_from_flow.cdc

import FungibleToken from 0xf233dcee88fe0abe
import FlowToken from 0x1654653399040a61
import Staking from 0x1b77ba4b414de352
import stFlowToken from 0xd6f80565193ad727

// DEX
import SwapRouter from 0xa6850776a94e6551
import SwapFactory from 0xb063c16cac85dbd1
import SwapInterfaces from 0xb78ef7afa52ff906
import SwapConfig from 0xb78ef7afa52ff906

// Stake FLOW -> (swap half to stFLOW) -> add LP -> stake LP into farmPoolId
transaction(flowAmount: UFix64, farmPoolId: UInt64) {
    let flowVault: auth(FungibleToken.Withdraw) &FlowToken.Vault
    let userCertificate: &Staking.UserCertificate
    let stakingCollectionRef: &{Staking.PoolCollectionPublic}

    prepare(signer: auth(SaveValue, BorrowValue, IssueStorageCapabilityController) &Account) {
        pre { flowAmount > 0.0: "flowAmount must be positive" }

        // FLOW vault
        self.flowVault = signer.storage
            .borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(from: /storage/flowTokenVault)
            ?? panic("Missing /storage/flowTokenVault")

        // UserCertificate
        self.userCertificate = signer.storage
            .borrow<&Staking.UserCertificate>(from: Staking.UserCertificateStoragePath)
            ?? panic("Missing Staking.UserCertificate; run Staking setup first")

        // Staking collection
        let stakingAccount = getAccount(0x1b77ba4b414de352)
        self.stakingCollectionRef = stakingAccount.capabilities
            .borrow<&{Staking.PoolCollectionPublic}>(Staking.CollectionPublicPath)
            ?? panic("Could not borrow staking collection")

        // Ensure stFlow vault exists (some pools reward or require it elsewhere)
        if signer.storage.borrow<&stFlowToken.Vault>(from: /storage/stFlowTokenVault) == nil {
            signer.storage.save(
                <- stFlowToken.createEmptyVault(vaultType: Type<@stFlowToken.Vault>()),
                to: /storage/stFlowTokenVault
            )
            let cap = signer.capabilities.storage.issue<&{FungibleToken.Receiver}>(/storage/stFlowTokenVault)
            signer.capabilities.publish(cap, at: /public/stFlowTokenReceiver)
        }
    }

    execute {
        let deadline = getCurrentBlock().timestamp + 60.0

        // 1) Withdraw FLOW
        let totalFlow <- self.flowVault.withdraw(amount: flowAmount)
        let halfFlow <- totalFlow.withdraw(amount: flowAmount / 2.0)

        // 2) Swap half FLOW -> stFLOW
        let stFlowVault <- SwapRouter.swapExactTokensForTokens(
            exactVaultIn: <-halfFlow,
            amountOutMin: 0.0,
            tokenKeyPath: [
                "A.1654653399040a61.FlowToken",
                "A.d6f80565193ad727.stFlowToken"
            ],
            deadline: deadline
        )

        // 3) Get FLOW–stFLOW pair
        let token0Key = "A.1654653399040a61.FlowToken"
        let token1Key = "A.d6f80565193ad727.stFlowToken"
        let pairAddress = SwapFactory.getPairAddress(token0Key: token0Key, token1Key: token1Key)
            ?? panic("FLOW–stFLOW pair does not exist")

        let pairRef = getAccount(pairAddress).capabilities
            .borrow<&{SwapInterfaces.PairPublic}>(SwapConfig.PairPublicPath)
            ?? panic("Could not borrow PairPublic")

        // 4) Add liquidity → LP
        let lpTokens <- pairRef.addLiquidity(
            tokenAVault: <- totalFlow,
            tokenBVault: <- stFlowVault
        )

        // 5) Stake LP into farm
        let poolRef = self.stakingCollectionRef.getPool(pid: farmPoolId)
        poolRef.stake(staker: self.userCertificate.owner!.address, stakingToken: <-lpTokens)

        log("SUCCESS: Staked FLOW–stFLOW LP in pool ".concat(farmPoolId.toString()))
    }
}
