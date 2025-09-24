import BandOracle from 0x6801a6222ebf784a
import FlowToken  from 0x1654653399040a61

// Returns a {String:String} map so Flow CLI prints it nicely.
access(all) fun main(
    baseSymbol: String,
    quoteSymbol: String,
    staleThreshold: UFix64
): {String: String} {
    let payment <- FlowToken.createEmptyVault(vaultType: Type<@FlowToken.Vault>())

    let rd = BandOracle.getReferenceData(
        baseSymbol: baseSymbol,
        quoteSymbol: quoteSymbol,
        payment: <-payment
    )

    let now = getCurrentBlock().timestamp  // UFix64 seconds
    let baseAge = now - UFix64(rd.baseTimestamp)
    let quoteAge = now - UFix64(rd.quoteTimestamp)

    let out: {String: String} = {}
    out["base"] = baseSymbol
    out["quote"] = quoteSymbol
    out["fixedPointRate"]   = rd.fixedPointRate.toString()
    out["integerE18Rate"]   = rd.integerE18Rate.toString()
    out["baseTimestamp"]    = rd.baseTimestamp.toString()
    out["quoteTimestamp"]   = rd.quoteTimestamp.toString()
    out["baseAgeSec"]       = baseAge.toString()
    out["quoteAgeSec"]      = quoteAge.toString()
    out["staleThresholdSec"]= staleThreshold.toString()
    out["okBase"]           = (baseAge <= staleThreshold) ? "true" : "false"
    out["okQuote"]          = (quoteAge <= staleThreshold) ? "true" : "false"
    out["okBoth"]           = ((baseAge <= staleThreshold) && (quoteAge <= staleThreshold)) ? "true" : "false"
    return out
}
