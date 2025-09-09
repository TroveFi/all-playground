// check-router-status.cdc
// This script checks the status and balances of the ActionRouter

import ActionRouterV2 from 0x79f5b5b0f95a160b

access(all) fun main(routerAddress: Address): ActionRouterV2.RouterStats {
    return ActionRouterV2.getStats()
}