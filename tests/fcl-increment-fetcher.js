// fcl-increment-fetcher.js
// Pure JavaScript version using FCL - no Flow CLI required

const fcl = require("@onflow/fcl")
const t = require("@onflow/types")

// Configure FCL for Flow mainnet
fcl.config({
  "accessNode.api": "https://rest-mainnet.onflow.org"
})

const CADENCE_SCRIPTS = {
  stFlowMetrics: `
    import LiquidStaking from 0xd6f80565193ad727
    import stFlowToken from 0xd6f80565193ad727

    access(all) fun main(): {String: UFix64} {
        return {
            "exchangeRate": LiquidStaking.calcFlowFromStFlow(stFlowAmount: 1.0),
            "totalStaked": LiquidStaking.getTotalValidStake(),
            "stFlowSupply": stFlowToken.totalSupply,
            "currentEpoch": LiquidStaking.getCurrentEpoch()
        }
    }
  `,
  
  dexMetrics: `
    import SwapFactory from 0xb063c16cac85dbd1

    access(all) fun main(): [AnyStruct] {
        let pairCount = SwapFactory.getAllPairsLength()
        if pairCount == 0 {
            return []
        }
        return SwapFactory.getSlicedPairInfos(from: 0, to: UInt64.max)
    }
  `,
  
  flowPrice: `
    import PublicPriceOracle from 0xec67451f8a58216a

    access(all) fun main(): UFix64 {
        return PublicPriceOracle.getLatestPrice(oracleAddr: 0xe385412159992e11)
    }
  `,

  // Simple test script to verify connection
  simpleTest: `
    access(all) fun main(): UFix64 {
        return 42.0
    }
  `
}

class FCLIncrementFetcher {
  constructor() {
    this.flowPrice = 0.34 // Fallback price
  }

  async executeScript(script) {
    try {
      console.log("Executing script...")
      const result = await fcl.query({
        cadence: script
      })
      console.log("Script result:", result)
      return result
    } catch (error) {
      console.error("Script execution error:", error)
      throw error
    }
  }

  async testConnection() {
    try {
      console.log("Testing FCL connection...")
      const result = await this.executeScript(CADENCE_SCRIPTS.simpleTest)
      console.log("Connection test result:", result)
      return result === "42.00000000" || result === 42.0
    } catch (error) {
      console.error("Connection test failed:", error)
      return false
    }
  }

  async getFlowPrice() {
    try {
      console.log("Fetching FLOW price from oracle...")
      const price = await this.executeScript(CADENCE_SCRIPTS.flowPrice)
      this.flowPrice = parseFloat(price)
      console.log("FLOW price:", this.flowPrice)
      return this.flowPrice
    } catch (error) {
      console.warn("Failed to fetch FLOW price, using fallback:", error.message)
      return this.flowPrice
    }
  }

  async getStakingMetrics() {
    try {
      console.log("Fetching staking metrics...")
      const data = await this.executeScript(CADENCE_SCRIPTS.stFlowMetrics)
      console.log("Raw staking data:", data)
      
      const totalStakedFlow = parseFloat(data.totalStaked)
      const totalStakedUSD = totalStakedFlow * this.flowPrice
      const exchangeRate = parseFloat(data.exchangeRate)
      
      // Calculate APY based on exchange rate appreciation
      const estimatedAPY = Math.max(0, ((exchangeRate - 1.0) * 52.14) * 100)
      
      const stakingMetrics = {
        stFlowFlowRate: exchangeRate,
        totalStakedFlow: totalStakedFlow,
        totalStakedUSD: totalStakedUSD,
        stFlowSupply: parseFloat(data.stFlowSupply),
        currentEpoch: parseInt(data.currentEpoch),
        estimatedAPY: estimatedAPY,
        timestamp: Date.now()
      }
      
      console.log("Processed staking metrics:", stakingMetrics)
      return stakingMetrics
    } catch (error) {
      console.error("Failed to fetch staking metrics:", error)
      throw error
    }
  }

