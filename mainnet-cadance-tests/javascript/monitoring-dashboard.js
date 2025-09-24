// monitoring-dashboard.js
// Real-time monitoring and analytics dashboard for LP farming operations

import EventEmitter from 'events';

class LPMonitoringDashboard extends EventEmitter {
  constructor(farmingEngine) {
    super();
    
    this.engine = farmingEngine;
    this.metrics = new Map();
    this.alerts = [];
    this.performanceHistory = [];
    this.isMonitoring = false;
    
    // Performance thresholds
    this.thresholds = {
      minAPR: 0.05,
      maxDrawdown: -0.20,
      maxSlippage: 0.01,
      minLiquidity: 10000,
      alertCooldown: 300000 // 5 minutes
    };
    
    this.lastAlertTime = new Map();
    
    // Bind to engine events
    this.setupEngineListeners();
  }

  setupEngineListeners() {
    this.engine.on('started', () => {
      this.log('LP Farming Engine started', 'info');
      this.startMonitoring();
    });

    this.engine.on('stopped', () => {
      this.log('LP Farming Engine stopped', 'info');
      this.stopMonitoring();
    });

    this.engine.on('strategyDeployed', (strategy) => {
      this.log(`Strategy ${strategy.id} deployed with ${strategy.amount} FLOW`, 'success');
      this.updateMetrics('strategiesDeployed', 1);
    });

    this.engine.on('strategyFailed', (strategy, error) => {
      this.createAlert({
        type: 'error',
        title: 'Strategy Deployment Failed',
        message: `Strategy ${strategy.id} failed: ${error.message}`,
        severity: 'high',
        timestamp: Date.now()
      });
    });

    this.engine.on('opportunitiesDiscovered', (opportunities) => {
      this.log(`Found ${opportunities.length} opportunities`, 'info');
      this.updateMetrics('lastOpportunityCount', opportunities.length);
    });
  }

  startMonitoring() {
    if (this.isMonitoring) return;
    
    this.isMonitoring = true;
    console.log('Starting LP monitoring dashboard...');
    
    // Performance tracking interval
    this.performanceInterval = setInterval(() => {
      this.trackPerformance();
    }, 30000); // Every 30 seconds
    
    // Alert checking interval
    this.alertInterval = setInterval(() => {
      this.checkAlerts();
    }, 15000); // Every 15 seconds
    
    // Metrics snapshot interval
    this.snapshotInterval = setInterval(() => {
      this.takeSnapshot();
    }, 300000); // Every 5 minutes
  }

  stopMonitoring() {
    if (!this.isMonitoring) return;
    
    this.isMonitoring = false;
    console.log('Stopping LP monitoring dashboard...');
    
    clearInterval(this.performanceInterval);
    clearInterval(this.alertInterval);
    clearInterval(this.snapshotInterval);
  }

  async trackPerformance() {
    try {
      const engineStats = this.engine.getStats();
      const activePositions = this.engine.getActivePositions();
      
      const performance = {
        timestamp: Date.now(),
        totalValue: this.calculateTotalValue(activePositions),
        totalPnL: this.calculateTotalPnL(activePositions),
        activeStrategies: activePositions.length,
        avgAPR: this.calculateAverageAPR(activePositions),
        successRate: this.calculateSuccessRate(engineStats),
        gasEfficiency: this.calculateGasEfficiency(activePositions)
      };
      
      this.performanceHistory.push(performance);
      
      // Keep only last 24 hours of data
      const cutoff = Date.now() - 86400000;
      this.performanceHistory = this.performanceHistory.filter(p => p.timestamp > cutoff);
      
      this.emit('performanceUpdate', performance);
      
    } catch (error) {
      console.error('Error tracking performance:', error);
    }
  }

  calculateTotalValue(positions) {
    return positions.reduce((total, pos) => total + pos.performance.currentValue, 0);
  }

  calculateTotalPnL(positions) {
    return positions.reduce((total, pos) => total + pos.performance.unrealizedPnL, 0);
  }

  calculateAverageAPR(positions) {
    if (positions.length === 0) return 0;
    
    const totalAPR = positions.reduce((sum, pos) => {
      return sum + (pos.analysis.expectedAPR || 0);
    }, 0);
    
    return totalAPR / positions.length;
  }

  calculateSuccessRate(stats) {
    const total = stats.successfulOperations + stats.failedOperations;
    if (total === 0) return 100;
    
    return (stats.successfulOperations / total) * 100;
  }

  calculateGasEfficiency(positions) {
    // Calculate average operations per strategy
    const totalOps = positions.reduce((sum, pos) => sum + pos.operations.length, 0);
    if (positions.length === 0) return 100;
    
    return Math.max(0, 100 - (totalOps / positions.length) * 10); // Simplified metric
  }

