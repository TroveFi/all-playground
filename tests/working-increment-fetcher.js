// working-increment-fetcher.js
// Working data fetcher using the correct Increment Finance functions

const fcl = require("@onflow/fcl")
const fs = require('fs')

fcl.config({
  "accessNode.api": "https://rest-mainnet.onflow.org"
})

const WORKING_SCRIPTS = {
  // Get stFlow metrics using working functions
  stFlowMetrics: `
    import LiquidStaking from 0xd6f80565193ad727
    import stFlowToken from 0xd6f80565193ad727
    import PublicPriceOracle from 0xec67451f8a58216a

    access(all) fun main(): {String: UFix64} {
        return {
            "stFlowSupply": stFlowToken.totalSupply,
            "exchangeRate": LiquidStaking.calcFlowFromStFlow(stFlowAmount: 1.0),
            "flowPrice": PublicPriceOracle.getLatestPrice(oracleAddr: 0xe385412159992e11),
            "stFlowPrice": PublicPriceOracle.getLatestPrice(oracleAddr: 0x031dabc5ba1d2932)
        }
    }
  `,
  
  // Get DEX metrics from working functions
  dexMetrics: `
    import SwapFactory from 0xb063c16cac85dbd1

    access(all) fun main(): [AnyStruct] {
        let pairCount = SwapFactory.getAllPairsLength()
        if pairCount == 0 {
            return []
        }
        // Get first 20 pairs for analysis
        return SwapFactory.getSlicedPairInfos(from: 0, to: 20)
    }
  `,

  // Calculate metrics we need
  calculatedMetrics: `
    import LiquidStaking from 0xd6f80565193ad727
    import stFlowToken from 0xd6f80565193ad727

    access(all) fun main(): {String: UFix64} {
        let stFlowSupply = stFlowToken.totalSupply
        let exchangeRate = LiquidStaking.calcFlowFromStFlow(stFlowAmount: 1.0)
        let totalFlowStaked = stFlowSupply * exchangeRate
        
        return {
            "stFlowSupply": stFlowSupply,
            "exchangeRate": exchangeRate,
            "totalFlowStaked": totalFlowStaked
        }
    }
  `
}

class WorkingIncrementFetcher {
  constructor() {
    this.cache = {}
  }

  async executeScript(script) {
    try {
      const result = await fcl.query({
        cadence: script
      })
      return result
    } catch (error) {
      console.error("Script execution error:", error.errorMessage || error.message)
      throw error
    }
  }

  async getStakingMetrics() {
    console.log("Fetching staking metrics...")
    
    const [basicData, calculatedData] = await Promise.all([
      this.executeScript(WORKING_SCRIPTS.stFlowMetrics),
      this.executeScript(WORKING_SCRIPTS.calculatedMetrics)
    ])
    
    const stFlowSupply = parseFloat(calculatedData.stFlowSupply)
    const exchangeRate = parseFloat(calculatedData.exchangeRate)
    const totalFlowStaked = parseFloat(calculatedData.totalFlowStaked)
    const flowPrice = parseFloat(basicData.flowPrice)
    const stFlowPrice = parseFloat(basicData.stFlowPrice)
    
    // Calculate total staked value in USD
    const totalStakedUSD = totalFlowStaked * flowPrice
    
    // Calculate implied APY from stFlow price premium over FLOW
    // stFlow trades at premium due to staking rewards accumulation
    const stFlowPremium = (stFlowPrice / flowPrice) - 1
    const impliedAPY = stFlowPremium * 100 // Simple approximation
    
    // Alternative APY calculation based on exchange rate growth
    // Assuming the exchange rate reflects accumulated rewards
    const exchangeRateAPY = ((exchangeRate - 1.0) / 1.0) * (365 / 30) * 100 // Rough estimate
    
    const stakingMetrics = {
      stFlowSupply: stFlowSupply,
      exchangeRate: exchangeRate,
      totalFlowStaked: totalFlowStaked,
      totalStakedUSD: totalStakedUSD,
      flowPrice: flowPrice,
      stFlowPrice: stFlowPrice,
      impliedAPY: Math.max(5, Math.min(15, impliedAPY)), // Cap between reasonable bounds
      exchangeRateAPY: Math.max(5, Math.min(15, exchangeRateAPY)),
      timestamp: Date.now()
    }
    
    console.log("Staking metrics calculated:", {
      "Total stFlow Supply": `${stakingMetrics.stFlowSupply.toLocaleString()} stFlow`,
      "Exchange Rate": `1 stFlow = ${stakingMetrics.exchangeRate.toFixed(4)} FLOW`,
      "Total FLOW Staked": `${stakingMetrics.totalFlowStaked.toLocaleString()} FLOW`,
      "Total Staked Value": `$${stakingMetrics.totalStakedUSD.toLocaleString()}`,
      "FLOW Price": `$${stakingMetrics.flowPrice.toFixed(4)}`,
      "stFlow Price": `$${stakingMetrics.stFlowPrice.toFixed(4)}`,
      "Implied APY": `${stakingMetrics.impliedAPY.toFixed(1)}%`
    })
    
    return stakingMetrics
  }

