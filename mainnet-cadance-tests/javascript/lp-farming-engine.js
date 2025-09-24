// lp-farming-engine.js
// Strategic engine for automated LP farming on IncrementFi

import FlowLPClient from './flow-client.js';
import EventEmitter from 'events';

class LPFarmingEngine extends EventEmitter {
  constructor(config = {}) {
    super();
    
    this.config = {
      network: config.network || 'mainnet',
      maxSlippage: config.maxSlippage || 0.005, // 0.5%
      minAPR: config.minAPR || 0.05, // 5%
      maxPositionSize: config.maxPositionSize || 1000.0,
      rebalanceThreshold: config.rebalanceThreshold || 0.1, // 10%
      compoundInterval: config.compoundInterval || 86400000, // 24 hours
      riskTolerance: config.riskTolerance || 'medium',
      gasOptimization: config.gasOptimization || true,
      ...config
    };

    this.client = new FlowLPClient(this.config.network);
    this.activePositions = new Map();
    this.strategies = new Map();
    this.isRunning = false;
    this.lastUpdate = null;
    
    // Performance tracking
    this.stats = {
      totalDeployed: 0,
      totalEarned: 0,
      totalFees: 0,
      successfulOperations: 0,
      failedOperations: 0,
      averageAPR: 0,
      bestPool: null,
      lastCompound: null
    };
  }

  // Core Strategy Methods
  async start() {
    if (this.isRunning) {
      throw new Error('Engine is already running');
    }

    console.log('Starting LP Farming Engine...');
    this.isRunning = true;
    
    try {
      // Initialize with health check
      const healthStatus = await this.client.healthCheck();
      console.log('Router Health Check:', healthStatus);
      
      // Discover and analyze pools
      await this.discoverOpportunities();
      
      // Start monitoring loop
      this.monitoringInterval = setInterval(() => {
        this.monitorPositions();
      }, 60000); // Check every minute
      
      // Start compound loop
      this.compoundInterval = setInterval(() => {
        this.autoCompound();
      }, this.config.compoundInterval);
      
      this.emit('started');
      console.log('LP Farming Engine started successfully');
      
    } catch (error) {
      this.isRunning = false;
      console.error('Failed to start engine:', error);
      throw error;
    }
  }

  async stop() {
    if (!this.isRunning) return;
    
    console.log('Stopping LP Farming Engine...');
    this.isRunning = false;
    
    clearInterval(this.monitoringInterval);
    clearInterval(this.compoundInterval);
    
    this.emit('stopped');
    console.log('LP Farming Engine stopped');
  }

  async discoverOpportunities() {
    try {
      console.log('Discovering LP opportunities...');
      
      const pools = await this.client.discoverActivePools();
      const opportunities = [];
      
      for (const pool of pools) {
        const opportunity = await this.analyzePool(pool);
        if (opportunity.viable) {
          opportunities.push(opportunity);
        }
      }
      
      // Sort by attractiveness score
      opportunities.sort((a, b) => b.score - a.score);
      
      console.log(`Found ${opportunities.length} viable opportunities`);
      this.emit('opportunitiesDiscovered', opportunities);
      
      return opportunities;
      
    } catch (error) {
      console.error('Error discovering opportunities:', error);
      this.stats.failedOperations++;
      throw error;
    }
  }

  async analyzePool(pool) {
    const analysis = {
      pool: pool,
      viable: false,
      score: 0,
      risk: 'unknown',
      expectedAPR: 0,
      liquidityScore: 0,
      recommendation: 'none'
    };

    try {
      // Liquidity analysis
      const totalLiquidity = pool.reserve0 + pool.reserve1; // Simplified
      analysis.liquidityScore = this.calculateLiquidityScore(totalLiquidity);
      
      // APR analysis
      analysis.expectedAPR = pool.farmAPR || 0;
      
      // Risk assessment
      analysis.risk = this.assessRisk(pool);
      
      // Calculate composite score
      analysis.score = this.calculateOpportunityScore(analysis);
      
      // Viability check
      analysis.viable = (
        analysis.expectedAPR >= this.config.minAPR &&
        analysis.liquidityScore >= 0.3 &&
        this.isRiskAcceptable(analysis.risk)
      );
      
      if (analysis.viable) {
        if (analysis.score > 0.8) {
          analysis.recommendation = 'strong_buy';
        } else if (analysis.score > 0.6) {
          analysis.recommendation = 'buy';
        } else {
          analysis.recommendation = 'consider';
        }
      }
      
    } catch (error) {
      console.error('Error analyzing pool:', error);
    }

    return analysis;
  }

