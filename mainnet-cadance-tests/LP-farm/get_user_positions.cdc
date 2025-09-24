import Staking from 0x1b77ba4b414de352

access(all) struct UserPosition {
    access(all) let pid: UInt64
    access(all) let stakingAmount: UFix64
    access(all) let acceptTokenKey: String

    init(pid: UInt64, stakingAmount: UFix64, acceptTokenKey: String) {
        self.pid = pid
        self.stakingAmount = stakingAmount
        self.acceptTokenKey = acceptTokenKey
    }
}

access(all) fun main(user: Address): [UserPosition] {
    let stakingIds = Staking.getUserStakingIds(address: user)
    var positions: [UserPosition] = []
    if stakingIds.length == 0 { return positions }

    let collectionRef = getAccount(0x1b77ba4b414de352).capabilities
        .borrow<&{Staking.PoolCollectionPublic}>(Staking.CollectionPublicPath)
        ?? panic("Could not borrow staking collection")

    for pid in stakingIds {
        let poolRef = collectionRef.getPool(pid: pid)
        if let userInfo = poolRef.getUserInfo(address: user) {
            if userInfo.stakingAmount > 0.0 {
                positions.append(UserPosition(
                    pid: pid,
                    stakingAmount: userInfo.stakingAmount,
                    acceptTokenKey: poolRef.getPoolInfo().acceptTokenKey
                ))
            }
        }
    }
    return positions
}