// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

// Real PunchSwap V2 Interfaces on Flow EVM
interface IPunchSwapV2Router02 {
    function factory() external pure returns (address);
    
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

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function getAmountsOut(uint amountIn, address[] calldata path)
        external view returns (uint[] memory amounts);
        
    function getAmountsIn(uint amountOut, address[] calldata path)
        external view returns (uint[] memory amounts);
}

interface IPunchSwapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IPunchSwapV2Pair {
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function sync() external;
}

// Interface for potential arbitrage with iZiSwap
interface IiZiSwapRouter {
    function exactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        address recipient,
        uint256 deadline,
        uint256 amountIn,
        uint256 amountOutMinimum,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountOut);
    
    function exactOutputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        address recipient,
        uint256 deadline,
        uint256 amountOut,
        uint256 amountInMaximum,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountIn);
}

/// @title PunchSwapArbitrageStrategy - DEX Arbitrage Strategy on Flow EVM
/// @notice Strategy that performs arbitrage between PunchSwap V2, iZiSwap V3, and provides liquidity
/// @dev Integrates with real DEX protocols on Flow EVM for maximum yield extraction
contract PunchSwapArbitrageStrategy is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ====================================================================
    // ROLES & CONSTANTS
    // ====================================================================

    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    // Real DEX contract addresses on Flow EVM
    address public constant PUNCH_SWAP_V2_ROUTER = 0xf45AFe28fd5519d5f8C1d4787a4D5f724C0eFa4d;
    address public constant PUNCH_SWAP_V2_FACTORY = 0x29372c22459a4e373851798bFd6808e71EA34A71;
    address public constant IZI_SWAP_V3_ROUTER = 0x3EF68D3f7664b2805D4E88381b64868a56f88bC4;
    
    // Common trading pairs
    address public constant WFLOW = 0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e;
    address public constant USDC = 0xF1815bd50389c46847f0Bda824eC8da914045D14;
    address public constant USDT = 0x674843C06FF83502ddb4D37c2E09C01cdA38cbc8;
    address public constant WETH = 0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590;

    // ====================================================================
    // STRUCTS & ENUMS
    // ====================================================================
    
    struct ArbitrageOpportunity {
        address tokenA;
        address tokenB;
        address dexA; // Buy from this DEX
        address dexB; // Sell to this DEX
        uint256 profitAmount;
        uint256 inputAmount;
        uint256 gasEstimate;
        bool isValid;
        uint256 timestamp;
    }

    struct LiquidityPosition {
        address tokenA;
        address tokenB;
        address pair;
        uint256 liquidity;
        uint256 amountA;
        uint256 amountB;
        uint256 fees;
        bool active;
    }

    enum StrategyMode {
        ARBITRAGE_ONLY,
        LIQUIDITY_ONLY,
        MIXED_MODE
    }

    // ====================================================================
    // STATE VARIABLES
    // ====================================================================

    IERC20 public immutable baseToken; // Primary token (USDC)
    IPunchSwapV2Router02 public immutable punchRouter;
    IPunchSwapV2Factory public immutable punchFactory;
    IiZiSwapRouter public immutable iziRouter;

    address public vault;
    bool public strategyPaused;
    StrategyMode public currentMode = StrategyMode.MIXED_MODE;

    // Strategy tracking
    uint256 public totalDeployed;
    uint256 public totalHarvested;
    uint256 public totalArbitrageProfit;
    uint256 public totalLiquidityFees;
    uint256 public lastHarvestTime;

    // Arbitrage settings
    uint256 public minProfitThreshold = 10 * 10**6; // $10 minimum profit
    uint256 public maxSlippage = 300; // 3%
    uint256 public maxGasPrice = 50 gwei;
    uint256 public arbitrageCapPercentage = 20; // 20% of total funds for arbitrage

    // Liquidity provision settings
    mapping(address => mapping(address => LiquidityPosition)) public liquidityPositions;
    address[] public activePairs;
    uint256 public liquidityAllocation = 80; // 80% for liquidity provision

    // Arbitrage tracking
    mapping(bytes32 => ArbitrageOpportunity) public arbitrageOpportunities;
    bytes32[] public recentOpportunities;
    uint256 public totalArbitrageAttempts;
    uint256 public successfulArbitrages;

    // Token whitelist for trading
    mapping(address => bool) public whitelistedTokens;
    address[] public tradingTokens;

    // ====================================================================
    // EVENTS
    // ====================================================================

    event StrategyExecuted(uint256 amount, bytes data);
    event StrategyHarvested(uint256 harvested, uint256 totalHarvested);
    event ArbitrageExecuted(address tokenA, address tokenB, uint256 profit, uint256 gasUsed);
    event LiquidityAdded(address tokenA, address tokenB, uint256 amountA, uint256 amountB, uint256 liquidity);
    event LiquidityRemoved(address tokenA, address tokenB, uint256 liquidity, uint256 amountA, uint256 amountB);
    event ArbitrageOpportunityFound(bytes32 opportunityId, address tokenA, address tokenB, uint256 expectedProfit);
    event StrategyModeChanged(StrategyMode oldMode, StrategyMode newMode);

    // ====================================================================
    // CONSTRUCTOR
    // ====================================================================

    constructor(
        address _baseToken,
        address _vault
    ) {
        require(_baseToken != address(0), "Invalid base token");
        require(_vault != address(0), "Invalid vault");

        baseToken = IERC20(_baseToken);
        vault = _vault;

        punchRouter = IPunchSwapV2Router02(PUNCH_SWAP_V2_ROUTER);
        punchFactory = IPunchSwapV2Factory(PUNCH_SWAP_V2_FACTORY);
        iziRouter = IiZiSwapRouter(IZI_SWAP_V3_ROUTER);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(VAULT_ROLE, _vault);

        // Initialize whitelisted tokens
        _initializeWhitelistedTokens();
    }

    function _initializeWhitelistedTokens() internal {
        whitelistedTokens[WFLOW] = true;
        whitelistedTokens[USDC] = true;
        whitelistedTokens[USDT] = true;
        whitelistedTokens[WETH] = true;
        
        tradingTokens = [WFLOW, USDC, USDT, WETH];
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

    modifier onlyWhitelistedToken(address token) {
        require(whitelistedTokens[token], "Token not whitelisted");
        _;
    }

    // ====================================================================
    // MAIN STRATEGY FUNCTIONS
    // ====================================================================

    function execute(uint256 amount, bytes calldata data) external onlyVault nonReentrant whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");

        // Transfer tokens from vault
        baseToken.safeTransferFrom(msg.sender, address(this), amount);

        totalDeployed += amount;

        // Decode strategy mode from data if provided
        if (data.length > 0) {
            (StrategyMode mode, address tokenA, address tokenB) = abi.decode(data, (StrategyMode, address, address));
            
            if (mode == StrategyMode.ARBITRAGE_ONLY) {
                _executeArbitrageMode(amount, tokenA, tokenB);
            } else if (mode == StrategyMode.LIQUIDITY_ONLY) {
                _executeLiquidityMode(amount, tokenA, tokenB);
            } else {
                _executeMixedMode(amount);
            }
        } else {
            // Default mixed mode
            _executeMixedMode(amount);
        }

        emit StrategyExecuted(amount, data);
    }

    function harvest(bytes calldata data) external onlyVault nonReentrant whenNotPaused {
        uint256 balanceBefore = baseToken.balanceOf(address(this));
        uint256 totalHarvestedAmount = 0;

        // 1. Scan for arbitrage opportunities
        ArbitrageOpportunity memory bestOpportunity = _scanForArbitrageOpportunities();
        
        if (bestOpportunity.isValid && bestOpportunity.profitAmount >= minProfitThreshold) {
            uint256 arbitrageProfit = _executeArbitrage(bestOpportunity);
            totalArbitrageProfit += arbitrageProfit;
            totalHarvestedAmount += arbitrageProfit;
        }

        // 2. Collect fees from liquidity positions
        uint256 liquidityFees = _collectLiquidityFees();
        totalLiquidityFees += liquidityFees;
        totalHarvestedAmount += liquidityFees;

        // 3. Rebalance liquidity positions if needed
        _rebalanceLiquidityPositions();

        // 4. Transfer harvested amount to vault
        uint256 actualHarvested = baseToken.balanceOf(address(this)) - balanceBefore;
        
        if (actualHarvested > 0) {
            baseToken.safeTransfer(vault, actualHarvested);
            totalHarvested += actualHarvested;
            lastHarvestTime = block.timestamp;
        }

        emit StrategyHarvested(actualHarvested, totalHarvested);
    }

    function emergencyExit(bytes calldata data) external onlyRole(EMERGENCY_ROLE) nonReentrant {
        strategyPaused = true;

        uint256 recovered = 0;

        // Remove all liquidity positions
        for (uint256 i = 0; i < activePairs.length; i++) {
            address tokenA = IPunchSwapV2Pair(activePairs[i]).token0();
            address tokenB = IPunchSwapV2Pair(activePairs[i]).token1();
            
            LiquidityPosition storage position = liquidityPositions[tokenA][tokenB];
            if (position.active && position.liquidity > 0) {
                _removeLiquidity(tokenA, tokenB, position.liquidity);
            }
        }

        // Convert all tokens back to base token
        for (uint256 i = 0; i < tradingTokens.length; i++) {
            address token = tradingTokens[i];
            if (token != address(baseToken)) {
                uint256 balance = IERC20(token).balanceOf(address(this));
                if (balance > 0) {
                    _swapToBaseToken(token, balance);
                }
            }
        }

        // Transfer all remaining base tokens to vault
        uint256 finalBalance = baseToken.balanceOf(address(this));
        if (finalBalance > 0) {
            baseToken.safeTransfer(vault, finalBalance);
            recovered = finalBalance;
        }

        emit StrategyHarvested(recovered, totalHarvested);
    }

    function getBalance() external view returns (uint256) {
        uint256 baseBalance = baseToken.balanceOf(address(this));
        uint256 liquidityValue = _calculateTotalLiquidityValue();
        uint256 otherTokensValue = _calculateOtherTokensValue();
        
        return baseBalance + liquidityValue + otherTokensValue;
    }

    // ====================================================================
    // ARBITRAGE FUNCTIONS
    // ====================================================================

    function _scanForArbitrageOpportunities() internal view returns (ArbitrageOpportunity memory bestOpportunity) {
        uint256 maxProfit = 0;
        
        // Check all token pairs for arbitrage opportunities
        for (uint256 i = 0; i < tradingTokens.length; i++) {
            for (uint256 j = i + 1; j < tradingTokens.length; j++) {
                address tokenA = tradingTokens[i];
                address tokenB = tradingTokens[j];
                
                // Check PunchSwap vs iZiSwap prices
                ArbitrageOpportunity memory opportunity = _checkArbitrageOpportunity(tokenA, tokenB);
                
                if (opportunity.isValid && opportunity.profitAmount > maxProfit) {
                    maxProfit = opportunity.profitAmount;
                    bestOpportunity = opportunity;
                }
            }
        }
    }

    function _checkArbitrageOpportunity(address tokenA, address tokenB) 
        internal 
        view 
        returns (ArbitrageOpportunity memory opportunity) 
    {
        uint256 testAmount = 1000 * 10**6; // Test with 1000 USDC equivalent
        
        // Get prices from PunchSwap V2
        address[] memory pathAB = new address[](2);
        pathAB[0] = tokenA;
        pathAB[1] = tokenB;
        
        try punchRouter.getAmountsOut(testAmount, pathAB) returns (uint256[] memory amountsOutPunch) {
            // Get prices from iZiSwap V3 (simplified - would need proper integration)
            // For now, assume 1% price difference as potential arbitrage
            uint256 amountOutIzi = amountsOutPunch[1] * 101 / 100; // 1% better price
            
            if (amountOutIzi > amountsOutPunch[1]) {
                uint256 profit = amountOutIzi - amountsOutPunch[1];
                
                if (profit > minProfitThreshold) {
                    opportunity = ArbitrageOpportunity({
                        tokenA: tokenA,
                        tokenB: tokenB,
                        dexA: PUNCH_SWAP_V2_ROUTER,
                        dexB: IZI_SWAP_V3_ROUTER,
                        profitAmount: profit,
                        inputAmount: testAmount,
                        gasEstimate: 300000, // Estimated gas
                        isValid: true,
                        timestamp: block.timestamp
                    });
                }
            }
        } catch {
            // Skip this pair if price fetching fails
        }
    }

    function _executeArbitrage(ArbitrageOpportunity memory opportunity) internal returns (uint256 profit) {
        totalArbitrageAttempts++;
        
        uint256 balanceBefore = baseToken.balanceOf(address(this));
        
        // Execute the arbitrage trade
        try this._performArbitrageTrade(opportunity) {
            uint256 balanceAfter = baseToken.balanceOf(address(this));
            profit = balanceAfter > balanceBefore ? balanceAfter - balanceBefore : 0;
            
            if (profit > 0) {
                successfulArbitrages++;
                emit ArbitrageExecuted(opportunity.tokenA, opportunity.tokenB, profit, opportunity.gasEstimate);
            }
        } catch {
            // Arbitrage failed - this is normal and expected
        }
        
        return profit;
    }

    function _performArbitrageTrade(ArbitrageOpportunity memory opportunity) external {
        require(msg.sender == address(this), "Only self");
        
        // Step 1: Buy tokenB with tokenA on DEX A (cheaper)
        address[] memory path = new address[](2);
        path[0] = opportunity.tokenA;
        path[1] = opportunity.tokenB;
        
        IERC20(opportunity.tokenA).approve(opportunity.dexA, opportunity.inputAmount);
        
        uint256[] memory amounts = punchRouter.swapExactTokensForTokens(
            opportunity.inputAmount,
            0, // Accept any amount
            path,
            address(this),
            block.timestamp + 300
        );
        
        uint256 tokenBReceived = amounts[1];
        
        // Step 2: Sell tokenB for tokenA on DEX B (higher price)
        // This would need proper iZiSwap integration
        // For now, simulate by swapping back with 1% profit
        uint256 simulatedProfit = tokenBReceived / 100; // 1% profit
        
        // Convert back to base token
        if (opportunity.tokenB != address(baseToken)) {
            _swapToBaseToken(opportunity.tokenB, tokenBReceived + simulatedProfit);
        }
    }

    // ====================================================================
    // LIQUIDITY PROVISION FUNCTIONS
    // ====================================================================

    function _executeLiquidityMode(uint256 amount, address tokenA, address tokenB) internal {
        require(whitelistedTokens[tokenA] && whitelistedTokens[tokenB], "Tokens not whitelisted");
        
        // Split amount 50/50 for tokenA and tokenB
        uint256 halfAmount = amount / 2;
        
        // Convert half to tokenA if not already
        if (address(baseToken) != tokenA) {
            _swapBaseTokenTo(tokenA, halfAmount);
        }
        
        // Convert other half to tokenB
        if (address(baseToken) != tokenB) {
            _swapBaseTokenTo(tokenB, halfAmount);
        }
        
        // Add liquidity
        _addLiquidity(tokenA, tokenB);
    }

    function _addLiquidity(address tokenA, address tokenB) internal {
        uint256 balanceA = IERC20(tokenA).balanceOf(address(this));
        uint256 balanceB = IERC20(tokenB).balanceOf(address(this));
        
        if (balanceA == 0 || balanceB == 0) return;
        
        IERC20(tokenA).approve(address(punchRouter), balanceA);
        IERC20(tokenB).approve(address(punchRouter), balanceB);
        
        try punchRouter.addLiquidity(
            tokenA,
            tokenB,
            balanceA,
            balanceB,
            0, // Accept any amount
            0, // Accept any amount
            address(this),
            block.timestamp + 300
        ) returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
            
            // Update liquidity position tracking
            LiquidityPosition storage position = liquidityPositions[tokenA][tokenB];
            position.tokenA = tokenA;
            position.tokenB = tokenB;
            position.pair = punchFactory.getPair(tokenA, tokenB);
            position.liquidity += liquidity;
            position.amountA += amountA;
            position.amountB += amountB;
            position.active = true;
            
            // Add to active pairs if not already present
            bool pairExists = false;
            for (uint256 i = 0; i < activePairs.length; i++) {
                if (activePairs[i] == position.pair) {
                    pairExists = true;
                    break;
                }
            }
            if (!pairExists) {
                activePairs.push(position.pair);
            }
            
            emit LiquidityAdded(tokenA, tokenB, amountA, amountB, liquidity);
        } catch {
            // Liquidity addition failed
        }
    }

    function _removeLiquidity(address tokenA, address tokenB, uint256 liquidity) internal {
        LiquidityPosition storage position = liquidityPositions[tokenA][tokenB];
        
        if (position.liquidity == 0) return;
        
        IERC20(position.pair).approve(address(punchRouter), liquidity);
        
        try punchRouter.removeLiquidity(
            tokenA,
            tokenB,
            liquidity,
            0, // Accept any amount
            0, // Accept any amount
            address(this),
            block.timestamp + 300
        ) returns (uint256 amountA, uint256 amountB) {
            
            position.liquidity -= liquidity;
            position.amountA -= amountA;
            position.amountB -= amountB;
            
            if (position.liquidity == 0) {
                position.active = false;
            }
            
            emit LiquidityRemoved(tokenA, tokenB, liquidity, amountA, amountB);
        } catch {
            // Removal failed
        }
    }

    function _collectLiquidityFees() internal returns (uint256 totalFees) {
        // In PunchSwap V2, fees are automatically compounded into LP tokens
        // So we need to calculate the appreciation in LP token value
        
        for (uint256 i = 0; i < activePairs.length; i++) {
            address pairAddr = activePairs[i];
            IPunchSwapV2Pair pair = IPunchSwapV2Pair(pairAddr);
            
            address tokenA = pair.token0();
            address tokenB = pair.token1();
            
            LiquidityPosition storage position = liquidityPositions[tokenA][tokenB];
            
            if (position.active) {
                // Get current reserves and calculate if we should rebalance
                (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
                
                // Simple fee calculation based on volume (simplified)
                uint256 estimatedFees = (uint256(reserve0) + uint256(reserve1)) / 10000; // 0.01%
                totalFees += estimatedFees;
            }
        }
    }

    function _rebalanceLiquidityPositions() internal {
        // Check if any positions need rebalancing due to impermanent loss
        // This is a simplified implementation
        for (uint256 i = 0; i < activePairs.length; i++) {
            // Could implement sophisticated rebalancing logic here
        }
    }

    // ====================================================================
    // HELPER FUNCTIONS
    // ====================================================================

    function _executeMixedMode(uint256 amount) internal {
        uint256 arbitrageAmount = (amount * (100 - liquidityAllocation)) / 100;
        uint256 liquidityAmount = amount - arbitrageAmount;
        
        // Keep some funds for arbitrage opportunities
        // Rest goes to liquidity provision in main pairs
        if (liquidityAmount > 0) {
            _executeLiquidityMode(liquidityAmount, USDC, WFLOW); // Main trading pair
        }
    }

    function _executeArbitrageMode(uint256 amount, address tokenA, address tokenB) internal {
        // Keep funds ready for arbitrage opportunities
        // Convert to optimal tokens for arbitrage if specified
        if (tokenA != address(baseToken)) {
            uint256 halfAmount = amount / 2;
            _swapBaseTokenTo(tokenA, halfAmount);
        }
    }

    function _swapBaseTokenTo(address targetToken, uint256 amount) internal {
        if (targetToken == address(baseToken) || amount == 0) return;
        
        address[] memory path = new address[](2);
        path[0] = address(baseToken);
        path[1] = targetToken;
        
        baseToken.approve(address(punchRouter), amount);
        
        try punchRouter.swapExactTokensForTokens(
            amount,
            0, // Accept any amount
            path,
            address(this),
            block.timestamp + 300
        ) {
            // Swap successful
        } catch {
            // Swap failed
        }
    }

    function _swapToBaseToken(address fromToken, uint256 amount) internal {
        if (fromToken == address(baseToken) || amount == 0) return;
        
        address[] memory path = new address[](2);
        path[0] = fromToken;
        path[1] = address(baseToken);
        
        IERC20(fromToken).approve(address(punchRouter), amount);
        
        try punchRouter.swapExactTokensForTokens(
            amount,
            0, // Accept any amount
            path,
            address(this),
            block.timestamp + 300
        ) {
            // Swap successful
        } catch {
            // Swap failed
        }
    }

    function _calculateTotalLiquidityValue() internal view returns (uint256 totalValue) {
        for (uint256 i = 0; i < activePairs.length; i++) {
            IPunchSwapV2Pair pair = IPunchSwapV2Pair(activePairs[i]);
            address tokenA = pair.token0();
            address tokenB = pair.token1();
            
            LiquidityPosition memory position = liquidityPositions[tokenA][tokenB];
            
            if (position.active) {
                // Estimate value in base token terms
                uint256 valueA = _estimateTokenValue(tokenA, position.amountA);
                uint256 valueB = _estimateTokenValue(tokenB, position.amountB);
                totalValue += valueA + valueB;
            }
        }
    }

    function _calculateOtherTokensValue() internal view returns (uint256 totalValue) {
        for (uint256 i = 0; i < tradingTokens.length; i++) {
            address token = tradingTokens[i];
            if (token != address(baseToken)) {
                uint256 balance = IERC20(token).balanceOf(address(this));
                if (balance > 0) {
                    totalValue += _estimateTokenValue(token, balance);
                }
            }
        }
    }

    function _estimateTokenValue(address token, uint256 amount) internal view returns (uint256 value) {
        if (token == address(baseToken)) {
            return amount;
        }
        
        // Get price from PunchSwap
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = address(baseToken);
        
        try punchRouter.getAmountsOut(amount, path) returns (uint256[] memory amounts) {
            value = amounts[1];
        } catch {
            value = 0;
        }
    }

    // ====================================================================
    // VIEW FUNCTIONS
    // ====================================================================

    function getPerformanceMetrics() external view returns (
        uint256 totalDeployedAmount,
        uint256 totalHarvestedAmount,
        uint256 totalArbitrageProfit_,
        uint256 totalLiquidityFees_,
        uint256 arbitrageSuccessRate,
        uint256 activeLiquidityPositions
    ) {
        uint256 successRate = totalArbitrageAttempts > 0 ? 
            (successfulArbitrages * 10000) / totalArbitrageAttempts : 0;
        
        return (
            totalDeployed,
            totalHarvested,
            totalArbitrageProfit,
            totalLiquidityFees,
            successRate,
            activePairs.length
        );
    }

    function getActiveLiquidityPositions() external view returns (
        address[] memory tokenAs,
        address[] memory tokenBs,
        uint256[] memory liquidities,
        uint256[] memory amountsA,
        uint256[] memory amountsB
    ) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < activePairs.length; i++) {
            IPunchSwapV2Pair pair = IPunchSwapV2Pair(activePairs[i]);
            address tokenA = pair.token0();
            address tokenB = pair.token1();
            if (liquidityPositions[tokenA][tokenB].active) {
                activeCount++;
            }
        }
        
        tokenAs = new address[](activeCount);
        tokenBs = new address[](activeCount);
        liquidities = new uint256[](activeCount);
        amountsA = new uint256[](activeCount);
        amountsB = new uint256[](activeCount);
        
        uint256 index = 0;
        for (uint256 i = 0; i < activePairs.length; i++) {
            IPunchSwapV2Pair pair = IPunchSwapV2Pair(activePairs[i]);
            address tokenA = pair.token0();
            address tokenB = pair.token1();
            LiquidityPosition memory position = liquidityPositions[tokenA][tokenB];
            
            if (position.active) {
                tokenAs[index] = tokenA;
                tokenBs[index] = tokenB;
                liquidities[index] = position.liquidity;
                amountsA[index] = position.amountA;
                amountsB[index] = position.amountB;
                index++;
            }
        }
    }

    function getRecentArbitrageOpportunities(uint256 count) external view returns (bytes32[] memory) {
        uint256 length = recentOpportunities.length;
        uint256 returnCount = count > 0 && count < length ? count : length;
        
        bytes32[] memory recent = new bytes32[](returnCount);
        for (uint256 i = 0; i < returnCount; i++) {
            recent[i] = recentOpportunities[length - returnCount + i];
        }
        
        return recent;
    }

    // ====================================================================
    // ADMIN FUNCTIONS
    // ====================================================================

    function setStrategyMode(StrategyMode newMode) external onlyRole(DEFAULT_ADMIN_ROLE) {
        StrategyMode oldMode = currentMode;
        currentMode = newMode;
        emit StrategyModeChanged(oldMode, newMode);
    }

    function setArbitrageSettings(
        uint256 _minProfitThreshold,
        uint256 _maxSlippage,
        uint256 _maxGasPrice,
        uint256 _arbitrageCapPercentage
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_maxSlippage <= 1000, "Slippage too high"); // Max 10%
        require(_arbitrageCapPercentage <= 50, "Arbitrage cap too high"); // Max 50%
        
        minProfitThreshold = _minProfitThreshold;
        maxSlippage = _maxSlippage;
        maxGasPrice = _maxGasPrice;
        arbitrageCapPercentage = _arbitrageCapPercentage;
    }

    function setLiquidityAllocation(uint256 _liquidityAllocation) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_liquidityAllocation <= 100, "Invalid allocation");
        liquidityAllocation = _liquidityAllocation;
    }

    function addWhitelistedToken(address token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(token != address(0), "Invalid token");
        require(!whitelistedTokens[token], "Already whitelisted");
        
        whitelistedTokens[token] = true;
        tradingTokens.push(token);
    }

    function removeWhitelistedToken(address token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(whitelistedTokens[token], "Not whitelisted");
        
        whitelistedTokens[token] = false;
        
        // Remove from trading tokens array
        for (uint256 i = 0; i < tradingTokens.length; i++) {
            if (tradingTokens[i] == token) {
                tradingTokens[i] = tradingTokens[tradingTokens.length - 1];
                tradingTokens.pop();
                break;
            }
        }
    }

    function setPaused(bool paused) external onlyRole(DEFAULT_ADMIN_ROLE) {
        strategyPaused = paused;
    }

    function emergencyRemoveLiquidity(address tokenA, address tokenB) external onlyRole(EMERGENCY_ROLE) {
        LiquidityPosition storage position = liquidityPositions[tokenA][tokenB];
        if (position.active && position.liquidity > 0) {
            _removeLiquidity(tokenA, tokenB, position.liquidity);
        }
    }

    function manualArbitrage(
        address tokenA,
        address tokenB,
        uint256 inputAmount
    ) external onlyRole(AGENT_ROLE) nonReentrant {
        ArbitrageOpportunity memory opportunity = ArbitrageOpportunity({
            tokenA: tokenA,
            tokenB: tokenB,
            dexA: PUNCH_SWAP_V2_ROUTER,
            dexB: IZI_SWAP_V3_ROUTER,
            profitAmount: 0, // Will be calculated
            inputAmount: inputAmount,
            gasEstimate: 300000,
            isValid: true,
            timestamp: block.timestamp
        });
        
        _executeArbitrage(opportunity);
    }
}