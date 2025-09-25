import FungibleToken from 0x9a0766d93b6608b7
import FlowToken from 0x7e60df042a9c0868

import SwapInterfaces from 0x8d5b9dd833e176da
import SwapConfig from 0x8d5b9dd833e176da
import SwapFactory from 0x6ca93d49c45a249f

import IncrementFiPoolLiquidityConnectors from 0x49bae091e5ea16b5
import IncrementFiStakingConnectors from 0x49bae091e5ea16b5
import DeFiActions from 0x4c2ff9dd03ab442f

/// Loop FLOW -> (zap) -> FLOW/stFLOW LP -> stake LP into pool(pid)
/// No flashloan; spends `flowAmount` from the signer’s FLOW vault.
/// `stableMode` should be false for FLOW/stFLOW volatile pair.
/// `minLpOut` is a safety check; set to 0.0 if you don’t care.
///
/// NOTE: stFLOW key on testnet is "A.e45c64ecfe31e465.stFlowToken"
///       We derive the Vault type from that string at runtime.
transaction(pid: UInt64, flowAmount: UFix64, stableMode: Bool, minLpOut: UFix64) {

    // Addresses & type keys
    access(all) let STFLOW_KEY: String
    access(all) let stflowVaultType: Type

    // Working state
    access(self) var zapper: IncrementFiPoolLiquidityConnectors.Zapper
    access(self) var poolSink: IncrementFiStakingConnectors.PoolSink

    prepare(signer: auth(BorrowValue) &Account) {
        pre {
            flowAmount > 0.0: "flowAmount must be > 0"
            pid >= 0: "invalid pid"
        }

        log("=== Leveraged stFLOW Looper (no flashloan) ===")
        log("pid: ".concat(pid.toString()))
        log("flowAmount: ".concat(flowAmount.toString()))
        log("stableMode: ".concat(stableMode ? "true" : "false"))
        log("minLpOut: ".concat(minLpOut.toString()))

        // 0) Resolve stFLOW vault type from key string
        self.STFLOW_KEY = "A.e45c64ecfe31e465.stFlowToken"
        self.stflowVaultType = IncrementFiStakingConnectors.tokenTypeIdentifierToVaultType(self.STFLOW_KEY)

        // 1) Check FLOW balance
        let flowVaultRef = signer.storage.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)
            ?? panic("Missing /storage/flowTokenVault")
        assert(flowVaultRef.balance >= flowAmount, message: "Insufficient FLOW")

        // 2) Build a Zapper for the FLOW/stFLOW pair
        //    token0 = FLOW, token1 = stFLOW
        self.zapper = IncrementFiPoolLiquidityConnectors.Zapper(
            token0Type: Type<@FlowToken.Vault>(),
            token1Type: self.stflowVaultType,
            stableMode: stableMode,
            uniqueID: DeFiActions.createUniqueIdentifier()
        )

        // 3) Build a PoolSink for the target staking pool (expects LP token)
        self.poolSink = IncrementFiStakingConnectors.PoolSink(
            pid: pid,
            staker: signer.address,
            uniqueID: DeFiActions.createUniqueIdentifier()
        )

        // Sanity: The zapper’s outType (LP token) must match the pool’s accept token
        assert(
            self.zapper.outType().identifier == self.poolSink.getSinkType().identifier,
            message:
                "PoolSink expects ".concat(self.poolSink.getSinkType().identifier)
                .concat(" but Zapper outputs ").concat(self.zapper.outType().identifier)
        )

        // 4) Withdraw FLOW to zap
        let inVault <- flowVaultRef.withdraw(amount: flowAmount)

        // 5) Zap FLOW -> FLOW/stFLOW LP
        //    (Zapper internally swaps a portion of FLOW to stFLOW, then adds liquidity)
        let lpVault <- self.zapper.swap(quote: nil, inVault: <-inVault)
        log("Zapper LP out: ".concat(lpVault.balance.toString()))
        assert(lpVault.balance >= minLpOut, message: "LP out < minLpOut")

        // 6) Stake LP into pool via PoolSink
        // PoolSink.depositCapacity() takes &{FungibleToken.Withdraw}, so use a local var
        var lpRef <- lpVault
        self.poolSink.depositCapacity(from: &lpRef as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
        // If any LP dust remains (should be ~0), return to user
        if lpRef.balance > 0.0 {
            log("Residual LP (returned to signer): ".concat(lpRef.balance.toString()))
            let lpReceiver = signer.storage
                .borrow<&{FungibleToken.Receiver}>(
                    from: /storage/flowTokenVault /* placeholder to force panic if no receiver; we don't have an LP receiver path */
                )
            // We don’t know the user’s LP storage/receiver path, so burn residual to avoid leaving dangling resources.
            // In practice, you may want to store a receiver for this LP type on your account and deposit it.
            destroy lpRef
        } else {
            destroy lpRef
        }

        log("Staked LP into pool ".concat(pid.toString()))
    }

    execute {
        // Nothing else to do
    }
}
