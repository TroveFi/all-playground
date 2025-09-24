import BandOracle from 0x2c71de7af78d1adf
import FlowToken from 0x7e60df042a9c0868
import FungibleToken from 0x9a0766d93b6608b7

// Test transaction to find which symbols work
transaction(baseSymbol: String, quoteSymbol: String) {
    prepare(signer: auth(BorrowValue) &Account) {
        log("Testing symbol pair: ".concat(baseSymbol).concat("/").concat(quoteSymbol))
        
        let fee = BandOracle.getFee()
        let paymentVault <- FlowToken.createEmptyVault(vaultType: Type<@FlowToken.Vault>())
        
        if fee > 0.0 {
            let vaultRef = signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(from: /storage/flowTokenVault)!
            let payment <- vaultRef.withdraw(amount: fee)
            paymentVault.deposit(from: <-payment)
        }
        
        // Try to get the data - will panic if symbols don't exist
        let referenceData = BandOracle.getReferenceData(
            baseSymbol: baseSymbol,
            quoteSymbol: quoteSymbol,
            payment: <-paymentVault
        )
        
        log("SUCCESS! Found data for ".concat(baseSymbol).concat("/").concat(quoteSymbol))
        log("Price: ".concat(referenceData.fixedPointRate.toString()))
        log("Rate (E18): ".concat(referenceData.integerE18Rate.toString()))
        log("Base timestamp: ".concat(referenceData.baseTimestamp.toString()))
        log("Quote timestamp: ".concat(referenceData.quoteTimestamp.toString()))
    }
}