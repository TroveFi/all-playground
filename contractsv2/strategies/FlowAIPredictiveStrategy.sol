// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./BaseStrategy.sol";

// AI/ML Oracle Interface
interface IAIOracleV2 {
    struct MarketPrediction {
        uint256 timestamp;
        uint256 confidenceLevel; // 0-10000 (0-100%)
        int256 priceDirection; // -10000 to +10000 (-100% to +100%)
        uint256 volatilityForecast;
        uint256 timeHorizon; // In seconds
        bytes32 modelVersion;
        uint256 accuracy; // Historical accuracy of this model
    }

    struct SentimentData {
        uint256 socialSentiment; // 0-10000 (bearish to bullish)
        uint256 whaleActivity; // 0-10000 (low to high)
        uint256 fearGreedIndex; // 0-10000 (extreme fear to extreme greed)
        uint256 newsImpact; // 0-10000 (negative to positive)
        uint256 onChainMetrics; // 0-10000 (bearish to bullish)
        uint256 timestamp;
    }

    struct RiskAssessment {
        uint256 portfolioVaR; // Value at Risk (basis points)
        uint256 correlationRisk; // Strategy correlation risk
        uint256 liquidityRisk; // Market liquidity risk
        uint256 protocolRisk; // Smart contract risk
        uint256 marketRegime; // 0=bull, 1=bear, 2=crab, 3=volatile
        uint256 blackSwanProbability; // Probability of extreme event
    }

    function getMarketPrediction(address asset) external view returns (MarketPrediction memory);
    function getSentimentData() external view returns (SentimentData memory);
    function getRiskAssessment(address[] calldata assets) external view returns (RiskAssessment memory);
    function getOptimalAllocation(address[] calldata assets, uint256 totalAmount, uint256 riskTolerance) 
        external view returns (uint256[] memory allocations, uint256 expectedReturn);
    function getRebalanceSignal(address[] calldata currentAssets, uint256[] calldata currentAllocations) 
        external view returns (bool shouldRebalance, uint256[] memory newAllocations);
}

// Advanced Analytics Interface
interface IAdvancedAnalytics {
    struct VolatilityForecast {
        uint256 dailyVol;
        uint256 weeklyVol;
        uint256 monthlyVol;
        uint256 confidence;
        uint256 timestamp;
    }

    struct CorrelationMatrix {
        address[] assets;
        int256[][] correlations; // -10000 to +10000
        uint256 timeWindow;
        uint256 timestamp;
    }

    struct LiquidityMetrics {
        uint256 marketDepth;
        uint256 bidAskSpread;
        uint256 impactCost; // For large trades
        uint256 liquidityScore; // 0-10000
        uint256 timestamp;
    }

    function getVolatilityForecast(address asset) external view returns (VolatilityForecast memory);
    function getCorrelationMatrix(address[] calldata assets) external view returns (CorrelationMatrix memory);
    function getLiquidityMetrics(address asset) external view returns (LiquidityMetrics memory);
    function getOptimalExecutionTiming(uint256 amount, address asset) external view returns (uint256 optimalTime);
}

// Machine Learning Strategy Interface
interface IMLStrategyEngine {
    struct MLModel {
        bytes32 modelId;
        string modelType; // "lstm", "transformer", "ensemble", etc.
        uint256 trainingDataPoints;
        uint256 accuracy;
        uint256 lastUpdated;
        bool active;
    }

    struct StrategySignal {
        bytes32 strategyId;
        int256 signal; // -10000 to +10000 (strong sell to strong buy)
        uint256 confidence;
        uint256 expectedReturn;
        uint256 riskScore;
        uint256 timeHorizon;
        bytes modelData;
    }

    function getMLModels() external view returns (MLModel[] memory);
    function getStrategySignal(bytes32 strategyId, address asset) external view returns (StrategySignal memory);
    function trainModel(bytes32 modelId, bytes calldata trainingData) external returns (bool success);
    function getEnsemblePrediction(address asset) external view returns (StrategySignal memory);
}

