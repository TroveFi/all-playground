// increment-real-data.js
// Clean implementation to get real APY and volume data from Increment Finance

const flowClient = require("@onflow/fcl")
const axios = require('axios')
const fs = require('fs')

// Configure Flow client
flowClient.config({
  "accessNode.api": "https://rest-mainnet.onflow.org"
})

const FLOW_API = "https://rest-mainnet.onflow.org"

class IncrementDataTracker {
  constructor() {
    this.apyDataFile = 'increment_apy_history.json'
    this.loadHistoricalData()
  }

  loadHistoricalData() {
    try {
      if (fs.existsSync(this.apyDataFile)) {
        const data = fs.readFileSync(this.apyDataFile, 'utf8')
        this.historicalData = JSON.parse(data)
      } else {
        this.historicalData = {
          exchangeRates: [],
          lastUpdate: null
        }
      }
    } catch (error) {
      console.error("Error loading historical data:", error)
      this.historicalData = { exchangeRates: [], lastUpdate: null }
    }
  }

  saveHistoricalData() {
    try {
      fs.writeFileSync(this.apyDataFile, JSON.stringify(this.historicalData, null, 2))
    } catch (error) {
      console.error("Error saving historical data:", error)
    }
  }

  async executeScript(cadenceScript) {
    try {
      const result = await flowClient.query({ cadence: cadenceScript })
      return result
    } catch (error) {
      console.error("Script execution error:", error.errorMessage || error.message)
      throw error
    }
  }

  async getLatestBlockHeight() {
    try {
      const response = await axios.get(`${FLOW_API}/v1/blocks?height=sealed`)
      return parseInt(response.data[0].header.height)
    } catch (error) {
      console.error("Error getting latest block:", error.message)
      throw error
    }
  }

  async trackExchangeRate() {
    console.log("Tracking current exchange rate...")
    
    const script = `
      import LiquidStaking from 0xd6f80565193ad727
      
      access(all) fun main(): {String: UFix64} {
          return {
              "exchangeRate": LiquidStaking.calcFlowFromStFlow(stFlowAmount: 1.0),
              "timestamp": getCurrentBlock().timestamp
          }
      }
    `
    
    const result = await this.executeScript(script)
    const rate = parseFloat(result.exchangeRate)
    const timestamp = parseFloat(result.timestamp)
    
    // Only add if it's a new day or different rate
    const lastEntry = this.historicalData.exchangeRates[this.historicalData.exchangeRates.length - 1]
    const oneDayAgo = timestamp - (24 * 60 * 60)
    
    if (!lastEntry || lastEntry.timestamp < oneDayAgo || Math.abs(lastEntry.rate - rate) > 0.0001) {
      this.historicalData.exchangeRates.push({
        rate: rate,
        timestamp: timestamp,
        date: new Date(timestamp * 1000).toISOString()
      })
      
      // Keep only last 365 data points
      if (this.historicalData.exchangeRates.length > 365) {
        this.historicalData.exchangeRates = this.historicalData.exchangeRates.slice(-365)
      }
      
      this.saveHistoricalData()
      console.log(`Exchange rate recorded: ${rate} at ${new Date(timestamp * 1000).toLocaleDateString()}`)
    }
    
    return rate
  }

  calculateAPY() {
    const rates = this.historicalData.exchangeRates
    
    if (rates.length < 2) {
      return {
        apy: null,
        message: `Need more data points. Currently have ${rates.length}, need at least 2`,
        dataPoints: rates.length
      }
    }

    // Sort by timestamp
    rates.sort((a, b) => a.timestamp - b.timestamp)
    
    const latest = rates[rates.length - 1]
    const earliest = rates[0]
    
    const timeSpanDays = (latest.timestamp - earliest.timestamp) / (24 * 60 * 60)
    const rateGrowth = (latest.rate - earliest.rate) / earliest.rate
    const annualizedGrowth = (rateGrowth * 365) / timeSpanDays
    const apy = annualizedGrowth * 100

    return {
      apy: apy,
      timeSpanDays: timeSpanDays,
      rateChange: {
        from: earliest.rate,
        to: latest.rate,
        growth: rateGrowth
      },
      dataPoints: rates.length,
      message: `APY calculated from ${timeSpanDays.toFixed(1)} days of data`
    }
  }

  async getPairAddresses() {
    console.log("Getting swap pair addresses...")
    
    const script = `
      import SwapFactory from 0xb063c16cac85dbd1
      
      access(all) fun main(): [Address] {
        let pairCount = SwapFactory.getAllPairsLength()
        if pairCount == 0 {
          return []
        }
        return SwapFactory.getSlicedPairs(from: 0, to: UInt64(pairCount))
      }
    `
    
    try {
      const result = await this.executeScript(script)
      console.log(`Found ${result.length} swap pairs`)
      return result
    } catch (error) {
      console.error("Error getting pair addresses:", error)
      return []
    }
  }

