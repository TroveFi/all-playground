import ActionRouterV2 from 0x79f5b5b0f95a160b

access(all) fun main(evmAddress: String): Bool {
    return ActionRouterV2.isAuthorized(caller: evmAddress)
}