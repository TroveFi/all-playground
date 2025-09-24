import ActionRouterV2 from 0x79f5b5b0f95a160b

access(all) fun main(): {String: AnyStruct} {
    let stats = ActionRouterV2.getStats()
    return {
        "isActive": stats.isActive,
        "totalStakeOps": stats.totalStakeOps,
        "totalUnstakeOps": stats.totalUnstakeOps,
        "totalFlowStaked": stats.totalFlowStaked,
        "currentFlowBalance": stats.currentFlowBalance,
        "currentStFlowBalance": stats.currentStFlowBalance
    }
}