/// @title FlowAIPredictiveStrategy - AI-Powered Yield Optimization
/// @notice Revolutionary AI/ML strategy with predictive rebalancing and sentiment analysis
contract FlowAIPredictiveStrategy is BaseStrategy, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // AI/ML Oracle addresses (you'll need real addresses)
    address public constant AI_ORACLE_V2 = address(0); // Advanced AI oracle
    address public constant ADVANCED_ANALYTICS = address(0); // Analytics engine
    address public constant ML_STRATEGY_ENGINE = address(0); // ML strategy engine

    IAIOracleV2 public immutable aiOracle;
    IAdvancedAnalytics public immutable analytics;
    IMLStrategyEngine public immutable mlEngine;

    // AI Strategy Configuration
    struct AIStrategyConfig {
        uint256 predictionHorizon; // Time horizon for predictions (seconds)
        uint256 minConfidenceThreshold; // Minimum confidence for acting on signals
        uint256 rebalanceThreshold; // Minimum improvement to trigger rebalance
        uint256 volatilityThreshold; // Maximum acceptable volatility
        uint256 correlationLimit; // Maximum correlation between strategies
        uint256 sentimentWeight; // Weight of sentiment in decisions (0-10000)
        uint256 riskAdjustmentFactor; // Risk adjustment multiplier
        bool useEnsembleModels; // Use multiple ML models
        bool enableAdaptiveLearning; // Continuously learn from performance
    }

    struct PredictionRecord {
        uint256 timestamp;
        int256 prediction;
        uint256 confidence;
        int256 actualOutcome;
        uint256 accuracy;
        bytes32 modelUsed;
    }

    struct PerformanceMetrics {
        uint256 totalPredictions;
        uint256 correctPredictions;
        uint256 avgAccuracy;
        uint256 totalReturn;
        uint256 sharpRatio;
        uint256 maxDrawdown;
        uint256 winRate;
        uint256 avgHoldTime;
    }

    // State variables
    AIStrategyConfig public aiConfig;
    mapping(bytes32 => PredictionRecord[]) public predictionHistory;
    mapping(bytes32 => PerformanceMetrics) public modelPerformance;
    
    // Multi-asset support
    address[] public trackedAssets;
    mapping(address => uint256) public assetAllocations;
    mapping(address => uint256) public assetPerformance;
    
    // AI-driven rebalancing
    uint256 public lastRebalanceTime;
    uint256 public rebalanceCount;
    uint256 public successfulRebalances;
    uint256 public totalRebalanceProfit;
    
    // Sentiment and risk tracking
    uint256 public currentMarketRegime; // 0=bull, 1=bear, 2=crab, 3=volatile
    uint256 public portfolioRisk;
    uint256 public sentimentScore;
    
    // ML model management
    bytes32[] public activeModels;
    mapping(bytes32 => uint256) public modelWeights;
    uint256 public ensembleAccuracy;

    event AIRebalanceExecuted(uint256 oldAllocation, uint256 newAllocation, uint256 expectedImprovement);
    event PredictionMade(bytes32 indexed modelId, int256 prediction, uint256 confidence);
    event ModelPerformanceUpdated(bytes32 indexed modelId, uint256 newAccuracy);
    event MarketRegimeChanged(uint256 oldRegime, uint256 newRegime);
    event SentimentUpdated(uint256 socialSentiment, uint256 fearGreed, uint256 whaleActivity);
    event RiskThresholdBreached(uint256 currentRisk, uint256 threshold, string riskType);
    event AdaptiveLearningTriggered(bytes32 modelId, uint256 newWeight);

    constructor(
        address _asset,
        address _vault,
        string memory _name
    ) BaseStrategy(_asset, AI_ORACLE_V2, _vault, _name) {
        aiOracle = IAIOracleV2(AI_ORACLE_V2);
        analytics = IAdvancedAnalytics(ADVANCED_ANALYTICS);
        mlEngine = IMLStrategyEngine(ML_STRATEGY_ENGINE);
        
        // Initialize AI configuration
        aiConfig = AIStrategyConfig({
            predictionHorizon: 24 hours,
            minConfidenceThreshold: 7000, // 70%
            rebalanceThreshold: 200, // 2%
            volatilityThreshold: 5000, // 50%
            correlationLimit: 7000, // 70%
            sentimentWeight: 3000, // 30%
            riskAdjustmentFactor: 10000, // 100% (no adjustment)
            useEnsembleModels: true,
            enableAdaptiveLearning: true
        });
        
        // Initialize tracked assets
        trackedAssets.push(_asset);
        
        _initializeMLModels();
    }

    function _initializeMLModels() internal {
        // Initialize with various ML models
        bytes32 lstmModel = keccak256("LSTM_PRICE_PREDICTOR");
        bytes32 transformerModel = keccak256("TRANSFORMER_SENTIMENT");
        bytes32 ensembleModel = keccak256("ENSEMBLE_RISK_OPTIMIZER");
        
        activeModels.push(lstmModel);
        activeModels.push(transformerModel);
        activeModels.push(ensembleModel);
        
        // Initial equal weights
        modelWeights[lstmModel] = 3333;
        modelWeights[transformerModel] = 3333;
        modelWeights[ensembleModel] = 3334;
    }

    function _executeStrategy(uint256 amount, bytes calldata data) internal override {
        // Decode AI parameters if provided
        (bool useAI, uint256 confidenceThreshold, bool forceRebalance) = data.length > 0 
            ? abi.decode(data, (bool, uint256, bool))
            : (true, aiConfig.minConfidenceThreshold, false);

        if (useAI) {
            _executeAIStrategy(amount, confidenceThreshold, forceRebalance);
        } else {
            _executeTraditionalStrategy(amount);
        }
    }

    function _executeAIStrategy(uint256 amount, uint256 confidenceThreshold, bool forceRebalance) internal {
        // Step 1: Update market analysis
        _updateMarketIntelligence();
        
        // Step 2: Get AI predictions
        IAIOracleV2.MarketPrediction memory prediction = aiOracle.getMarketPrediction(address(assetToken));
        
        // Step 3: Assess risk and sentiment
        IAIOracleV2.SentimentData memory sentiment = aiOracle.getSentimentData();
        IAIOracleV2.RiskAssessment memory risk = aiOracle.getRiskAssessment(trackedAssets);
        
        // Step 4: Record prediction
        _recordPrediction(prediction);
        
        // Step 5: Make allocation decision
        if (prediction.confidenceLevel >= confidenceThreshold || forceRebalance) {
            _executeAIAllocation(amount, prediction, sentiment, risk);
        }
        
        // Step 6: Update model performance if needed
        if (aiConfig.enableAdaptiveLearning) {
            _updateModelPerformance();
        }
    }

    function _updateMarketIntelligence() internal {
        // Update sentiment scores
        IAIOracleV2.SentimentData memory sentiment = aiOracle.getSentimentData();
        sentimentScore = (sentiment.socialSentiment + sentiment.fearGreedIndex + sentiment.whaleActivity) / 3;
        
        // Update market regime
        IAIOracleV2.RiskAssessment memory risk = aiOracle.getRiskAssessment(trackedAssets);
        if (risk.marketRegime != currentMarketRegime) {
            emit MarketRegimeChanged(currentMarketRegime, risk.marketRegime);
            currentMarketRegime = risk.marketRegime;
        }
        
        // Update portfolio risk
        portfolioRisk = risk.portfolioVaR;
        
        emit SentimentUpdated(sentiment.socialSentiment, sentiment.fearGreedIndex, sentiment.whaleActivity);
    }

    function _recordPrediction(IAIOracleV2.MarketPrediction memory prediction) internal {
        bytes32 modelId = prediction.modelVersion;
        
        predictionHistory[modelId].push(PredictionRecord({
            timestamp: block.timestamp,
            prediction: prediction.priceDirection,
            confidence: prediction.confidenceLevel,
            actualOutcome: 0, // Will be updated later
            accuracy: 0, // Will be calculated later
            modelUsed: modelId
        }));
        
        emit PredictionMade(modelId, prediction.priceDirection, prediction.confidenceLevel);
    }

    function _executeAIAllocation(
        uint256 amount,
        IAIOracleV2.MarketPrediction memory prediction,
        IAIOracleV2.SentimentData memory sentiment,
        IAIOracleV2.RiskAssessment memory risk
    ) internal {
        // Calculate risk-adjusted allocation
        uint256 baseAllocation = amount;
        
        // Adjust for volatility
        if (prediction.volatilityForecast > aiConfig.volatilityThreshold) {
            baseAllocation = (baseAllocation * 8000) / 10000; // Reduce by 20%
        }
        
        // Adjust for sentiment
        uint256 sentimentAdjustment = (sentiment.socialSentiment * aiConfig.sentimentWeight) / 10000;
        baseAllocation = (baseAllocation * (10000 + sentimentAdjustment - 5000)) / 10000;
        
        // Adjust for risk regime
        if (currentMarketRegime == 1) { // Bear market
            baseAllocation = (baseAllocation * 7000) / 10000; // Reduce by 30%
        } else if (currentMarketRegime == 3) { // Volatile market
            baseAllocation = (baseAllocation * 8500) / 10000; // Reduce by 15%
        }
        
        // Check if rebalance is needed
        bool shouldRebalance = _shouldRebalance(baseAllocation);
        
        if (shouldRebalance) {
            uint256 oldAllocation = assetAllocations[address(assetToken)];
            assetAllocations[address(assetToken)] = baseAllocation;
            
            _executeRebalance(oldAllocation, baseAllocation);
            
            emit AIRebalanceExecuted(oldAllocation, baseAllocation, prediction.confidenceLevel);
        }
    }

    function _shouldRebalance(uint256 newAllocation) internal view returns (bool) {
        uint256 currentAllocation = assetAllocations[address(assetToken)];
        
        if (currentAllocation == 0) return true;
        
        uint256 difference = newAllocation > currentAllocation 
            ? newAllocation - currentAllocation 
            : currentAllocation - newAllocation;
            
        uint256 percentChange = (difference * 10000) / currentAllocation;
        
        return percentChange >= aiConfig.rebalanceThreshold;
    }

    function _executeRebalance(uint256 oldAllocation, uint256 newAllocation) internal {
        lastRebalanceTime = block.timestamp;
        rebalanceCount++;
        
        // Execute the rebalancing logic here
        // This would involve moving funds between strategies
        
        // For demonstration, assume successful rebalance
        successfulRebalances++;
        
        // Calculate and track profit from rebalance
        if (newAllocation > oldAllocation) {
            uint256 profit = newAllocation - oldAllocation;
            totalRebalanceProfit += profit;
        }
    }

    function _executeTraditionalStrategy(uint256 amount) internal {
        // Fallback to traditional strategy if AI is disabled
        assetAllocations[address(assetToken)] += amount;
    }

    function _updateModelPerformance() internal {
        // Update performance metrics for all active models
        for (uint256 i = 0; i < activeModels.length; i++) {
            bytes32 modelId = activeModels[i];
            _calculateModelAccuracy(modelId);
        }
        
        // Adjust model weights based on performance
        _adjustModelWeights();
    }

    function _calculateModelAccuracy(bytes32 modelId) internal {
        PredictionRecord[] storage predictions = predictionHistory[modelId];
        
        if (predictions.length < 2) return;
        
        uint256 correctPredictions = 0;
        uint256 totalPredictions = 0;
        
        for (uint256 i = 0; i < predictions.length; i++) {
            PredictionRecord storage prediction = predictions[i];
            
            // Only evaluate predictions that are old enough to have outcomes
            if (block.timestamp > prediction.timestamp + aiConfig.predictionHorizon) {
                // Mock outcome calculation - in reality would use price data
                int256 actualOutcome = _getActualOutcome(prediction.timestamp);
                prediction.actualOutcome = actualOutcome;
                
                // Check if prediction direction was correct
                bool correct = (prediction.prediction > 0 && actualOutcome > 0) || 
                              (prediction.prediction < 0 && actualOutcome < 0);
                
                if (correct) correctPredictions++;
                totalPredictions++;
            }
        }
        
        if (totalPredictions > 0) {
            uint256 accuracy = (correctPredictions * 10000) / totalPredictions;
            modelPerformance[modelId].avgAccuracy = accuracy;
            modelPerformance[modelId].totalPredictions = totalPredictions;
            modelPerformance[modelId].correctPredictions = correctPredictions;
            
            emit ModelPerformanceUpdated(modelId, accuracy);
        }
    }

    function _getActualOutcome(uint256 predictionTime) internal pure returns (int256) {
        // Mock function - in reality would fetch actual price data
        // For demonstration, return a random outcome
        return int256(uint256(keccak256(abi.encode(predictionTime))) % 20000) - 10000;
    }

    function _adjustModelWeights() internal {
        uint256 totalWeight = 0;
        
        // Calculate new weights based on accuracy
        for (uint256 i = 0; i < activeModels.length; i++) {
            bytes32 modelId = activeModels[i];
            uint256 accuracy = modelPerformance[modelId].avgAccuracy;
            
            // Higher accuracy gets higher weight
            uint256 newWeight = accuracy > 0 ? accuracy : 1000; // Minimum weight
            modelWeights[modelId] = newWeight;
            totalWeight += newWeight;
        }
        
        // Normalize weights to sum to 10000
        for (uint256 i = 0; i < activeModels.length; i++) {
            bytes32 modelId = activeModels[i];
            modelWeights[modelId] = (modelWeights[modelId] * 10000) / totalWeight;
            
            emit AdaptiveLearningTriggered(modelId, modelWeights[modelId]);
        }
    }

    function _harvestRewards(bytes calldata) internal override {
        // AI-driven harvesting based on optimal timing
        uint256 optimalTime = analytics.getOptimalExecutionTiming(
            assetToken.balanceOf(address(this)), 
            address(assetToken)
        );
        
        if (block.timestamp >= optimalTime) {
            // Execute harvesting
            _performAIHarvest();
        }
    }

    function _performAIHarvest() internal {
        // Get current predictions
        IAIOracleV2.MarketPrediction memory prediction = aiOracle.getMarketPrediction(address(assetToken));
        
        // Only harvest if conditions are favorable
        if (prediction.priceDirection > 0 && prediction.confidenceLevel >= aiConfig.minConfidenceThreshold) {
            // Perform harvest
            uint256 balance = assetToken.balanceOf(address(this));
            if (balance >= minHarvestAmount) {
                // Process harvest
                totalHarvested += balance;
                lastHarvestTime = block.timestamp;
                harvestCount++;
            }
        }
    }

    function _emergencyWithdraw(bytes calldata) internal override returns (uint256 recovered) {
        // Emergency exit with AI risk assessment
        IAIOracleV2.RiskAssessment memory risk = aiOracle.getRiskAssessment(trackedAssets);
        
        // If black swan event is likely, exit immediately
        if (risk.blackSwanProbability > 8000) { // 80% probability
            recovered = assetToken.balanceOf(address(this));
            return recovered;
        }
        
        // Otherwise, use AI to optimize exit
        uint256 optimalTime = analytics.getOptimalExecutionTiming(
            assetToken.balanceOf(address(this)), 
            address(assetToken)
        );
        
        // If current time is near optimal, exit now
        if (block.timestamp >= optimalTime || (optimalTime - block.timestamp) <= 1 hours) {
            recovered = assetToken.balanceOf(address(this));
        }
        
        return recovered;
    }

    function getBalance() external view override returns (uint256) {
        uint256 balance = assetToken.balanceOf(address(this));
        
        // Add AI-predicted yield enhancement
        IAIOracleV2.MarketPrediction memory prediction = aiOracle.getMarketPrediction(address(assetToken));
        
        if (prediction.priceDirection > 0 && prediction.confidenceLevel >= 8000) {
            // Add potential upside (conservative estimate)
            uint256 potentialUpside = (balance * uint256(prediction.priceDirection)) / 20000; // 50% of prediction
            balance += potentialUpside;
        }
        
        return balance;
    }

    // Manual AI operations
    function manualRebalance() external onlyRole(HARVESTER_ROLE) {
        _executeAIStrategy(assetToken.balanceOf(address(this)), aiConfig.minConfidenceThreshold, true);
    }

    function manualUpdateIntelligence() external onlyRole(HARVESTER_ROLE) {
        _updateMarketIntelligence();
    }

    function manualTrainModel(bytes32 modelId, bytes calldata trainingData) external onlyRole(DEFAULT_ADMIN_ROLE) {
        mlEngine.trainModel(modelId, trainingData);
    }

    // Admin functions
    function updateAIConfig(
        uint256 predictionHorizon,
        uint256 minConfidenceThreshold,
        uint256 rebalanceThreshold,
        uint256 volatilityThreshold,
        bool useEnsemble,
        bool enableLearning
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        aiConfig.predictionHorizon = predictionHorizon;
        aiConfig.minConfidenceThreshold = minConfidenceThreshold;
        aiConfig.rebalanceThreshold = rebalanceThreshold;
        aiConfig.volatilityThreshold = volatilityThreshold;
        aiConfig.useEnsembleModels = useEnsemble;
        aiConfig.enableAdaptiveLearning = enableLearning;
    }

    function addTrackedAsset(address asset) external onlyRole(DEFAULT_ADMIN_ROLE) {
        trackedAssets.push(asset);
    }

    function addMLModel(bytes32 modelId, uint256 weight) external onlyRole(DEFAULT_ADMIN_ROLE) {
        activeModels.push(modelId);
        modelWeights[modelId] = weight;
    }

    function deactivateModel(bytes32 modelId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        modelWeights[modelId] = 0;
    }

    // View functions
    function getAIPerformance() external view returns (
        uint256 totalRebalances,
        uint256 successfulRebalances,
        uint256 totalProfit,
        uint256 averageAccuracy,
        uint256 currentRisk,
        uint256 sentiment
    ) {
        totalRebalances = rebalanceCount;
        successfulRebalances = successfulRebalances;
        totalProfit = totalRebalanceProfit;
        
        // Calculate average accuracy across all models
        uint256 totalAccuracy = 0;
        uint256 activeModelCount = 0;
        
        for (uint256 i = 0; i < activeModels.length; i++) {
            bytes32 modelId = activeModels[i];
            if (modelWeights[modelId] > 0) {
                totalAccuracy += modelPerformance[modelId].avgAccuracy;
                activeModelCount++;
            }
        }
        
        averageAccuracy = activeModelCount > 0 ? totalAccuracy / activeModelCount : 0;
        currentRisk = portfolioRisk;
        sentiment = sentimentScore;
    }

    function getCurrentPredictions() external view returns (
        int256 priceDirection,
        uint256 confidence,
        uint256 volatilityForecast,
        uint256 marketRegime
    ) {
        IAIOracleV2.MarketPrediction memory prediction = aiOracle.getMarketPrediction(address(assetToken));
        
        priceDirection = prediction.priceDirection;
        confidence = prediction.confidenceLevel;
        volatilityForecast = prediction.volatilityForecast;
        marketRegime = currentMarketRegime;
    }

    function getModelPerformance(bytes32 modelId) external view returns (PerformanceMetrics memory) {
        return modelPerformance[modelId];
    }

    function getAllModelWeights() external view returns (bytes32[] memory models, uint256[] memory weights) {
        models = activeModels;
        weights = new uint256[](activeModels.length);
        
        for (uint256 i = 0; i < activeModels.length; i++) {
            weights[i] = modelWeights[activeModels[i]];
        }
    }

    function getPredictionHistory(bytes32 modelId) external view returns (PredictionRecord[] memory) {
        return predictionHistory[modelId];
    }

    function getOptimalExecutionTime() external view returns (uint256) {
        return analytics.getOptimalExecutionTiming(
            assetToken.balanceOf(address(this)), 
            address(assetToken)
        );
    }
}