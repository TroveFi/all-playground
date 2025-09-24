// Analysis script to rank Increment pools by opportunity
// Run this to get data-driven recommendations before executing

access(all) struct PoolAnalysis {
    access(all) let pid: UInt64
    access(all) let rewardPerSecond: UFix64
    access(all) let totalStaking: UFix64
    access(all) let rewardPerUnit: UFix64 // RPS / total staking
    access(all) let riskScore: UFix64 // 1-10, higher = riskier
    access(all) let opportunityScore: UFix64 // Combined metric
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
    // Based on the real data you provided
    let poolData: [{String: AnyStruct}] = [
        {"pid": 0, "rps": 0.07293684, "staking": 130.14440688, "token": "USDC"},
        {"pid": 1, "rps": 0.02918598, "staking": 202.90379740, "token": "FLOW"},
        {"pid": 2, "rps": 0.03124041, "staking": 166.93767941, "token": "FLOW+USDC"}, // Combined RPS
        {"pid": 3, "rps": 0.01324995, "staking": 39.42333802, "token": "stFLOW"},
        {"pid": 4, "rps": 0.01915896, "staking": 14.44143350, "token": "stFLOW"},
        {"pid": 5, "rps": 116.75899918, "staking": 21547.74328444, "token": "SDM"},
        {"pid": 6, "rps": 0.06769855, "staking": 201.28900532, "token": "stFLOW"},
        {"pid": 7, "rps": 0.02638165, "staking": 44.01441775, "token": "stFLOW"},
        {"pid": 8, "rps": 0.01924433, "staking": 588.88838641, "token": "stFLOW"},
        {"pid": 9, "rps": 0.01592607, "staking": 5.50300161, "token": "stFLOW"},
        {"pid": 10, "rps": 0.02651191, "staking": 294.68624531, "token": "stFLOW"},
        {"pid": 11, "rps": 0.01230649, "staking": 83.40850579, "token": "stFLOW"},
        {"pid": 12, "rps": 0.02460989, "staking": 0.61096564, "token": "stFLOW"},
        {"pid": 13, "rps": 0.01753892, "staking": 11.39582890, "token": "stFLOW"},
        {"pid": 14, "rps": 1805.87709956, "staking": 0.0, "token": "stFLOW"},
        {"pid": 15, "rps": 0.01149141, "staking": 165.41289590, "token": "stFLOW"},
        {"pid": 16, "rps": 0.02725033, "staking": 9.19665390, "token": "stFLOW"},
        {"pid": 17, "rps": 0.02180906, "staking": 6.00000001, "token": "stFLOW"},
        {"pid": 18, "rps": 0.01283381, "staking": 30.37768700, "token": "stFLOW"},
        {"pid": 19, "rps": 0.19863132, "staking": 0.41245765, "token": "stFLOW"}
    ]
    
    let analyses: [PoolAnalysis] = []
    
    for pool in poolData {
        let pid = pool["pid"]! as! UInt64
        let rps = pool["rps"]! as! UFix64
        let staking = pool["staking"]! as! UFix64
        let token = pool["token"]! as! String
        
        // Calculate metrics
        let rewardPerUnit = staking > 0.0 ? rps / staking : rps * 1000000.0 // Massive bonus for empty pools
        
        // Risk scoring (1-10, higher = riskier)
        var riskScore: UFix64 = 5.0 // Base risk
        
        if staking == 0.0 {
            riskScore = 9.5 // Very high risk - why is no one staking?
        } else if staking < 10.0 {
            riskScore = 8.0 // High risk - low adoption
        } else if staking < 100.0 {
            riskScore = 6.0 // Medium risk
        } else if staking > 1000.0 {
            riskScore = 3.0 // Lower risk - established
        }
        
        // Token-specific risk adjustments
        if token == "SDM" {
            riskScore = riskScore + 2.0 // Unknown token
        } else if token == "USDC" {
            riskScore = riskScore - 1.0 // Stable token
        }
        
        // Opportunity score (reward per unit / risk)
        let opportunityScore = rewardPerUnit / (riskScore * riskScore) // Square risk penalty
        
        // Generate recommendation
        var recommendation = ""
        if pid == 14 {
            recommendation = "EXTREME CAUTION: 1805 RPS with 0 staking is suspicious. Test with $10 max."
        } else if pid == 5 {
            recommendation = "HIGH YIELD: 116.76 RPS but unknown SDM token. Medium risk."
        } else if pid == 19 {
            recommendation = "OPPORTUNITY: 0.199 RPS with minimal competition. Good risk/reward."
        } else if pid == 12 {
            recommendation = "LOW COMPETITION: Only 0.61 total staking. Consider small position."
        } else if rewardPerUnit > 0.001 {
            recommendation = "DECENT: Above-average reward per unit staked."
        } else {
            recommendation = "STANDARD: Average reward rate, established pool."
        }
        
        let analysis = PoolAnalysis(
            pid: pid,
            rewardPerSecond: rps,
            totalStaking: staking,
            rewardPerUnit: rewardPerUnit,
            riskScore: riskScore,
            opportunityScore: opportunityScore,
            recommendation: recommendation
        )
        
        analyses.append(analysis)
    }
    
    // Sort by opportunity score (would need custom sorting in real implementation)
    return analyses
}

// Helper function to calculate estimated daily returns
access(all) fun calculateDailyReturns(rps: UFix64, myStaking: UFix64, totalStaking: UFix64): UFix64 {
    if totalStaking == 0.0 {
        return rps * 86400.0 // Full rewards if empty pool
    }
    
    let myShare = myStaking / (totalStaking + myStaking)
    let dailyRewards = rps * 86400.0 * myShare
    return dailyRewards
}

// Risk assessment helper
access(all) fun assessPoolRisk(pid: UInt64, totalStaking: UFix64, rps: UFix64): String {
    if pid == 14 && totalStaking == 0.0 {
        return "CRITICAL: Pool appears broken or exploitable. Avoid or test with minimal funds."
    }
    
    if rps > 100.0 {
        return "HIGH: Extremely high rewards suggest high-risk or speculative tokens."
    }
    
    if totalStaking < 1.0 {
        return "MEDIUM-HIGH: Very low adoption may indicate hidden issues."
    }
    
    if totalStaking > 1000.0 {
        return "LOW-MEDIUM: Established pool with decent adoption."
    }
    
    return "MEDIUM: Standard risk profile for DeFi farming."
}