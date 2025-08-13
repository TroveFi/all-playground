// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./BaseStrategy.sol";

// Perpetual trading interfaces (for hedging)
interface IPerpetualProtocol {
    function openPosition(
        address market,
        bool isLong,
        uint256 size,
        uint256 leverage,
        uint256 acceptablePrice
    ) external returns (bytes32 positionId);

    function closePosition(bytes32 positionId, uint256 acceptablePrice) external;
    
    function getPosition(bytes32 positionId) external view returns (
        address market,
        bool isLong,
        uint256 size,
        uint256 entryPrice,
        uint256 leverage,
        int256 pnl,
        bool isOpen
    );

    function getFundingRate(address market) external view returns (int256 fundingRate);
    function getMarketPrice(address market) external view returns (uint256 price);
    function liquidatePosition(bytes32 positionId) external;
}

// Options protocol interface
interface IOptionsProtocol {
    struct OptionData {
        address underlying;
        uint256 strike;
        uint256 expiry;
        bool isCall;
        uint256 premium;
        bool isOpen;
    }

    function buyOption(
        address underlying,
        uint256 strike,
        uint256 expiry,
        bool isCall,
        uint256 amount
    ) external returns (bytes32 optionId);

    function sellOption(bytes32 optionId) external;
    function exerciseOption(bytes32 optionId) external;
    function getOptionData(bytes32 optionId) external view returns (OptionData memory);
    function getImpliedVolatility(address underlying) external view returns (uint256);
}

// Yield farming interface with liquidity provision
interface IAdvancedYieldFarming {
    function provideLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        int24 tickLower,
        int24 tickUpper
    ) external returns (uint256 tokenId);

    function removeLiquidity(
        uint256 tokenId,
        uint128 liquidity
    ) external returns (uint256 amount0, uint256 amount1);

    function collectFees(uint256 tokenId) external returns (uint256 amount0, uint256 amount1);
    
    function getPositionInfo(uint256 tokenId) external view returns (
        uint128 liquidity,
        int24 tickLower,
        int24 tickUpper,
        uint256 feeGrowthInside0LastX128,
        uint256 feeGrowthInside1LastX128,
        uint128 tokensOwed0,
        uint128 tokensOwed1
    );
}

// Volatility oracle for strategy optimization
interface IVolatilityOracle {
    function getHistoricalVolatility(address asset, uint256 timeWindow) external view returns (uint256);
    function getImpliedVolatility(address asset) external view returns (uint256);
    function getRealizedVolatility(address asset) external view returns (uint256);
    function getVolatilitySkew(address asset) external view returns (int256);
    function getVolatilityTrend(address asset) external view returns (int256);
}

