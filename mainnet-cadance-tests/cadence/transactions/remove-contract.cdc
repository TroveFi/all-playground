transaction {
    prepare(signer: auth(Contracts) &Account) {
        signer.contracts.remove(name: "ActionRouter")
        log("ActionRouter contract removed")
    }
}