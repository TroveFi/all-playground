import BandOracle from 0x2c71de7af78d1adf
import FlowToken from 0x7e60df042a9c0868
import FungibleToken from 0x9a0766d93b6608b7

transaction(baseSymbol: String, quoteSymbol: String) {
    prepare(signer: auth(BorrowValue) &Account) {
        let fee = BandOracle.getFee()
        log("Oracle fee: ".concat(fee.toString()).concat(" FLOW"))
        
        let paymentVault <- FlowToken.createEmptyVault(vaultType: Type<@FlowToken.Vault>())
        
        if fee > 0.0 {
            let vaultRef = signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(from: /storage/flowTokenVault)
                ?? panic("Could not borrow Flow vault")
            
            let payment <- vaultRef.withdraw(amount: fee)
            paymentVault.deposit(from: <-payment)
        }
        
        let referenceData = BandOracle.getReferenceData(
            baseSymbol: baseSymbol,
            quoteSymbol: quoteSymbol,
            payment: <-paymentVault
        )
        
        log("=== PRICE DATA ===")
        log("Pair: ".concat(baseSymbol).concat("/").concat(quoteSymbol))
        log("Price: ".concat(referenceData.fixedPointRate.toString()))
        
        if baseSymbol == "FLOW" && quoteSymbol == "USD" {
            log("FLOW PRICE: $".concat(referenceData.fixedPointRate.toString()))
        }
    }
}