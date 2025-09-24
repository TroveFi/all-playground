import ActionRouterV3 from 0x79f5b5b0f95a160b

access(all) fun main(): {String: AnyStruct} {
    let stats = ActionRouterV3.getStats()
    return {
        "totalStakeOps": stats.totalStakeOps,
        "totalUnstakeOps": stats.totalUnstakeOps,
        "totalFlowStaked": stats.totalFlowStaked,
        "exchangeRate": stats.exchangeRate,
        "isActive": stats.isActive,
        "protocolFeeRate": stats.protocolFeeRate,
        "accumulatedFees": stats.accumulatedFees,
        "currentFlowBalance": stats.currentFlowBalance,
        "currentStFlowBalance": stats.currentStFlowBalance,
        "blockHeight": stats.blockHeight,
        "timestamp": stats.timestamp
    }
}