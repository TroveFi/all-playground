import Staking from 0x1b77ba4b414de352
import LendingInterfaces from 0x2df970b6cdee5735
import LendingComptroller from 0xf80cb737bfe7c792
import LendingConfig from 0x2df970b6cdee5735

access(all) struct Opportunity {
    access(all) let type: String // "Farm", "Lending", "Borrow"
    access(all) let identifier: String
    access(all) let apr: UFix64
    access(all) let tvl: UFix64
    access(all) let token: String
    access(all) let riskScore: UFix64
    
    init(type: String, identifier: String, apr: UFix64, tvl: UFix64, token: String, riskScore: UFix64) {
        self.type = type
        self.identifier = identifier
        self.apr = apr
        self.tvl = tvl
        self.token = token
        self.riskScore = riskScore
    }
}

access(all) fun main(): [Opportunity] {
    let opportunities: [Opportunity] = []
    
    // Get farming opportunities
    let stakingCollection = getAccount(0x1b77ba4b414de352).capabilities
        .borrow<&{Staking.PoolCollectionPublic}>(Staking.CollectionPublicPath)
    
    if stakingCollection != nil {
        let poolCount = stakingCollection!.getCollectionLength()
        var i: UInt64 = 0
        while i < UInt64(poolCount) && i < 20 {
            let poolRef = stakingCollection!.getPool(pid: i)
            let poolInfo = poolRef.getPoolInfo()
            
            if poolInfo.status == "1" { // Active pools only
                let rewardInfo = poolRef.getRewardInfo()
                var totalRPS: UFix64 = 0.0
                for tokenKey in rewardInfo.keys {
                    totalRPS = totalRPS + rewardInfo[tokenKey]!.rewardPerSeed
                }
                
                opportunities.append(Opportunity(
                    type: "Farm",
                    identifier: "Pool-".concat(i.toString()),
                    apr: totalRPS * 86400.0 * 365.0, // Rough APR estimate
                    tvl: poolInfo.totalStaking,
                    token: poolInfo.acceptTokenKey,
                    riskScore: poolInfo.totalStaking < 10.0 ? 7.0 : 4.0
                ))
            }
            i = i + 1
        }
    }
    
    // Get lending opportunities
    let comptroller = getAccount(0xf80cb737bfe7c792).capabilities
        .borrow<&{LendingInterfaces.ComptrollerPublic}>(LendingConfig.ComptrollerPublicPath)
    
    if comptroller != nil {
        let markets = comptroller!.getAllMarkets()
        for poolAddr in markets {
            let marketInfo = comptroller!.getMarketInfo(poolAddr: poolAddr)
            if marketInfo["isOpen"]! as! Bool {
                let supplyAPR = LendingConfig.ScaledUInt256ToUFix64(
                    UInt256.fromString(marketInfo["marketSupplyApr"]! as! String)!
                )
                
                opportunities.append(Opportunity(
                    type: "Lending",
                    identifier: poolAddr.toString(),
                    apr: supplyAPR,
                    tvl: 0.0, // Would need to calculate
                    token: marketInfo["marketType"]! as! String,
                    riskScore: 3.0 // Lending is generally lower risk
                ))
            }
        }
    }
    
    return opportunities
}