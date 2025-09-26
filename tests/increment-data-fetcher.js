// increment-data-fetcher.js
// Test script to fetch Increment Finance metrics from Flow blockchain

const { exec } = require('child_process');
const fs = require('fs');

// Cadence script to get stFlow metrics
const stFlowMetricsScript = `
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
`;

// Cadence script to get DEX TVL and volume
const dexMetricsScript = `
import SwapFactory from 0xb063c16cac85dbd1

access(all) fun main(): [AnyStruct] {
    let pairCount = SwapFactory.getAllPairsLength()
    if pairCount == 0 {
        return []
    }
    return SwapFactory.getSlicedPairInfos(from: 0, to: UInt64.max)
}
`;

// Cadence script to get price from oracle
const priceScript = `
import PublicPriceOracle from 0xec67451f8a58216a

access(all) fun main(): UFix64 {
    return PublicPriceOracle.getLatestPrice(oracleAddr: 0xe385412159992e11)
}
`;

class IncrementDataFetcher {
    constructor() {
        this.flowPrice = 0.34; // Fallback price, will be updated from oracle
    }

    // Execute Cadence script using Flow CLI
    async executeScript(script, filename) {
        return new Promise((resolve, reject) => {
            // Write script to temporary file
            fs.writeFileSync(`temp_${filename}.cdc`, script);
            
            // Execute using Flow CLI
            exec(`flow scripts execute temp_${filename}.cdc --network mainnet`, (error, stdout, stderr) => {
                // Clean up temp file
                try { fs.unlinkSync(`temp_${filename}.cdc`); } catch {}
                
                if (error) {
                    console.error(`Error executing ${filename}:`, error);
                    reject(error);
                    return;
                }
                
                try {
                    // Parse the result - Flow CLI returns the result as a string
                    const result = JSON.parse(stdout.trim());
                    resolve(result);
                } catch (parseError) {
                    console.error(`Parse error for ${filename}:`, parseError);
                    console.log(`Raw output: ${stdout}`);
                    reject(parseError);
                }
            });
        });
    }

    // Alternative: Use FCL for browser/Node.js
    async executeFCLScript(script) {
        // If FCL is available, use this instead
        try {
            const fcl = require("@onflow/fcl");
            
            fcl.config({
                "accessNode.api": "https://rest-mainnet.onflow.org"
            });

            const result = await fcl.query({
                cadence: script
            });
            
            return result;
        } catch (error) {
            console.error("FCL execution error:", error);
            throw error;
        }
    }

    // Fetch FLOW price from oracle
    async getFlowPrice() {
        try {
            const price = await this.executeScript(priceScript, 'price');
            this.flowPrice = parseFloat(price);
            return this.flowPrice;
        } catch (error) {
            console.warn("Failed to fetch FLOW price, using fallback:", error.message);
            return this.flowPrice;
        }
    }

    // Fetch stFlow staking metrics
    async getStakingMetrics() {
        try {
            const data = await this.executeScript(stFlowMetricsScript, 'staking');
            const flowPrice = await this.getFlowPrice();
            
            const totalStakedFlow = parseFloat(data.totalStaked);
            const totalStakedUSD = totalStakedFlow * flowPrice;
            const exchangeRate = parseFloat(data.exchangeRate);
            
            // Calculate APY - stFlow appreciates against FLOW over time
            // This is a simplified calculation - real APY needs historical data
            const estimatedAPY = ((exchangeRate - 1.0) * 52.14) * 100; // Rough estimate
            
            return {
                stFlowFlowRate: exchangeRate,
                totalStakedFlow: totalStakedFlow,
                totalStakedUSD: totalStakedUSD,
                stFlowSupply: parseFloat(data.stFlowSupply),
                currentEpoch: parseInt(data.currentEpoch),
                estimatedAPY: Math.max(0, estimatedAPY),
                timestamp: Date.now()
            };
        } catch (error) {
            console.error("Failed to fetch staking metrics:", error);
            throw error;
        }
    }

