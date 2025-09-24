import ArbitrageBotController from 0x2409dfbcc4c9d705

access(all) fun main(): {String: AnyStruct} {
    let controllerRef = getAccount(0x2409dfbcc4c9d705)
        .contracts.borrow<&ArbitrageBotController>(name: "ArbitrageBotController")
        ?? panic("Could not borrow ArbitrageBotController reference")
    
    return controllerRef.getBotStatus()
}