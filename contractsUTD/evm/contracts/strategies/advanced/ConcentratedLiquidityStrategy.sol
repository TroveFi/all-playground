// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// Uniswap V3 style concentrated liquidity interfaces
interface INonfungiblePositionManager {
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

    struct IncreaseLiquidityParams {
        uint256 tokenId;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
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

    function increaseLiquidity(IncreaseLiquidityParams calldata params) external payable returns (
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );

    function decreaseLiquidity(DecreaseLiquidityParams calldata params) external payable returns (
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
}

interface IUniswapV3Pool {
    function slot0() external view returns (
        uint160 sqrtPriceX96,
        int24 tick,
        uint16 observationIndex,
        uint16 observationCardinality,
        uint16 observationCardinalityNext,
        uint8 feeProtocol,
        bool unlocked
    );

    function tickSpacing() external view returns (int24);
    function fee() external view returns (uint24);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function liquidity() external view returns (uint128);
}

interface ITickMath {
    function getSqrtRatioAtTick(int24 tick) external pure returns (uint160 sqrtPriceX96);
    function getTickAtSqrtRatio(uint160 sqrtPriceX96) external pure returns (int24 tick);
}

/// @title ConcentratedLiquidityStrategy - Uniswap V3 Style Liquidity Provision
/// @notice Provides concentrated liquidity with automatic range management and rebalancing
/// @dev Manages liquidity positions within specific price ranges to maximize fee collection
contract ConcentratedLiquidityStrategy is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ====================================================================
    // CONSTANTS & ROLES
    // ====================================================================
    
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    // Protocol addresses (conceptual - would need actual V3 DEX on Flow)
    address public constant POSITION_MANAGER = 0x1234567890123456789012345678901234567890;
    address public constant TICK_MATH = 0x2345678901234567890123456789012345678901;
    
    // Pool configuration
    uint24 public constant POOL_FEE = 3000; // 0.3% fee tier
    int24 public constant TICK_SPACING = 60; // 0.3% tier tick spacing

    // ====================================================================
    // STATE VARIABLES
    // ====================================================================
    
    INonfungiblePositionManager public immutable positionManager;
    ITickMath public immutable tickMath;
    IERC20 public immutable token0;
    IERC20 public immutable token1;
    IUniswapV3Pool public immutable pool;
    
    address public vault;
    bool public strategyPaused;
    
    // Position tracking
    uint256[] public tokenIds; // NFT token IDs for positions
    mapping(uint256 => bool) public activePositions;
    uint256 public totalDeployed;
    uint256 public totalHarvested;
    uint256 public lastHarvestTime;
    
    // Range management
    int24 public baseTick; // Current market tick
    int24 public rangeWidth = 4000; // Default range width (±40% from current price)
    int24 public rebalanceThreshold = 2000; // Rebalance when price moves 20%
    uint256 public maxPositions = 3; // Maximum concurrent positions
    
    // Fee collection
    uint256 public collectedFees0;
    uint256 public collectedFees1;
    uint256 public lastFeeCollection;
    uint256 public feeCollectionInterval = 1 days;
    
    // Auto-management
    bool public autoRebalance = true;
    bool public autoCollectFees = true;
    uint256 public lastRebalanceTime;
    uint256 public rebalanceInterval = 4 hours;
    
    // Performance tracking
    uint256 public totalFeesEarned;
    uint256 public rebalanceCount;
    uint256 public impermanentLoss;
    uint256 public totalLiquidityProvided;

    // ====================================================================
    // EVENTS
    // ====================================================================
    
    event StrategyExecuted(uint256 tokenId, int24 tickLower, int24 tickUpper, uint128 liquidity);
    event LiquidityAdded(uint256 tokenId, uint256 amount0, uint256 amount1);
    event LiquidityRemoved(uint256 tokenId, uint256 amount0, uint256 amount1);
    event FeesCollected(uint256 tokenId, uint256 amount0, uint256 amount1);
    event PositionRebalanced(uint256 oldTokenId, uint256 newTokenId, int24 newTickLower, int24 newTickUpper);
    event RangeAdjusted(int24 oldRangeWidth, int24 newRangeWidth);
    event AutoRebalanceTriggered(int24 currentTick, int24 positionTick);

    // ====================================================================
    // CONSTRUCTOR
    // ====================================================================
    
