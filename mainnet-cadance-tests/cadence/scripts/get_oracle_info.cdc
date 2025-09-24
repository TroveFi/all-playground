import BandOracle from 0x2c71de7af78d1adf

access(all) fun main(): {String: AnyStruct} {
    let currentFee = BandOracle.getFee()
    
    return {
        "oracleFee": currentFee,
        "feeStatus": currentFee == 0.0 ? "FREE" : "PAID",
        "testPairs": [
            {"base": "FLOW", "quote": "USD"},
            {"base": "BTC", "quote": "USD"},
            {"base": "ETH", "quote": "USD"}
        ],
        "instructions": "Use get_oracle_price_paid.cdc to get actual prices"
    }
}