  calculateLiquidityScore(totalLiquidity) {
    // Score liquidity from 0-1 based on thresholds
    if (totalLiquidity < 1000) return 0.1;
    if (totalLiquidity < 10000) return 0.3;
    if (totalLiquidity < 100000) return 0.5;
    if (totalLiquidity < 1000000) return 0.7;
    return 0.9;
  }

  assessRisk(pool) {
    let riskFactors = 0;
    
    // Impermanent loss risk
    if (pool.isStable) {
      riskFactors += 0.1; // Stable pairs have low IL risk
    } else {
      riskFactors += 0.5; // Volatile pairs have higher IL risk
    }
    
    // Liquidity risk
    const liquidity = pool.reserve0 + pool.reserve1;
    if (liquidity < 10000) riskFactors += 0.3;
    else if (liquidity < 100000) riskFactors += 0.1;
    
    // Farm duration risk
    if (pool.farmEndsAt && pool.farmEndsAt < Date.now() + 7 * 24 * 60 * 60 * 1000) {
      riskFactors += 0.2; // Farm ending soon
    }
    
    if (riskFactors < 0.3) return 'low';
    if (riskFactors < 0.6) return 'medium';
    return 'high';
  }

  calculateOpportunityScore(analysis) {
    let score = 0;
    
    // APR component (40% weight)
    score += (analysis.expectedAPR * 0.4);
    
    // Liquidity component (30% weight)
    score += (analysis.liquidityScore * 0.3);
    
    // Risk adjustment (30% weight)
    const riskMultiplier = analysis.risk === 'low' ? 1.0 : analysis.risk === 'medium' ? 0.8 : 0.5;
    score *= riskMultiplier;
    
    return Math.min(score, 1.0); // Cap at 1.0
  }

  isRiskAcceptable(risk) {
    const tolerance = this.config.riskTolerance;
    
    if (tolerance === 'low') return risk === 'low';
    if (tolerance === 'medium') return risk !== 'high';
    if (tolerance === 'high') return true;
    
    return false;
  }

  // Position Management
  async deployStrategy(opportunity, amount) {
    if (!this.isRunning) {
      throw new Error('Engine is not running');
    }

    const strategy = {
      id: this.generateId(),
      pool: opportunity.pool,
      analysis: opportunity,
      amount: amount,
      status: 'deploying',
      startTime: Date.now(),
      lastAction: Date.now(),
      operations: [],
      performance: {
        initialValue: amount,
        currentValue: amount,
        totalRewards: 0,
        realizedPnL: 0,
        unrealizedPnL: 0
      }
    };

    try {
      console.log(`Deploying strategy ${strategy.id} for ${amount} FLOW`);
      
      // Step 1: Calculate optimal token amounts
      const liquidityCalc = await this.client.calculateLiquidityAmounts(
        opportunity.pool.pairAddress,
        amount / 2, // Split amount between tokens
        amount / 2,
        this.config.maxSlippage
      );

      // Step 2: Prepare batch operations if gas optimization is enabled
      if (this.config.gasOptimization) {
        await this.executeBatchStrategy(strategy, liquidityCalc);
      } else {
        await this.executeSequentialStrategy(strategy, liquidityCalc);
      }

      strategy.status = 'active';
      this.activePositions.set(strategy.id, strategy);
      this.strategies.set(strategy.id, strategy);
      
      this.stats.totalDeployed += amount;
      this.stats.successfulOperations++;
      
      this.emit('strategyDeployed', strategy);
      console.log(`Strategy ${strategy.id} deployed successfully`);
      
      return strategy;
      
    } catch (error) {
      strategy.status = 'failed';
      strategy.error = error.message;
      
      this.stats.failedOperations++;
      
      console.error(`Failed to deploy strategy ${strategy.id}:`, error);
      this.emit('strategyFailed', strategy, error);
      
      throw error;
    }
  }