  async getSwapEvents(startHeight, endHeight) {
    console.log(`Fetching swap events from blocks ${startHeight} to ${endHeight}...`)
    
    const pairAddresses = await this.getPairAddresses()
    if (pairAddresses.length === 0) {
      console.log("No pairs found")
      return []
    }

    const allEvents = []
    
    // Check first 3 pairs to avoid rate limits, and try a few different block ranges
    for (let i = 0; i < Math.min(pairAddresses.length, 3); i++) {
      const pairAddr = pairAddresses[i]
      const eventType = `A.${pairAddr.replace('0x', '')}.SwapPair.Swap`
      
      try {
        console.log(`Checking pair ${i + 1}/3: ${pairAddr}`)
        
        // Try smaller ranges first
        const ranges = [
          { start: endHeight - 100, end: endHeight },
          { start: endHeight - 249, end: endHeight - 100 },
          { start: startHeight, end: startHeight + 100 }
        ]
        
        for (const range of ranges) {
          try {
            const url = `${FLOW_API}/v1/events`
            const params = {
              type: eventType,
              start_height: range.start,
              end_height: range.end
            }
            
            console.log(`  Trying range ${range.start} to ${range.end}`)
            const response = await axios.get(url, { params })
            
            // Debug: log the response structure
            if (response.data && response.data.length > 0) {
              console.log(`  API Response structure:`, JSON.stringify(response.data[0], null, 2).substring(0, 500) + '...')
            }
            
            if (response.data && response.data.length > 0) {
              console.log(`  Found ${response.data.length} blocks with swap events`)
              
              for (const blockEvents of response.data) {
                // Handle different response structures
                let eventsArray = []
                
                if (blockEvents.events && Array.isArray(blockEvents.events)) {
                  eventsArray = blockEvents.events
                } else if (Array.isArray(blockEvents)) {
                  // Sometimes the events are directly in the array
                  eventsArray = blockEvents
                } else if (blockEvents.payload) {
                  // Sometimes there's a single event
                  eventsArray = [blockEvents]
                }
                
                console.log(`    Processing ${eventsArray.length} events in block ${blockEvents.block_height || 'unknown'}`)
                
                for (const event of eventsArray) {
                  allEvents.push({
                    pairAddress: pairAddr,
                    blockHeight: blockEvents.block_height || event.block_height,
                    blockTimestamp: blockEvents.block_timestamp || event.block_timestamp,
                    transactionId: event.transaction_id,
                    data: event.payload
                  })
                }
              }
              break // Found events, move to next pair
            } else {
              console.log(`  No events in this range`)
            }
            
            // Add delay between range checks
            await new Promise(resolve => setTimeout(resolve, 200))
            
          } catch (rangeError) {
            console.log(`  Range ${range.start}-${range.end} failed: ${rangeError.response?.data?.message || rangeError.message}`)
          }
        }
        
        // Add delay between pairs
        await new Promise(resolve => setTimeout(resolve, 500))
        
      } catch (error) {
        console.error(`Error with pair ${pairAddr}:`, error.response?.data?.message || error.message)
      }
    }
    
    console.log(`Total swap events collected: ${allEvents.length}`)
    return allEvents
  }

  parseSwapEvent(event) {
    try {
      const data = event.data
      
      if (data && (data.amount0In !== undefined || data.amount1In !== undefined)) {
        const amount0In = parseFloat(data.amount0In || "0")
        const amount1In = parseFloat(data.amount1In || "0")
        const amount0Out = parseFloat(data.amount0Out || "0")
        const amount1Out = parseFloat(data.amount1Out || "0")
        
        // Volume is the input amount
        const volumeIn = amount0In > 0 ? amount0In : amount1In
        
        return {
          pairAddress: event.pairAddress,
          volumeIn: volumeIn,
          amount0In: amount0In,
          amount1In: amount1In,
          amount0Out: amount0Out,
          amount1Out: amount1Out,
          token0Type: data.amount0Type || "",
          token1Type: data.amount1Type || "",
          timestamp: event.blockTimestamp,
          txId: event.transactionId
        }
      }
    } catch (error) {
      console.error("Error parsing swap event:", error)
    }
    return null
  }