    // Fetch DEX TVL and volume
    async getDEXMetrics() {
        try {
            const pairInfos = await this.executeScript(dexMetricsScript, 'dex');
            
            let totalTVL = 0;
            let totalVolume24h = 0; // This would need historical data
            const flowPrice = this.flowPrice;
            
            const pairs = pairInfos.map(pairInfo => {
                const [token0Key, token1Key, token0Balance, token1Balance, pairAddress, lpTokenBalance] = pairInfo;
                
                // Calculate TVL for this pair (simplified)
                const token0BalanceNum = parseFloat(token0Balance);
                const token1BalanceNum = parseFloat(token1Balance);
                
                // Rough TVL calculation - assumes one token is FLOW or USDC
                let pairTVL = 0;
                if (token0Key.includes('FlowToken')) {
                    pairTVL = token0BalanceNum * flowPrice * 2; // Double for both sides
                } else if (token1Key.includes('FlowToken')) {
                    pairTVL = token1BalanceNum * flowPrice * 2;
                } else if (token0Key.includes('USDC') || token1Key.includes('USDC')) {
                    pairTVL = Math.max(token0BalanceNum, token1BalanceNum) * 2;
                }
                
                totalTVL += pairTVL;
                
                return {
                    token0: token0Key,
                    token1: token1Key,
                    token0Balance: token0BalanceNum,
                    token1Balance: token1BalanceNum,
                    pairAddress,
                    tvl: pairTVL
                };
            });
            
            return {
                totalTVL: totalTVL,
                volume24h: totalVolume24h, // Would need to track swaps over time
                pairCount: pairs.length,
                pairs: pairs,
                timestamp: Date.now()
            };
        } catch (error) {
            console.error("Failed to fetch DEX metrics:", error);
            throw error;
        }
    }

    // Get all metrics
    async getAllMetrics() {
        try {
            console.log("Fetching Increment Finance metrics...");
            
            const [stakingMetrics, dexMetrics] = await Promise.all([
                this.getStakingMetrics(),
                this.getDEXMetrics()
            ]);
            
            const combinedMetrics = {
                staking: stakingMetrics,
                dex: dexMetrics,
                summary: {
                    totalTVL: stakingMetrics.totalStakedUSD + dexMetrics.totalTVL,
                    flowPrice: this.flowPrice,
                    lastUpdated: new Date().toISOString()
                }
            };
            
            console.log("Metrics fetched successfully:");
            console.log(JSON.stringify(combinedMetrics, null, 2));
            
            return combinedMetrics;
        } catch (error) {
            console.error("Failed to fetch all metrics:", error);
            throw error;
        }
    }
}

// Test the fetcher
async function test() {
    const fetcher = new IncrementDataFetcher();
    
    try {
        const metrics = await fetcher.getAllMetrics();
        
        // Save to file for inspection
        fs.writeFileSync('increment_metrics.json', JSON.stringify(metrics, null, 2));
        console.log("\nMetrics saved to increment_metrics.json");
        
        // Display key metrics
        console.log("\n=== KEY METRICS ===");
        console.log(`Total TVL: $${metrics.summary.totalTVL.toFixed(2)}`);
        console.log(`Total Staked FLOW: ${metrics.staking.totalStakedFlow.toFixed(0)} FLOW`);
        console.log(`stFlow/FLOW Rate: ${metrics.staking.stFlowFlowRate.toFixed(6)}`);
        console.log(`Estimated APY: ${metrics.staking.estimatedAPY.toFixed(2)}%`);
        console.log(`DEX Pairs: ${metrics.dex.pairCount}`);
        
    } catch (error) {
        console.error("Test failed:", error);
    }
}

// Export for use in other modules
module.exports = { IncrementDataFetcher };

// Run test if called directly
if (require.main === module) {
    test();
}