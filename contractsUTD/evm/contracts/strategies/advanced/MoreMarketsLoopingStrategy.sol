// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// Enhanced More.Markets interface with additional functions
interface IEnhancedPool {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
    function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf) external;
    function repay(address asset, uint256 amount, uint256 interestRateMode, address onBehalfOf) external returns (uint256);
    function getUserAccountData(address user) external view returns (
        uint256 totalCollateralBase,
        uint256 totalDebtBase,
        uint256 availableBorrowsBase,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    );
    function getReserveData(address asset) external view returns (
        uint256 configuration,
        uint128 liquidityIndex,
        uint128 variableBorrowIndex,
        uint128 currentLiquidityRate,
        uint128 currentVariableBorrowRate,
        uint128 currentStableBorrowRate,
        uint40 lastUpdateTimestamp,
        address aTokenAddress,
        address stableDebtTokenAddress,
        address variableDebtTokenAddress,
        address interestRateStrategyAddress,
        uint8 id
    );
}

// Enhanced DEX interface with multiple router support
interface IMultiDexRouter {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    
    function getAmountsOut(uint amountIn, address[] calldata path)
        external view returns (uint[] memory amounts);
    
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
}

// Yield farming interface for additional rewards
interface IYieldFarm {
    function deposit(uint256 pid, uint256 amount) external;
    function withdraw(uint256 pid, uint256 amount) external;
    function emergencyWithdraw(uint256 pid) external;
    function userInfo(uint256 pid, address user) external view returns (uint256 amount, uint256 rewardDebt);
    function pendingRewards(uint256 pid, address user) external view returns (uint256);
    function harvest(uint256 pid) external;
}

// Price oracle interface for better risk management
interface IPriceOracle {
    function getAssetPrice(address asset) external view returns (uint256);
    function getAssetsPrices(address[] calldata assets) external view returns (uint256[] memory);
}

// WFLOW interface
interface IWFLOW is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
}

