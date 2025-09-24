import Staking from 0x1b77ba4b414de352

access(all) fun main(pid: UInt64): {String: AnyStruct} {
    let stakingAccount = getAccount(0x1b77ba4b414de352)
    let pools = stakingAccount.capabilities
        .borrow<&{Staking.PoolCollectionPublic}>(Staking.CollectionPublicPath)
        ?? panic("Could not borrow Staking.PoolCollectionPublic")

    let pool = pools.getPool(pid: pid)
    let info = pool.getPoolInfo()

    // Common statuses: "0"=pending, "1"=ended/paused, "2"=active
    let isActive = info.status == "2"

    return {
        "pid": pid,
        "status": info.status,
        "isActive": isActive,
        "acceptTokenKey": info.acceptTokenKey,
        "totalStaking": info.totalStaking,
        "limitAmount": info.limitAmount,
        "rewardsInfoKeys": info.rewardsInfo.keys
    }
}