  async checkAlerts() {
    const activePositions = this.engine.getActivePositions();
    
    for (const position of activePositions) {
      await this.checkPositionAlerts(position);
    }
    
    await this.checkSystemAlerts();
  }

  async checkPositionAlerts(position) {
    const alertKey = `position_${position.id}`;
    
    // Check for significant losses
    if (position.performance.unrealizedPnL / position.performance.initialValue < this.thresholds.maxDrawdown) {
      this.createAlert({
        type: 'warning',
        title: 'Significant Loss Detected',
        message: `Position ${position.id} has unrealized loss of ${(position.performance.unrealizedPnL / position.performance.initialValue * 100).toFixed(2)}%`,
        severity: 'high',
        positionId: position.id,
        timestamp: Date.now()
      });
    }
    
    // Check for low APR
    if (position.analysis.expectedAPR < this.thresholds.minAPR) {
      this.createAlert({
        type: 'info',
        title: 'Low APR Warning',
        message: `Position ${position.id} APR dropped to ${(position.analysis.expectedAPR * 100).toFixed(2)}%`,
        severity: 'medium',
        positionId: position.id,
        timestamp: Date.now()
      });
    }
  }

  async checkSystemAlerts() {
    try {
      const healthStatus = await this.engine.client.healthCheck();
      
      if (!healthStatus.isActive) {
        this.createAlert({
          type: 'error',
          title: 'ActionRouter Inactive',
          message: 'The ActionRouter contract is currently inactive',
          severity: 'critical',
          timestamp: Date.now()
        });
      }
      
      if (healthStatus.rateLimitRemaining < 5) {
        this.createAlert({
          type: 'warning',
          title: 'Rate Limit Warning',
          message: `Only ${healthStatus.rateLimitRemaining} operations remaining in current block`,
          severity: 'medium',
          timestamp: Date.now()
        });
      }
      
    } catch (error) {
      this.createAlert({
        type: 'error',
        title: 'Health Check Failed',
        message: `Unable to check system health: ${error.message}`,
        severity: 'high',
        timestamp: Date.now()
      });
    }
  }

  createAlert(alert) {
    const alertKey = `${alert.type}_${alert.title}_${alert.positionId || 'system'}`;
    const lastAlert = this.lastAlertTime.get(alertKey);
    
    // Check cooldown period
    if (lastAlert && Date.now() - lastAlert < this.thresholds.alertCooldown) {
      return;
    }
    
    alert.id = this.generateAlertId();
    this.alerts.unshift(alert);
    this.lastAlertTime.set(alertKey, alert.timestamp);
    
    // Keep only last 100 alerts
    if (this.alerts.length > 100) {
      this.alerts = this.alerts.slice(0, 100);
    }
    
    this.log(alert.message, alert.type);
    this.emit('alert', alert);
  }

  takeSnapshot() {
    const snapshot = {
      timestamp: Date.now(),
      stats: this.engine.getStats(),
      positions: this.engine.getActivePositions().length,
      totalValue: this.calculateTotalValue(this.engine.getActivePositions()),
      alerts: this.alerts.filter(a => Date.now() - a.timestamp < 3600000).length, // Last hour
      metrics: Object.fromEntries(this.metrics)
    };
    
    this.emit('snapshot', snapshot);
  }

  updateMetrics(key, value, operation = 'set') {
    if (operation === 'set') {
      this.metrics.set(key, value);
    } else if (operation === 'increment') {
      const current = this.metrics.get(key) || 0;
      this.metrics.set(key, current + value);
    }
  }

  log(message, level = 'info') {
    const timestamp = new Date().toISOString();
    const logEntry = {
      timestamp,
      level,
      message,
      service: 'LP_MONITOR'
    };
    
    console.log(`[${timestamp}] ${level.toUpperCase()}: ${message}`);
    this.emit('log', logEntry);
  }

