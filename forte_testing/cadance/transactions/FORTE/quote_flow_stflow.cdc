import FlowToken      from 0x7e60df042a9c0868
import stFlowToken    from 0xe45c64ecfe31e465
import SwapInterfaces from 0x8d5b9dd833e176da
import SwapConfig     from 0x8d5b9dd833e176da
import SwapFactory    from 0x6ca93d49c45a249f

access(all) let KNOWN_PAIR: Address = 0xd0098d511ae7051e

access(all) fun main(): {String: AnyStruct} {
    let cap = getAccount(KNOWN_PAIR)
        .capabilities
        .borrow<&{SwapInterfaces.PairPublic}>(SwapConfig.PairPublicPath)

    if cap == nil {
        return {"ok": false, "reason": "PairPublic missing at known address", "pair": KNOWN_PAIR}
    }

    let info = cap!.getPairInfoStruct()
    let flowKey   = Type<FlowToken>().identifier
    let stFlowKey = Type<stFlowToken>().identifier

    let isCorrectPair =
        (info.token0Key == flowKey && info.token1Key == stFlowKey) ||
        (info.token1Key == flowKey && info.token0Key == stFlowKey)

    return {
        "ok": isCorrectPair,
        "pair": KNOWN_PAIR,
        "token0Key": info.token0Key,
        "token1Key": info.token1Key,
        "flashloanFeeBps": SwapFactory.getFlashloanRateBps()
    }
}
