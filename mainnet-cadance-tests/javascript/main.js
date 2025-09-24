// main.js
// Complete LP farming integration with IncrementFi

import FlowLPClient from './flow-client.js';
import LPFarmingEngine from './lp-farming-engine.js';
import LPMonitoringDashboard from './monitoring-dashboard.js';
import EventEmitter from 'events';

class LPFarmingIntegration extends EventEmitter {
  constructor(config = {}) {
    super();
    
    this.config = {
      network: 'mainnet',
      userAddress: null,
      privateKey: null,
      totalCapital: 1000.0,
      riskTolerance: 'medium',
      autoStart: false,
      monitoring: true,
      ...config
    };

    // Initialize components
    this.client = new FlowLPClient(this.config.network);
    this.engine = new LPFarmingEngine({
      network: this.config.network,
      riskTolerance: this.config.riskTolerance,
      maxPositionSize: this.config.totalCapital * 0.4,
      gasOptimization: true
    });
    
    if (this.config.monitoring) {
      this.dashboard = new LPMonitoringDashboard(this.engine);
    }

    this.isInitialized = false;
    this.setupEventHandlers();
  }

  setupEventHandlers() {
    // Engine events
    this.engine.on('started', () => {
      this.emit('systemReady');
      console.log('LP Farming system is ready');
    });

    this.engine.on('strategyDeployed', (strategy) => {
      console.log(`✅ Strategy deployed: ${strategy.id} (${strategy.amount} FLOW)`);
      this.emit('strategyUpdate', strategy);
    });

    this.engine.on('opportunitiesDiscovered', (opportunities) => {
      console.log(`🎯 Found ${opportunities.length} opportunities`);
      this.emit('opportunitiesUpdate', opportunities);
    });

    // Dashboard events
    if (this.dashboard) {
      this.dashboard.on('alert', (alert) => {
        console.log(`⚠️  Alert: ${alert.message}`);
        this.emit('alert', alert);
      });

      this.dashboard.on('performanceUpdate', (performance) => {
        this.emit('performanceUpdate', performance);
      });
    }
  }

  async initialize() {
    if (this.isInitialized) return;

    console.log('Initializing LP Farming Integration...');
    
    try {
      // Validate configuration
      this.validateConfig();
      
      // Test connection to Flow network
      await this.testConnection();
      
      // Initialize FCL with user authentication if needed
      if (this.config.userAddress) {
        await this.setupAuthentication();
      }
      
      this.isInitialized = true;
      console.log('✅ LP Farming Integration initialized successfully');
      
      if (this.config.autoStart) {
        await this.start();
      }
      
    } catch (error) {
      console.error('❌ Failed to initialize:', error);
      throw error;
    }
  }

  validateConfig() {
    if (this.config.totalCapital <= 0) {
      throw new Error('Total capital must be positive');
    }
    
    if (!['low', 'medium', 'high'].includes(this.config.riskTolerance)) {
      throw new Error('Risk tolerance must be low, medium, or high');
    }
  }

  async testConnection() {
    try {
      const healthStatus = await this.client.healthCheck();
      if (!healthStatus.isActive) {
        console.warn('⚠️  ActionRouter is currently inactive');
      }
      console.log('🔗 Connection to Flow network established');
    } catch (error) {
      throw new Error(`Failed to connect to Flow network: ${error.message}`);
    }
  }

  async setupAuthentication() {
    // This would handle FCL authentication setup
    console.log('🔐 Setting up authentication...');
    // Implementation depends on your authentication strategy
  }

  async start() {
    if (!this.isInitialized) {
      await this.initialize();
    }

    console.log('🚀 Starting LP Farming operations...');
    
    // Start the farming engine
    await this.engine.start();
    
    // Enable monitoring if configured
    if (this.dashboard) {
      console.log('📊 Monitoring dashboard activated');
    }
  }

  async stop() {
    console.log('🛑 Stopping LP Farming operations...');
    
    await this.engine.stop();
    
    if (this.dashboard) {
      this.dashboard.stopMonitoring();
    }
    
    console.log('✅ LP Farming operations stopped');
  }

  // High-level strategy methods
  async deployOptimalStrategy() {
    try {
      console.log('🎯 Calculating optimal allocation...');
      
      const allocation = await this.engine.getOptimalAllocation(this.config.totalCapital);
      
      if (allocation.length === 0) {
        console.log('❌ No viable opportunities found');
        return [];
      }

      console.log('📋 Optimal allocation:');
      allocation.forEach(alloc => {
        console.log(`  • ${alloc.opportunity.pool.token0}/${alloc.opportunity.pool.token1}: ${alloc.amount} FLOW (${alloc.percentage.toFixed(1)}%)`);
      });

      const deployedStrategies = [];
      
      for (const alloc of allocation) {
        try {
          const strategy = await this.engine.deployStrategy(alloc.opportunity, alloc.amount);
          deployedStrategies.push(strategy);
          
          // Small delay between deployments to avoid rate limiting
          await this.sleep(2000);
          
        } catch (error) {
          console.error(`Failed to deploy strategy for ${alloc.opportunity.pool.token0}/${alloc.opportunity.pool.token1}:`, error.message);
        }
      }

      return deployedStrategies;
      
    } catch (error) {
      console.error('Error deploying optimal strategy:', error);
      throw error;
    }
  }

