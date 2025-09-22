
import BandOracle    from 0x6801a6222ebf784a
import FlowToken     from 0x1654653399040a61

access(all) fun main(baseSymbol: String, quoteSymbol: String): {String: String} {
    // Create an empty FLOW vault to satisfy the `payment` parameter.
    // (Band fee is currently 0 on mainnet, so this is fine.)
    let payment <- FlowToken.createEmptyVault(vaultType: Type<@FlowToken.Vault>())

    let rd = BandOracle.getReferenceData(
        baseSymbol: baseSymbol,
        quoteSymbol: quoteSymbol,
        payment: <-payment
    )

    // Build a simple map of strings so printing is trivial in CLI
    let out: {String: String} = {}
    out["base"] = baseSymbol
    out["quote"] = quoteSymbol
    out["fixedPointRate"] = rd.fixedPointRate.toString()
    out["integerE18Rate"] = rd.integerE18Rate.toString()   // (big int → string)
    out["baseTimestamp"] = rd.baseTimestamp.toString()     // UInt64
    out["quoteTimestamp"] = rd.quoteTimestamp.toString()   // UInt64
    return out
}


// MAINNET -> USAGE: flow scripts execute cadence/scripts/read_band_reference_data_mainnet.cdc \      
//  "ETH" "USD" \      
//  --network mainnet