  async executeBatchStrategy(strategy, liquidityCalc) {
    const operations = [
      {
        operationType: 'add_liquidity',
        poolAddress: strategy.pool.pairAddress,
        amount0: liquidityCalc.token0Amount,
        amount1: liquidityCalc.token1Amount,
        minAmount0: liquidityCalc.token0Amount * (1 - this.config.maxSlippage),
        minAmount1: liquidityCalc.token1Amount * (1 - this.config.maxSlippage),
        deadline: Date.now() + 300000 // 5 minutes
      }
    ];

    // Add staking operation if farm is available
    if (strategy.pool.farmAddress) {
      operations.push({
        operationType: 'stake',
        farmAddress: strategy.pool.farmAddress,
        amount0: liquidityCalc.lpTokensReceived
      });
    }

    const result = await this.client.batchLPOperations(operations);
    strategy.operations.push({
      type: 'batch_deploy',
      timestamp: Date.now(),
      result: result,
      operations: operations
    });

    return result;
  }

  async executeSequentialStrategy(strategy, liquidityCalc) {
    // Step 1: Add liquidity
    const liquidityResult = await this.client.addLiquidityFlowStFlow(
      strategy.userAddress,
      liquidityCalc.token0Amount,
      liquidityCalc.token1Amount,
      liquidityCalc.token0Amount * (1 - this.config.maxSlippage),
      liquidityCalc.token1Amount * (1 - this.config.maxSlippage),
      Date.now() + 300000
    );

    strategy.operations.push({
      type: 'add_liquidity',
      timestamp: Date.now(),
      result: liquidityResult
    });

    // Step 2: Stake in farm if available
    if (strategy.pool.farmAddress) {
      const stakeResult = await this.client.stakeLPTokensInFarm(
        strategy.pool.farmAddress,
        liquidityCalc.lpTokensReceived,
        strategy.pool.poolId
      );

      strategy.operations.push({
        type: 'stake',
        timestamp: Date.now(),
        result: stakeResult
      });
    }
  }

  async monitorPositions() {
    if (!this.isRunning || this.activePositions.size === 0) return;

    try {
      console.log(`Monitoring ${this.activePositions.size} active positions...`);
      
      for (const [strategyId, strategy] of this.activePositions) {
        await this.monitorStrategy(strategy);
      }
      
      this.lastUpdate = Date.now();
      this.emit('positionsUpdated', Array.from(this.activePositions.values()));
      
    } catch (error) {
      console.error('Error monitoring positions:', error);
    }
  }

  async monitorStrategy(strategy) {
    try {
      // Update pool information
      const currentPoolInfo = await this.client.getPoolInfo(strategy.pool.pairAddress);
      
      // Calculate current position value
      const positionValue = await this.calculatePositionValue(strategy, currentPoolInfo);
      
      // Update performance metrics
      strategy.performance.currentValue = positionValue.total;
      strategy.performance.unrealizedPnL = positionValue.total - strategy.performance.initialValue;
      
      // Check if rebalancing is needed
      const shouldRebalance = this.shouldRebalance(strategy, currentPoolInfo);
      if (shouldRebalance) {
        await this.rebalanceStrategy(strategy);
      }
      
      // Check if position should be closed
      const shouldClose = this.shouldClosePosition(strategy, currentPoolInfo);
      if (shouldClose.should) {
        await this.closeStrategy(strategy, shouldClose.reason);
      }
      
    } catch (error) {
      console.error(`Error monitoring strategy ${strategy.id}:`, error);
    }
  }

