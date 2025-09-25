import FungibleToken from 0x9a0766d93b6608b7
import FlowToken from 0x7e60df042a9c0868
import stFlowToken from 0xe45c64ecfe31e465

import SwapInterfaces from 0x8d5b9dd833e176da
import SwapConfig from 0x8d5b9dd833e176da
import SwapFactory from 0x6ca93d49c45a249f

import IncrementFiFlashloanConnectors from 0x49bae091e5ea16b5

transaction(amount: UFix64) {
    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController, SaveValue) &Account) {
        pre {
            amount > 0.0: "Amount must be positive"
            amount <= 5.0: "Keep flashloan test amounts small"
        }

        // Known FLOW/stFLOW pair (declared inside transaction scope)
        let KNOWN_PAIR: Address = 0xd0098d511ae7051e

        // 1) Validate that KNOWN_PAIR is FLOW/stFLOW
        var pairAddr: Address = 0x0000000000000000
        let p = getAccount(KNOWN_PAIR)
            .capabilities
            .borrow<&{SwapInterfaces.PairPublic}>(SwapConfig.PairPublicPath)

        if p != nil {
            let info = p!.getPairInfoStruct()
            let isFlowStFlow =
                (info.token0Key == Type<FlowToken>().identifier && info.token1Key == Type<stFlowToken>().identifier) ||
                (info.token1Key == Type<FlowToken>().identifier && info.token0Key == Type<stFlowToken>().identifier)
            if isFlowStFlow { pairAddr = KNOWN_PAIR }
        }
        assert(pairAddr != 0x0000000000000000, message: "Could not find FLOW/stFLOW pair")

        // 2) Fee math & coverage
        let bps = SwapFactory.getFlashloanRateBps()
        let fee = UFix64(bps) * amount / 10000.0

        let flowVaultRef = signer.storage.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)
            ?? panic("Missing /storage/flowTokenVault")
        assert(flowVaultRef.balance >= fee, message: "Insufficient FLOW to cover flashloan fee")

        // 3) Idempotent executor setup
        let execPath = IncrementFiFlashloanConnectors.ExecutorStoragePath
        if signer.storage.borrow<&IncrementFiFlashloanConnectors.Executor>(from: execPath) == nil {
            let ex <- IncrementFiFlashloanConnectors.createExecutor()
            signer.storage.save(<-ex, to: execPath)
        }
        let execCap: Capability<&{SwapInterfaces.FlashLoanExecutor}> =
            signer.capabilities.storage.issue<&{SwapInterfaces.FlashLoanExecutor}>(execPath)

        // 4) Pair ref
        let pair = getAccount(pairAddr)
            .capabilities
            .borrow<&{SwapInterfaces.PairPublic}>(SwapConfig.PairPublicPath)
            ?? panic("PairPublic missing at ".concat(pairAddr.toString()))

        // 5) Callback pays fee from your FLOW vault and returns loan+fee
        let params: {String: AnyStruct} = {}
        params["fee"] = fee
        params["callback"] = fun(feeAmount: UFix64, loanVault: @{FungibleToken.Vault}, data: AnyStruct?): @{FungibleToken.Vault} {
            let flowVault = signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
                from: /storage/flowTokenVault
            )!
            loanVault.deposit(from: <- flowVault.withdraw(amount: feeAmount))
            return <-loanVault
        }

        // 6) Execute flashloan (FLOW)
        pair.flashloan(
            executor: execCap.borrow() ?? panic("could not borrow executor cap"),
            requestedTokenVaultType: Type<@FlowToken.Vault>(),
            requestedAmount: amount,
            params: params
        )
    }
}
