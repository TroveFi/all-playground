import Staking from 0x1b77ba4b414de352

access(all) struct UserStakingPosition {
    access(all) let pid: UInt64
    access(all) let stakingAmount: UFix64
    access(all) let isBlocked: Bool
    access(all) let claimedRewards: {String: UFix64}
    access(all) let unclaimedRewards: {String: UFix64}
    access(all) let poolStatus: String
    access(all) let acceptTokenKey: String
    
    init(
        pid: UInt64,
        stakingAmount: UFix64,
        isBlocked: Bool,
        claimedRewards: {String: UFix64},
        unclaimedRewards: {String: UFix64},
        poolStatus: String,
        acceptTokenKey: String
    ) {
        self.pid = pid
        self.stakingAmount = stakingAmount
        self.isBlocked = isBlocked
        self.claimedRewards = claimedRewards
        self.unclaimedRewards = unclaimedRewards
        self.poolStatus = poolStatus
        self.acceptTokenKey = acceptTokenKey
    }
}

access(all) fun main(userAddress: Address): [UserStakingPosition] {
    let stakingIds = Staking.getUserStakingIds(address: userAddress)
    let positions: [UserStakingPosition] = []
    
    if stakingIds.length == 0 {
        return positions
    }
    
    let stakingAccount = getAccount(0x1b77ba4b414de352)
    let collectionRef = stakingAccount.capabilities.borrow<&{Staking.PoolCollectionPublic}>(Staking.CollectionPublicPath)
    
    if collectionRef == nil {
        return positions
    }
    
    for pid in stakingIds {
        let poolRef = collectionRef!.getPool(pid: pid)
        let poolInfo = poolRef.getPoolInfo()
        let userInfo = poolRef.getUserInfo(address: userAddress)
        
        if userInfo != nil {
            let position = UserStakingPosition(
                pid: pid,
                stakingAmount: userInfo!.stakingAmount,
                isBlocked: userInfo!.isBlocked,
                claimedRewards: userInfo!.claimedRewards,
                unclaimedRewards: userInfo!.unclaimedRewards,
                poolStatus: poolInfo.status,
                acceptTokenKey: poolInfo.acceptTokenKey
            )
            
            positions.append(position)
        }
    }
    
    return positions
}