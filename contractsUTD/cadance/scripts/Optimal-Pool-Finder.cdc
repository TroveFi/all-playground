// Simple script to determine the optimal pool based on current conditions
// Run this first to get recommendations, then execute the strategy

access(all) fun main(): {String: AnyStruct} {
    
    // Current pool data (you'd update this with real-time data)
    let pools = {
        "Flow-stFlow-204": {
            "type": "LP",
            "apr": 7.69,
            "tvl": 116736.41,
            "risk": 2.0, // Low risk
            "liquidity": "High",
            "tokens": ["FLOW", "stFLOW"],
            "swapsNeeded": 1 // FLOW -> stFLOW
        },
        "stFlow-LOPPY-205": {
            "type": "LP", 
            "apr": 111.43,
            "tvl": 1693.62,
            "risk": 8.5, // High risk - low TVL, unknown token
            "liquidity": "Low",
            "tokens": ["stFLOW", "LOPPY"],
            "swapsNeeded": 2 // FLOW -> stFLOW -> LOPPY
        },
        "stFlow-MVP-206": {
            "type": "LP",
            "apr": 30.85, 
            "tvl": 2831.55,
            "risk": 6.0, // Medium risk
            "liquidity": "Low",
            "tokens": ["stFLOW", "MVP"],
            "swapsNeeded": 2 // FLOW -> stFLOW -> MVP
        },
        "LOPPY-Staking-20": {
            "type": "Staking",
            "apr": 113.60,
            "tvl": 1663.42, 
            "risk": 9.0, // Very high risk - single token exposure to unknown asset
            "liquidity": "Low",
            "tokens": ["LOPPY"],
            "swapsNeeded": 2 // FLOW -> stFLOW -> LOPPY
        },
        "MVP-Staking-14": {
            "type": "Staking",
            "apr": 14.95,
            "tvl": 1948.49,
            "risk": 5.0, // Medium risk 
            "liquidity": "Low", 
            "tokens": ["MVP"],
            "swapsNeeded": 2 // FLOW -> stFLOW -> MVP
        }
    }
    
    // Risk tolerance settings (customize based on user preference)
    let riskTolerance = 5.0 // 1-10 scale, higher = more risk tolerant
    let minimumAPR = 10.0 // Minimum APR to consider
    let minimumTVL = 1000.0 // Minimum TVL for safety
    
    // Calculate risk-adjusted returns
    var bestPool = ""
    var bestScore = 0.0
    var recommendations: [AnyStruct] = []
    
    for poolId in pools.keys {
        let pool = pools[poolId]! as! {String: AnyStruct}
        let apr = pool["apr"]! as! UFix64
        let risk = pool["risk"]! as! UFix64
        let tvl = pool["tvl"]! as! UFix64
        
        // Skip pools that don't meet minimum criteria
        if apr < minimumAPR || tvl < minimumTVL {
            continue
        }
        
        // Skip pools with risk above tolerance
        if risk > riskTolerance {
            continue
        }
        
        // Calculate risk-adjusted score (APR / Risk)
        let riskAdjustedReturn = apr / risk
        let score = riskAdjustedReturn * (tvl / 10000.0) // TVL bonus
        
        if score > bestScore {
            bestScore = score
            bestPool = poolId
        }
        
        recommendations.append({
            "poolId": poolId,
            "apr": apr,
            "risk": risk,
            "tvl": tvl,
            "score": score,
            "recommendation": getRecommendation(apr: apr, risk: risk, tvl: tvl)
        })
    }
    
    return {
        "recommendedPool": bestPool,
        "bestScore": bestScore,
        "allPools": recommendations,
        "analysis": getAnalysis(),
        "riskWarning": getRiskWarning()
    }
}

access(all) fun getRecommendation(apr: UFix64, risk: UFix64, tvl: UFix64): String {
    if risk > 8.0 {
        return "HIGH RISK: Only for experienced DeFi users. High APR but significant loss potential."
    } else if risk > 5.0 {
        return "MEDIUM RISK: Good for diversification, but monitor position closely."
    } else if apr > 15.0 {
        return "RECOMMENDED: Good risk/reward ratio with decent TVL."
    } else {
        return "CONSERVATIVE: Safe option with moderate returns."
    }
}

access(all) fun getAnalysis(): {String: String} {
    return {
        "flowStFlow": "SAFEST - Established pair with good liquidity. 7.69% APR with low risk.",
        "stFlowLoppy": "HIGHEST YIELD - 111% APR but VERY HIGH RISK. Small TVL, unknown token.",
        "stFlowMvp": "BALANCED - 30.85% APR with moderate risk. Medium TVL.",
        "loppyStaking": "SPECULATIVE - 113% APR but pure speculation on LOPPY token.",
        "mvpStaking": "MODERATE - 14.95% APR, reasonable for conservative users."
    }
}

access(all) fun getRiskWarning(): String {
    return "WARNING: High APR pools often indicate high risk. Tokens like LOPPY and MVP are speculative and could lose significant value. Never invest more than you can afford to lose. Consider starting with small amounts to test strategies."
}

// Helper function to estimate swap costs
access(all) fun getSwapCosts(fromToken: String, toToken: String, amount: UFix64): UFix64 {
    // Estimated slippage + gas costs
    if fromToken == "FLOW" && toToken == "stFLOW" {
        return 0.0 // No cost for staking
    }
    
    // For DEX swaps, estimate 0.3% fee + 0.5% slippage on small pools
    return amount * 0.008 // 0.8% total cost estimate
}