import FungibleToken from 0x9a0766d93b6608b7
import FlowToken from 0x7e60df042a9c0868

import SwapInterfaces from 0x8d5b9dd833e176da
import SwapConfig from 0x8d5b9dd833e176da
import SwapFactory from 0x6ca93d49c45a249f

import IncrementFiFlashloanConnectors from 0x49bae091e5ea16b5
import DeFiActions from 0x4c2ff9dd03ab442f

// Borrow FLOW directly from a SwapPair, using the generic Executor.
// Safe to run multiple times (will reuse an existing Executor).
transaction(pairAddress: Address, amount: UFix64) {
    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController, SaveValue) &Account) {
        pre {
            amount > 0.0: "Amount must be positive"
            amount <= 1.0: "Keep flashloan test amounts small"
        }

        log("Direct flashloan from Pair")
        log("Pair: ".concat(pairAddress.toString()))
        log("Amount: ".concat(amount.toString()))

        // 1) Ensure an Executor exists at the canonical path (create+save only if missing)
        let execPath = IncrementFiFlashloanConnectors.ExecutorStoragePath
        if signer.storage.type(at: execPath) == nil {
            let executor <- IncrementFiFlashloanConnectors.createExecutor()
            signer.storage.save(<-executor, to: execPath)
            log("Executor created & saved at ".concat(execPath.toString()))
        } else {
            log("Executor already exists at ".concat(execPath.toString()))
        }

        // Issue a typed capability to the stored Executor
        let execCap: Capability<&{SwapInterfaces.FlashLoanExecutor}> =
            signer.capabilities.storage.issue<&{SwapInterfaces.FlashLoanExecutor}>(execPath)
        assert(execCap.check(), message: "Executor capability invalid")

        // 2) Compute fee from factory bps
        let bps = SwapFactory.getFlashloanRateBps() // Int
        let fee = UFix64(bps) * amount / 10000.0
        log("Fee (FLOW): ".concat(fee.toString()))

        // Make sure we can pay the fee in FLOW
        let flowVaultRef = signer.storage.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)
            ?? panic("Missing /storage/flowTokenVault")
        assert(flowVaultRef.balance >= fee, message: "Insufficient FLOW to cover flashloan fee")

        // 3) Get the Pair capability
        let pair = getAccount(pairAddress).capabilities
            .borrow<&{SwapInterfaces.PairPublic}>(SwapConfig.PairPublicPath)
            ?? panic("Could not borrow PairPublic at ".concat(pairAddress.toString()))

        // 4) Build params expected by the generic Executor
        let params: {String: AnyStruct} = {}
        params["fee"] = fee
        params["callback"] = fun(feeAmount: UFix64, loanVault: @{FungibleToken.Vault}, data: AnyStruct?): @{FungibleToken.Vault} {
            log("=== FLASHLOAN CALLBACK ===")
            log("Loaned: ".concat(loanVault.balance.toString()))
            log("Fee: ".concat(feeAmount.toString()))

            // Your custom logic goes here (arbs, swaps, etc.). For dry-run: pay fee then repay.
            let flowVault = signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
                from: /storage/flowTokenVault
            )!
            loanVault.deposit(from: <- flowVault.withdraw(amount: feeAmount))

            log("Repaying: ".concat(loanVault.balance.toString()))
            log("=== CALLBACK DONE ===")
            return <-loanVault
        }

        // 5) Execute flashloan for FLOW
        pair.flashloan(
            executor: execCap.borrow() ?? panic("Could not borrow executor cap"),
            requestedTokenVaultType: Type<@FlowToken.Vault>(),  // Borrow FLOW
            requestedAmount: amount,
            params: params
        )

        log("Flashloan finished")
    }
}
