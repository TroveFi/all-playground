import IncrementFiStakingConnectors from 0x49bae091e5ea16b5
import SwapInterfaces from 0x8d5b9dd833e176da
import SwapConfig from 0x8d5b9dd833e176da

// Inspect a single pid and (if valid) report the accept token & whether it's the FLOW/stFLOW LP
access(all) fun main(pid: UInt64): {String: AnyStruct} {
    let FLOW_KEY = "A.7e60df042a9c0868.FlowToken"
    let STFLOW_KEY = "A.e45c64ecfe31e465.stFlowToken"

    // Will panic if pid is invalid (that's expected) — so run this with specific guesses
    let pool = IncrementFiStakingConnectors.borrowPool(pid: pid)!
    let acceptKey = pool.getPoolInfo().acceptTokenKey

    // If this is an LP pool, acceptKey should be the LP token key of its pair.
    // Try to borrow the pair and compare token keys.
    let pairRef = IncrementFiStakingConnectors.borrowPairPublicByPid(pid: pid)
    var matched = false
    var t0 = ""
    var t1 = ""
    var lpKey = ""

    if pairRef != nil {
        let info = pairRef!.getPairInfo()
        t0 = info[0] as! String
        t1 = info[1] as! String
        let lpType = pairRef!.getLpTokenVaultType()
        lpKey = SwapConfig.SliceTokenTypeIdentifierFromVaultType(vaultTypeIdentifier: lpType.identifier)

        let isFlowStFlow =
            (t0 == FLOW_KEY && t1 == STFLOW_KEY) ||
            (t0 == STFLOW_KEY && t1 == FLOW_KEY)

        matched = isFlowStFlow && (acceptKey == lpKey)
    }

    return {
        "pid": pid,
        "acceptTokenKey": acceptKey,
        "pairToken0Key": t0,
        "pairToken1Key": t1,
        "lpTokenKey": lpKey,
        "isFLOW_stFLOW_LP_StakingPool": matched
    }
}
