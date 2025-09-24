import SwapFactory from 0xb063c16cac85dbd1

access(all) fun main(): Address? {
    return SwapFactory.getPairAddress(
        token0Key: "A.1654653399040a61.FlowToken",
        token1Key: "A.d6f80565193ad727.stFlowToken"
    )
}
