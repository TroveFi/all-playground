import SwapInterfaces from 0x8d5b9dd833e176da
import SwapConfig     from 0x8d5b9dd833e176da
import SwapFactory    from 0x6ca93d49c45a249f
import FlowToken      from 0x7e60df042a9c0868

// stFLOW on testnet
access(all) let STFLOW_KEY: String = "A.e45c64ecfe31e465.stFlowToken"
// Known FLOW/stFLOW pair (from your earlier dump), used as a fallback
access(all) let KNOWN_FLOW_STFLOW: Address = 0xd0098d511ae7051e

access(all) fun main(): {String: AnyStruct} {
    // Use CONTRACT identifiers (no ".Vault")
    let FLOW_KEY = Type<FlowToken>().identifier

    // 1) Scan pairs from the factory
    let pairs: [Address] = SwapFactory.getSlicedPairs(
        from: 0 as UInt64,
        to: 10000 as UInt64
    )

    for addr in pairs {
        if let p = getAccount(addr)
            .capabilities
            .borrow<&{SwapInterfaces.PairPublic}>(SwapConfig.PairPublicPath)
        {
            let info = p.getPairInfoStruct()

            let isFlowStFlow =
                (info.token0Key == FLOW_KEY && info.token1Key == STFLOW_KEY) ||
                (info.token1Key == FLOW_KEY && info.token0Key == STFLOW_KEY)

            if isFlowStFlow {
                return {
                    "pair": addr,
                    "token0Key": info.token0Key,
                    "token1Key": info.token1Key
                }
            }
        }
    }

    // 2) Fallback to the known address; verify its keys so you still get the keys back
    if let p2 = getAccount(KNOWN_FLOW_STFLOW)
        .capabilities
        .borrow<&{SwapInterfaces.PairPublic}>(SwapConfig.PairPublicPath)
    {
        let info2 = p2.getPairInfoStruct()
        return {
            "pair": KNOWN_FLOW_STFLOW,
            "token0Key": info2.token0Key,
            "token1Key": info2.token1Key
        }
    }

    // 3) Nothing found
    return { "pair": 0x0000000000000000 }
}