  generateAlertId() {
    return `alert_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  }

  // Dashboard API Methods
  getDashboardData() {
    const recentPerformance = this.performanceHistory.slice(-20); // Last 20 data points
    const activePositions = this.engine.getActivePositions();
    
    return {
      summary: {
        totalValue: this.calculateTotalValue(activePositions),
        totalPnL: this.calculateTotalPnL(activePositions),
        activeStrategies: activePositions.length,
        averageAPR: this.calculateAverageAPR(activePositions),
        successRate: this.calculateSuccessRate(this.engine.getStats())
      },
      performance: recentPerformance,
      positions: activePositions.map(pos => ({
        id: pos.id,
        pool: `${pos.pool.token0}/${pos.pool.token1}`,
        amount: pos.amount,
        currentValue: pos.performance.currentValue,
        pnl: pos.performance.unrealizedPnL,
        pnlPercent: (pos.performance.unrealizedPnL / pos.performance.initialValue) * 100,
        apr: pos.analysis.expectedAPR * 100,
        status: pos.status,
        age: Date.now() - pos.startTime
      })),
      alerts: this.alerts.slice(0, 10), // Recent 10 alerts
      metrics: Object.fromEntries(this.metrics),
      systemHealth: this.getSystemHealth()
    };
  }

  getSystemHealth() {
    return {
      engineRunning: this.engine.isRunning,
      monitoringActive: this.isMonitoring,
      lastUpdate: this.engine.lastUpdate,
      dataPoints: this.performanceHistory.length,
      alertsToday: this.alerts.filter(a => Date.now() - a.timestamp < 86400000).length
    };
  }

  getPerformanceAnalytics() {
    if (this.performanceHistory.length < 2) {
      return { error: 'Insufficient data for analytics' };
    }
    
    const data = this.performanceHistory;
    const latest = data[data.length - 1];
    const earliest = data[0];
    
    const totalReturn = ((latest.totalValue - earliest.totalValue) / earliest.totalValue) * 100;
    const timespan = latest.timestamp - earliest.timestamp;
    const annualizedReturn = (totalReturn / timespan) * (365 * 24 * 60 * 60 * 1000);
    
    // Calculate Sharpe ratio (simplified)
    const returns = data.slice(1).map((point, i) => {
      const prev = data[i];
      return (point.totalValue - prev.totalValue) / prev.totalValue;
    });
    
    const avgReturn = returns.reduce((sum, r) => sum + r, 0) / returns.length;
    const returnVariance = returns.reduce((sum, r) => sum + Math.pow(r - avgReturn, 2), 0) / returns.length;
    const volatility = Math.sqrt(returnVariance);
    const sharpeRatio = volatility > 0 ? avgReturn / volatility : 0;
    
    // Maximum drawdown
    let maxDrawdown = 0;
    let peak = data[0].totalValue;
    
    for (const point of data) {
      if (point.totalValue > peak) {
        peak = point.totalValue;
      }
      const drawdown = (peak - point.totalValue) / peak;
      if (drawdown > maxDrawdown) {
        maxDrawdown = drawdown;
      }
    }
    
    return {
      totalReturn: totalReturn,
      annualizedReturn: annualizedReturn,
      sharpeRatio: sharpeRatio,
      volatility: volatility * 100,
      maxDrawdown: maxDrawdown * 100,
      bestDay: Math.max(...returns) * 100,
      worstDay: Math.min(...returns) * 100,
      winRate: (returns.filter(r => r > 0).length / returns.length) * 100,
      dataPoints: data.length,
      timespan: timespan
    };
  }

  getTopPerformingPools() {
    const positions = this.engine.getActivePositions();
    
    return positions
      .map(pos => ({
        pool: `${pos.pool.token0}/${pos.pool.token1}`,
        pnlPercent: (pos.performance.unrealizedPnL / pos.performance.initialValue) * 100,
        apr: pos.analysis.expectedAPR * 100,
        value: pos.performance.currentValue,
        age: Date.now() - pos.startTime
      }))
      .sort((a, b) => b.pnlPercent - a.pnlPercent)
      .slice(0, 5);
  }

  getRecentActivity() {
    const allOperations = [];
    
    for (const position of this.engine.getActivePositions()) {
      for (const op of position.operations) {
        allOperations.push({
          positionId: position.id,
          pool: `${position.pool.token0}/${position.pool.token1}`,
          type: op.type,
          timestamp: op.timestamp,
          success: !!op.result
        });
      }
    }
    
    return allOperations
      .sort((a, b) => b.timestamp - a.timestamp)
      .slice(0, 20);
  }

  exportData(format = 'json') {
    const data = {
      metadata: {
        exportTime: new Date().toISOString(),
        format: format,
        version: '1.0'
      },
      dashboard: this.getDashboardData(),
      analytics: this.getPerformanceAnalytics(),
      fullHistory: this.performanceHistory,
      positions: this.engine.getActivePositions(),
      alerts: this.alerts
    };
    
    if (format === 'json') {
      return JSON.stringify(data, null, 2);
    } else if (format === 'csv') {
      // Convert to CSV format for performance data
      const headers = ['timestamp', 'totalValue', 'totalPnL', 'activeStrategies', 'avgAPR'];
      const rows = this.performanceHistory.map(p => [
        new Date(p.timestamp).toISOString(),
        p.totalValue,
        p.totalPnL,
        p.activeStrategies,
        p.avgAPR
      ]);
      
      return [headers, ...rows].map(row => row.join(',')).join('\n');
    }
    
    return data;
  }
}

export default LPMonitoringDashboard;