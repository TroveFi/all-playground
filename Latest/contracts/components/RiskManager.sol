// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

interface IEnhancedStrategy {
    function getHealthFactor() external view returns (uint256);
    function getLeverageRatio() external view returns (uint256);
    function checkLiquidationRisk() external view returns (bool atRisk, uint256 buffer);
    function emergencyDelever() external;
}

contract RiskManager is AccessControl {
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");
    bytes32 public constant STRATEGY_MANAGER_ROLE = keccak256("STRATEGY_MANAGER_ROLE");

    struct RiskMetrics {
        uint256 totalLeverage;
        uint256 averageHealthFactor;
        uint256 totalAtRisk;
        uint256 lastRiskAssessment;
        bool emergencyTriggered;
    }

    RiskMetrics public riskMetrics;

    uint256 public maxPortfolioLeverage = 4 * 1e18; // 4x max
    uint256 public emergencyHealthFactorThreshold = 12 * 1e17; // 1.2
    uint256 public maxHighRiskAllocation = 2000; // 20%
    uint256 public riskCheckInterval = 1 hours;

    address[] public monitoredStrategies;
    mapping(address => bool) public isMonitored;
    mapping(address => uint256) public strategyRiskLevel;

    event RiskMetricsUpdated(uint256 totalLeverage, uint256 avgHealthFactor, uint256 totalAtRisk);
    event EmergencyTriggered(address indexed strategy, uint256 healthFactor);
    event StrategyAddedToMonitoring(address indexed strategy, uint256 riskLevel);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        riskMetrics.lastRiskAssessment = block.timestamp;
    }

    function addStrategyToMonitoring(address strategy, uint256 riskLevel) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(strategy != address(0), "Invalid strategy");
        require(riskLevel >= 1 && riskLevel <= 3, "Invalid risk level");
        require(!isMonitored[strategy], "Already monitored");

        monitoredStrategies.push(strategy);
        isMonitored[strategy] = true;
        strategyRiskLevel[strategy] = riskLevel;

        emit StrategyAddedToMonitoring(strategy, riskLevel);
    }

    function checkRisk() external view returns (bool healthy, uint256 riskScore) {
        if (block.timestamp < riskMetrics.lastRiskAssessment + riskCheckInterval) {
            return (true, 0);
        }

        uint256 totalLeverage = 0;
        uint256 totalHealthFactor = 0;
        uint256 totalAtRisk = 0;
        uint256 strategyCount = 0;

        for (uint256 i = 0; i < monitoredStrategies.length; i++) {
            address strategy = monitoredStrategies[i];
            
            try IEnhancedStrategy(strategy).getLeverageRatio() returns (uint256 leverage) {
                totalLeverage += leverage;
                strategyCount++;
            } catch {}

            try IEnhancedStrategy(strategy).getHealthFactor() returns (uint256 hf) {
                totalHealthFactor += hf;
                if (hf < emergencyHealthFactorThreshold) {
                    totalAtRisk++;
                }
            } catch {}
        }

        uint256 avgLeverage = strategyCount > 0 ? totalLeverage / strategyCount : 0;
        uint256 avgHealthFactor = strategyCount > 0 ? totalHealthFactor / strategyCount : type(uint256).max;

        healthy = avgLeverage <= maxPortfolioLeverage && totalAtRisk == 0;
        riskScore = totalAtRisk * 100 + (avgLeverage > maxPortfolioLeverage ? 50 : 0);

        return (healthy, riskScore);
    }

    function performRiskCheck() external onlyRole(STRATEGY_MANAGER_ROLE) {
        uint256 totalLeverage = 0;
        uint256 totalHealthFactor = 0;
        uint256 totalAtRisk = 0;
        uint256 strategyCount = 0;

        for (uint256 i = 0; i < monitoredStrategies.length; i++) {
            address strategy = monitoredStrategies[i];
            
            try IEnhancedStrategy(strategy).getLeverageRatio() returns (uint256 leverage) {
                totalLeverage += leverage;
                strategyCount++;
            } catch {}

            try IEnhancedStrategy(strategy).getHealthFactor() returns (uint256 hf) {
                totalHealthFactor += hf;
                if (hf < emergencyHealthFactorThreshold) {
                    totalAtRisk++;
                    // Trigger emergency delever
                    try IEnhancedStrategy(strategy).emergencyDelever() {
                        emit EmergencyTriggered(strategy, hf);
                    } catch {}
                }
            } catch {}
        }

        riskMetrics.totalLeverage = strategyCount > 0 ? totalLeverage / strategyCount : 0;
        riskMetrics.averageHealthFactor = strategyCount > 0 ? totalHealthFactor / strategyCount : type(uint256).max;
        riskMetrics.totalAtRisk = totalAtRisk;
        riskMetrics.lastRiskAssessment = block.timestamp;

        if (riskMetrics.totalLeverage > maxPortfolioLeverage) {
            riskMetrics.emergencyTriggered = true;
        }

        emit RiskMetricsUpdated(riskMetrics.totalLeverage, riskMetrics.averageHealthFactor, riskMetrics.totalAtRisk);
    }

    function isWithinRiskLimits(uint256 amount) external view returns (bool) {
        // Simple check - more sophisticated logic could be added
        return amount <= 1000000 * 1e6; // 1M USDC max per operation
    }

    function getRiskMetrics() external view returns (
        uint256 totalLeverage,
        uint256 avgHealthFactor,
        bool emergency
    ) {
        return (
            riskMetrics.totalLeverage,
            riskMetrics.averageHealthFactor,
            riskMetrics.emergencyTriggered
        );
    }

    function setRiskParameters(
        uint256 _maxPortfolioLeverage,
        uint256 _emergencyHealthFactorThreshold,
        uint256 _maxHighRiskAllocation,
        uint256 _riskCheckInterval
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxPortfolioLeverage = _maxPortfolioLeverage;
        emergencyHealthFactorThreshold = _emergencyHealthFactorThreshold;
        maxHighRiskAllocation = _maxHighRiskAllocation;
        riskCheckInterval = _riskCheckInterval;
    }

    function resetEmergencyFlag() external onlyRole(DEFAULT_ADMIN_ROLE) {
        riskMetrics.emergencyTriggered = false;
    }
}