  async calculateVolume() {
    console.log("=== Calculating Real Volume ===")
    
    try {
      const latestHeight = await this.getLatestBlockHeight()
      console.log(`Latest block height: ${latestHeight}`)
      
      // Use 249 blocks (API limit is actually <250) which is about 4 minutes on Flow
      const blocksToCheck = 249
      const startHeight = Math.max(1, latestHeight - blocksToCheck)
      
      let events = await this.getSwapEvents(startHeight, latestHeight)
      
      // If no recent events found, try looking further back
      if (events.length === 0) {
        console.log("No recent events found, trying last hour...")
        const oneHourBlocks = 3600 // 1 hour = 3600 seconds = 3600 blocks
        const olderStartHeight = Math.max(1, latestHeight - oneHourBlocks)
        const olderEndHeight = latestHeight - blocksToCheck
        events = await this.getSwapEvents(olderStartHeight, olderEndHeight)
      }
      
      let totalVolume = 0
      let swapCount = 0
      const volumeByPair = {}
      const swapDetails = []
      
      for (const event of events) {
        const parsed = this.parseSwapEvent(event)
        if (parsed) {
          const swapVolume = parsed.volumeIn
          totalVolume += swapVolume
          swapCount++
          
          const token0Name = parsed.token0Type.split('.').pop() || 'Unknown'
          const token1Name = parsed.token1Type.split('.').pop() || 'Unknown'
          const pairKey = `${token0Name}/${token1Name}`
          
          if (!volumeByPair[pairKey]) {
            volumeByPair[pairKey] = 0
          }
          volumeByPair[pairKey] += swapVolume
          
          swapDetails.push({
            pair: pairKey,
            volume: swapVolume,
            timestamp: parsed.timestamp
          })
        }
      }
      
      // Extrapolate to 24 hours
      const hoursInPeriod = blocksToCheck / 3600 // Flow: ~1 block per second
      const estimated24hVolume = totalVolume * (24 / hoursInPeriod)
      
      const results = {
        totalVolumeRaw: totalVolume,
        estimated24hVolume: estimated24hVolume,
        swapCount: swapCount,
        volumeByPair: volumeByPair,
        blockRange: {
          start: startHeight,
          end: latestHeight,
          totalBlocks: latestHeight - startHeight,
          hoursRepresented: hoursInPeriod
        },
        dataQuality: events.length > 0 ? "Real on-chain Swap events from SwapPair contracts" : "No swap events found in recent blocks",
        timestamp: Date.now()
      }
      
      console.log("=== VOLUME RESULTS ===")
      console.log(`Raw Volume (${hoursInPeriod.toFixed(2)}h): ${totalVolume.toLocaleString()}`)
      console.log(`Estimated 24h Volume: ${estimated24hVolume.toLocaleString()}`)
      console.log(`Total Swaps: ${swapCount}`)
      console.log(`Blocks Analyzed: ${results.blockRange.totalBlocks}`)
      
      if (events.length === 0) {
        console.log("⚠️  No swap events found - Increment may have low trading volume right now")
        console.log("   Try running again later or check a longer time period")
      }
      
      if (Object.keys(volumeByPair).length > 0) {
        console.log(`Top Pairs by Volume:`)
        const sortedPairs = Object.entries(volumeByPair)
          .sort(([,a], [,b]) => b - a)
          .slice(0, 3)
        
        for (const [pair, volume] of sortedPairs) {
          console.log(`  ${pair}: ${volume.toLocaleString()}`)
        }
      }
      
      return results
      
    } catch (error) {
      console.error("Failed to calculate volume:", error)
      throw error
    }
  }

  async getAllData() {
    console.log("=== Getting Real Increment Finance Data ===")
    
    try {
      // Track current exchange rate for APY calculation
      await this.trackExchangeRate()
      
      // Calculate APY from historical data
      const apyData = this.calculateAPY()
      
      // Calculate volume from recent swap events
      const volumeData = await this.calculateVolume()
      
      // Update last update timestamp
      this.historicalData.lastUpdate = new Date().toISOString()
      this.saveHistoricalData()
      
      const results = {
        apy: {
          value: apyData.apy,
          dataPoints: apyData.dataPoints,
          timeSpan: apyData.timeSpanDays,
          message: apyData.message
        },
        volume: {
          raw: volumeData.totalVolumeRaw,
          estimated24h: volumeData.estimated24hVolume,
          swapCount: volumeData.swapCount,
          topPairs: volumeData.volumeByPair,
          dataQuality: volumeData.dataQuality
        },
        timestamp: new Date().toISOString()
      }
      
      console.log("\n=== FINAL RESULTS ===")
      console.log(`APY: ${apyData.apy ? apyData.apy.toFixed(3) + '%' : 'Need more historical data'}`)
      console.log(`24h Volume: ${volumeData.estimated24hVolume.toLocaleString()} (estimated)`)
      console.log(`Swaps in period: ${volumeData.swapCount}`)
      console.log(`APY Data Points: ${apyData.dataPoints}`)
      
      // Save combined results
      fs.writeFileSync('increment_real_data.json', JSON.stringify(results, null, 2))
      console.log("Data saved to increment_real_data.json")
      
      return results
      
    } catch (error) {
      console.error("Failed to get real data:", error)
      throw error
    }
  }
}

// Main execution
async function main() {
  const tracker = new IncrementDataTracker()
  
  try {
    const results = await tracker.getAllData()
    
    console.log("\n=== SUCCESS ===")
    console.log("Real data collection complete")
    console.log("Run this script daily to build APY historical data")
    
    return results
    
  } catch (error) {
    console.error("Failed:", error.message)
    process.exit(1)
  }
}

// Export for use in other files
module.exports = { IncrementDataTracker }

// Run if called directly
if (require.main === module) {
  main()
}