access(all) struct PoolAnalysis {
    access(all) let pid: UInt64
    access(all) let rewardPerSecond: UFix64
    access(all) let totalStaking: UFix64
    access(all) let rewardPerUnit: UFix64
    access(all) let riskScore: UFix64
    access(all) let opportunityScore: UFix64
    access(all) let recommendation: String
    
    init(
        pid: UInt64,
        rewardPerSecond: UFix64,
        totalStaking: UFix64,
        rewardPerUnit: UFix64,
        riskScore: UFix64,
        opportunityScore: UFix64,
        recommendation: String
    ) {
        self.pid = pid
        self.rewardPerSecond = rewardPerSecond
        self.totalStaking = totalStaking
        self.rewardPerUnit = rewardPerUnit
        self.riskScore = riskScore
        self.opportunityScore = opportunityScore
        self.recommendation = recommendation
    }
}

access(all) fun main(): [PoolAnalysis] {
    let poolData: [{String: AnyStruct}] = [
        {"pid": UInt64(0), "rps": 0.07293684, "staking": 130.14440688, "token": "USDC"},
        {"pid": UInt64(1), "rps": 0.02918598, "staking": 202.90379740, "token": "FLOW"},
        {"pid": UInt64(2), "rps": 0.03124041, "staking": 166.93767941, "token": "FLOW+USDC"},
        {"pid": UInt64(3), "rps": 0.01324995, "staking": 39.42333802, "token": "stFLOW"},
        {"pid": UInt64(4), "rps": 0.01915896, "staking": 14.44143350, "token": "stFLOW"},
        {"pid": UInt64(5), "rps": 116.75899918, "staking": 21547.74328444, "token": "SDM"},
        {"pid": UInt64(6), "rps": 0.06769855, "staking": 201.28900532, "token": "stFLOW"},
        {"pid": UInt64(7), "rps": 0.02638165, "staking": 44.01441775, "token": "stFLOW"},
        {"pid": UInt64(8), "rps": 0.01924433, "staking": 588.88838641, "token": "stFLOW"},
        {"pid": UInt64(9), "rps": 0.01592607, "staking": 5.50300161, "token": "stFLOW"},
        {"pid": UInt64(10), "rps": 0.02651191, "staking": 294.68624531, "token": "stFLOW"},
        {"pid": UInt64(11), "rps": 0.01230649, "staking": 83.40850579, "token": "stFLOW"},
        {"pid": UInt64(12), "rps": 0.02460989, "staking": 0.61096564, "token": "stFLOW"},
        {"pid": UInt64(13), "rps": 0.01753892, "staking": 11.39582890, "token": "stFLOW"},
        {"pid": UInt64(14), "rps": 1805.87709956, "staking": 0.0, "token": "stFLOW"},
        {"pid": UInt64(15), "rps": 0.01149141, "staking": 165.41289590, "token": "stFLOW"},
        {"pid": UInt64(16), "rps": 0.02725033, "staking": 9.19665390, "token": "stFLOW"},
        {"pid": UInt64(17), "rps": 0.02180906, "staking": 6.00000001, "token": "stFLOW"},
        {"pid": UInt64(18), "rps": 0.01283381, "staking": 30.37768700, "token": "stFLOW"},
        {"pid": UInt64(19), "rps": 0.19863132, "staking": 0.41245765, "token": "stFLOW"}
    ]
    
    let analyses: [PoolAnalysis] = []
    
    for pool in poolData {
        let pid = pool["pid"]! as! UInt64
        let rps = pool["rps"]! as! UFix64
        let staking = pool["staking"]! as! UFix64
        let token = pool["token"]! as! String
        
        let rewardPerUnit = staking > 0.0 ? rps / staking : 999999.0
        
        var riskScore: UFix64 = 5.0
        if staking == 0.0 { riskScore = 9.5 }
        else if staking < 1.0 { riskScore = 8.0 }
        else if staking < 10.0 { riskScore = 7.0 }
        else if staking < 100.0 { riskScore = 5.0 }
        else { riskScore = 3.0 }
        
        if token == "SDM" { riskScore = riskScore + 2.0 }
        else if token == "USDC" { riskScore = riskScore - 1.0 }
        
        let opportunityScore = rewardPerUnit / (riskScore * riskScore)
        
        var recommendation = ""
        if pid == 14 { recommendation = "DANGER: 1805 RPS with 0 staking. Likely broken." }
        else if pid == 5 { recommendation = "HIGH RISK: 116.76 RPS, unknown SDM token." }
        else if pid == 19 { recommendation = "BEST OPPORTUNITY: 0.48 rewards per unit staked." }
        else if pid == 12 { recommendation = "LOW COMPETITION: 0.04 rewards per unit." }
        else if rewardPerUnit > 0.002 { recommendation = "GOOD: Above average efficiency." }
        else { recommendation = "STANDARD: Average pool, decent safety." }
        
        analyses.append(PoolAnalysis(
            pid: pid,
            rewardPerSecond: rps,
            totalStaking: staking,
            rewardPerUnit: rewardPerUnit,
            riskScore: riskScore,
            opportunityScore: opportunityScore,
            recommendation: recommendation
        ))
    }
    
    return analyses
}