  async rebalanceAllPositions() {
    console.log('⚖️  Rebalancing all positions...');
    
    const activePositions = this.engine.getActivePositions();
    
    if (activePositions.length === 0) {
      console.log('No active positions to rebalance');
      return;
    }

    for (const position of activePositions) {
      try {
        await this.engine.monitorStrategy(position);
        console.log(`✅ Rebalanced strategy ${position.id}`);
      } catch (error) {
        console.error(`❌ Failed to rebalance strategy ${position.id}:`, error.message);
      }
    }
  }

  async emergencyExit() {
    console.log('🚨 Executing emergency exit...');
    
    const activePositions = this.engine.getActivePositions();
    
    for (const position of activePositions) {
      try {
        await this.engine.closeStrategy(position, 'Emergency exit');
        console.log(`✅ Closed strategy ${position.id}`);
      } catch (error) {
        console.error(`❌ Failed to close strategy ${position.id}:`, error.message);
      }
    }
  }

  // Analytics and reporting
  getPortfolioSummary() {
    const positions = this.engine.getActivePositions();
    const stats = this.engine.getStats();
    
    const summary = {
      totalValue: positions.reduce((sum, pos) => sum + pos.performance.currentValue, 0),
      totalPnL: positions.reduce((sum, pos) => sum + pos.performance.unrealizedPnL, 0),
      totalRewards: positions.reduce((sum, pos) => sum + pos.performance.totalRewards, 0),
      activeStrategies: positions.length,
      avgAPR: positions.length > 0 ? 
        positions.reduce((sum, pos) => sum + (pos.analysis.expectedAPR || 0), 0) / positions.length : 0,
      successRate: stats.successfulOperations / (stats.successfulOperations + stats.failedOperations) * 100,
      totalOperations: stats.successfulOperations + stats.failedOperations
    };

    return summary;
  }

  getDetailedReport() {
    const summary = this.getPortfolioSummary();
    const positions = this.engine.getActivePositions();
    const analytics = this.dashboard ? this.dashboard.getPerformanceAnalytics() : {};

    return {
      timestamp: new Date().toISOString(),
      summary,
      positions: positions.map(pos => ({
        id: pos.id,
        pool: `${pos.pool.token0}/${pos.pool.token1}`,
        amount: pos.amount,
        currentValue: pos.performance.currentValue,
        pnl: pos.performance.unrealizedPnL,
        pnlPercent: (pos.performance.unrealizedPnL / pos.performance.initialValue) * 100,
        apr: (pos.analysis.expectedAPR || 0) * 100,
        status: pos.status,
        runtime: Date.now() - pos.startTime,
        operationsCount: pos.operations.length
      })),
      analytics,
      systemHealth: this.getSystemHealth()
    };
  }

  getSystemHealth() {
    return {
      engineRunning: this.engine.isRunning,
      monitoringActive: this.dashboard ? this.dashboard.isMonitoring : false,
      lastUpdate: this.engine.lastUpdate,
      connectionStatus: 'connected', // Would check actual connection
      errors: this.getRecentErrors()
    };
  }

  getRecentErrors() {
    // Return recent errors from logs
    return [];
  }

  // Utility methods
  async sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  formatCurrency(amount, currency = 'FLOW') {
    return `${amount.toFixed(4)} ${currency}`;
  }

  formatPercent(value) {
    return `${(value * 100).toFixed(2)}%`;
  }

  formatDuration(ms) {
    const hours = Math.floor(ms / 3600000);
    const minutes = Math.floor((ms % 3600000) / 60000);
    return `${hours}h ${minutes}m`;
  }
}

// Example usage and CLI interface
class LPFarmingCLI {
  constructor() {
    this.integration = new LPFarmingIntegration({
      network: 'mainnet',
      totalCapital: 1000.0,
      riskTolerance: 'medium',
      monitoring: true
    });
  }

  async run() {
    console.log('🌊 Flow LP Farming Bot');
    console.log('====================');
    
    try {
      // Initialize
      await this.integration.initialize();
      
      // Start operations
      await this.integration.start();
      
      // Deploy optimal strategy
      const strategies = await this.integration.deployOptimalStrategy();
      console.log(`✅ Deployed ${strategies.length} strategies`);
      
      // Show portfolio summary
      this.showPortfolioSummary();
      
      // Set up periodic reporting
      setInterval(() => {
        this.showPortfolioSummary();
      }, 300000); // Every 5 minutes
      
      // Handle process signals
      process.on('SIGINT', async () => {
        console.log('\n🛑 Shutting down gracefully...');
        await this.integration.stop();
        process.exit(0);
      });
      
    } catch (error) {
      console.error('❌ Fatal error:', error);
      process.exit(1);
    }
  }

  showPortfolioSummary() {
    const summary = this.integration.getPortfolioSummary();
    
    console.log('\n📊 Portfolio Summary');
    console.log('===================');
    console.log(`Total Value: ${this.integration.formatCurrency(summary.totalValue)}`);
    console.log(`P&L: ${this.integration.formatCurrency(summary.totalPnL)} (${this.integration.formatPercent(summary.totalPnL / 1000)})`);
    console.log(`Rewards: ${this.integration.formatCurrency(summary.totalRewards)}`);
    console.log(`Active Strategies: ${summary.activeStrategies}`);
    console.log(`Average APR: ${this.integration.formatPercent(summary.avgAPR)}`);
    console.log(`Success Rate: ${summary.successRate.toFixed(1)}%`);
    console.log('===================\n');
  }
}

// Export for use
export { LPFarmingIntegration, LPFarmingCLI };

// Run CLI if this is the main module
if (import.meta.url === `file://${process.argv[1]}`) {
  const cli = new LPFarmingCLI();
  cli.run();
}