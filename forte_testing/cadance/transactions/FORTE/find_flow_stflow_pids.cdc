import IncrementFiStakingConnectors from 0x49bae091e5ea16b5
import SwapInterfaces from 0x8d5b9dd833e176da
import SwapConfig from 0x8d5b9dd833e176da

// Find staking pool IDs (pid) whose pair is FLOW / stFLOW (any order)
access(all) fun main(maxPid: UInt64): {String: AnyStruct} {
    let FLOW_KEY = "A.7e60df042a9c0868.FlowToken"
    let STFLOW_KEY = "A.e45c64ecfe31e465.stFlowToken"

    var matches: [{String: AnyStruct}] = []
    var scanned: [UInt64] = []

    var pid: UInt64 = 0
    while pid <= maxPid {
        scanned.append(pid)

        let pool = IncrementFiStakingConnectors.borrowPool(pid: pid)
        if pool == nil {
            pid = pid + 1
            continue
        }

        // Try to borrow the PairPublic for this pool
        let pairRef = IncrementFiStakingConnectors.borrowPairPublicByPid(pid: pid)
        if pairRef == nil {
            pid = pid + 1
            continue
        }

        let info = pairRef!.getPairInfo()
        let token0Key = info[0] as! String
        let token1Key = info[1] as! String

        let isFlowStFlow =
            (token0Key == FLOW_KEY && token1Key == STFLOW_KEY) ||
            (token0Key == STFLOW_KEY && token1Key == FLOW_KEY)

        if isFlowStFlow {
            // LP token key derived from the pair’s LP vault type
            let lpType = pairRef!.getLpTokenVaultType()
            let lpKey = SwapConfig.SliceTokenTypeIdentifierFromVaultType(vaultTypeIdentifier: lpType.identifier)

            let poolInfo = pool!.getPoolInfo()
            // acceptTokenKey should match lpKey for an LP-staking pool
            let acceptKey = poolInfo.acceptTokenKey

            matches.append({
                "pid": pid,
                "token0Key": token0Key,
                "token1Key": token1Key,
                "acceptTokenKey": acceptKey,
                "lpTokenKey": lpKey,
                "lpSupply": info[5] as! UFix64,
                "swapFeeBps": info[6] as! UInt64,
                "stable": info[7] as! Bool
            })
        }

        pid = pid + 1
    }

    return {
        "scannedUpTo": maxPid,
        "scannedList": scanned,
        "flowStFlowPools": matches
    }
}