    constructor(
        address _vault,
        address _token0,
        address _token1,
        address _pool
    ) {
        require(_vault != address(0), "Invalid vault");
        require(_token0 != address(0), "Invalid token0");
        require(_token1 != address(0), "Invalid token1");
        require(_pool != address(0), "Invalid pool");

        vault = _vault;
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
        pool = IUniswapV3Pool(_pool);
        
        positionManager = INonfungiblePositionManager(POSITION_MANAGER);
        tickMath = ITickMath(TICK_MATH);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(VAULT_ROLE, _vault);
    }

    // ====================================================================
    // MODIFIERS
    // ====================================================================
    
    modifier onlyVault() {
        require(msg.sender == vault, "Only vault can call");
        _;
    }

    modifier whenNotPaused() {
        require(!strategyPaused, "Strategy is paused");
        _;
    }

    modifier autoManagement() {
        _checkAutoManagement();
        _;
    }

    // ====================================================================
    // MAIN STRATEGY FUNCTIONS
    // ====================================================================

    function execute(uint256 amount, bytes calldata data) 
        external 
        onlyVault 
        nonReentrant 
        whenNotPaused 
        autoManagement 
    {
        require(amount > 0, "Amount must be greater than 0");

        // Decode range parameters if provided
        (int24 customRangeWidth, bool useFullRange) = data.length > 0 ?
            abi.decode(data, (int24, bool)) : (rangeWidth, false);

        // Get current market state
        (uint160 sqrtPriceX96, int24 currentTick,,,,,) = pool.slot0();
        baseTick = currentTick;

        // Calculate position range
        (int24 tickLower, int24 tickUpper) = useFullRange ?
            _getFullRangePositions() :
            _calculateOptimalRange(currentTick, customRangeWidth);

        // Create concentrated liquidity position
        uint256 tokenId = _createPosition(amount, tickLower, tickUpper);

        totalDeployed += amount;
        
        emit StrategyExecuted(tokenId, tickLower, tickUpper, 0);
    }

    function harvest(bytes calldata data) 
        external 
        onlyVault 
        nonReentrant 
        whenNotPaused 
        autoManagement 
    {
        uint256 totalCollected0 = 0;
        uint256 totalCollected1 = 0;

        // 1. Collect fees from all active positions
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            if (activePositions[tokenId]) {
                (uint256 amount0, uint256 amount1) = _collectFeesFromPosition(tokenId);
                totalCollected0 += amount0;
                totalCollected1 += amount1;
            }
        }

        // 2. Check if rebalancing is needed
        if (autoRebalance && _needsRebalancing()) {
            _rebalancePositions();
        }

        // 3. Convert collected fees to base asset and transfer to vault
        uint256 totalHarvestedValue = _convertAndTransferToVault(totalCollected0, totalCollected1);

        if (totalHarvestedValue > 0) {
            totalHarvested += totalHarvestedValue;
            totalFeesEarned += totalHarvestedValue;
        }

        lastHarvestTime = block.timestamp;
        lastFeeCollection = block.timestamp;
    }

    function emergencyExit(bytes calldata data) 
        external 
        onlyRole(EMERGENCY_ROLE) 
        nonReentrant 
    {
        strategyPaused = true;

        uint256 totalRecovered0 = 0;
        uint256 totalRecovered1 = 0;

        // Close all positions
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            if (activePositions[tokenId]) {
                (uint256 amount0, uint256 amount1) = _closePosition(tokenId);
                totalRecovered0 += amount0;
                totalRecovered1 += amount1;
                activePositions[tokenId] = false;
            }
        }

