// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./BaseStrategy.sol";

// Concentrated Liquidity Interface (like Uniswap V3 for Flow)
interface IFlowConcentratedLiquidity {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    function mint(MintParams calldata params) external payable returns (
        uint256 tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );

    function collect(CollectParams calldata params) external payable returns (
        uint256 amount0,
        uint256 amount1
    );

    function positions(uint256 tokenId) external view returns (
        uint96 nonce,
        address operator,
        address token0,
        address token1,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 feeGrowthInside0LastX128,
        uint256 feeGrowthInside1LastX128,
        uint128 tokensOwed0,
        uint128 tokensOwed1
    );

    function getCurrentTick() external view returns (int24 tick);
    function getSqrtPriceX96() external view returns (uint160 sqrtPriceX96);
}

/// @title FlowConcentratedLiquidityStrategy - Maximum Capital Efficiency
/// @notice Advanced concentrated liquidity strategy for Flow DEXs with auto-rebalancing
contract FlowConcentratedLiquidityStrategy is BaseStrategy {
    using SafeERC20 for IERC20;

    // Flow concentrated liquidity addresses (you'll need real addresses)
    address public constant FLOW_CONCENTRATED_POOL_FACTORY = address(0);
    address public constant FLOW_POSITION_MANAGER = address(0);

    IFlowConcentratedLiquidity public immutable positionManager;
    IERC20 public immutable token0;
    IERC20 public immutable token1;
    uint24 public immutable poolFee;

    // Position management
    uint256[] public activePositions; // NFT token IDs
    int24 public currentTick;
    uint160 public currentSqrtPriceX96;
    
    // Strategy parameters
    int24 public tickSpacing = 60; // Standard tick spacing
    int24 public rangeMultiplier = 10; // Range = current tick ± (rangeMultiplier * tickSpacing)
    uint256 public rebalanceThreshold = 500; // 5% price movement triggers rebalance
    bool public autoCompound = true;
    bool public autoRebalance = true;
    
    // Performance tracking
    uint256 public totalFeesCollected;
    uint256 public totalLiquidityProvided;
    uint256 public rebalanceCount;
    uint256 public lastRebalanceTime;

    event LiquidityAdded(uint256 indexed tokenId, uint128 liquidity, int24 tickLower, int24 tickUpper);
    event FeesCollected(uint256 indexed tokenId, uint256 amount0, uint256 amount1);
    event PositionRebalanced(uint256 oldTokenId, uint256 newTokenId, int24 newTickLower, int24 newTickUpper);
    event RangeOptimized(int24 newTickLower, int24 newTickUpper, uint256 expectedFees);

    constructor(
        address _asset,
        address _token0,
        address _token1,
        uint24 _poolFee,
        address _vault,
        string memory _name
    ) BaseStrategy(_asset, FLOW_POSITION_MANAGER, _vault, _name) {
        require(_token0 != address(0) && _token1 != address(0), "Invalid tokens");
        require(_token0 < _token1, "Tokens not sorted");
        
        positionManager = IFlowConcentratedLiquidity(FLOW_POSITION_MANAGER);
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
        poolFee = _poolFee;
    }

    function _executeStrategy(uint256 amount, bytes calldata data) internal override {
        // Decode concentrated liquidity parameters
        (int24 customRangeMultiplier, bool enableAutoRebalance) = data.length > 0 
            ? abi.decode(data, (int24, bool))
            : (rangeMultiplier, true);

        rangeMultiplier = customRangeMultiplier;
        autoRebalance = enableAutoRebalance;

        // Update current price and tick
        _updateCurrentPrice();

        // Calculate optimal range around current price
        (int24 tickLower, int24 tickUpper) = _calculateOptimalRange();

        // Split asset amount for both tokens
        (uint256 amount0, uint256 amount1) = _calculateOptimalAmounts(amount, tickLower, tickUpper);

        // Convert asset to token0/token1 if needed
        _prepareTokens(amount0, amount1);

        // Create concentrated liquidity position
        _createConcentratedPosition(amount0, amount1, tickLower, tickUpper);
    }

    function _updateCurrentPrice() internal {
        try positionManager.getCurrentTick() returns (int24 tick) {
            currentTick = tick;
        } catch {
            // Fallback to last known tick
        }

        try positionManager.getSqrtPriceX96() returns (uint160 sqrtPrice) {
            currentSqrtPriceX96 = sqrtPrice;
        } catch {
            // Fallback to last known price
        }
    }

    function _calculateOptimalRange() internal view returns (int24 tickLower, int24 tickUpper) {
        // Calculate range around current tick
        int24 tickRange = rangeMultiplier * tickSpacing;
        
        // Ensure ticks are aligned to tick spacing
        tickLower = currentTick - tickRange;
        tickUpper = currentTick + tickRange;
        
        // Align to tick spacing
        tickLower = (tickLower / tickSpacing) * tickSpacing;
        tickUpper = (tickUpper / tickSpacing) * tickSpacing;
        
        return (tickLower, tickUpper);
    }

    function _calculateOptimalAmounts(
        uint256 totalAmount,
        int24 tickLower,
        int24 tickUpper
    ) internal view returns (uint256 amount0, uint256 amount1) {
        // Simplified calculation - in practice would use complex math
        // to calculate exact amounts needed for concentrated liquidity
        
        if (currentTick <= tickLower) {
            // Price below range, use all token0
            amount0 = totalAmount;
            amount1 = 0;
        } else if (currentTick >= tickUpper) {
            // Price above range, use all token1
            amount0 = 0;
            amount1 = totalAmount;
        } else {
            // Price in range, use both tokens
            amount0 = totalAmount / 2;
            amount1 = totalAmount / 2;
        }
    }

    function _prepareTokens(uint256 amount0Needed, uint256 amount1Needed) internal {
        // Convert asset token to token0 and token1 as needed
        // This would involve DEX swaps if asset != token0/token1
        
        uint256 assetBalance = assetToken.balanceOf(address(this));
        
        if (address(assetToken) == address(token0)) {
            // Asset is token0, swap portion to token1 if needed
            if (amount1Needed > 0) {
                _swapToken0ForToken1(amount1Needed);
            }
        } else if (address(assetToken) == address(token1)) {
            // Asset is token1, swap portion to token0 if needed
            if (amount0Needed > 0) {
                _swapToken1ForToken0(amount0Needed);
            }
        } else {
            // Asset is neither, swap to both
            if (amount0Needed > 0) {
                _swapAssetForToken0(amount0Needed);
            }
            if (amount1Needed > 0) {
                _swapAssetForToken1(amount1Needed);
            }
        }
    }

    function _createConcentratedPosition(
        uint256 amount0,
        uint256 amount1,
        int24 tickLower,
        int24 tickUpper
    ) internal {
        // Approve tokens
        token0.approve(address(positionManager), amount0);
        token1.approve(address(positionManager), amount1);

        IFlowConcentratedLiquidity.MintParams memory params = IFlowConcentratedLiquidity.MintParams({
            token0: address(token0),
            token1: address(token1),
            fee: poolFee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: (amount0 * 9500) / 10000, // 5% slippage
            amount1Min: (amount1 * 9500) / 10000, // 5% slippage
            recipient: address(this),
            deadline: block.timestamp + 300
        });

        try positionManager.mint(params) returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 actualAmount0,
            uint256 actualAmount1
        ) {
            activePositions.push(tokenId);
            totalLiquidityProvided += liquidity;
            
            emit LiquidityAdded(tokenId, liquidity, tickLower, tickUpper);
        } catch {
            // Position creation failed
            revert("Failed to create concentrated position");
        }
    }

    function _harvestRewards(bytes calldata) internal override {
        // Collect fees from all active positions
        for (uint256 i = 0; i < activePositions.length; i++) {
            _collectFeesFromPosition(activePositions[i]);
        }

        // Check if rebalancing is needed
        if (autoRebalance && _shouldRebalance()) {
            _rebalancePositions();
        }

        // Auto-compound if enabled
        if (autoCompound) {
            _autoCompound();
        }
    }

    function _collectFeesFromPosition(uint256 tokenId) internal {
        IFlowConcentratedLiquidity.CollectParams memory params = IFlowConcentratedLiquidity.CollectParams({
            tokenId: tokenId,
            recipient: address(this),
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });

        try positionManager.collect(params) returns (uint256 amount0, uint256 amount1) {
            if (amount0 > 0 || amount1 > 0) {
                totalFeesCollected += amount0 + amount1; // Simplified
                emit FeesCollected(tokenId, amount0, amount1);
            }
        } catch {
            // Fee collection failed
        }
    }

    function _shouldRebalance() internal view returns (bool) {
        if (activePositions.length == 0) return false;
        if (block.timestamp < lastRebalanceTime + 1 hours) return false; // Min 1 hour between rebalances

        // Check if current price has moved outside optimal range
        for (uint256 i = 0; i < activePositions.length; i++) {
            uint256 tokenId = activePositions[i];
            
            try positionManager.positions(tokenId) returns (
                uint96,
                address,
                address,
                address,
                uint24,
                int24 tickLower,
                int24 tickUpper,
                uint128 liquidity,
                uint256,
                uint256,
                uint128,
                uint128
            ) {
                if (liquidity > 0) {
                    // Check if current tick is still in optimal range
                    int24 rangeMid = (tickLower + tickUpper) / 2;
                    int24 deviation = currentTick > rangeMid ? currentTick - rangeMid : rangeMid - currentTick;
                    int24 maxDeviation = (rangeMultiplier * tickSpacing * rebalanceThreshold) / 10000;
                    
                    if (deviation > maxDeviation) {
                        return true;
                    }
                }
            } catch {
                continue;
            }
        }

        return false;
    }

    function _rebalancePositions() internal {
        // Close existing positions and create new ones with updated ranges
        uint256 totalValue = _closeAllPositions();
        
        if (totalValue > minHarvestAmount) {
            // Create new position with current optimal range
            (int24 newTickLower, int24 newTickUpper) = _calculateOptimalRange();
            (uint256 amount0, uint256 amount1) = _calculateOptimalAmounts(totalValue, newTickLower, newTickUpper);
            
            _prepareTokens(amount0, amount1);
            _createConcentratedPosition(amount0, amount1, newTickLower, newTickUpper);
            
            rebalanceCount++;
            lastRebalanceTime = block.timestamp;
            
            emit PositionRebalanced(0, activePositions[activePositions.length - 1], newTickLower, newTickUpper);
        }
    }

    function _closeAllPositions() internal returns (uint256 totalValue) {
        uint256 token0Balance = token0.balanceOf(address(this));
        uint256 token1Balance = token1.balanceOf(address(this));

        // Collect all fees first
        for (uint256 i = 0; i < activePositions.length; i++) {
            _collectFeesFromPosition(activePositions[i]);
        }

        // Note: In a real implementation, you would need to call decreaseLiquidity
        // and burn the NFT positions to extract the liquidity
        // For this demo, we'll just clear the positions array
        delete activePositions;

        // Calculate total value (simplified)
        uint256 newToken0Balance = token0.balanceOf(address(this));
        uint256 newToken1Balance = token1.balanceOf(address(this));
        
        totalValue = (newToken0Balance - token0Balance) + (newToken1Balance - token1Balance);
        return totalValue;
    }

    function _autoCompound() internal {
        uint256 token0Balance = token0.balanceOf(address(this));
        uint256 token1Balance = token1.balanceOf(address(this));
        
        if (token0Balance + token1Balance >= minHarvestAmount) {
            // Add collected fees back to liquidity positions
            if (activePositions.length > 0) {
                (int24 tickLower, int24 tickUpper) = _calculateOptimalRange();
                _createConcentratedPosition(token0Balance, token1Balance, tickLower, tickUpper);
            }
        }
    }

    function _swapToken0ForToken1(uint256 amount) internal {
        // Simplified swap implementation
        // Would integrate with Flow DEXs (IncrementFi, BloctoSwap, etc.)
    }

    function _swapToken1ForToken0(uint256 amount) internal {
        // Simplified swap implementation
    }

    function _swapAssetForToken0(uint256 amount) internal {
        // Simplified swap implementation
    }

    function _swapAssetForToken1(uint256 amount) internal {
        // Simplified swap implementation
    }

    function _emergencyWithdraw(bytes calldata) internal override returns (uint256 recovered) {
        // Emergency close all positions and recover tokens
        recovered = _closeAllPositions();
        
        // Convert all tokens back to base asset
        uint256 token0Balance = token0.balanceOf(address(this));
        uint256 token1Balance = token1.balanceOf(address(this));
        
        // Convert token0 and token1 back to asset token if needed
        if (address(assetToken) != address(token0) && token0Balance > 0) {
            // Swap token0 to asset
        }
        
        if (address(assetToken) != address(token1) && token1Balance > 0) {
            // Swap token1 to asset
        }
        
        recovered += assetToken.balanceOf(address(this));
        return recovered;
    }

    function getBalance() external view override returns (uint256) {
        uint256 totalValue = assetToken.balanceOf(address(this));
        
        // Add value of concentrated liquidity positions
        for (uint256 i = 0; i < activePositions.length; i++) {
            uint256 tokenId = activePositions[i];
            
            try positionManager.positions(tokenId) returns (
                uint96,
                address,
                address,
                address,
                uint24,
                int24,
                int24,
                uint128 liquidity,
                uint256,
                uint256,
                uint128 tokensOwed0,
                uint128 tokensOwed1
            ) {
                // Simplified position value calculation
                // In practice would calculate exact token amounts from liquidity
                totalValue += liquidity / 1e12; // Rough approximation
                totalValue += uint256(tokensOwed0) + uint256(tokensOwed1);
            } catch {
                continue;
            }
        }
        
        return totalValue;
    }

    // Manual control functions
    function manualRebalance() external onlyRole(HARVESTER_ROLE) {
        _updateCurrentPrice();
        _rebalancePositions();
    }

    function manualCollectFees() external onlyRole(HARVESTER_ROLE) {
        for (uint256 i = 0; i < activePositions.length; i++) {
            _collectFeesFromPosition(activePositions[i]);
        }
    }

    // Admin functions
    function setRangeMultiplier(int24 _rangeMultiplier) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_rangeMultiplier > 0 && _rangeMultiplier <= 50, "Invalid range multiplier");
        rangeMultiplier = _rangeMultiplier;
    }

    function setRebalanceThreshold(uint256 _threshold) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_threshold <= 5000, "Threshold too high"); // Max 50%
        rebalanceThreshold = _threshold;
    }

    function setAutoRebalance(bool _autoRebalance) external onlyRole(DEFAULT_ADMIN_ROLE) {
        autoRebalance = _autoRebalance;
    }

    function setAutoCompound(bool _autoCompound) external onlyRole(DEFAULT_ADMIN_ROLE) {
        autoCompound = _autoCompound;
    }

    // View functions
    function getActivePositions() external view returns (uint256[] memory) {
        return activePositions;
    }

    function getPositionDetails(uint256 tokenId) external view returns (
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 fees0,
        uint256 fees1
    ) {
        try positionManager.positions(tokenId) returns (
            uint96,
            address,
            address,
            address,
            uint24,
            int24 _tickLower,
            int24 _tickUpper,
            uint128 _liquidity,
            uint256,
            uint256,
            uint128 _fees0,
            uint128 _fees1
        ) {
            return (_tickLower, _tickUpper, _liquidity, uint256(_fees0), uint256(_fees1));
        } catch {
            return (0, 0, 0, 0, 0);
        }
    }

    function getPerformanceMetrics() external view returns (
        uint256 totalFees,
        uint256 totalLiquidity,
        uint256 rebalances,
        uint256 activePositionCount
    ) {
        return (
            totalFeesCollected,
            totalLiquidityProvided,
            rebalanceCount,
            activePositions.length
        );
    }

    function getCurrentRange() external view returns (int24 tickLower, int24 tickUpper) {
        return _calculateOptimalRange();
    }
}