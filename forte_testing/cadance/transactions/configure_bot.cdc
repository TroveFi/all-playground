import ArbitrageBotController from 0x2409dfbcc4c9d705

transaction(minProfit: UFix64, maxTrade: UFix64, crossVM: Bool, maxLoss: UFix64) {
    prepare(signer: auth(BorrowValue) &Account) {
        let adminRef = signer.storage.borrow<&ArbitrageBotController.Admin>(from: /storage/ArbitrageBotAdmin)
            ?? panic("Could not borrow admin reference")
        
        adminRef.updateConfig(
            minProfit: minProfit,
            maxTrade: maxTrade, 
            crossVM: crossVM,
            maxLoss: maxLoss
        )
        log("Bot configured:")
        log("- Min profit threshold: ".concat(minProfit.toString()).concat("%"))
        log("- Max trade size: ".concat(maxTrade.toString()).concat(" FLOW"))
        log("- Cross-VM enabled: ".concat(crossVM.toString()))
        log("- Max daily loss: ".concat(maxLoss.toString()).concat(" FLOW"))
    }
}