        // Transfer all recovered tokens to vault
        if (totalRecovered0 > 0) {
            token0.safeTransfer(vault, totalRecovered0);
        }
        if (totalRecovered1 > 0) {
            token1.safeTransfer(vault, totalRecovered1);
        }
    }

    // ====================================================================
    // CONCENTRATED LIQUIDITY LOGIC
    // ====================================================================

    function _createPosition(
        uint256 amount,
        int24 tickLower,
        int24 tickUpper
    ) internal returns (uint256 tokenId) {
        // Calculate token amounts based on current price and range
        (uint256 amount0Desired, uint256 amount1Desired) = _calculateTokenAmounts(
            amount,
            tickLower,
            tickUpper
        );

        // Approve tokens for position manager
        token0.approve(address(positionManager), amount0Desired);
        token1.approve(address(positionManager), amount1Desired);

        // Create position
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: address(token0),
            token1: address(token1),
            fee: POOL_FEE,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount0Desired,
            amount1Desired: amount1Desired,
            amount0Min: (amount0Desired * 95) / 100, // 5% slippage
            amount1Min: (amount1Desired * 95) / 100,
            recipient: address(this),
            deadline: block.timestamp + 300
        });

        uint256 amount0;
        uint256 amount1;
        (tokenId, , amount0, amount1) = positionManager.mint(params);

        // Track position
        tokenIds.push(tokenId);
        activePositions[tokenId] = true;
        totalLiquidityProvided += amount0 + amount1; // Simplified tracking

        emit LiquidityAdded(tokenId, amount0, amount1);
    }

    function _calculateTokenAmounts(
        uint256 totalAmount,
        int24 tickLower,
        int24 tickUpper
    ) internal view returns (uint256 amount0, uint256 amount1) {
        (uint160 sqrtPriceX96, int24 currentTick,,,,,) = pool.slot0();
        
        // Get sqrt prices at ticks
        uint160 sqrtRatioAX96 = tickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtRatioBX96 = tickMath.getSqrtRatioAtTick(tickUpper);

        // Calculate optimal token distribution
        if (currentTick < tickLower) {
            // Price below range, provide only token0
            amount0 = totalAmount;
            amount1 = 0;
        } else if (currentTick >= tickUpper) {
            // Price above range, provide only token1
            amount0 = 0;
            amount1 = totalAmount;
        } else {
            // Price in range, calculate proportion
            // Simplified calculation - in production would use proper math
            int24 tickRange = tickUpper - tickLower;
            int24 currentOffset = currentTick - tickLower;
            
            // Convert to uint256 safely
            uint256 proportion = uint256(int256(currentOffset)) * 1e18 / uint256(int256(tickRange));
            amount0 = (totalAmount * (1e18 - proportion)) / 1e18;
            amount1 = (totalAmount * proportion) / 1e18;
        }
    }

    function _calculateOptimalRange(
        int24 currentTick,
        int24 width
    ) internal view returns (int24 tickLower, int24 tickUpper) {
        int24 tickSpacing = pool.tickSpacing();
        
        // Round ticks to nearest valid tick
        tickLower = ((currentTick - width) / tickSpacing) * tickSpacing;
        tickUpper = ((currentTick + width) / tickSpacing) * tickSpacing;
        
        // Ensure minimum range
        if (tickUpper - tickLower < tickSpacing * 2) {
            tickLower -= tickSpacing;
            tickUpper += tickSpacing;
        }
    }

    function _getFullRangePositions() internal view returns (int24 tickLower, int24 tickUpper) {
        // Full range positions (maximum possible range)
        tickLower = -887272; // Min tick for most pools
        tickUpper = 887272;  // Max tick for most pools
    }

    // ====================================================================
    // POSITION MANAGEMENT
    // ====================================================================

    function _needsRebalancing() internal view returns (bool) {
        if (block.timestamp < lastRebalanceTime + rebalanceInterval) {
            return false;
        }

        (uint160 sqrtPriceX96, int24 currentTick,,,,,) = pool.slot0();
        
        // Check if price has moved significantly from any active position
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            if (activePositions[tokenId]) {
                (,, address token0Addr, address token1Addr,, int24 tickLower, int24 tickUpper, uint128 liquidity,,,,) = 
                    positionManager.positions(tokenId);
                
                // Check if current price is near the edges of the range
                int24 lowerThreshold = tickLower + rebalanceThreshold;
                int24 upperThreshold = tickUpper - rebalanceThreshold;
                
                if (currentTick <= lowerThreshold || currentTick >= upperThreshold) {
                    return true;
                }
            }
        }

        return false;
    }

    function _rebalancePositions() internal {
        (uint160 sqrtPriceX96, int24 currentTick,,,,,) = pool.slot0();
        
        // Close positions that are out of range
        uint256[] memory positionsToClose = new uint256[](tokenIds.length);
        uint256 closeCount = 0;
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            if (activePositions[tokenId]) {
                (,, address token0Addr, address token1Addr,, int24 tickLower, int24 tickUpper, uint128 liquidity,,,,) = 
                    positionManager.positions(tokenId);
                
                // Check if position needs rebalancing
                if (currentTick <= tickLower + rebalanceThreshold || 
                    currentTick >= tickUpper - rebalanceThreshold) {
                    positionsToClose[closeCount] = tokenId;
                    closeCount++;
                }
            }
        }

        // Close out-of-range positions and create new ones
        for (uint256 i = 0; i < closeCount; i++) {
            uint256 oldTokenId = positionsToClose[i];
            (uint256 amount0, uint256 amount1) = _closePosition(oldTokenId);
            activePositions[oldTokenId] = false;
            
            // Create new position around current price
            (int24 newTickLower, int24 newTickUpper) = _calculateOptimalRange(currentTick, rangeWidth);
            uint256 totalAmount = amount0 + amount1; // Simplified
            uint256 newTokenId = _createPosition(totalAmount, newTickLower, newTickUpper);
            
            rebalanceCount++;
            emit PositionRebalanced(oldTokenId, newTokenId, newTickLower, newTickUpper);
        }

        lastRebalanceTime = block.timestamp;
    }

    function _closePosition(uint256 tokenId) internal returns (uint256 amount0, uint256 amount1) {
        // Get position info
        (,, address token0Addr, address token1Addr,, int24 tickLower, int24 tickUpper, uint128 liquidity,,,,) = 
            positionManager.positions(tokenId);

        if (liquidity > 0) {
            // Decrease liquidity to zero
            INonfungiblePositionManager.DecreaseLiquidityParams memory decreaseParams = 
                INonfungiblePositionManager.DecreaseLiquidityParams({
                    tokenId: tokenId,
                    liquidity: liquidity,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp + 300
                });

            positionManager.decreaseLiquidity(decreaseParams);
        }

        // Collect all fees and liquidity
        INonfungiblePositionManager.CollectParams memory collectParams = 
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });

        (amount0, amount1) = positionManager.collect(collectParams);

        emit LiquidityRemoved(tokenId, amount0, amount1);
    }

    function _collectFeesFromPosition(uint256 tokenId) internal returns (uint256 amount0, uint256 amount1) {
        INonfungiblePositionManager.CollectParams memory params = 
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });

        (amount0, amount1) = positionManager.collect(params);

        collectedFees0 += amount0;
        collectedFees1 += amount1;

        emit FeesCollected(tokenId, amount0, amount1);
    }

    function _convertAndTransferToVault(
        uint256 amount0,
        uint256 amount1
    ) internal returns (uint256 totalValue) {
        // Convert both tokens to base asset value
        // This is simplified - in production would use price oracles
        totalValue = amount0 + amount1; // Assuming 1:1 for simplicity
        
        // Transfer collected fees to vault (keeping in original tokens for now)
        if (amount0 > 0) {
            token0.safeTransfer(vault, amount0);
        }
        if (amount1 > 0) {
            token1.safeTransfer(vault, amount1);
        }
    }

    // ====================================================================
    // AUTO MANAGEMENT
    // ====================================================================

    function _checkAutoManagement() internal {
        // Auto-collect fees
        if (autoCollectFees && 
            block.timestamp >= lastFeeCollection + feeCollectionInterval) {
            _autoCollectFees();
        }

        // Auto-rebalance check
        if (autoRebalance && _needsRebalancing()) {
            emit AutoRebalanceTriggered(baseTick, 0); // Simplified
        }
    }

    function _autoCollectFees() internal {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            if (activePositions[tokenId]) {
                _collectFeesFromPosition(tokenId);
            }
        }
    }

    // ====================================================================
    // ENHANCED STRATEGY INTERFACE
    // ====================================================================

    function getHealthFactor() external view returns (uint256) {
        // Concentrated liquidity doesn't have traditional health factor
        return type(uint256).max;
    }

    function getLeverageRatio() external pure returns (uint256) {
        return 1e18; // No leverage in LP positions
    }

    function getPositionValue() external view returns (uint256 collateral, uint256 debt) {
        collateral = getBalance();
        debt = 0; // No debt in LP
    }

    function checkLiquidationRisk() external pure returns (bool atRisk, uint256 buffer) {
        atRisk = false; // No liquidation risk in LP
        buffer = type(uint256).max;
    }

    function getMaxWithdrawable() external view returns (uint256) {
        return getBalance();
    }

    function adjustLeverage(uint256 targetRatio, uint256 maxSlippage) external onlyRole(AGENT_ROLE) {
        // Adjust range width instead of leverage
        rangeWidth = int24(uint24(targetRatio / 100)); // Convert ratio to tick range
        emit RangeAdjusted(rangeWidth, int24(uint24(targetRatio / 100)));
    }

    function emergencyDelever() external onlyRole(AGENT_ROLE) {
        // Close all positions in emergency
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (activePositions[tokenIds[i]]) {
                _closePosition(tokenIds[i]);
                activePositions[tokenIds[i]] = false;
            }
        }
    }

    function rebalance(bytes calldata rebalanceData) external onlyRole(AGENT_ROLE) {
        (int24 newRangeWidth) = abi.decode(rebalanceData, (int24));
        rangeWidth = newRangeWidth;
        _rebalancePositions();
    }

    function setRiskParameters(
        uint256 maxLeverage,
        uint256 targetHealthFactor,
        uint256 liquidationBuffer
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Use parameters to set range management
        rangeWidth = int24(uint24(maxLeverage / 100));
        rebalanceThreshold = int24(uint24(liquidationBuffer));
    }

    // ====================================================================
    // VIEW FUNCTIONS
    // ====================================================================

    function getBalance() public view returns (uint256 totalValue) {
        // Calculate total value of all positions plus loose tokens
        totalValue = token0.balanceOf(address(this)) + token1.balanceOf(address(this));
        
        // Add value of active positions (simplified)
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (activePositions[tokenIds[i]]) {
                // In production, would calculate actual position value
                totalValue += 0; // Placeholder
            }
        }
    }

    function getActivePositions() external view returns (
        uint256[] memory activeTokenIds,
        int24[] memory tickLowers,
        int24[] memory tickUppers,
        uint128[] memory liquidities
    ) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (activePositions[tokenIds[i]]) {
                activeCount++;
            }
        }

        activeTokenIds = new uint256[](activeCount);
        tickLowers = new int24[](activeCount);
        tickUppers = new int24[](activeCount);
        liquidities = new uint128[](activeCount);

        uint256 index = 0;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            if (activePositions[tokenId]) {
                (,, address token0Addr, address token1Addr,, int24 tickLower, int24 tickUpper, uint128 liquidity,,,,) = 
                    positionManager.positions(tokenId);
                
                activeTokenIds[index] = tokenId;
                tickLowers[index] = tickLower;
                tickUppers[index] = tickUpper;
                liquidities[index] = liquidity;
                index++;
            }
        }
    }

    function getPerformanceMetrics() external view returns (
        uint256 totalDeployedAmount,
        uint256 totalHarvestedAmount,
        uint256 totalFeesCollected,
        uint256 rebalancesCount,
        uint256 activePositionsCount,
        uint256 impermanentLossAmount
    ) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (activePositions[tokenIds[i]]) {
                activeCount++;
            }
        }

        return (
            totalDeployed,
            totalHarvested,
            totalFeesEarned,
            rebalanceCount,
            activeCount,
            impermanentLoss
        );
    }

    // ====================================================================
    // ADMIN FUNCTIONS
    // ====================================================================

    function setRangeParameters(
        int24 _rangeWidth,
        int24 _rebalanceThreshold,
        uint256 _maxPositions
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_rangeWidth > 0, "Invalid range width");
        require(_rebalanceThreshold > 0, "Invalid rebalance threshold");
        require(_maxPositions > 0, "Invalid max positions");

        rangeWidth = _rangeWidth;
        rebalanceThreshold = _rebalanceThreshold;
        maxPositions = _maxPositions;
    }

    function setAutoManagement(
        bool _autoRebalance,
        bool _autoCollectFees,
        uint256 _rebalanceInterval,
        uint256 _feeCollectionInterval
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        autoRebalance = _autoRebalance;
        autoCollectFees = _autoCollectFees;
        rebalanceInterval = _rebalanceInterval;
        feeCollectionInterval = _feeCollectionInterval;
    }

    function setPaused(bool paused) external onlyRole(DEFAULT_ADMIN_ROLE) {
        strategyPaused = paused;
    }

    function manualRebalance() external onlyRole(AGENT_ROLE) {
        _rebalancePositions();
    }

    function manualCollectFees() external onlyRole(AGENT_ROLE) {
        _autoCollectFees();
    }

    // IStrategy interface compatibility
    function underlyingToken() external view returns (address) {
        return address(token0); // Return primary token
    }

    function protocol() external view returns (address) {
        return address(positionManager);
    }

    function paused() external view returns (bool) {
        return strategyPaused;
    }
}