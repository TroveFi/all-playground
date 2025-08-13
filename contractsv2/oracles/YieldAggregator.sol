// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IRiskOracle.sol";
import "../interfaces/IStrategyRegistry.sol";

/// @title YieldAggregator - Advanced Multi-Chain Yield Optimization
/// @notice Sophisticated yield aggregator with ML-powered optimization and risk management
contract YieldAggregator is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant YIELD_MANAGER_ROLE = keccak256("YIELD_MANAGER_ROLE");
    bytes32 public constant PYTHON_AGENT_ROLE = keccak256("PYTHON_AGENT_ROLE");

    struct YieldOpportunity {
        address protocol;
        uint16 chainId;
        address asset;
        uint256 currentAPY;
        uint256 historicalAPY;
        uint256 riskScore;
        uint256 tvl;
        uint256 availableCapacity;
        uint256 liquidityDepth;
        uint256 impermanentLossRisk;
        uint256 slippageEstimate;
        uint256 withdrawalTime;
        uint256 gasOptimizationScore;
        bool crossChainRequired;
        bool active;
        uint256 lastUpdate;
        bytes strategyData;
    }

    struct OptimizedAllocation {
        address protocol;
        uint16 chainId;
        uint256 amount;
        uint256 expectedAPY;
        uint256 riskScore;
        uint256 allocation;
        uint256 gasEstimate;
        bool requiresBridge;
        bytes executionData;
    }

    struct YieldPerformanceMetrics {
        uint256 totalYieldGenerated;
        uint256 totalGasCosts;
        uint256 netYield;
        uint256 bestAPY;
        uint256 worstAPY;
        uint256 averageAPY;
        uint256 sharpeRatio;
        uint256 maxDrawdown;
        uint256 successfulRebalances;
        uint256 failedRebalances;
        uint256 lastCalculation;
    }

    struct MarketConditions {
        uint256 volatilityIndex;
        uint256 liquidityIndex;
        uint256 riskSentiment;
        uint256 yieldTrend;
        uint256 gasPrice;
        bool marketStress;
        uint256 lastUpdate;
    }

    struct OptimizationConfig {
        uint256 maxRiskTolerance;
        uint256 minYieldThreshold;
        uint256 rebalanceThreshold;
        uint256 maxGasPercentage;
        uint256 diversificationTarget;
        uint256 maxSingleAllocation;
        bool allowCrossChain;
        bool enableAutoRebalancing;
        uint256 rebalanceInterval;
        uint256 emergencyExitThreshold;
    }

    // Core state
    IRiskOracle public riskOracle;
    IStrategyRegistry public strategyRegistry;
    
    // Yield opportunities tracking
    mapping(bytes32 => YieldOpportunity) public yieldOpportunities;
    bytes32[] public activeOpportunities;
    mapping(address => bytes32[]) public opportunitiesByAsset;
    mapping(uint16 => bytes32[]) public opportunitiesByChain;
    
    // Performance tracking
    mapping(address => YieldPerformanceMetrics) public assetPerformance;
    YieldPerformanceMetrics public globalPerformance;
    
    // Market conditions
    MarketConditions public marketConditions;
    OptimizationConfig public optimizationConfig;
    
    // Yield prediction and ML integration
    mapping(bytes32 => uint256) public predictedAPY;
    mapping(bytes32 => uint256) public yieldVolatility;
    mapping(bytes32 => uint256) public liquidityScore;
    mapping(bytes32 => uint256) public correlationScore;
    
    // Events
    event YieldOpportunityAdded(bytes32 indexed opportunityId, address protocol, uint16 chainId, uint256 apy);
    event YieldOpportunityUpdated(bytes32 indexed opportunityId, uint256 newAPY, uint256 riskScore);
    event OptimalAllocationCalculated(uint256 totalAmount, uint256 expectedAPY, uint256 strategiesUsed);
    event YieldRebalanced(address indexed asset, uint256 oldAPY, uint256 newAPY, uint256 gasCost);
    event MarketConditionsUpdated(uint256 volatility, uint256 liquidity, bool stress);

    constructor(
        address _riskOracle,
        address _strategyRegistry
    ) {
        require(_riskOracle != address(0), "Invalid risk oracle");
        require(_strategyRegistry != address(0), "Invalid strategy registry");

        riskOracle = IRiskOracle(_riskOracle);
        strategyRegistry = IStrategyRegistry(_strategyRegistry);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(YIELD_MANAGER_ROLE, msg.sender);

        // Initialize with conservative settings
        optimizationConfig = OptimizationConfig({
            maxRiskTolerance: 6000, // 60%
            minYieldThreshold: 100, // 1%
            rebalanceThreshold: 500, // 5%
            maxGasPercentage: 1000, // 10%
            diversificationTarget: 3,
            maxSingleAllocation: 4000, // 40%
            allowCrossChain: true,
            enableAutoRebalancing: false,
            rebalanceInterval: 4 hours,
            emergencyExitThreshold: 8000 // 80%
        });
    }

    function addYieldOpportunity(
        address protocol,
        uint16 chainId,
        address asset,
        uint256 currentAPY,
        uint256 tvl,
        uint256 availableCapacity,
        uint256 liquidityDepth,
        uint256 withdrawalTime,
        bool crossChainRequired,
        bytes calldata strategyData
    ) external onlyRole(YIELD_MANAGER_ROLE) {
        bytes32 opportunityId = keccak256(abi.encodePacked(protocol, chainId, asset));
        
        // Get risk assessment from oracle
        (uint256 riskScore, string memory riskLevel, bool approved,) = 
            riskOracle.assessStrategyRisk(protocol);

        yieldOpportunities[opportunityId] = YieldOpportunity({
            protocol: protocol,
            chainId: chainId,
            asset: asset,
            currentAPY: currentAPY,
            historicalAPY: currentAPY,
            riskScore: riskScore,
            tvl: tvl,
            availableCapacity: availableCapacity,
            liquidityDepth: liquidityDepth,
            impermanentLossRisk: 0,
            slippageEstimate: 0,
            withdrawalTime: withdrawalTime,
            gasOptimizationScore: 0,
            crossChainRequired: crossChainRequired,
            active: approved && riskScore <= optimizationConfig.maxRiskTolerance,
            lastUpdate: block.timestamp,
            strategyData: strategyData
        });

        if (yieldOpportunities[opportunityId].active) {
            activeOpportunities.push(opportunityId);
            opportunitiesByAsset[asset].push(opportunityId);
            opportunitiesByChain[chainId].push(opportunityId);
        }

        emit YieldOpportunityAdded(opportunityId, protocol, chainId, currentAPY);
    }

    function calculateOptimalAllocation(
        address asset,
        uint256 totalAmount,
        uint256 maxRiskTolerance
    ) external view returns (
        address[] memory strategies,
        uint256[] memory allocations,
        uint256 totalExpectedAPY
    ) {
        bytes32[] memory assetOpportunities = opportunitiesByAsset[asset];
        
        // Filter opportunities by risk tolerance
        uint256 validCount = 0;
        for (uint i = 0; i < assetOpportunities.length; i++) {
            YieldOpportunity memory opp = yieldOpportunities[assetOpportunities[i]];
            if (opp.active && 
                opp.riskScore <= maxRiskTolerance && 
                opp.currentAPY >= optimizationConfig.minYieldThreshold) {
                validCount++;
            }
        }

        if (validCount == 0) {
            return (new address[](0), new uint256[](0), 0);
        }

        // Create allocations arrays
        strategies = new address[](validCount);
        allocations = new uint256[](validCount);
        uint256 index = 0;

        // Apply modern portfolio theory with risk-adjusted returns
        uint256 remainingAmount = totalAmount;
        uint256 totalWeight = 0;

        // First pass: calculate weights based on risk-adjusted returns
        address[] memory tempStrategies = new address[](validCount);
        uint256[] memory tempWeights = new uint256[](validCount);
        
        for (uint i = 0; i < assetOpportunities.length && index < validCount; i++) {
            YieldOpportunity memory opp = yieldOpportunities[assetOpportunities[i]];
            
            if (opp.active && 
                opp.riskScore <= maxRiskTolerance && 
                opp.currentAPY >= optimizationConfig.minYieldThreshold) {
                
                // Calculate risk-adjusted return
                uint256 riskAdjustedReturn = (opp.currentAPY * 10000) / (opp.riskScore + 1000);
                
                // Apply liquidity scoring
                uint256 liquidityBonus = opp.liquidityDepth > 1000000 * 1e18 ? 110 : 100;
                riskAdjustedReturn = (riskAdjustedReturn * liquidityBonus) / 100;
                
                tempStrategies[index] = opp.protocol;
                tempWeights[index] = riskAdjustedReturn;
                totalWeight += riskAdjustedReturn;
                index++;
            }
        }

        // Second pass: calculate actual allocations
        uint256 allocatedAmount = 0;
        for (uint i = 0; i < index; i++) {
            strategies[i] = tempStrategies[i];
            
            if (i == index - 1) {
                // Last allocation gets remaining amount
                allocations[i] = remainingAmount - allocatedAmount;
            } else {
                allocations[i] = (totalAmount * tempWeights[i]) / totalWeight;
                allocatedAmount += allocations[i];
            }
            
            // Calculate contribution to total expected APY
            bytes32 oppId = keccak256(abi.encodePacked(strategies[i], uint16(30302), asset));
            YieldOpportunity memory opp = yieldOpportunities[oppId];
            
            uint256 allocationPercentage = (allocations[i] * 10000) / totalAmount;
            totalExpectedAPY += (opp.currentAPY * allocationPercentage) / 10000;
        }
    }

    function getTopYieldOpportunities(
        address asset,
        uint256 maxRiskTolerance,
        uint256 count
    ) external view returns (OptimizedAllocation[] memory opportunities) {
        bytes32[] memory assetOpportunities = opportunitiesByAsset[asset];
        
        uint256 validCount = 0;
        for (uint i = 0; i < assetOpportunities.length; i++) {
            YieldOpportunity memory opp = yieldOpportunities[assetOpportunities[i]];
            if (opp.active && opp.riskScore <= maxRiskTolerance) {
                validCount++;
            }
        }
        
        if (validCount == 0) {
            return new OptimizedAllocation[](0);
        }
        
        uint256 returnCount = validCount < count ? validCount : count;
        opportunities = new OptimizedAllocation[](returnCount);
        
        uint256 index = 0;
        for (uint i = 0; i < assetOpportunities.length && index < returnCount; i++) {
            YieldOpportunity memory opp = yieldOpportunities[assetOpportunities[i]];
            if (opp.active && opp.riskScore <= maxRiskTolerance) {
                opportunities[index] = OptimizedAllocation({
                    protocol: opp.protocol,
                    chainId: opp.chainId,
                    amount: 0,
                    expectedAPY: opp.currentAPY,
                    riskScore: opp.riskScore,
                    allocation: 0,
                    gasEstimate: _estimateGasForStrategy(opp),
                    requiresBridge: opp.crossChainRequired,
                    executionData: opp.strategyData
                });
                index++;
            }
        }
    }

    function shouldRebalance(address asset) external view returns (
        bool shouldRebalance_,
        uint256 currentAPY,
        uint256 potentialAPY,
        uint256 improvementBps
    ) {
        YieldPerformanceMetrics memory performance = assetPerformance[asset];
        currentAPY = performance.averageAPY;
        
        // Calculate potential optimal APY
        (,, uint256 optimalAPY) = this.calculateOptimalAllocation(
            asset, 
            1000000 * 1e18, 
            optimizationConfig.maxRiskTolerance
        );
        
        potentialAPY = optimalAPY;
        
        if (potentialAPY > currentAPY) {
            improvementBps = potentialAPY - currentAPY;
            shouldRebalance_ = improvementBps >= optimizationConfig.rebalanceThreshold;
        }
    }

    function updateMarketConditions(
        uint256 volatilityIndex,
        uint256 liquidityIndex,
        uint256 riskSentiment,
        uint256 yieldTrend,
        bool marketStress
    ) external onlyRole(PYTHON_AGENT_ROLE) {
        marketConditions = MarketConditions({
            volatilityIndex: volatilityIndex,
            liquidityIndex: liquidityIndex,
            riskSentiment: riskSentiment,
            yieldTrend: yieldTrend,
            gasPrice: tx.gasprice,
            marketStress: marketStress,
            lastUpdate: block.timestamp
        });
        
        if (marketStress) {
            optimizationConfig.maxRiskTolerance = optimizationConfig.maxRiskTolerance * 80 / 100;
            optimizationConfig.diversificationTarget = optimizationConfig.diversificationTarget + 1;
        }
        
        emit MarketConditionsUpdated(volatilityIndex, liquidityIndex, marketStress);
    }

    function _estimateGasForStrategy(YieldOpportunity memory opportunity) internal pure returns (uint256) {
        uint256 baseGas = 200000;
        
        if (opportunity.crossChainRequired) {
            baseGas += 500000;
        }
        
        if (opportunity.strategyData.length > 0) {
            baseGas += 100000;
        }
        
        return baseGas;
    }

    // Admin functions
    function setOptimizationConfig(
        uint256 maxRiskTolerance,
        uint256 minYieldThreshold,
        uint256 rebalanceThreshold,
        uint256 maxGasPercentage,
        uint256 diversificationTarget,
        uint256 maxSingleAllocation,
        bool allowCrossChain,
        bool enableAutoRebalancing,
        uint256 rebalanceInterval
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        optimizationConfig = OptimizationConfig({
            maxRiskTolerance: maxRiskTolerance,
            minYieldThreshold: minYieldThreshold,
            rebalanceThreshold: rebalanceThreshold,
            maxGasPercentage: maxGasPercentage,
            diversificationTarget: diversificationTarget,
            maxSingleAllocation: maxSingleAllocation,
            allowCrossChain: allowCrossChain,
            enableAutoRebalancing: enableAutoRebalancing,
            rebalanceInterval: rebalanceInterval,
            emergencyExitThreshold: optimizationConfig.emergencyExitThreshold
        });
    }

    function addPythonAgent(address agent) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(PYTHON_AGENT_ROLE, agent);
    }

    // View functions
    function getYieldOpportunity(bytes32 opportunityId) external view returns (YieldOpportunity memory) {
        return yieldOpportunities[opportunityId];
    }

    function getActiveOpportunities() external view returns (bytes32[] memory) {
        return activeOpportunities;
    }

    function getOpportunitiesByAsset(address asset) external view returns (bytes32[] memory) {
        return opportunitiesByAsset[asset];
    }

    function getPerformanceMetrics(address asset) external view returns (YieldPerformanceMetrics memory) {
        return assetPerformance[asset];
    }

    function getMarketConditions() external view returns (MarketConditions memory) {
        return marketConditions;
    }

    function getOptimizationConfig() external view returns (OptimizationConfig memory) {
        return optimizationConfig;
    }
}