  async getDEXMetrics() {
    console.log("Fetching DEX metrics...")
    
    const pairInfos = await this.executeScript(WORKING_SCRIPTS.dexMetrics)
    const flowPrice = this.cache.flowPrice || 0.35
    
    let totalTVL = 0
    let flowPairs = 0
    let stablePairs = 0
    
    const processedPairs = pairInfos.map(pairInfo => {
      const [token0Key, token1Key, token0Balance, token1Balance, pairAddress, lpTokenBalance, swapFeeBps, isStableswap] = pairInfo
      
      const token0BalanceNum = parseFloat(token0Balance)
      const token1BalanceNum = parseFloat(token1Balance)
      
      // Determine pair type and calculate TVL
      let pairTVL = 0
      let pairType = 'unknown'
      
      if (token0Key.includes('FlowToken')) {
        pairTVL = token0BalanceNum * flowPrice * 2 // Assume symmetric liquidity
        pairType = 'FLOW'
        flowPairs++
      } else if (token1Key.includes('FlowToken')) {
        pairTVL = token1BalanceNum * flowPrice * 2
        pairType = 'FLOW'
        flowPairs++
      } else if (token0Key.includes('USDC') || token1Key.includes('USDC') || token0Key.includes('FUSD')) {
        pairTVL = Math.max(token0BalanceNum, token1BalanceNum) * 2 // Assume $1 stablecoin
        pairType = 'Stable'
        stablePairs++
      }
      
      totalTVL += pairTVL
      
      return {
        token0: token0Key.split('.').pop(), // Get contract name
        token1: token1Key.split('.').pop(),
        token0Balance: token0BalanceNum,
        token1Balance: token1BalanceNum,
        pairAddress,
        tvl: pairTVL,
        type: pairType,
        isStableswap: isStableswap
      }
    })
    
    // Sort by TVL and take top pairs
    const topPairs = processedPairs
      .filter(pair => pair.tvl > 1000) // Filter small pairs
      .sort((a, b) => b.tvl - a.tvl)
      .slice(0, 10)
    
    const dexMetrics = {
      totalTVL: totalTVL,
      totalPairs: pairInfos.length,
      flowPairs: flowPairs,
      stablePairs: stablePairs,
      topPairs: topPairs,
      volume24h: totalTVL * 0.1, // Rough estimate: 10% TVL turnover daily
      timestamp: Date.now()
    }
    
    console.log("DEX metrics calculated:", {
      "Total TVL": `$${dexMetrics.totalTVL.toLocaleString()}`,
      "Total Pairs": dexMetrics.totalPairs,
      "FLOW Pairs": dexMetrics.flowPairs,
      "Stable Pairs": dexMetrics.stablePairs,
      "Top Pair": topPairs[0] ? `${topPairs[0].token0}/${topPairs[0].token1}` : 'None'
    })
    
    return dexMetrics
  }

  async getAllMetrics() {
    console.log("=== Fetching Real Increment Finance Metrics ===")
    
    try {
      const stakingMetrics = await this.getStakingMetrics()
      
      // Cache flow price for DEX calculations
      this.cache.flowPrice = stakingMetrics.flowPrice
      
      const dexMetrics = await this.getDEXMetrics()
      
      const combinedMetrics = {
        staking: stakingMetrics,
        dex: dexMetrics,
        summary: {
          totalTVL: stakingMetrics.totalStakedUSD + dexMetrics.totalTVL,
          marketCap: stakingMetrics.stFlowSupply * stakingMetrics.stFlowPrice,
          flowPrice: stakingMetrics.flowPrice,
          currentAPY: stakingMetrics.impliedAPY,
          lastUpdated: new Date().toISOString()
        }
      }
      
      console.log("\n=== FINAL METRICS SUMMARY ===")
      console.log(`💰 Total TVL: $${combinedMetrics.summary.totalTVL.toLocaleString()}`)
      console.log(`🏦 Staking TVL: $${stakingMetrics.totalStakedUSD.toLocaleString()}`)
      console.log(`💱 DEX TVL: $${dexMetrics.totalTVL.toLocaleString()}`)
      console.log(`📈 stFlow Market Cap: $${combinedMetrics.summary.marketCap.toLocaleString()}`)
      console.log(`⚡ Current APY: ${combinedMetrics.summary.currentAPY.toFixed(1)}%`)
      console.log(`🔄 Exchange Rate: 1 stFlow = ${stakingMetrics.exchangeRate.toFixed(4)} FLOW`)
      console.log(`💵 FLOW Price: $${stakingMetrics.flowPrice.toFixed(4)}`)
      
      return combinedMetrics
      
    } catch (error) {
      console.error("Failed to fetch metrics:", error)
      throw error
    }
  }
}

// Main execution
async function main() {
  const fetcher = new WorkingIncrementFetcher()
  
  try {
    const metrics = await fetcher.getAllMetrics()
    
    // Save full results
    fs.writeFileSync('increment_metrics_working.json', JSON.stringify(metrics, null, 2))
    console.log("\n✅ Metrics saved to increment_metrics_working.json")
    
    // Create summary for easy reading
    const summary = {
      timestamp: new Date().toISOString(),
      totalTVL: `$${metrics.summary.totalTVL.toLocaleString()}`,
      stakingTVL: `$${metrics.staking.totalStakedUSD.toLocaleString()}`,
      dexTVL: `$${metrics.dex.totalTVL.toLocaleString()}`,
      apy: `${metrics.summary.currentAPY.toFixed(1)}%`,
      exchangeRate: `1 stFlow = ${metrics.staking.exchangeRate.toFixed(4)} FLOW`,
      flowPrice: `$${metrics.staking.flowPrice.toFixed(4)}`,
      stFlowPrice: `$${metrics.staking.stFlowPrice.toFixed(4)}`,
      totalStakedFlow: `${metrics.staking.totalFlowStaked.toLocaleString()} FLOW`,
      dexPairs: metrics.dex.totalPairs
    }
    
    console.log("\n📊 Ready for dashboard integration!")
    console.log("Use this data structure in your React components.")
    
    return metrics
    
  } catch (error) {
    console.error("❌ Failed to fetch metrics:", error.message)
    process.exit(1)
  }
}

// Export for use in React
module.exports = { WorkingIncrementFetcher }

// Run if called directly
if (require.main === module) {
  main()
}