/// @title ProductionLoopingStrategy - Advanced Leveraged Lending Strategy
/// @notice Ultra-optimized looping strategy with multiple yield sources and advanced risk management
/// @dev Implements dynamic leverage, yield farming, and cross-protocol optimization
contract ProductionLoopingStrategy is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ====================================================================
    // CONSTANTS & CONFIGURATION
    // ====================================================================
    
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");
    
    uint256 public constant VARIABLE_RATE = 2;
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant PRECISION = 1e18;
    uint256 public constant MAX_LOOPS = 10;
    uint256 public constant REBALANCE_THRESHOLD = 100; // 1%
    
    // Enhanced protocol addresses - Flow EVM
    address public constant MORE_MARKETS_POOL = 0xbC92aaC2DBBF42215248B5688eB3D3d2b32F2c8d;
    address public constant PUNCH_SWAP_ROUTER = 0xf45AFe28fd5519d5f8C1d4787a4D5f724C0eFa4d;
    address public constant INCREMENT_ROUTER = 0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590;
    
    // Token addresses
    address public constant USDC = 0xF1815bd50389c46847f0Bda824eC8da914045D14;
    address public constant WFLOW = 0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e;
    address public constant STFLOW = 0x1b97100eA1D7126C4d60027e231EA4CB25314bdb;
    address public constant ANKR_FLOW = 0x5598c0652B899EB40f169Dd5949BdBE0BF36ffDe;

    // ====================================================================
    // STATE VARIABLES
    // ====================================================================
    
    // Core contracts
    IEnhancedPool public immutable lendingPool;
    IMultiDexRouter public immutable primaryRouter;
    IMultiDexRouter public immutable secondaryRouter;
    IERC20 public immutable usdcToken;
    IERC20 public immutable stFlowToken;
    IERC20 public immutable ankrFlowToken;
    IWFLOW public immutable wflowToken;
    
    // External integrations
    IPriceOracle public priceOracle;
    IYieldFarm public yieldFarm;
    address public vault;
    
    // Strategy configuration
    struct StrategyConfig {
        uint256 targetLeverage;         // Target leverage multiplier (1.8x = 1.8e18)
        uint256 maxLeverage;            // Maximum allowed leverage
        uint256 minLeverage;            // Minimum leverage for efficiency
        uint256 targetHealthFactor;     // Target health factor
        uint256 minHealthFactor;        // Emergency threshold
        uint256 maxSlippage;            // Maximum slippage tolerance
        uint256 rebalanceThreshold;     // When to trigger rebalancing
        uint256 yieldHarvestThreshold;  // Minimum yield to harvest
        bool useYieldFarming;           // Enable additional yield farming
        bool useMultipleCollaterals;    // Use both stFLOW and ankrFLOW
        bool dynamicLeverage;           // Adjust leverage based on market conditions
    }
    
    StrategyConfig public config;
    
    // Position tracking with enhanced metrics
    struct Position {
        uint256 totalUSDCDeployed;
        uint256 totalStFLOWSupplied;
        uint256 totalAnkrFLOWSupplied;
        uint256 totalWFLOWBorrowed;
        uint256 totalYieldFarmDeposited;
        uint256 accumulatedYield;
        uint256 lastRebalanceTime;
        uint256 lastHarvestTime;
        uint256 rebalanceCount;
        uint256 harvestCount;
        uint256 currentLeverage;
        uint256 currentHealthFactor;
        bool isActive;
    }
    
    Position public position;
    
    // Performance tracking
    struct PerformanceMetrics {
        uint256 totalNetYield;
        uint256 totalGasCosts;
        uint256 totalSlippageCosts;
        uint256 avgAPY;
        uint256 maxDrawdown;
        uint256 sharpeRatio;
        uint256 lastUpdateTime;
    }
    
    PerformanceMetrics public performance;
    
    // Risk management
    bool public strategyPaused;
    bool public emergencyMode;
    uint256 public lastRiskCheck;
    uint256 public riskCheckInterval = 1 hours;
    
    // Gas optimization
    mapping(address => uint256) public tokenApprovals;
    uint256 public gasOptimizationLevel = 2; // 0=none, 1=basic, 2=advanced

    // ====================================================================
    // EVENTS
    // ====================================================================
    
    event StrategyInitialized(uint256 usdcAmount, uint256 targetLeverage);
    event PositionBuilt(uint256 loops, uint256 finalLeverage, uint256 healthFactor);
    event PositionRebalanced(uint256 oldLeverage, uint256 newLeverage, uint256 gasUsed);
    event YieldHarvested(uint256 totalYield, uint256 netYield, uint256 fees);
    event AutoCompounded(uint256 compoundedAmount, uint256 newLeverage);
    event RiskParametersAdjusted(string parameter, uint256 oldValue, uint256 newValue);
    event EmergencyAction(string action, uint256 recoveredAmount);
    event CrossProtocolArbitrage(uint256 profit, address fromProtocol, address toProtocol);

    // ====================================================================
    // CONSTRUCTOR
    // ====================================================================
    
    constructor(
        address _vault,
        address _priceOracle,
        address _yieldFarm
    ) {
        require(_vault != address(0), "Invalid vault");

        vault = _vault;
        lendingPool = IEnhancedPool(MORE_MARKETS_POOL);
        primaryRouter = IMultiDexRouter(PUNCH_SWAP_ROUTER);
        secondaryRouter = IMultiDexRouter(INCREMENT_ROUTER);
        usdcToken = IERC20(USDC);
        stFlowToken = IERC20(STFLOW);
        ankrFlowToken = IERC20(ANKR_FLOW);
        wflowToken = IWFLOW(WFLOW);
        
        if (_priceOracle != address(0)) {
            priceOracle = IPriceOracle(_priceOracle);
        }
        
        if (_yieldFarm != address(0)) {
            yieldFarm = IYieldFarm(_yieldFarm);
        }

        // Initialize optimal configuration - Conservative for production
        config = StrategyConfig({
            targetLeverage: 15 * 1e17,       // 1.5x (conservative start)
            maxLeverage: 20 * 1e17,          // 2.0x maximum
            minLeverage: 11 * 1e17,          // 1.1x minimum
            targetHealthFactor: 25 * 1e17,   // 2.5 target HF (safer)
            minHealthFactor: 18 * 1e17,      // 1.8 minimum HF
            maxSlippage: 200,                // 2% max slippage
            rebalanceThreshold: 100,         // 1% threshold
            yieldHarvestThreshold: 1e15,     // 0.001 token minimum
            useYieldFarming: false,          // Start conservative
            useMultipleCollaterals: false,   // Start with single collateral
            dynamicLeverage: false           // Start with fixed leverage
        });

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(VAULT_ROLE, _vault);
        _grantRole(KEEPER_ROLE, msg.sender);
    }

    // ====================================================================
    // MODIFIERS
    // ====================================================================
    
    modifier onlyVault() {
        require(hasRole(VAULT_ROLE, msg.sender), "Only vault");
        _;
    }

    modifier onlyKeeper() {
        require(hasRole(KEEPER_ROLE, msg.sender), "Only keeper");
        _;
    }

    modifier whenNotPaused() {
        require(!strategyPaused && !emergencyMode, "Strategy paused");
        _;
    }

    modifier healthCheck() {
        _checkHealthFactor();
        _;
        _updateRiskMetrics();
    }

    modifier gasOptimized() {
        uint256 gasStart = gasleft();
        _;
        performance.totalGasCosts += (gasStart - gasleft()) * tx.gasprice;
    }

    // ====================================================================
    // MAIN STRATEGY FUNCTIONS
    // ====================================================================

    /// @notice Execute the enhanced looping strategy
    function execute(uint256 amount, bytes calldata data) 
        external 
        onlyVault 
        nonReentrant 
        whenNotPaused 
        healthCheck 
        gasOptimized
    {
        require(amount > 0, "Invalid amount");
        require(!position.isActive || _shouldReinvest(), "Position active");

        // The vault transfers USDC to this contract, so no transferFrom is needed here.
        // The amount is now available as this contract's balance.

        // Decode additional parameters
        (uint256 leverageOverride, bool useAutoCompounding) = data.length > 0 ? 
            abi.decode(data, (uint256, bool)) : (0, true);

        uint256 targetLev = leverageOverride > 0 ? leverageOverride : 
            (config.dynamicLeverage ? _calculateOptimalLeverage() : config.targetLeverage);

        // Convert USDC to WFLOW for looping strategy
        uint256 wflowAmount = _convertUSDCToWFLOW(amount);
        require(wflowAmount > 0, "Swap USDC->WFLOW failed");

        // Build leveraged position with enhanced looping
        _buildEnhancedPosition(wflowAmount, targetLev);

        position.totalUSDCDeployed += amount;
        position.isActive = true;
        position.lastRebalanceTime = block.timestamp;

        emit StrategyInitialized(amount, targetLev);
    }

    /// @notice Enhanced harvest with multi-source yield collection
    function harvest(bytes calldata data) 
        external 
        onlyVault 
        nonReentrant 
        whenNotPaused 
        healthCheck 
        gasOptimized
    {
        uint256 totalYieldBefore = _getTotalPortfolioValue();

        // 1. Harvest lending rewards (interest rate differential)
        uint256 lendingYield = _harvestLendingRewards();

        // 2. Harvest yield farming rewards if enabled
        uint256 farmingYield = config.useYieldFarming ? _harvestYieldFarmingRewards() : 0;

        // 3. Check for arbitrage opportunities
        uint256 arbitrageProfit = _executeArbitrageOpportunities();

        // 4. Rebalance if needed
        if (_shouldRebalance()) {
            _rebalancePosition();
        }

        // 5. Auto-compound if profitable
        uint256 compoundedAmount = _autoCompoundYield(lendingYield + farmingYield + arbitrageProfit);

        uint256 totalYieldAfter = _getTotalPortfolioValue();
        uint256 netYield = totalYieldAfter > totalYieldBefore ? 
            totalYieldAfter - totalYieldBefore : 0;

        // Convert excess to USDC and send to vault
        if (netYield > config.yieldHarvestThreshold) {
            uint256 usdcToVault = _convertExcessToUSDC(netYield);
            if (usdcToVault > 0) {
                usdcToken.safeTransfer(vault, usdcToVault);
            }
        }

        _updatePerformanceMetrics(netYield, compoundedAmount);
        position.lastHarvestTime = block.timestamp;
        position.harvestCount++;

        emit YieldHarvested(lendingYield + farmingYield + arbitrageProfit, netYield, 0);
    }

    /// @notice Enhanced emergency exit with maximum value recovery
    function emergencyExit(bytes calldata data) 
        external 
        onlyRole(EMERGENCY_ROLE) 
        nonReentrant 
        gasOptimized
    {
        emergencyMode = true;
        strategyPaused = true;

        uint256 recoveredUSDC = _executeEmergencyExit();

        // Transfer all recovered USDC to vault
        if (recoveredUSDC > 0) {
            usdcToken.safeTransfer(vault, recoveredUSDC);
        }

        position.isActive = false;
        emit EmergencyAction("Full exit", recoveredUSDC);
    }

    // ====================================================================
    // ENHANCED POSITION MANAGEMENT
    // ====================================================================

    /// @notice Build leveraged position with advanced optimization
    function _buildEnhancedPosition(uint256 initialWFLOW, uint256 targetLev) internal {
        uint256 loops = 0;
        uint256 currentLeverage = PRECISION; // Start at 1x
        
        // Supply initial WFLOW as collateral
        _supplyWFLOWCollateral(initialWFLOW);

        while (currentLeverage < targetLev && loops < MAX_LOOPS) {
            // Calculate optimal borrow amount
            uint256 borrowAmount = _calculateOptimalBorrowAmount(targetLev, currentLeverage);
            
            if (borrowAmount < config.yieldHarvestThreshold) break;

            // Check health factor before borrowing
            (, , , , , uint256 healthFactor) = lendingPool.getUserAccountData(address(this));
            if (healthFactor <= config.minHealthFactor * 105 / 100) break; // 5% safety buffer

            // Borrow USDC against WFLOW collateral
            lendingPool.borrow(USDC, borrowAmount, VARIABLE_RATE, 0, address(this));

            // Convert borrowed USDC to WFLOW and supply as additional collateral
            uint256 newWFLOW = _convertUSDCToWFLOW(borrowAmount);
            if (newWFLOW > 0) {
                _supplyWFLOWCollateral(newWFLOW);
            }

            // Update leverage
            currentLeverage = _calculateCurrentLeverage();
            loops++;
        }

        position.currentLeverage = currentLeverage;
        (, , , , , position.currentHealthFactor) = lendingPool.getUserAccountData(address(this));

        emit PositionBuilt(loops, currentLeverage, position.currentHealthFactor);
    }

    /// @notice Supply WFLOW as collateral
    function _supplyWFLOWCollateral(uint256 amount) internal {
        if (amount > 0) {
            _optimizedApprove(WFLOW, address(lendingPool), amount);
            lendingPool.supply(WFLOW, amount, address(this), 0);
            position.totalStFLOWSupplied += amount; // Track as equivalent
        }
    }

    /// @notice Calculate optimal borrow amount for next loop iteration
    function _calculateOptimalBorrowAmount(uint256 targetLev, uint256 currentLev) internal view returns (uint256) {
        (uint256 totalCollateral, , uint256 availableBorrows, , , ) = 
            lendingPool.getUserAccountData(address(this));

        // Calculate how much more leverage we need
        uint256 leverageGap = targetLev > currentLev ? targetLev - currentLev : 0;
        if (leverageGap == 0) return 0;

        // Calculate required additional debt
        uint256 additionalDebt = (totalCollateral * leverageGap) / targetLev;
        
        // Apply safety margin (75% of available borrows for production safety)
        uint256 safeAvailableBorrows = (availableBorrows * 75) / 100;
        
        return Math.min(additionalDebt, safeAvailableBorrows);
    }

    /// @notice Convert USDC to WFLOW
    function _convertUSDCToWFLOW(uint256 usdcAmount) internal returns (uint256 wflowAmount) {
        if (usdcAmount == 0) return 0;
        return _swapTokensOptimized(USDC, WFLOW, usdcAmount);
    }

    /// @notice Convert WFLOW to USDC
    function _convertWFLOWToUSDC(uint256 wflowAmount) internal returns (uint256 usdcAmount) {
        if (wflowAmount == 0) return 0;
        return _swapTokensOptimized(WFLOW, USDC, wflowAmount);
    }

    // ====================================================================
    // YIELD OPTIMIZATION FUNCTIONS
    // ====================================================================

    /// @notice Harvest lending protocol rewards
    function _harvestLendingRewards() internal returns (uint256 yield) {
        // Calculate net position value change
        uint256 currentValue = _getTotalPortfolioValue();
        uint256 netWorth = currentValue > position.totalUSDCDeployed ? 
            currentValue - position.totalUSDCDeployed : 0;
        return netWorth;
    }

    /// @notice Harvest yield farming rewards if enabled
    function _harvestYieldFarmingRewards() internal returns (uint256 yield) {
        if (address(yieldFarm) == address(0)) return 0;

        try yieldFarm.harvest(0) {
            // Calculate farming rewards received
            yield = 0; // Placeholder - implement based on actual yield farm
        } catch {
            yield = 0;
        }
    }

    /// @notice Look for and execute arbitrage opportunities
    function _executeArbitrageOpportunities() internal returns (uint256 profit) {
        // Check price differences between DEXes for WFLOW/USDC pairs
        uint256 punchPrice = _getTokenPrice(primaryRouter, WFLOW, USDC, 1e18);
        uint256 incrementPrice = _getTokenPrice(secondaryRouter, WFLOW, USDC, 1e18);

        if (punchPrice == 0 || incrementPrice == 0) return 0;

        uint256 priceDiff = punchPrice > incrementPrice ? 
            punchPrice - incrementPrice : incrementPrice - punchPrice;

        // Execute arbitrage if price difference > 0.5%
        if (priceDiff > (Math.max(punchPrice, incrementPrice) / 200)) {
            profit = _executeArbitrageTrade(punchPrice > incrementPrice);
        }
    }

    /// @notice Execute arbitrage trade between DEXes
    function _executeArbitrageTrade(bool buyOnIncrement) internal returns (uint256 profit) {
        uint256 tradeAmount = Math.min(
            wflowToken.balanceOf(address(this)) / 20, // Max 5% of WFLOW balance for safety
            5 * 1e18 // Max 5 WFLOW
        );

        if (tradeAmount < 1e17) return 0; // Minimum 0.1 WFLOW

        if (buyOnIncrement) {
            // Buy WFLOW on Increment, sell on Punch
            uint256 usdcAmount = _convertWFLOWToUSDC(tradeAmount);
            if (usdcAmount > 0) {
                uint256 wflowBought = _swapTokens(secondaryRouter, USDC, WFLOW, usdcAmount);
                profit = wflowBought > tradeAmount ? wflowBought - tradeAmount : 0;
            }
        } else {
            // Buy WFLOW on Punch, sell on Increment
            uint256 usdcAmount = _swapTokens(secondaryRouter, WFLOW, USDC, tradeAmount);
            if (usdcAmount > 0) {
                uint256 wflowBought = _swapTokens(primaryRouter, USDC, WFLOW, usdcAmount);
                profit = wflowBought > tradeAmount ? wflowBought - tradeAmount : 0;
            }
        }

        if (profit > 0) {
            emit CrossProtocolArbitrage(profit, 
                buyOnIncrement ? INCREMENT_ROUTER : PUNCH_SWAP_ROUTER,
                buyOnIncrement ? PUNCH_SWAP_ROUTER : INCREMENT_ROUTER);
        }
    }

    /// @notice Auto-compound yield back into the position
    function _autoCompoundYield(uint256 yieldAmount) internal returns (uint256 compounded) {
        if (yieldAmount < config.yieldHarvestThreshold) return 0;

        // Use 70% of yield for compounding, keep 30% as profit for production safety
        uint256 compoundAmount = (yieldAmount * 70) / 100;
        
        if (compoundAmount > 0) {
            // Convert to USDC first then reinvest
            uint256 usdcAmount = _convertToUSDC(compoundAmount);
            
            if (usdcAmount > 0) {
                // Add one more loop iteration
                uint256 wflowAmount = _convertUSDCToWFLOW(usdcAmount);
                if (wflowAmount > 0) {
                    _buildEnhancedPosition(wflowAmount, config.targetLeverage);
                    compounded = wflowAmount;
                    
                    emit AutoCompounded(compounded, position.currentLeverage);
                }
            }
        }
    }

    // ====================================================================
    // ADVANCED RISK MANAGEMENT
    // ====================================================================

    /// @notice Dynamic leverage calculation based on market conditions
    function _calculateOptimalLeverage() internal view returns (uint256) {
        if (address(priceOracle) == address(0)) {
            return config.targetLeverage;
        }

        try priceOracle.getAssetPrice(WFLOW) returns (uint256 price) {
            // Implement volatility-based leverage adjustment
            uint256 volatility = _calculateVolatility(price);
            
            if (volatility > 25 * 1e16) { // High volatility (>25%)
                return Math.max(config.minLeverage, config.targetLeverage * 90 / 100);
            } else if (volatility < 10 * 1e16) { // Low volatility (<10%)
                return Math.min(config.maxLeverage, config.targetLeverage * 105 / 100);
            }
            
            return config.targetLeverage;
        } catch {
            return config.targetLeverage;
        }
    }

    /// @notice Calculate price volatility (simplified implementation)
    function _calculateVolatility(uint256 currentPrice) internal pure returns (uint256) {
        // Simplified volatility calculation for production
        // In full implementation, this would use historical price data
        return 15 * 1e16; // Default 15% volatility
    }

    /// @notice Check if position should be rebalanced
    function _shouldRebalance() internal view returns (bool) {
        uint256 currentLev = _calculateCurrentLeverage();
        uint256 targetLev = config.dynamicLeverage ? _calculateOptimalLeverage() : config.targetLeverage;
        
        uint256 leverageDiff = currentLev > targetLev ? currentLev - targetLev : targetLev - currentLev;
        bool leverageOutOfRange = leverageDiff > (targetLev * config.rebalanceThreshold) / BASIS_POINTS;

        (, , , , , uint256 healthFactor) = lendingPool.getUserAccountData(address(this));
        bool healthFactorLow = healthFactor < config.minHealthFactor * 125 / 100; // 25% buffer

        return leverageOutOfRange || healthFactorLow || 
                (block.timestamp - position.lastRebalanceTime > 24 hours);
    }

    /// @notice Rebalance position to optimal parameters
    function _rebalancePosition() internal {
        uint256 gasStart = gasleft();
        
        uint256 currentLev = _calculateCurrentLeverage();
        uint256 targetLev = config.dynamicLeverage ? _calculateOptimalLeverage() : config.targetLeverage;

        if (currentLev > targetLev * 105 / 100) {
            _reduceLeverage(targetLev);
        } else if (currentLev < targetLev * 95 / 100) {
            _increaseLeverage(targetLev);
        }

        position.currentLeverage = _calculateCurrentLeverage();
        (, , , , , position.currentHealthFactor) = lendingPool.getUserAccountData(address(this));
        
        uint256 gasUsed = gasStart - gasleft();
        position.lastRebalanceTime = block.timestamp;
        position.rebalanceCount++;

        emit PositionRebalanced(currentLev, position.currentLeverage, gasUsed);
    }

    /// @notice Reduce leverage by repaying debt
    function _reduceLeverage(uint256 targetLev) internal {
        (uint256 totalCollateral, uint256 totalDebt, , , , ) = 
            lendingPool.getUserAccountData(address(this));

        if (totalDebt == 0) return;

        uint256 targetDebt = totalCollateral - (totalCollateral * PRECISION / targetLev);
        uint256 debtToRepay = totalDebt > targetDebt ? totalDebt - targetDebt : 0;

        if (debtToRepay > 0) {
            // Withdraw WFLOW collateral
            uint256 wflowToWithdraw = (debtToRepay * 110) / 100; // 10% buffer
            
            try lendingPool.withdraw(WFLOW, wflowToWithdraw, address(this)) returns (uint256 withdrawn) {
                // Convert withdrawn WFLOW to USDC for repayment
                uint256 usdcForRepay = _convertWFLOWToUSDC(withdrawn);
                
                if (usdcForRepay > 0) {
                    _optimizedApprove(USDC, address(lendingPool), usdcForRepay);
                    lendingPool.repay(USDC, usdcForRepay, VARIABLE_RATE, address(this));
                }
            } catch {
                // Withdrawal failed, continue
            }
        }
    }

    /// @notice Increase leverage by borrowing more
    function _increaseLeverage(uint256 targetLev) internal {
        (uint256 totalCollateral, uint256 totalDebt, uint256 availableBorrows, , , ) = 
            lendingPool.getUserAccountData(address(this));

        uint256 targetDebt = totalCollateral - (totalCollateral * PRECISION / targetLev);
        uint256 additionalBorrow = targetDebt > totalDebt ? targetDebt - totalDebt : 0;

        uint256 safeBorrow = Math.min(additionalBorrow, (availableBorrows * 75) / 100); // 75% safety

        if (safeBorrow >= config.yieldHarvestThreshold) {
            lendingPool.borrow(USDC, safeBorrow, VARIABLE_RATE, 0, address(this));

            uint256 newWFLOW = _convertUSDCToWFLOW(safeBorrow);
            if (newWFLOW > 0) {
                _supplyWFLOWCollateral(newWFLOW);
            }
        }
    }

    // ====================================================================
    // ADVANCED TOKEN OPERATIONS
    // ====================================================================

    /// @notice Optimized token swapping with best route detection
    function _swapTokensOptimized(address tokenIn, address tokenOut, uint256 amountIn) 
        internal 
        returns (uint256 amountOut) 
    {
        if (amountIn == 0) return 0;

        // Try primary router first
        uint256 primaryQuote = _getTokenPrice(primaryRouter, tokenIn, tokenOut, amountIn);
        uint256 secondaryQuote = _getTokenPrice(secondaryRouter, tokenIn, tokenOut, amountIn);

        // Use router with better price, fallback to primary if secondary fails
        IMultiDexRouter router = (secondaryQuote > primaryQuote && secondaryQuote > 0) ? 
            secondaryRouter : primaryRouter;
        
        return _swapTokens(router, tokenIn, tokenOut, amountIn);
    }

    /// @notice Execute token swap on specified router
    function _swapTokens(IMultiDexRouter router, address tokenIn, address tokenOut, uint256 amountIn)
        internal
        returns (uint256 amountOut)
    {
        if (amountIn == 0) return 0;

        _optimizedApprove(tokenIn, address(router), amountIn);

        address[] memory path;
        if (tokenIn == USDC && tokenOut == WFLOW) {
            path = new address[](2);
            path[0] = USDC;
            path[1] = WFLOW;
        } else if (tokenIn == WFLOW && tokenOut == USDC) {
            path = new address[](2);
            path[0] = WFLOW;
            path[1] = USDC;
        } else {
            // Fallback for any other potential swaps
            path = new address[](2);
            path[0] = tokenIn;
            path[1] = tokenOut;
        }

        try router.getAmountsOut(amountIn, path) returns (uint256[] memory amounts) {
            if (amounts.length >= 2 && amounts[1] > 0) {
                uint256 minAmountOut = (amounts[1] * (BASIS_POINTS - config.maxSlippage)) / BASIS_POINTS;

                try router.swapExactTokensForTokens(
                    amountIn,
                    minAmountOut,
                    path,
                    address(this),
                    block.timestamp + 300
                ) returns (uint256[] memory swapAmounts) {
                    amountOut = swapAmounts[1];
                } catch {
                    amountOut = 0;
                }
            }
        } catch {
            amountOut = 0;
        }
    }

    /// @notice Get token price quote from router
    function _getTokenPrice(IMultiDexRouter router, address tokenIn, address tokenOut, uint256 amountIn)
        internal
        view
        returns (uint256 amountOut)
    {
        if (amountIn == 0) return 0;
        
        address[] memory path;
        if (tokenIn == USDC && tokenOut == WFLOW) {
            path = new address[](2);
            path[0] = USDC;
            path[1] = WFLOW;
        } else if (tokenIn == WFLOW && tokenOut == USDC) {
            path = new address[](2);
            path[0] = WFLOW;
            path[1] = USDC;
        } else {
            // Fallback for any other potential swaps
            path = new address[](2);
            path[0] = tokenIn;
            path[1] = tokenOut;
        }

        try router.getAmountsOut(amountIn, path) returns (uint256[] memory amounts) {
            amountOut = amounts.length >= 2 ? amounts[1] : 0;
        } catch {
            amountOut = 0;
        }
    }

    /// @notice Optimized token approval to save gas
    function _optimizedApprove(address token, address spender, uint256 amount) internal {
        uint256 currentAllowance = IERC20(token).allowance(address(this), spender);
        
        if (currentAllowance >= amount) {
            return;
        }
        
        if (currentAllowance > 0) {
            IERC20(token).safeApprove(spender, 0);
        }
        
        IERC20(token).safeApprove(spender, type(uint256).max);
    }

    /// @notice Convert excess tokens to USDC
    function _convertExcessToUSDC(uint256 yieldAmount) internal returns (uint256 usdcAmount) {
        // Convert any loose WFLOW to USDC
        uint256 wflowBalance = wflowToken.balanceOf(address(this));
        
        if (wflowBalance > 0) {
            usdcAmount = _swapTokensOptimized(WFLOW, USDC, wflowBalance);
        }
        
        // Add any existing USDC balance
        usdcAmount += usdcToken.balanceOf(address(this));
    }

    /// @notice Convert any token amount to USDC
    function _convertToUSDC(uint256 tokenAmount) internal returns (uint256 usdcAmount) {
        // Simplified conversion - assumes input is in WFLOW equivalent
        return _swapTokensOptimized(WFLOW, USDC, tokenAmount);
    }

    // ====================================================================
    // EMERGENCY FUNCTIONS
    // ====================================================================

    /// @notice Execute comprehensive emergency exit
    function _executeEmergencyExit() internal returns (uint256 recoveredUSDC) {
        uint256 iterations = 0;
        
        // Unwind position iteratively
        while (iterations < MAX_LOOPS) {
            (, uint256 totalDebt, , , , ) = lendingPool.getUserAccountData(address(this));
            
            if (totalDebt == 0) break;

            // Emergency withdrawal with maximum buffer
            uint256 wflowToWithdraw = (totalDebt * 150) / 100; // 50% buffer for emergency
            
            try lendingPool.withdraw(WFLOW, wflowToWithdraw, address(this)) returns (uint256 withdrawn) {
                uint256 usdcForRepay = _convertWFLOWToUSDC(withdrawn);
                
                if (usdcForRepay > 0) {
                    _optimizedApprove(USDC, address(lendingPool), usdcForRepay);
                    lendingPool.repay(USDC, type(uint256).max, VARIABLE_RATE, address(this));
                }
            } catch {
                break; // Exit if withdrawal fails
            }
            
            iterations++;
        }

        // Withdraw all remaining collateral
        try lendingPool.withdraw(WFLOW, type(uint256).max, address(this)) {
            // Convert everything to USDC
            recoveredUSDC = _convertExcessToUSDC(0);
        } catch {
            // Emergency fallback - just return existing USDC
            recoveredUSDC = usdcToken.balanceOf(address(this));
        }

        // Reset position tracking
        position.totalStFLOWSupplied = 0;
        position.totalAnkrFLOWSupplied = 0;
        position.totalWFLOWBorrowed = 0;
        position.currentLeverage = PRECISION;
    }

    // ====================================================================
    // HELPER FUNCTIONS
    // ====================================================================

    /// @notice Calculate current leverage ratio
    function _calculateCurrentLeverage() internal view returns (uint256) {
        (uint256 totalCollateral, uint256 totalDebt, , , , ) = 
            lendingPool.getUserAccountData(address(this));

        if (totalDebt == 0 || totalCollateral == 0) {
            return PRECISION;
        }

        return (totalCollateral * PRECISION) / (totalCollateral - totalDebt);
    }

    /// @notice Get total portfolio value in USD terms
    function _getTotalPortfolioValue() internal view returns (uint256) {
        (uint256 totalCollateral, uint256 totalDebt, , , , ) = 
            lendingPool.getUserAccountData(address(this));

        return totalCollateral > totalDebt ? totalCollateral - totalDebt : 0;
    }

    /// @notice Check if strategy should reinvest (for subsequent executions)
    function _shouldReinvest() internal view returns (bool) {
        uint256 currentValue = _getTotalPortfolioValue();
        return currentValue < position.totalUSDCDeployed * 85 / 100; // Allow if position lost >15%
    }

    /// @notice Update performance metrics
    function _updatePerformanceMetrics(uint256 yield, uint256 compounded) internal {
        performance.totalNetYield += yield;
        performance.lastUpdateTime = block.timestamp;
        
        // Calculate APY (simplified)
        if (position.totalUSDCDeployed > 0 && position.lastHarvestTime > 0) {
            uint256 timeElapsed = block.timestamp - position.lastHarvestTime;
            if (timeElapsed > 0) {
                uint256 currentAPY = (yield * 365 days * BASIS_POINTS) / (position.totalUSDCDeployed * timeElapsed);
                performance.avgAPY = (performance.avgAPY + currentAPY) / 2; // Simple moving average
            }
        }
    }

    /// @notice Check health factor and risk metrics
    function _checkHealthFactor() internal view {
        if (position.isActive) {
            (, , , , , uint256 healthFactor) = lendingPool.getUserAccountData(address(this));
            require(healthFactor >= config.minHealthFactor * 95 / 100, "Health factor too low");
        }
    }

    /// @notice Update risk metrics
    function _updateRiskMetrics() internal {
        if (block.timestamp - lastRiskCheck >= riskCheckInterval) {
            if (position.isActive) {
                position.currentLeverage = _calculateCurrentLeverage();
                (, , , , , position.currentHealthFactor) = lendingPool.getUserAccountData(address(this));
            }
            lastRiskCheck = block.timestamp;
        }
    }

    // ====================================================================
    // AUTOMATED KEEPER FUNCTIONS
    // ====================================================================

    /// @notice Automated rebalancing (callable by keepers)
    function keeperRebalance() external onlyKeeper nonReentrant gasOptimized {
        require(_shouldRebalance(), "Rebalance not needed");
        _rebalancePosition();
    }

    /// @notice Automated harvest (callable by keepers)
    function keeperHarvest() external onlyKeeper nonReentrant gasOptimized {
        require(block.timestamp - position.lastHarvestTime >= 12 hours, "Too soon to harvest");
        this.harvest("");
    }

    /// @notice Emergency deleveraging (callable by keepers)
    function keeperEmergencyDelever() external onlyKeeper nonReentrant {
        (, , , , , uint256 healthFactor) = lendingPool.getUserAccountData(address(this));
        require(healthFactor <= config.minHealthFactor * 115 / 100, "No emergency needed");
        
        _reduceLeverage(config.minLeverage);
    }

    // ====================================================================
    // ENHANCED ADMIN FUNCTIONS
    // ====================================================================

    function updateStrategyConfig(
        uint256 _targetLeverage,
        uint256 _maxLeverage,
        uint256 _minLeverage,
        uint256 _targetHealthFactor,
        uint256 _minHealthFactor,
        uint256 _maxSlippage
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_maxLeverage >= _targetLeverage && _targetLeverage >= _minLeverage, "Invalid leverage range");
        require(_targetHealthFactor > _minHealthFactor && _minHealthFactor >= 11e17, "Invalid health factors");
        require(_maxSlippage <= 500, "Slippage too high"); // Max 5%
        
        config.targetLeverage = _targetLeverage;
        config.maxLeverage = _maxLeverage;
        config.minLeverage = _minLeverage;
        config.targetHealthFactor = _targetHealthFactor;
        config.minHealthFactor = _minHealthFactor;
        config.maxSlippage = _maxSlippage;
    }

    function toggleFeatures(
        bool _useYieldFarming,
        bool _useMultipleCollaterals,
        bool _dynamicLeverage
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        config.useYieldFarming = _useYieldFarming;
        config.useMultipleCollaterals = _useMultipleCollaterals;
        config.dynamicLeverage = _dynamicLeverage;
    }

    function setExternalContracts(
        address _priceOracle,
        address _yieldFarm
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_priceOracle != address(0)) {
            priceOracle = IPriceOracle(_priceOracle);
        }
        if (_yieldFarm != address(0)) {
            yieldFarm = IYieldFarm(_yieldFarm);
        }
    }

    function setPaused(bool paused) external onlyRole(DEFAULT_ADMIN_ROLE) {
        strategyPaused = paused;
    }

    function setGasOptimization(uint256 level) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(level <= 2, "Invalid optimization level");
        gasOptimizationLevel = level;
    }

    function setRiskCheckInterval(uint256 interval) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(interval >= 30 minutes && interval <= 24 hours, "Invalid interval");
        riskCheckInterval = interval;
    }

    // ====================================================================
    // VIEW FUNCTIONS
    // ====================================================================

    function getPosition() external view returns (
        uint256 totalDeployed,
        uint256 currentLeverage,
        uint256 healthFactor,
        uint256 totalYield,
        bool isActive
    ) {
        return (
            position.totalUSDCDeployed,
            position.currentLeverage,
            position.currentHealthFactor,
            position.accumulatedYield,
            position.isActive
        );
    }

    function getPerformanceMetrics() external view returns (
        uint256 totalNetYield,
        uint256 avgAPY,
        uint256 totalGasCosts,
        uint256 harvestCount,
        uint256 rebalanceCount
    ) {
        return (
            performance.totalNetYield,
            performance.avgAPY,
            performance.totalGasCosts,
            position.harvestCount,
            position.rebalanceCount
        );
    }

    function getDetailedPosition() external view returns (
        uint256 wflowSupplied,
        uint256 usdcBorrowed,
        uint256 totalCollateralUSD,
        uint256 totalDebtUSD,
        uint256 availableBorrowsUSD,
        uint256 netWorthUSD
    ) {
        (totalCollateralUSD, totalDebtUSD, availableBorrowsUSD, , , ) = 
            lendingPool.getUserAccountData(address(this));
            
        netWorthUSD = totalCollateralUSD > totalDebtUSD ? totalCollateralUSD - totalDebtUSD : 0;
            
        return (
            position.totalStFLOWSupplied, // Actually WFLOW supplied
            position.totalWFLOWBorrowed,  // Actually USDC borrowed
            totalCollateralUSD,
            totalDebtUSD,
            availableBorrowsUSD,
            netWorthUSD
        );
    }

    function getOptimalLeverage() external view returns (uint256) {
        return config.dynamicLeverage ? _calculateOptimalLeverage() : config.targetLeverage;
    }

    function shouldRebalance() external view returns (bool) {
        return _shouldRebalance();
    }

    function getTokenBalances() external view returns (
        uint256 usdc,
        uint256 wflow
    ) {
        return (
            usdcToken.balanceOf(address(this)),
            wflowToken.balanceOf(address(this))
        );
    }

    function getStrategyInfo() external view returns (
        string memory name,
        string memory version,
        address underlyingAsset,
        address borrowAsset,
        uint256 currentAPY
    ) {
        return (
            "WFLOW/USDC Looping Strategy",
            "1.0.1", // Version bump
            WFLOW,
            USDC,
            performance.avgAPY
        );
    }

    // ====================================================================
    // LEGACY COMPATIBILITY
    // ====================================================================

    function getBalance() external view returns (uint256) {
        return _getTotalPortfolioValue();
    }

    function underlyingToken() external pure returns (address) {
        return USDC;
    }

    function protocol() external view returns (address) {
        return address(lendingPool);
    }

    function paused() external view returns (bool) {
        return strategyPaused;
    }

    /// @notice Emergency token recovery
    function emergencyWithdrawToken(address token, uint256 amount) 
        external 
        onlyRole(EMERGENCY_ROLE) 
    {
        require(emergencyMode, "Not in emergency mode");
        require(token != WFLOW && token != USDC, "Cannot withdraw strategy tokens");
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    /// @notice Emergency ETH recovery
    function emergencyWithdrawETH() external onlyRole(EMERGENCY_ROLE) {
        require(emergencyMode, "Not in emergency mode");
        payable(msg.sender).transfer(address(this).balance);
    }

    /// @notice Receive native FLOW for gas operations
    receive() external payable {
        // Accept native FLOW
    }

    /// @notice Fallback function
    fallback() external payable {
        revert("Function not found");
    }
}
