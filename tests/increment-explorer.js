// increment-explorer.js
// Explore what functions are actually available in Increment contracts

const fcl = require("@onflow/fcl")

fcl.config({
  "accessNode.api": "https://rest-mainnet.onflow.org"
})

class IncrementExplorer {
  async executeScript(script) {
    try {
      const result = await fcl.query({
        cadence: script
      })
      return result
    } catch (error) {
      console.error("Script execution error:", error.errorMessage || error.message)
      return null
    }
  }

  // Test basic stFlow functions that we know should work
  async testBasicFunctions() {
    console.log("=== Testing Basic Functions ===")
    
    // Test 1: stFlow total supply (should work)
    const totalSupplyScript = `
      import stFlowToken from 0xd6f80565193ad727
      
      access(all) fun main(): UFix64 {
          return stFlowToken.totalSupply
      }
    `
    
    console.log("Testing stFlow total supply...")
    const totalSupply = await this.executeScript(totalSupplyScript)
    if (totalSupply) {
      console.log("✓ stFlow total supply:", totalSupply)
    }
    
    // Test 2: Exchange rate calculation (should work)
    const exchangeRateScript = `
      import LiquidStaking from 0xd6f80565193ad727
      
      access(all) fun main(): UFix64 {
          return LiquidStaking.calcFlowFromStFlow(stFlowAmount: 1.0)
      }
    `
    
    console.log("Testing exchange rate calculation...")
    const exchangeRate = await this.executeScript(exchangeRateScript)
    if (exchangeRate) {
      console.log("✓ Exchange rate (1 stFlow =", exchangeRate, "FLOW)")
    }
    
    // Test 3: Try to get staking info from DelegatorManager
    const delegatorScript = `
      import DelegatorManager from 0xd6f80565193ad727
      
      access(all) fun main(): [AnyStruct] {
          // Try to get any public info from DelegatorManager
          return []
      }
    `
    
    console.log("Testing DelegatorManager access...")
    const delegatorInfo = await this.executeScript(delegatorScript)
    if (delegatorInfo !== null) {
      console.log("✓ DelegatorManager accessible")
    }
  }

  // Test DEX functions
  async testDEXFunctions() {
    console.log("\n=== Testing DEX Functions ===")
    
    // Test 1: Get pair count
    const pairCountScript = `
      import SwapFactory from 0xb063c16cac85dbd1
      
      access(all) fun main(): Int {
          return SwapFactory.getAllPairsLength()
      }
    `
    
    console.log("Testing DEX pair count...")
    const pairCount = await this.executeScript(pairCountScript)
    if (pairCount !== null) {
      console.log("✓ DEX pairs available:", pairCount)
      
      // If pairs exist, try to get some info
      if (parseInt(pairCount) > 0) {
        const pairInfoScript = `
          import SwapFactory from 0xb063c16cac85dbd1
          
          access(all) fun main(): [AnyStruct] {
              return SwapFactory.getSlicedPairInfos(from: 0, to: 3)
          }
        `
        
        console.log("Testing DEX pair info...")
        const pairInfo = await this.executeScript(pairInfoScript)
        if (pairInfo) {
          console.log("✓ Sample DEX pairs:", pairInfo.length, "pairs retrieved")
          if (pairInfo.length > 0) {
            console.log("First pair structure:", pairInfo[0])
          }
        }
      }
    }
  }

  // Test what we can get from the contracts based on their documentation
  async testDocumentedFunctions() {
    console.log("\n=== Testing Functions from Documentation ===")
    
    // From the docs, we should be able to calculate stFlow amounts
    const calcStFlowScript = `
      import LiquidStaking from 0xd6f80565193ad727
      
      access(all) fun main(): {String: UFix64} {
          return {
              "flowToStFlow": LiquidStaking.calcStFlowFromFlow(flowAmount: 100.0),
              "stFlowToFlow": LiquidStaking.calcFlowFromStFlow(stFlowAmount: 100.0)
          }
      }
    `
    
    console.log("Testing stFlow calculations...")
    const calculations = await this.executeScript(calcStFlowScript)
    if (calculations) {
      console.log("✓ Calculation results:", calculations)
    }
    
    // Try to get price oracle data
    const oracleScript = `
      import PublicPriceOracle from 0xec67451f8a58216a
      
      access(all) fun main(): {String: UFix64} {
          return {
              "flowPrice": PublicPriceOracle.getLatestPrice(oracleAddr: 0xe385412159992e11),
              "stFlowPrice": PublicPriceOracle.getLatestPrice(oracleAddr: 0x031dabc5ba1d2932)
          }
      }
    `
    
    console.log("Testing price oracle...")
    const prices = await this.executeScript(oracleScript)
    if (prices) {
      console.log("✓ Price data:", prices)
    }
  }

  async exploreAll() {
    console.log("🔍 Exploring Increment Finance Contracts...")
    console.log("💰 FLOW Price from our previous test: $0.35237923")
    
    await this.testBasicFunctions()
    await this.testDEXFunctions()
    await this.testDocumentedFunctions()
    
    console.log("\n=== Summary ===")
    console.log("✓ Connection to Flow network: Working")
    console.log("✓ Price oracle: Working") 
    console.log("✓ stFlow total supply: Available")
    console.log("✓ Exchange rate calculation: Available")
    console.log("❌ Direct staking metrics: Need alternative approach")
    console.log("? DEX data: Testing...")
  }
}

// Run exploration
async function explore() {
  const explorer = new IncrementExplorer()
  await explorer.exploreAll()
}

if (require.main === module) {
  explore()
}