  async getDEXMetrics() {
    try {
      console.log("Fetching DEX metrics...")
      const pairInfos = await this.executeScript(CADENCE_SCRIPTS.dexMetrics)
      console.log("Raw DEX data:", pairInfos)
      
      let totalTVL = 0
      const flowPrice = this.flowPrice
      
      const pairs = pairInfos.map(pairInfo => {
        const [token0Key, token1Key, token0Balance, token1Balance, pairAddress, lpTokenBalance] = pairInfo
        
        const token0BalanceNum = parseFloat(token0Balance)
        const token1BalanceNum = parseFloat(token1Balance)
        
        // Calculate TVL for this pair
        let pairTVL = 0
        if (token0Key.includes('FlowToken')) {
          pairTVL = token0BalanceNum * flowPrice * 2
        } else if (token1Key.includes('FlowToken')) {
          pairTVL = token1BalanceNum * flowPrice * 2
        } else if (token0Key.includes('USDC') || token1Key.includes('USDC')) {
          pairTVL = Math.max(token0BalanceNum, token1BalanceNum) * 2
        }
        
        totalTVL += pairTVL
        
        return {
          token0: token0Key,
          token1: token1Key,
          token0Balance: token0BalanceNum,
          token1Balance: token1BalanceNum,
          pairAddress,
          tvl: pairTVL
        }
      })
      
      const dexMetrics = {
        totalTVL: totalTVL,
        volume24h: 0, // Would need historical tracking
        pairCount: pairs.length,
        pairs: pairs,
        timestamp: Date.now()
      }
      
      console.log("Processed DEX metrics:", dexMetrics)
      return dexMetrics
    } catch (error) {
      console.error("Failed to fetch DEX metrics:", error)
      throw error
    }
  }

  async getAllMetrics() {
    try {
      console.log("=== Starting Increment Finance data fetch ===")
      
      // Test connection first
      const connectionOk = await this.testConnection()
      if (!connectionOk) {
        throw new Error("Failed to establish connection to Flow network")
      }
      console.log("✓ Connection to Flow network established")
      
      // Fetch FLOW price first
      await this.getFlowPrice()
      
      // Fetch all metrics
      const [stakingMetrics, dexMetrics] = await Promise.all([
        this.getStakingMetrics(),
        this.getDEXMetrics()
      ])
      
      const combinedMetrics = {
        staking: stakingMetrics,
        dex: dexMetrics,
        summary: {
          totalTVL: stakingMetrics.totalStakedUSD + dexMetrics.totalTVL,
          flowPrice: this.flowPrice,
          lastUpdated: new Date().toISOString()
        }
      }
      
      console.log("\n=== FINAL METRICS ===")
      console.log(`Total TVL: $${combinedMetrics.summary.totalTVL.toFixed(2)}`)
      console.log(`Total Staked FLOW: ${stakingMetrics.totalStakedFlow.toFixed(0)} FLOW`)
      console.log(`stFlow/FLOW Rate: ${stakingMetrics.stFlowFlowRate.toFixed(6)}`)
      console.log(`Estimated APY: ${stakingMetrics.estimatedAPY.toFixed(2)}%`)
      console.log(`DEX Pairs: ${dexMetrics.pairCount}`)
      console.log(`FLOW Price: $${this.flowPrice}`)
      
      return combinedMetrics
    } catch (error) {
      console.error("Failed to fetch all metrics:", error)
      throw error
    }
  }
}

// Test function
async function test() {
  const fetcher = new FCLIncrementFetcher()
  
  try {
    const metrics = await fetcher.getAllMetrics()
    
    // Save results
    const fs = require('fs')
    fs.writeFileSync('increment_metrics_fcl.json', JSON.stringify(metrics, null, 2))
    console.log("\n✓ Metrics saved to increment_metrics_fcl.json")
    
    return metrics
  } catch (error) {
    console.error("Test failed:", error)
    process.exit(1)
  }
}

// Export for use in other modules
module.exports = { FCLIncrementFetcher }

// Run test if called directly
if (require.main === module) {
  test()
}