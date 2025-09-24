import ArbitrageBotController from 0x2409dfbcc4c9d705

transaction() {
    prepare(signer: auth(BorrowValue) &Account) {
        let adminRef = signer.storage.borrow<&ArbitrageBotController.Admin>(from: /storage/ArbitrageBotAdmin)
            ?? panic("Could not borrow admin reference")
        
        adminRef.startBot()
        log("Arbitrage bot started and ready for trading")
    }
}