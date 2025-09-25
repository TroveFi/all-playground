// cadence/transactions/8_flash_arb_flow_usdc.cdc
//
// FLOW–USDC Flash-Arb (MVP, resilient discovery & re-runnable)

import FungibleToken from 0x9a0766d93b6608b7
import FlowToken from 0x7e60df042a9c0868

import SwapInterfaces from 0x8d5b9dd833e176da
import SwapConfig from 0x8d5b9dd833e176da
import SwapFactory from 0x6ca93d49c45a249f

import IncrementFiFlashloanConnectors from 0x49bae091e5ea16b5
import DeFiActions from 0x4c2ff9dd03ab442f

transaction(amount: UFix64, minProfitBps: Int) {

    let execStoragePath: StoragePath
    var pairAddr: Address

    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController, SaveValue) &Account) {
        pre {
            amount > 0.0: "Amount must be positive"
            amount <= 1.0: "Keep flashloan test amounts small while testing"
            minProfitBps >= 0: "minProfitBps cannot be negative"
        }

        log("=== FLOW–USDC Flash-Arb (MVP) ===")
        log("Requested loan (FLOW): ".concat(amount.toString()))

        self.execStoragePath = IncrementFiFlashloanConnectors.ExecutorStoragePath

        // Ensure executor exists (idempotent)
        if signer.storage.borrow<&IncrementFiFlashloanConnectors.Executor>(from: self.execStoragePath) == nil {
            let newExec <- IncrementFiFlashloanConnectors.createExecutor()
            signer.storage.save(<-newExec, to: self.execStoragePath)
            log("Executor saved to storage")
        } else {
            log("Reusing existing Executor from storage")
        }

        // Probe a cap (value type, not a resource)
        let execCapProbe = signer.capabilities.storage.issue<&{SwapInterfaces.FlashLoanExecutor}>(self.execStoragePath)
        assert(execCapProbe.check(), message: "Executor cap invalid")

        // -------- Local constants (must live inside prepare) --------
        let KNOWN_FLOW_USDC_1: Address = 0xd953c643042ca011 // FLOW / A.0898... USDCFlow
        let KNOWN_FLOW_USDC_2: Address = 0x9a6c19d8a25222eb // FLOW / A.64ad... USDCFlow

        let FLOW_KEY: String = Type<@FlowToken.Vault>().identifier
        let USDC_KEYS: [String] = [
            "A.0898fa4896d73752.USDCFlow",
            "A.64adf39cbc354fcb.USDCFlow"
        ]
        let FUSD_KEY: String = "A.e223d8a629e49c68.FUSD"

        // Helper: does this pair match FLOW + any of the provided keys?
        fun pairMatches(_ p: &{SwapInterfaces.PairPublic}, wantOther: [String]): Bool {
            let info = p.getPairInfoStruct()
            let t0 = info.token0Key
            let t1 = info.token1Key
            let flowLeft = t0 == FLOW_KEY && wantOther.contains(t1)
            let flowRight = t1 == FLOW_KEY && wantOther.contains(t0)
            return flowLeft || flowRight
        }

        // -------- Pair discovery (robust) --------
        self.pairAddr = 0x0000000000000000
        let pairs: [Address] = SwapFactory.getSlicedPairs(from: 0 as UInt64, to: 10000 as UInt64)

        // Pass 1: try both USDCFlow keys
        var found = false
        for addr in pairs {
            if let p = getAccount(addr).capabilities.borrow<&{SwapInterfaces.PairPublic}>(SwapConfig.PairPublicPath) {
                if pairMatches(p, wantOther: USDC_KEYS) {
                    self.pairAddr = addr
                    found = true
                    break
                }
            }
        }

        // Pass 2: try FUSD (useful for dry-runs when USDCFlow pool isn’t found)
        if !found {
            for addr in pairs {
                if let p = getAccount(addr).capabilities.borrow<&{SwapInterfaces.PairPublic}>(SwapConfig.PairPublicPath) {
                    if pairMatches(p, wantOther: [FUSD_KEY]) {
                        self.pairAddr = addr
                        found = true
                        log("NOTE: Falling back to FLOW/FUSD pair for dry-run")
                        break
                    }
                }
            }
        }

        // Pass 3: hard fallbacks to known pair addresses (verify capability first)
        if !found {
            let candidates: [Address] = [KNOWN_FLOW_USDC_1, KNOWN_FLOW_USDC_2]
            for addr in candidates {
                if let _ = getAccount(addr).capabilities.borrow<&{SwapInterfaces.PairPublic}>(SwapConfig.PairPublicPath) {
                    self.pairAddr = addr
                    found = true
                    log("Using known pair address fallback: ".concat(addr.toString()))
                    break
                }
            }
        }

        assert(found && self.pairAddr != 0x0000000000000000, message: "Could not find a FLOW/USDC (or FUSD) pair on testnet via factory or fallbacks")
        log("Using pair: ".concat(self.pairAddr.toString()))

        // Compute fee & sanity check
        let bps = SwapFactory.getFlashloanRateBps() // Int
        let fee = UFix64(bps) * amount / 10000.0
        log("Factory flashloan fee bps: ".concat(bps.toString()))
        log("Fee (FLOW): ".concat(fee.toString()))

        let flowVaultRef = signer.storage.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)
            ?? panic("Missing /storage/flowTokenVault")
        assert(flowVaultRef.balance >= fee, message: "Insufficient FLOW to cover flashloan fee")

        let minProfit = UFix64(minProfitBps) * amount / 10000.0
        log("Target min profit (FLOW): ".concat(minProfit.toString()))

        // Build params for executor callback
        let params: {String: AnyStruct} = {}
        params["fee"] = fee
        params["minProfit"] = minProfit

        // Borrow PairPublic
        let pair = getAccount(self.pairAddr).capabilities
            .borrow<&{SwapInterfaces.PairPublic}>(SwapConfig.PairPublicPath)
            ?? panic("Could not borrow PairPublic at ".concat(self.pairAddr.toString()))

        // Issue a live executor cap
        let liveExecCap = signer.capabilities.storage.issue<&{SwapInterfaces.FlashLoanExecutor}>(self.execStoragePath)
        assert(liveExecCap.check(), message: "Executor cap invalid at execution time")

        // Inline callback (captures `signer`)
        params["callback"] = fun(feeAmount: UFix64, loanVault: @{FungibleToken.Vault}, data: AnyStruct?): @{FungibleToken.Vault} {
            log("=== CALLBACK (MVP) ===")
            log("Borrowed FLOW: ".concat(loanVault.balance.toString()))
            log("Fee required: ".concat(feeAmount.toString()))

            // TODO: Insert venue A/B real swaps here and enforce profit >= fee + minProfit

            let flowVault = signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
                from: /storage/flowTokenVault
            ) ?? panic("No FLOW vault for signer")

            // Pay the fee from your signer vault into the borrowed vault
            loanVault.deposit(from: <- flowVault.withdraw(amount: feeAmount))

            log("Repayment amount (FLOW): ".concat(loanVault.balance.toString()))
            log("=== CALLBACK END ===")
            return <-loanVault
        }

        // Execute flashloan (borrow FLOW)
        pair.flashloan(
            executor: liveExecCap.borrow() ?? panic("Failed to borrow executor cap"),
            requestedTokenVaultType: Type<@FlowToken.Vault>(),
            requestedAmount: amount,
            params: params
        )

        log("=== Flashloan complete (MVP) ===")
    }

    execute {}
}
