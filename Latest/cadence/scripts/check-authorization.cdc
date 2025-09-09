// check-authorization.cdc
// This script checks if an EVM address (string) is authorized to call the ActionRouter

import ActionRouterV2 from 0x79f5b5b0f95a160b

access(all) fun main(evmAddress: String): Bool {
    return ActionRouterV2.isAuthorized(caller: evmAddress)
}