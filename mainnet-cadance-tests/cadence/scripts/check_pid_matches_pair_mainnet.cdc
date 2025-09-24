import Staking from 0x1b77ba4b414de352

// Check one pid: does its acceptTokenKey correspond to LP at pairAddr?
access(all) fun main(pid: UInt64, pairAddr: Address): {String: AnyStruct} {
    let stakingAccount = getAccount(0x1b77ba4b414de352)
    let pools = stakingAccount.capabilities
        .borrow<&{Staking.PoolCollectionPublic}>(Staking.CollectionPublicPath)
        ?? panic("Could not borrow Staking.PoolCollectionPublic")

    // NOTE: This will fail with a precondition if pid doesn't exist — that's OK if you call it in a shell loop with `|| true`
    let pool = pools.getPool(pid: pid)
    let info = pool.getPoolInfo()

    // Pools store the LP token as the *token key* "A.<pairAddress>.SwapPair".
    // Turn that back into a Vault type so we can read the address and compare.
    let lpVaultType = CompositeType(info.acceptTokenKey.concat(".Vault"))!
    let vaultAddr = lpVaultType.address?.toString() ?? "0x0000000000000000"
    let matches = (lpVaultType.address != nil) && (lpVaultType.address! == pairAddr)

    return {
        "pid": pid,
        "acceptTokenKey": info.acceptTokenKey,
        "lpVaultType": lpVaultType.identifier,
        "lpVaultAddress": vaultAddr,
        "matchesPair": matches
    }
}