/// @title FlowDeltaNeutralStrategy - Market-Neutral Yield Generation
/// @notice Advanced delta-neutral strategy combining spot positions with derivatives hedging
contract FlowDeltaNeutralStrategy is BaseStrategy, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Protocol addresses (you'll need real addresses)
    address public constant PERPETUAL_PROTOCOL = address(0); // Perp protocol on Flow
    address public constant OPTIONS_PROTOCOL = address(0); // Options protocol
    address public constant YIELD_FARMING_PROTOCOL = address(0); // Concentrated liquidity
    address public constant VOLATILITY_ORACLE = address(0); // Volatility data

    IPerpetualProtocol public immutable perpProtocol;
    IOptionsProtocol public immutable optionsProtocol;
    IAdvancedYieldFarming public immutable yieldFarming;
    IVolatilityOracle public immutable volatilityOracle;

    // Strategy components
    enum StrategyType {
        SPOT_PERP_NEUTRAL,     // Long spot + short perp
        LP_HEDGED,             // LP position + hedged with perps
        COVERED_CALL,          // Long spot + sell calls
        PROTECTIVE_PUT,        // Long spot + buy puts
        VOLATILITY_FARMING,    // Long volatility + hedge delta
        BASIS_TRADING          // Exploit spot/futures basis
    }

    struct DeltaNeutralPosition {
        bytes32 positionId;
        StrategyType strategyType;
        
        // Spot component
        uint256 spotAmount;
        address spotAsset;
        
        // Derivative component
        bytes32 hedgePositionId;
        bool isHedgeLong;
        uint256 hedgeSize;
        uint256 hedgeLeverage;
        
        // LP component (if applicable)
        uint256 lpTokenId;
        uint256 lpLiquidity;
        
        // Options component (if applicable)
        bytes32 optionId;
        bool isOptionCall;
        uint256 optionStrike;
        uint256 optionExpiry;
        
        // Position metrics
        uint256 entryTime;
        uint256 targetDelta; // Target delta (0 for neutral)
        uint256 currentDelta;
        int256 totalPnL;
        uint256 yieldEarned;
        uint256 feesEarned;
        bool active;
    }

    struct StrategyConfig {
        uint256 maxPositions;
        uint256 targetVolatility; // Target vol for vol farming
        uint256 rebalanceThreshold; // Delta threshold for rebalancing
        uint256 maxLeverage;
        uint256 hedgeRatio; // Hedge ratio (10000 = 100%)
        uint256 volThresholdHigh; // High vol threshold
        uint256 volThresholdLow; // Low vol threshold
        bool enableAutoRebalance;
        bool enableVolatilityFarming;
        bool enableFundingRateArb;
    }

    // State variables
    mapping(bytes32 => DeltaNeutralPosition) public positions;
    bytes32[] public activePositions;
    mapping(StrategyType => uint256) public strategyPerformance;
    
    StrategyConfig public strategyConfig;
    
    // Performance tracking
    uint256 public totalYieldGenerated;
    uint256 public totalFeesCollected;
    uint256 public totalFundingEarned;
    uint256 public rebalanceCount;
    uint256 public positionCounter;
    
    // Delta management
    int256 public portfolioDelta;
    uint256 public lastRebalanceTime;
    uint256 public targetNeutralityRatio = 9900; // 99% neutral
    
    // Volatility metrics
    uint256 public currentVolatility;
    uint256 public averageVolatility;
    int256 public volTrend;

    event DeltaNeutralPositionOpened(
        bytes32 indexed positionId,
        StrategyType strategyType,
        uint256 spotAmount,
        uint256 hedgeSize
    );
    
    event PositionRebalanced(
        bytes32 indexed positionId,
        int256 oldDelta,
        int256 newDelta,
        uint256 rebalanceCost
    );
    
    event VolatilityFarmingExecuted(
        bytes32 indexed positionId,
        uint256 volCaptured,
        uint256 profit
    );
    
    event FundingRateEarned(
        bytes32 indexed positionId,
        int256 fundingRate,
        uint256 amount
    );
    
    event BasisTradingExecuted(
        uint256 basisDifference,
        uint256 profit
    );

    constructor(
        address _asset,
        address _vault,
        string memory _name
    ) BaseStrategy(_asset, PERPETUAL_PROTOCOL, _vault, _name) {
        perpProtocol = IPerpetualProtocol(PERPETUAL_PROTOCOL);
        optionsProtocol = IOptionsProtocol(OPTIONS_PROTOCOL);
        yieldFarming = IAdvancedYieldFarming(YIELD_FARMING_PROTOCOL);
        volatilityOracle = IVolatilityOracle(VOLATILITY_ORACLE);
        
        // Initialize strategy configuration
        strategyConfig = StrategyConfig({
            maxPositions: 10,
            targetVolatility: 3000, // 30%
            rebalanceThreshold: 500, // 5% delta
            maxLeverage: 5,
            hedgeRatio: 10000, // 100% hedge
            volThresholdHigh: 5000, // 50%
            volThresholdLow: 1000, // 10%
            enableAutoRebalance: true,
            enableVolatilityFarming: true,
            enableFundingRateArb: true
        });
    }

    function _executeStrategy(uint256 amount, bytes calldata data) internal override {
        // Decode strategy parameters
        (StrategyType strategyType, uint256 targetLeverage, bool forceRebalance) = data.length > 0 
            ? abi.decode(data, (StrategyType, uint256, bool))
            : (StrategyType.SPOT_PERP_NEUTRAL, 2, false);

        // Update volatility metrics
        _updateVolatilityMetrics();
        
        // Choose optimal strategy based on market conditions
        if (currentVolatility > strategyConfig.volThresholdHigh && strategyConfig.enableVolatilityFarming) {
            strategyType = StrategyType.VOLATILITY_FARMING;
        } else if (currentVolatility < strategyConfig.volThresholdLow) {
            strategyType = StrategyType.SPOT_PERP_NEUTRAL;
        }

        // Execute the selected strategy
        if (strategyType == StrategyType.SPOT_PERP_NEUTRAL) {
            _executeSpotPerpNeutral(amount, targetLeverage);
        } else if (strategyType == StrategyType.LP_HEDGED) {
            _executeLPHedged(amount, targetLeverage);
        } else if (strategyType == StrategyType.VOLATILITY_FARMING) {
            _executeVolatilityFarming(amount);
        } else if (strategyType == StrategyType.BASIS_TRADING) {
            _executeBasisTrading(amount);
        }

        // Rebalance if needed
        if (forceRebalance || _shouldRebalance()) {
            _rebalancePortfolio();
        }
    }

    function _executeSpotPerpNeutral(uint256 amount, uint256 leverage) internal {
        // Step 1: Take long spot position
        uint256 spotAmount = amount;
        
        // Step 2: Open short perpetual position to hedge
        uint256 perpSize = (spotAmount * strategyConfig.hedgeRatio) / 10000;
        
        bytes32 perpPositionId = perpProtocol.openPosition(
            address(assetToken), // Market
            false, // Short position
            perpSize,
            leverage,
            0 // Accept any price for now
        );
        
        // Step 3: Create position record
        bytes32 positionId = keccak256(abi.encodePacked(
            "SPOT_PERP",
            block.timestamp,
            positionCounter++
        ));
        
        positions[positionId] = DeltaNeutralPosition({
            positionId: positionId,
            strategyType: StrategyType.SPOT_PERP_NEUTRAL,
            spotAmount: spotAmount,
            spotAsset: address(assetToken),
            hedgePositionId: perpPositionId,
            isHedgeLong: false,
            hedgeSize: perpSize,
            hedgeLeverage: leverage,
            lpTokenId: 0,
            lpLiquidity: 0,
            optionId: bytes32(0),
            isOptionCall: false,
            optionStrike: 0,
            optionExpiry: 0,
            entryTime: block.timestamp,
            targetDelta: 0, // Delta neutral
            currentDelta: 0,
            totalPnL: 0,
            yieldEarned: 0,
            feesEarned: 0,
            active: true
        });
        
        activePositions.push(positionId);
        
        emit DeltaNeutralPositionOpened(positionId, StrategyType.SPOT_PERP_NEUTRAL, spotAmount, perpSize);
    }

    function _executeLPHedged(uint256 amount, uint256 leverage) internal {
        // Step 1: Provide concentrated liquidity
        uint256 halfAmount = amount / 2;
        
        // Assume we're providing USDC/WETH liquidity
        address pairedToken = address(0); // TODO: Set WETH address
        
        uint256 lpTokenId = yieldFarming.provideLiquidity(
            address(assetToken),
            pairedToken,
            halfAmount,
            halfAmount,
            -60, // Tick lower
            60   // Tick upper
        );
        
        // Step 2: Hedge the LP position with perpetuals
        // LP positions have inherent long exposure to both assets
        uint256 hedgeSize = amount; // Hedge full exposure
        
        bytes32 perpPositionId = perpProtocol.openPosition(
            address(assetToken),
            false, // Short to hedge
            hedgeSize,
            leverage,
            0
        );
        
        // Step 3: Create position record
        bytes32 positionId = keccak256(abi.encodePacked(
            "LP_HEDGED",
            block.timestamp,
            positionCounter++
        ));
        
        positions[positionId] = DeltaNeutralPosition({
            positionId: positionId,
            strategyType: StrategyType.LP_HEDGED,
            spotAmount: amount,
            spotAsset: address(assetToken),
            hedgePositionId: perpPositionId,
            isHedgeLong: false,
            hedgeSize: hedgeSize,
            hedgeLeverage: leverage,
            lpTokenId: lpTokenId,
            lpLiquidity: 0, // Will be updated
            optionId: bytes32(0),
            isOptionCall: false,
            optionStrike: 0,
            optionExpiry: 0,
            entryTime: block.timestamp,
            targetDelta: 0,
            currentDelta: 0,
            totalPnL: 0,
            yieldEarned: 0,
            feesEarned: 0,
            active: true
        });
        
        activePositions.push(positionId);
        
        emit DeltaNeutralPositionOpened(positionId, StrategyType.LP_HEDGED, amount, hedgeSize);
    }

    function _executeVolatilityFarming(uint256 amount) internal {
        // Volatility farming: benefit from high volatility while staying delta neutral
        
        // Step 1: Create a straddle (buy call + buy put)
        uint256 currentPrice = perpProtocol.getMarketPrice(address(assetToken));
        uint256 expiry = block.timestamp + 7 days; // 1 week expiry
        
        bytes32 callOptionId = optionsProtocol.buyOption(
            address(assetToken),
            currentPrice, // ATM call
            expiry,
            true, // Call option
            amount / 2
        );
        
        bytes32 putOptionId = optionsProtocol.buyOption(
            address(assetToken),
            currentPrice, // ATM put
            expiry,
            false, // Put option
            amount / 2
        );
        
        // Step 2: Delta hedge the options
        // ATM straddle has near-zero delta initially, but will need rebalancing
        
        bytes32 positionId = keccak256(abi.encodePacked(
            "VOL_FARMING",
            block.timestamp,
            positionCounter++
        ));
        
        positions[positionId] = DeltaNeutralPosition({
            positionId: positionId,
            strategyType: StrategyType.VOLATILITY_FARMING,
            spotAmount: amount,
            spotAsset: address(assetToken),
            hedgePositionId: bytes32(0),
            isHedgeLong: false,
            hedgeSize: 0,
            hedgeLeverage: 1,
            lpTokenId: 0,
            lpLiquidity: 0,
            optionId: callOptionId, // Store call option (put in separate mapping if needed)
            isOptionCall: true,
            optionStrike: currentPrice,
            optionExpiry: expiry,
            entryTime: block.timestamp,
            targetDelta: 0,
            currentDelta: 0,
            totalPnL: 0,
            yieldEarned: 0,
            feesEarned: 0,
            active: true
        });
        
        activePositions.push(positionId);
        
        emit DeltaNeutralPositionOpened(positionId, StrategyType.VOLATILITY_FARMING, amount, 0);
    }

    function _executeBasisTrading(uint256 amount) internal {
        // Exploit the basis (difference between spot and futures prices)
        uint256 spotPrice = perpProtocol.getMarketPrice(address(assetToken));
        
        // For simplification, assume futures are trading at premium
        // In reality, would check actual futures prices
        
        // Long spot, short futures
        bytes32 futuresPositionId = perpProtocol.openPosition(
            address(assetToken),
            false, // Short futures
            amount,
            2, // 2x leverage
            0
        );
        
        bytes32 positionId = keccak256(abi.encodePacked(
            "BASIS_TRADING",
            block.timestamp,
            positionCounter++
        ));
        
        positions[positionId] = DeltaNeutralPosition({
            positionId: positionId,
            strategyType: StrategyType.BASIS_TRADING,
            spotAmount: amount,
            spotAsset: address(assetToken),
            hedgePositionId: futuresPositionId,
            isHedgeLong: false,
            hedgeSize: amount,
            hedgeLeverage: 2,
            lpTokenId: 0,
            lpLiquidity: 0,
            optionId: bytes32(0),
            isOptionCall: false,
            optionStrike: 0,
            optionExpiry: 0,
            entryTime: block.timestamp,
            targetDelta: 0,
            currentDelta: 0,
            totalPnL: 0,
            yieldEarned: 0,
            feesEarned: 0,
            active: true
        });
        
        activePositions.push(positionId);
        
        emit DeltaNeutralPositionOpened(positionId, StrategyType.BASIS_TRADING, amount, amount);
    }

    function _updateVolatilityMetrics() internal {
        currentVolatility = volatilityOracle.getRealizedVolatility(address(assetToken));
        
        // Update moving average
        if (averageVolatility == 0) {
            averageVolatility = currentVolatility;
        } else {
            averageVolatility = (averageVolatility * 9 + currentVolatility) / 10; // EMA
        }
        
        volTrend = volatilityOracle.getVolatilityTrend(address(assetToken));
    }

    function _shouldRebalance() internal view returns (bool) {
        if (!strategyConfig.enableAutoRebalance) return false;
        
        // Check if portfolio delta has drifted too far from neutral
        uint256 deltaThreshold = strategyConfig.rebalanceThreshold;
        int256 absDelta = portfolioDelta > 0 ? portfolioDelta : -portfolioDelta;
        
        return uint256(absDelta) > deltaThreshold;
    }

    function _rebalancePortfolio() internal {
        int256 totalDelta = 0;
        
        // Calculate total portfolio delta
        for (uint256 i = 0; i < activePositions.length; i++) {
            bytes32 positionId = activePositions[i];
            DeltaNeutralPosition storage position = positions[positionId];
            
            if (position.active) {
                int256 positionDelta = _calculatePositionDelta(positionId);
                totalDelta += positionDelta;
                position.currentDelta = uint256(positionDelta > 0 ? positionDelta : -positionDelta);
            }
        }
        
        portfolioDelta = totalDelta;
        
        // If delta is too high, hedge it
        if (_shouldRebalance()) {
            _hedgePortfolioDelta(totalDelta);
        }
        
        lastRebalanceTime = block.timestamp;
        rebalanceCount++;
    }

    function _calculatePositionDelta(bytes32 positionId) internal view returns (int256) {
        DeltaNeutralPosition memory position = positions[positionId];
        
        if (!position.active) return 0;
        
        // Simplified delta calculation
        // In reality, would use actual option delta calculations
        
        if (position.strategyType == StrategyType.SPOT_PERP_NEUTRAL) {
            // Long spot (delta = +1) + short perp (delta = -1) = 0
            return int256(position.spotAmount) - int256(position.hedgeSize);
        } else if (position.strategyType == StrategyType.LP_HEDGED) {
            // LP position has variable delta based on price movement
            return int256(position.spotAmount / 2); // Simplified
        } else if (position.strategyType == StrategyType.VOLATILITY_FARMING) {
            // Options delta changes with price and time
            return 0; // Simplified - assume delta neutral straddle
        }
        
        return 0;
    }

    function _hedgePortfolioDelta(int256 totalDelta) internal {
        if (totalDelta == 0) return;
        
        // Use perpetuals to hedge the delta
        bool isLong = totalDelta < 0; // If portfolio is short delta, go long
        uint256 hedgeSize = uint256(totalDelta > 0 ? totalDelta : -totalDelta);
        
        perpProtocol.openPosition(
            address(assetToken),
            isLong,
            hedgeSize,
            2, // 2x leverage
            0
        );
        
        emit PositionRebalanced(
            bytes32(0), // Portfolio-level rebalance
            portfolioDelta,
            0, // Target is always 0
            hedgeSize
        );
    }

    function _harvestRewards(bytes calldata) internal override {
        uint256 totalHarvested = 0;
        
        for (uint256 i = 0; i < activePositions.length; i++) {
            bytes32 positionId = activePositions[i];
            DeltaNeutralPosition storage position = positions[positionId];
            
            if (position.active) {
                uint256 harvested = _harvestPositionRewards(positionId);
                totalHarvested += harvested;
            }
        }
        
        // Check for funding rate arbitrage opportunities
        if (strategyConfig.enableFundingRateArb) {
            _checkFundingRateOpportunities();
        }
        
        totalYieldGenerated += totalHarvested;
    }

    function _harvestPositionRewards(bytes32 positionId) internal returns (uint256) {
        DeltaNeutralPosition storage position = positions[positionId];
        uint256 totalRewards = 0;
        
        if (position.strategyType == StrategyType.LP_HEDGED && position.lpTokenId > 0) {
            // Collect LP fees
            try yieldFarming.collectFees(position.lpTokenId) returns (uint256 amount0, uint256 amount1) {
                uint256 fees = amount0 + amount1; // Simplified
                position.feesEarned += fees;
                totalRewards += fees;
                totalFeesCollected += fees;
            } catch {
                // Fee collection failed
            }
        }
        
        // Check funding rates for perpetual positions
        if (position.hedgePositionId != bytes32(0)) {
            int256 fundingRate = perpProtocol.getFundingRate(address(assetToken));
            
            if (fundingRate > 0 && !position.isHedgeLong) {
                // Earning funding (short position with positive funding)
                uint256 fundingEarned = (position.hedgeSize * uint256(fundingRate)) / 10000;
                position.yieldEarned += fundingEarned;
                totalRewards += fundingEarned;
                totalFundingEarned += fundingEarned;
                
                emit FundingRateEarned(positionId, fundingRate, fundingEarned);
            }
        }
        
        // Volatility farming rewards
        if (position.strategyType == StrategyType.VOLATILITY_FARMING) {
            uint256 volCaptured = _calculateVolatilityCaptured(positionId);
            if (volCaptured > 0) {
                position.yieldEarned += volCaptured;
                totalRewards += volCaptured;
                
                emit VolatilityFarmingExecuted(positionId, currentVolatility, volCaptured);
            }
        }
        
        return totalRewards;
    }

    function _calculateVolatilityCaptured(bytes32 positionId) internal view returns (uint256) {
        DeltaNeutralPosition memory position = positions[positionId];
        
        // Simplified volatility capture calculation
        // In reality, would calculate based on actual option payoffs
        
        uint256 timeElapsed = block.timestamp - position.entryTime;
        if (timeElapsed < 1 days) return 0;
        
        uint256 volDifference = currentVolatility > position.targetDelta 
            ? currentVolatility - position.targetDelta 
            : 0;
            
        return (position.spotAmount * volDifference * timeElapsed) / (365 days * 10000);
    }

    function _checkFundingRateOpportunities() internal {
        int256 fundingRate = perpProtocol.getFundingRate(address(assetToken));
        
        // If funding rate is very positive, consider opening short positions
        if (fundingRate > 100) { // 1% funding rate
            // Opportunity to earn funding by being short
            // This would involve opening additional short positions
        }
    }

    function _emergencyWithdraw(bytes calldata) internal override returns (uint256 recovered) {
        uint256 totalRecovered = 0;
        
        // Close all active positions
        for (uint256 i = 0; i < activePositions.length; i++) {
            bytes32 positionId = activePositions[i];
            DeltaNeutralPosition storage position = positions[positionId];
            
            if (position.active) {
                totalRecovered += _emergencyClosePosition(positionId);
            }
        }
        
        // Add liquid balance
        totalRecovered += assetToken.balanceOf(address(this));
        
        return totalRecovered;
    }

    function _emergencyClosePosition(bytes32 positionId) internal returns (uint256 recovered) {
        DeltaNeutralPosition storage position = positions[positionId];
        
        // Close perpetual positions
        if (position.hedgePositionId != bytes32(0)) {
            try perpProtocol.closePosition(position.hedgePositionId, 0) {
                // Position closed successfully
            } catch {
                // Position close failed
            }
        }
        
        // Close LP positions
        if (position.lpTokenId > 0) {
            try yieldFarming.removeLiquidity(position.lpTokenId, 0) returns (uint256 amount0, uint256 amount1) {
                recovered += amount0 + amount1;
            } catch {
                // LP removal failed
            }
        }
        
        // Exercise/sell options
        if (position.optionId != bytes32(0)) {
            try optionsProtocol.sellOption(position.optionId) {
                // Option sold successfully
            } catch {
                // Option sale failed
            }
        }
        
        position.active = false;
        recovered += position.spotAmount; // Return spot amount
        
        return recovered;
    }

    function getBalance() external view override returns (uint256) {
        uint256 totalBalance = assetToken.balanceOf(address(this));
        
        // Add value of all active positions
        for (uint256 i = 0; i < activePositions.length; i++) {
            bytes32 positionId = activePositions[i];
            DeltaNeutralPosition memory position = positions[positionId];
            
            if (position.active) {
                totalBalance += position.spotAmount;
                totalBalance += position.yieldEarned;
                totalBalance += position.feesEarned;
                
                // Add PnL (could be negative)
                if (position.totalPnL > 0) {
                    totalBalance += uint256(position.totalPnL);
                } else if (position.totalPnL < 0) {
                    uint256 loss = uint256(-position.totalPnL);
                    totalBalance = totalBalance > loss ? totalBalance - loss : 0;
                }
            }
        }
        
        return totalBalance;
    }

    // Manual operations
    function manualRebalance() external onlyRole(HARVESTER_ROLE) {
        _rebalancePortfolio();
    }

    function manualClosePosition(bytes32 positionId) external onlyRole(HARVESTER_ROLE) {
        require(positions[positionId].active, "Position not active");
        _emergencyClosePosition(positionId);
    }

    function manualHarvestPosition(bytes32 positionId) external onlyRole(HARVESTER_ROLE) {
        require(positions[positionId].active, "Position not active");
        _harvestPositionRewards(positionId);
    }

    // Admin functions
    function updateStrategyConfig(
        uint256 maxPositions,
        uint256 rebalanceThreshold,
        uint256 maxLeverage,
        uint256 hedgeRatio,
        bool enableAutoRebalance,
        bool enableVolFarming,
        bool enableFundingArb
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        strategyConfig.maxPositions = maxPositions;
        strategyConfig.rebalanceThreshold = rebalanceThreshold;
        strategyConfig.maxLeverage = maxLeverage;
        strategyConfig.hedgeRatio = hedgeRatio;
        strategyConfig.enableAutoRebalance = enableAutoRebalance;
        strategyConfig.enableVolatilityFarming = enableVolFarming;
        strategyConfig.enableFundingRateArb = enableFundingArb;
    }

    function setVolatilityThresholds(uint256 high, uint256 low) external onlyRole(DEFAULT_ADMIN_ROLE) {
        strategyConfig.volThresholdHigh = high;
        strategyConfig.volThresholdLow = low;
    }

    function emergencyCloseAllPositions() external onlyRole(EMERGENCY_ROLE) {
        for (uint256 i = 0; i < activePositions.length; i++) {
            bytes32 positionId = activePositions[i];
            if (positions[positionId].active) {
                _emergencyClosePosition(positionId);
            }
        }
    }

    // View functions
    function getDeltaNeutralPerformance() external view returns (
        uint256 totalYield,
        uint256 totalFees,
        uint256 totalFunding,
        uint256 rebalances,
        int256 currentPortfolioDelta,
        uint256 activePositionCount
    ) {
        totalYield = totalYieldGenerated;
        totalFees = totalFeesCollected;
        totalFunding = totalFundingEarned;
        rebalances = rebalanceCount;
        currentPortfolioDelta = portfolioDelta;
        activePositionCount = activePositions.length;
    }

    function getPosition(bytes32 positionId) external view returns (DeltaNeutralPosition memory) {
        return positions[positionId];
    }

    function getAllActivePositions() external view returns (DeltaNeutralPosition[] memory) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < activePositions.length; i++) {
            if (positions[activePositions[i]].active) {
                activeCount++;
            }
        }

        DeltaNeutralPosition[] memory activePositionsList = new DeltaNeutralPosition[](activeCount);
        uint256 index = 0;

        for (uint256 i = 0; i < activePositions.length; i++) {
            bytes32 positionId = activePositions[i];
            if (positions[positionId].active) {
                activePositionsList[index] = positions[positionId];
                index++;
            }
        }

        return activePositionsList;
    }

    function getVolatilityMetrics() external view returns (
        uint256 current,
        uint256 average,
        int256 trend,
        uint256 implied
    ) {
        current = currentVolatility;
        average = averageVolatility;
        trend = volTrend;
        implied = volatilityOracle.getImpliedVolatility(address(assetToken));
    }

    function getCurrentFundingRate() external view returns (int256) {
        return perpProtocol.getFundingRate(address(assetToken));
    }

    function getStrategyPerformance(StrategyType strategyType) external view returns (uint256) {
        return strategyPerformance[strategyType];
    }
}