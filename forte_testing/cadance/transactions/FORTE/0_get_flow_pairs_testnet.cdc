import SwapInterfaces from 0x8d5b9dd833e176da
import SwapConfig from 0x8d5b9dd833e176da
import SwapFactory from 0x6ca93d49c45a249f

access(all) fun main(): {Address: {String: String}} {
    let out: {Address: {String: String}} = {}

    let total: Int = SwapFactory.getAllPairsLength()
    if total <= 0 { return out }

    let addrs = SwapFactory.getSlicedPairs(from: UInt64(0), to: UInt64(total))

    for a in addrs {
        let pairRef = getAccount(a)
            .capabilities
            .borrow<&{SwapInterfaces.PairPublic}>(SwapConfig.PairPublicPath)
            ?? panic("cannot borrow PairPublic at ".concat(a.toString()))

        let info = pairRef.getPairInfoStruct()
        let t0 = info.token0Key
        let t1 = info.token1Key

        if t0 == "A.7e60df042a9c0868.FlowToken" || t1 == "A.7e60df042a9c0868.FlowToken" {
            out[a] = {
                "token0Key": t0,
                "token1Key": t1
            }
        }
    }
    return out
}