  async calculatePositionValue(strategy, currentPoolInfo) {
    // This would calculate the current USD value of the LP position
    // Including staked tokens, pending rewards, etc.
    return {
      lpTokens: 0,
      stakedTokens: 0,
      pendingRewards: 0,
      total: strategy.performance.initialValue // Placeholder
    };
  }

  shouldRebalance(strategy, currentPoolInfo) {
    // Check if pool composition has changed significantly
    const originalRatio = strategy.analysis.pool.reserve0 / strategy.analysis.pool.reserve1;
    const currentRatio = currentPoolInfo.reserve0 / currentPoolInfo.reserve1;
    
    const ratioChange = Math.abs(currentRatio - originalRatio) / originalRatio;
    
    return ratioChange > this.config.rebalanceThreshold;
  }

  shouldClosePosition(strategy, currentPoolInfo) {
    const reasons = [];
    
    // Check if farm has ended
    if (strategy.pool.farmEndsAt && Date.now() > strategy.pool.farmEndsAt) {
      reasons.push('Farm ended');
    }
    
    // Check if APR has dropped significantly
    if (currentPoolInfo.farmAPR && currentPoolInfo.farmAPR < this.config.minAPR * 0.5) {
      reasons.push('APR dropped below threshold');
    }
    
    // Check if liquidity has dropped significantly
    const liquidityDrop = (strategy.analysis.pool.totalSupply - currentPoolInfo.totalSupply) / strategy.analysis.pool.totalSupply;
    if (liquidityDrop > 0.5) {
      reasons.push('Significant liquidity withdrawal');
    }
    
    return {
      should: reasons.length > 0,
      reason: reasons.join(', ')
    };
  }

  async autoCompound() {
    if (!this.isRunning) return;
    
    console.log('Starting auto-compound process...');
    
    for (const [strategyId, strategy] of this.activePositions) {
      try {
        await this.compoundStrategy(strategy);
      } catch (error) {
        console.error(`Error compounding strategy ${strategyId}:`, error);
      }
    }
    
    this.stats.lastCompound = Date.now();
  }

  async compoundStrategy(strategy) {
    if (!strategy.pool.farmAddress) return; // No farm to compound
    
    console.log(`Compounding strategy ${strategy.id}...`);
    
    try {
      // Claim rewards
      const claimResult = await this.client.claimFarmRewards(
        strategy.pool.farmAddress,
        strategy.pool.poolId
      );
      
      if (claimResult && claimResult.events) {
        // Parse claimed rewards and add back to liquidity
        // This would require more sophisticated logic based on reward token types
        
        strategy.operations.push({
          type: 'compound',
          timestamp: Date.now(),
          result: claimResult
        });
        
        strategy.performance.totalRewards += 10; // Placeholder
      }
      
    } catch (error) {
      console.error(`Failed to compound strategy ${strategy.id}:`, error);
    }
  }

  // Utility Methods
  generateId() {
    return `strategy_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  }

  getStats() {
    return {
      ...this.stats,
      activePositions: this.activePositions.size,
      totalStrategies: this.strategies.size,
      isRunning: this.isRunning,
      lastUpdate: this.lastUpdate
    };
  }

  getActivePositions() {
    return Array.from(this.activePositions.values());
  }

  async getOptimalAllocation(totalAmount) {
    const opportunities = await this.discoverOpportunities();
    const allocation = [];
    
    let remainingAmount = totalAmount;
    
    for (const opp of opportunities.slice(0, 3)) { // Top 3 opportunities
      if (remainingAmount <= 0) break;
      
      const allocationAmount = Math.min(
        remainingAmount * 0.4, // Max 40% per pool
        this.config.maxPositionSize
      );
      
      allocation.push({
        opportunity: opp,
        amount: allocationAmount,
        percentage: (allocationAmount / totalAmount) * 100
      });
      
      remainingAmount -= allocationAmount;
    }
    
    return allocation;
  }
}

export default LPFarmingEngine;