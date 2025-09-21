import FungibleToken from 0xf233dcee88fe0abe
import FlowToken from 0x1654653399040a61

// Automated Arbitrage Bot Controller - Schedule & Monitor
contract ArbitrageBotController {
    
    // Bot configuration
    access(all) var botEnabled: Bool
    access(all) var minProfitThreshold: UFix64
    access(all) var maxTradeSize: UFix64
    access(all) var enableCrossVM: Bool
    access(all) var emergencyStop: Bool
    
    // Risk management
    access(all) var dailyTotalTrades: UFix64
    access(all) var dailyMaxLoss: UFix64
    access(all) var dailyCurrentLoss: UFix64
    access(all) var lastResetDate: UFix64
    
    // Performance tracking
    access(all) var totalProfits: UFix64
    access(all) var totalTrades: UInt64
    access(all) var successfulTrades: UInt64
    access(all) var failedTrades: UInt64
    
    // Events for monitoring
    access(all) event BotStarted()
    access(all) event BotStopped()
    access(all) event ArbitrageExecuted(profit: UFix64, volume: UFix64, pair: String)
    access(all) event ArbitrageOpportunity(spread: UFix64, pair: String)
    access(all) event ArbitrageFailed(reason: String, pair: String)
    access(all) event EmergencyStopActivated(reason: String)
    access(all) event DailyLimitReached(currentLoss: UFix64, maxLoss: UFix64)
    
    // Admin resource for bot control
    access(all) resource Admin {
        
        access(all) fun startBot() {
            ArbitrageBotController.botEnabled = true
            ArbitrageBotController.emergencyStop = false
            emit BotStarted()
        }
        
        access(all) fun stopBot() {
            ArbitrageBotController.botEnabled = false
            emit BotStopped()
        }
        
        access(all) fun emergencyStop(reason: String) {
            ArbitrageBotController.emergencyStop = true
            ArbitrageBotController.botEnabled = false
            emit EmergencyStopActivated(reason: reason)
        }
        
        access(all) fun updateConfig(
            minProfit: UFix64?,
            maxTrade: UFix64?,
            crossVM: Bool?,
            maxLoss: UFix64?
        ) {
            if minProfit != nil {
                ArbitrageBotController.minProfitThreshold = minProfit!
            }
            if maxTrade != nil {
                ArbitrageBotController.maxTradeSize = maxTrade!
            }
            if crossVM != nil {
                ArbitrageBotController.enableCrossVM = crossVM!
            }
            if maxLoss != nil {
                ArbitrageBotController.dailyMaxLoss = maxLoss!
            }
        }
        
        access(all) fun resetDailyStats() {
            ArbitrageBotController.dailyCurrentLoss = 0.0
            ArbitrageBotController.dailyTotalTrades = 0.0
            ArbitrageBotController.lastResetDate = getCurrentBlock().timestamp
        }
    }
    
    // Public monitoring functions
    access(all) view fun getBotStatus(): {String: AnyStruct} {
        return {
            "enabled": self.botEnabled,
            "emergencyStop": self.emergencyStop,
            "minProfitThreshold": self.minProfitThreshold,
            "maxTradeSize": self.maxTradeSize,
            "enableCrossVM": self.enableCrossVM,
            "totalProfits": self.totalProfits,
            "totalTrades": self.totalTrades,
            "successRate": self.totalTrades > 0 ? UFix64(self.successfulTrades) / UFix64(self.totalTrades) * 100.0 : 0.0,
            "dailyCurrentLoss": self.dailyCurrentLoss,
            "dailyMaxLoss": self.dailyMaxLoss
        }
    }
    
    access(all) fun shouldExecuteBot(): Bool {
        // Check if bot should run based on current conditions
        if !self.botEnabled || self.emergencyStop {
            return false
        }
        
        // Check daily loss limits
        if self.dailyCurrentLoss >= self.dailyMaxLoss {
            emit DailyLimitReached(currentLoss: self.dailyCurrentLoss, maxLoss: self.dailyMaxLoss)
            return false
        }
        
        // Reset daily stats if new day
        let currentTime = getCurrentBlock().timestamp
        let dayInSeconds: UFix64 = 86400.0
        if currentTime - self.lastResetDate >= dayInSeconds {
            self.dailyCurrentLoss = 0.0
            self.dailyTotalTrades = 0.0
            self.lastResetDate = currentTime
        }
        
        return true
    }
    
    access(all) fun recordTrade(success: Bool, profit: UFix64, volume: UFix64, pair: String) {
        self.totalTrades = self.totalTrades + 1
        self.dailyTotalTrades = self.dailyTotalTrades + volume
        
        if success {
            self.successfulTrades = self.successfulTrades + 1
            self.totalProfits = self.totalProfits + profit
            emit ArbitrageExecuted(profit: profit, volume: volume, pair: pair)
        } else {
            self.failedTrades = self.failedTrades + 1
            if profit < 0.0 {
                self.dailyCurrentLoss = self.dailyCurrentLoss + (profit * -1.0)
            }
            emit ArbitrageFailed(reason: "Trade execution failed", pair: pair)
        }
    }
    
    init() {
        // Initialize with conservative settings
        self.botEnabled = false
        self.minProfitThreshold = 0.5  // 0.5% minimum profit
        self.maxTradeSize = 100.0       // Max 100 FLOW per trade
        self.enableCrossVM = false      // Start with single VM only
        self.emergencyStop = false
        
        // Risk management defaults
        self.dailyMaxLoss = 50.0        // Max 50 FLOW loss per day
        self.dailyCurrentLoss = 0.0
        self.dailyTotalTrades = 0.0
        self.lastResetDate = getCurrentBlock().timestamp
        
        // Performance tracking
        self.totalProfits = 0.0
        self.totalTrades = 0
        self.successfulTrades = 0
        self.failedTrades = 0
        
        // Store admin resource
        self.account.storage.save(<-create Admin(), to: /storage/ArbitrageBotAdmin)
        self.account.capabilities.publish(
            self.account.capabilities.storage.issue<&Admin>(/storage/ArbitrageBotAdmin),
            at: /public/ArbitrageBotAdmin
        )
    }
}