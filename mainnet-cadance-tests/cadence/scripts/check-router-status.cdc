// check-router-status-v3.cdc
// This script checks the status and balances of ActionRouterV3

import ActionRouterV3 from 0x79f5b5b0f95a160b

access(all) fun main(): ActionRouterV3.RouterStats {
    return ActionRouterV3.getStats()
}