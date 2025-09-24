import BandOracle from 0x2c71de7af78d1adf
import FlowToken from 0x7e60df042a9c0868
import FungibleToken from 0x9a0766d93b6608b7

// Transaction to get price data from Band Oracle with payment
// Usage: flow transactions send get_oracle_price_paid.cdc "FLOW" "USD" --signer testnet-defi --network testnet
transaction(baseSymbol: String, quoteSymbol: String) {
    prepare(signer: auth(BorrowValue) &Account) {
        
        // Get the current fee
        let fee = BandOracle.getFee()
        log("Oracle fee required: ".concat(fee.toString()).concat(" FLOW"))
        
        if fee == 0.0 {
            log("Oracle is free to use!")
        } else {
            // Borrow Flow vault to pay fee
            let vaultRef = signer.storage.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)
                ?? panic("Could not borrow Flow token vault")
            
            if vaultRef.balance < fee {
                panic("Insufficient FLOW balance. Need ".concat(fee.toString()).concat(" FLOW"))
            }
            
            log("Paying ".concat(fee.toString()).concat(" FLOW for oracle data"))
        }
        
        // Create payment vault
        let paymentVault <- FlowToken.createEmptyVault(vaultType: Type<@FlowToken.Vault>())
        
        if fee > 0.0 {
            let vaultRef = signer.storage.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)!
            let payment <- vaultRef.withdraw(amount: fee)
            paymentVault.deposit(from: <-payment)
        }
        
        // Get reference data from oracle
        let referenceData = BandOracle.getReferenceData(
            baseSymbol: baseSymbol,
            quoteSymbol: quoteSymbol,
            payment: <-paymentVault
        )
        
        // Log the results
        log("=== ORACLE PRICE DATA ===")
        log("Pair: ".concat(baseSymbol).concat("/").concat(quoteSymbol))
        log("Rate (18 decimals): ".concat(referenceData.integerE18Rate.toString()))
        log("Rate (fixed point): ".concat(referenceData.fixedPointRate.toString()))
        log("Base timestamp: ".concat(referenceData.baseTimestamp.toString()))
        log("Quote timestamp: ".concat(referenceData.quoteTimestamp.toString()))
        
        // Calculate human readable price
        let humanPrice = referenceData.fixedPointRate
        log("Human readable price: 1 ".concat(baseSymbol).concat(" = ").concat(humanPrice.toString()).concat(" ").concat(quoteSymbol))
        
        if baseSymbol == "FLOW" && quoteSymbol == "USD" {
            log("Current FLOW price: $".concat(humanPrice.toString()))
        }
    }
}