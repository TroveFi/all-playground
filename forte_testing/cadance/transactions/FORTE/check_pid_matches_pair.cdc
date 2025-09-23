import IncrementFiStakingConnectors from 0x49bae091e5ea16b5
import SwapConfig from 0x8d5b9dd833e176da

// Check one pid: does its acceptTokenKey correspond to LP at pairAddr?
access(all) fun main(pid: UInt64, pairAddr: Address): {String: AnyStruct} {
    var ok = false
    var acceptKey = ""
    var vaultTypeID = ""
    var vaultAddr = "0x0000000000000000"

    let pool = IncrementFiStakingConnectors.borrowPool(pid: pid)
    if pool != nil {
        acceptKey = pool!.getPoolInfo().acceptTokenKey
        // Pools store the LP as a token key "A.<pairAddress>.SwapPair"
        let lpVaultType = IncrementFiStakingConnectors.tokenTypeIdentifierToVaultType(acceptKey)
        vaultTypeID = lpVaultType.identifier
        if let addr = lpVaultType.address {
            vaultAddr = addr.toString()
            ok = addr == pairAddr
        }
    }

    return {
        "pid": pid,
        "acceptTokenKey": acceptKey,
        "lpVaultType": vaultTypeID,
        "lpVaultAddress": vaultAddr,
        "matchesPair": ok
    }
}
