import FungibleToken from 0xf233dcee88fe0abe
import FlowToken from 0x1654653399040a61
import Staking from 0x1b77ba4b414de352
import stFlowToken from 0xd6f80565193ad727

// DEX
import SwapRouter from 0xa6850776a94e6551
import SwapFactory from 0xb063c16cac85dbd1
import SwapInterfaces from 0xb78ef7afa52ff906
import SwapConfig from 0xb78ef7afa52ff906

/// Loops 2–4 times attempting:
/// 1) split remaining FLOW (50/50),
/// 2) swap half FLOW -> stFLOW,
/// 3) add liquidity into FLOW-stFLOW pair,
/// 4) stake LP into first active pool ID that matches FLOW-stFLOW.
/// In practice, with 1 FLOW only the first loop will have material effect; later loops will likely no-op.
transaction(
    flowAmount: UFix64,
    loopCount: UInt8,                 // suggest 2–4
    pidCandidates: [UInt64]           // e.g. [3, 6, 9, 11, 13, 15, 18, 20]
) {
    // user resources
    let flowVault: auth(FungibleToken.Withdraw) &FlowToken.Vault
    let userCert: &Staking.UserCertificate
    let poolCollection: &{Staking.PoolCollectionPublic}

    // the FLOW-stFLOW Pair we want (you already discovered this on mainnet)
    let pairAddress: Address
    let pairRef: &{SwapInterfaces.PairPublic}

    prepare(signer: auth(Storage, Capabilities) &Account) {
        // Borrow user Flow vault
        self.flowVault = signer.storage
            .borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(from: /storage/flowTokenVault)
            ?? panic("Missing /storage/flowTokenVault")

        // Borrow user certificate (must be created in advance via the Staking setup flow)
        self.userCert = signer.storage
            .borrow<&Staking.UserCertificate>(from: Staking.UserCertificateStoragePath)
            ?? panic("Missing Staking.UserCertificate — run staking setup first")

        // Borrow global PoolCollection
        let stakingAcct = getAccount(0x1b77ba4b414de352)
        self.poolCollection = stakingAcct.capabilities
            .borrow<&{Staking.PoolCollectionPublic}>(Staking.CollectionPublicPath)
            ?? panic("Could not borrow Staking.PoolCollectionPublic")

        // Confirm the FLOW-stFLOW pair exists and fetch PairPublic
        let token0Key = "A.1654653399040a61.FlowToken"
        let token1Key = "A.d6f80565193ad727.stFlowToken"
        let pairAddr = SwapFactory.getPairAddress(token0Key: token0Key, token1Key: token1Key)
            ?? panic("FLOW-stFLOW pair missing on mainnet")
        self.pairAddress = pairAddr

        self.pairRef = getAccount(pairAddr)
            .capabilities
            .borrow<&{SwapInterfaces.PairPublic}>(SwapConfig.PairPublicPath)
            ?? panic("Could not borrow PairPublic for FLOW-stFLOW")
    }

    execute {
        pre {
            loopCount >= 2 && loopCount <= 4:
                "loopCount should be between 2 and 4 for this test"
            flowAmount >= 0.000001:
                "flowAmount must be > 0"
        }

        // Choose first active pid that matches this pair address
        var chosenPid: UInt64? = nil
        for pid in pidCandidates {
            let p = self.poolCollection.getPool(pid: pid)
            let info = p.getPoolInfo()
            // Pool accepts LP as a token key "A.<pairAddress>.SwapPair"
            if info.status == "2" {
                let lpVaultType = CompositeType(info.acceptTokenKey.concat(".Vault"))!
                if lpVaultType.address != nil && lpVaultType.address! == self.pairAddress {
                    chosenPid = pid
                    break
                }
            }
        }
        assert(chosenPid != nil, message: "No active pid among candidates matches FLOW-stFLOW pair")

        let deadline = getCurrentBlock().timestamp + 60.0

        // Withdraw the test amount of FLOW
        let workingFlow <- self.flowVault.withdraw(amount: flowAmount)
        log("Loop start — FLOW withdrawn: ".concat(workingFlow.balance.toString()))
        log("Selected pid: ".concat(chosenPid!.toString()))

        var i: UInt8 = 0
        while i < loopCount {
            log("Loop #".concat(i.toString()))

            if workingFlow.balance <= 0.000001 {
                log("No FLOW left — skipping remaining loops")
                break
            }

            // Naive 50/50 split for zap (good enough for a smoke test with 1 FLOW)
            let halfIn <- workingFlow.withdraw(amount: workingFlow.balance / 2.0)

            // Swap FLOW -> stFLOW along the simple 2-hop path
            let stFlowOut <- SwapRouter.swapExactTokensForTokens(
                exactVaultIn: <-halfIn,
                amountOutMin: 0.0, // test run; in prod set slippage guard
                tokenKeyPath: [
                    "A.1654653399040a61.FlowToken",
                    "A.d6f80565193ad727.stFlowToken"
                ],
                deadline: deadline
            )
            log("Swapped ~half FLOW to stFLOW: ".concat(stFlowOut.balance.toString()))

            // Add liquidity: remaining FLOW + stFLOW
            let lpTokens <- self.pairRef.addLiquidity(
                tokenAVault: <-workingFlow,    // remaining FLOW
                tokenBVault: <-stFlowOut       // the stFLOW we just got
            )
            log("LP minted: ".concat(lpTokens.balance.toString()))

            // Stake LP into chosen pid
            let pool = self.poolCollection.getPool(pid: chosenPid!)
            pool.stake(staker: self.userCert.owner!.address, stakingToken: <-lpTokens)
            log("Staked LP in pid ".concat(chosenPid!.toString()))

            // Refill workingFlow with any FLOW we still control (usually 0 after addLiquidity)
            let refill <- FlowToken.createEmptyVault()
            workingFlow <- refill
            destroy refill

            i = i + 1
        }

        // burn any empty vaults we control (should be zeroed by now)
        destroy workingFlow
        log("Done.")
    }
}
