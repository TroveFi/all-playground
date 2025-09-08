// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// More.Markets Aave-style interfaces
interface IPool {
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
}

// Uniswap V2 style DEX interface
interface IPunchSwapRouter {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    
    function getAmountsOut(uint amountIn, address[] calldata path)
        external view returns (uint[] memory amounts);
}

// WFLOW interface for wrapping/unwrapping native FLOW
interface IWFLOW is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
}

/// @title MoreMarketsLoopingStrategy - Rebuilt Leveraged Lending Strategy
/// @notice Implements leveraged looping on More.Markets using USDC/stFLOW/WFLOW
/// @dev Accepts USDC from vault, converts to stFLOW, loops with WFLOW borrows
contract MoreMarketsLoopingStrategy is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ====================================================================
    // CONSTANTS & ADDRESSES
    // ====================================================================
    
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    
    uint256 public constant VARIABLE_RATE = 2;
    uint256 public constant BASIS_POINTS = 10000;
    
    // Flow EVM Mainnet addresses
    address public constant MORE_MARKETS_POOL = 0xbC92aaC2DBBF42215248B5688eB3D3d2b32F2c8d;
    address public constant PUNCH_SWAP_ROUTER = 0xf45AFe28fd5519d5f8C1d4787a4D5f724C0eFa4d;
    address public constant INCREMENT_ROUTER = 0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590;
    
    address public constant USDC = 0xF1815bd50389c46847f0Bda824eC8da914045D14;
    address public constant WFLOW = 0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e;
    address public constant STFLOW = 0x1b97100eA1D7126C4d60027e231EA4CB25314bdb;

    // ====================================================================
    // STATE VARIABLES
    // ====================================================================
    
    IPool public immutable lendingPool;
    IPunchSwapRouter public immutable router;
    IERC20 public immutable usdcToken;
    IERC20 public immutable stFlowToken;
    IWFLOW public immutable wflowToken;
    
    address public vault;
    bool public strategyPaused;
    bool public emergencyMode;

    // Strategy parameters
    uint256 public targetLeverage = 2 * 1e18;        // 2x leverage (conservative)
    uint256 public maxLeverage = 25 * 1e17;          // 2.5x max leverage
    uint256 public targetHealthFactor = 25 * 1e17;   // 2.5 target health factor
    uint256 public minHealthFactor = 17 * 1e17;      // 1.7 minimum health factor
    uint256 public maxSlippage = 500;                // 5% max slippage
    uint256 public maxLoops = 3;                     // Max 3 loops

    // Position tracking
    uint256 public totalUSDCDeployed;
    uint256 public totalStFLOWSupplied;
    uint256 public totalWFLOWBorrowed;
    uint256 public totalHarvested;
    uint256 public lastHarvestTime;
    uint256 public harvestCount;

    // ====================================================================
    // EVENTS
    // ====================================================================
    
    event StrategyExecuted(uint256 usdcAmount, uint256 stFlowSupplied, uint256 leverage);
    event LoopIteration(uint256 iteration, uint256 borrowed, uint256 supplied);
    event Harvested(uint256 harvestedUSDC);
    event PositionUnwound(uint256 recoveredUSDC);
    event LeverageAdjusted(uint256 oldLeverage, uint256 newLeverage);
    event TokenSwapped(address fromToken, address toToken, uint256 fromAmount, uint256 toAmount);

    // ====================================================================
    // CONSTRUCTOR
    // ====================================================================
    
    constructor(address _vault) {
        require(_vault != address(0), "Invalid vault");

        vault = _vault;
        lendingPool = IPool(MORE_MARKETS_POOL);
        router = IPunchSwapRouter(PUNCH_SWAP_ROUTER);
        usdcToken = IERC20(USDC);
        stFlowToken = IERC20(STFLOW);
        wflowToken = IWFLOW(WFLOW);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(VAULT_ROLE, _vault);
    }

    // ====================================================================
    // RECEIVE ETH
    // ====================================================================
    
    receive() external payable {
        // Accept native FLOW for gas operations and potential wrapping
    }

    fallback() external payable {
        // Handle any unexpected calls
    }

    // ====================================================================
    // MODIFIERS
    // ====================================================================
    
    modifier onlyVault() {
        require(hasRole(VAULT_ROLE, msg.sender), "Only vault");
        _;
    }

    modifier whenNotPaused() {
        require(!strategyPaused && !emergencyMode, "Strategy paused");
        _;
    }

    modifier healthCheck() {
        _checkHealthFactor();
        _;
    }

    // ====================================================================
    // MAIN STRATEGY FUNCTIONS
    // ====================================================================

    /// @notice Execute the looping strategy with USDC from vault
    /// @param amount USDC amount to deploy
    /// @param data Optional leverage override
    function execute(uint256 amount, bytes calldata data) 
        external 
        onlyVault 
        nonReentrant 
        whenNotPaused 
        healthCheck 
    {
        require(amount > 0, "Invalid amount");

        // Get USDC from vault
        usdcToken.safeTransferFrom(msg.sender, address(this), amount);

        // Decode target leverage if provided
        uint256 leverage = targetLeverage;
        if (data.length > 0) {
            leverage = abi.decode(data, (uint256));
            require(leverage <= maxLeverage, "Leverage too high");
            require(leverage >= 1e18, "Leverage too low");
        }

        // Convert USDC to stFLOW for collateral
        uint256 stFlowAmount = _convertUSDCToStFLOW(amount);
        require(stFlowAmount > 0, "USDC to stFLOW conversion failed");

        // Execute leveraged position
        _buildLeveragedPosition(stFlowAmount, leverage);

        totalUSDCDeployed += amount;

        emit StrategyExecuted(amount, stFlowAmount, leverage);
    }

    /// @notice Harvest yields and rebalance if needed
    function harvest(bytes calldata data) 
        external 
        onlyVault 
        nonReentrant 
        whenNotPaused 
        healthCheck 
    {
        uint256 usdcBefore = usdcToken.balanceOf(address(this));

        // Check position health and rebalance if needed
        (uint256 currentLeverage, uint256 healthFactor) = _getPositionMetrics();
        
        if (_shouldRebalance(currentLeverage, healthFactor)) {
            _rebalancePosition();
        }

        // Calculate and realize any yield
        uint256 yield = _calculateYield();
        if (yield > 0) {
            _realizeYield(yield);
        }

        // Convert any harvested tokens to USDC
        _convertAllToUSDC();

        uint256 usdcAfter = usdcToken.balanceOf(address(this));
        uint256 harvestedAmount = usdcAfter - usdcBefore;

        // Send harvested USDC back to vault
        if (harvestedAmount > 0) {
            usdcToken.safeTransfer(vault, harvestedAmount);
            totalHarvested += harvestedAmount;
            harvestCount++;
        }

        lastHarvestTime = block.timestamp;
        emit Harvested(harvestedAmount);
    }

    /// @notice Emergency exit - unwind all positions
    function emergencyExit(bytes calldata data) 
        external 
        onlyRole(EMERGENCY_ROLE) 
        nonReentrant 
    {
        emergencyMode = true;
        strategyPaused = true;

        uint256 recoveredUSDC = _unwindPosition();

        // Transfer all recovered USDC to vault
        if (recoveredUSDC > 0) {
            usdcToken.safeTransfer(vault, recoveredUSDC);
        }

        emit PositionUnwound(recoveredUSDC);
    }

    // ====================================================================
    // INTERNAL STRATEGY LOGIC
    // ====================================================================

    /// @notice Build leveraged position through looping
    function _buildLeveragedPosition(uint256 initialStFlow, uint256 targetLev) internal {
        // Supply initial stFLOW as collateral
        _supplyCollateral(initialStFlow);

        // Calculate total position size needed for target leverage
        uint256 totalPosition = (initialStFlow * targetLev) / 1e18;
        uint256 additionalNeeded = totalPosition - initialStFlow;

        uint256 remainingToBorrow = additionalNeeded;
        uint256 iteration = 0;

        while (remainingToBorrow > 0 && iteration < maxLoops) {
            // Check current borrow capacity
            (, , uint256 availableBorrows, , , uint256 healthFactor) = 
                lendingPool.getUserAccountData(address(this));

            // Safety check
            if (healthFactor <= minHealthFactor) break;

            // Calculate safe borrow amount
            uint256 safeBorrowAmount = (availableBorrows * 70) / 100; // 70% safety buffer
            uint256 borrowAmount = Math.min(remainingToBorrow, safeBorrowAmount);

            if (borrowAmount < 1e15) break; // Minimum 0.001 WFLOW

            // Borrow WFLOW
            lendingPool.borrow(WFLOW, borrowAmount, VARIABLE_RATE, 0, address(this));
            totalWFLOWBorrowed += borrowAmount;

            // Convert WFLOW to stFLOW
            uint256 newStFlow = _convertWFLOWToStFLOW(borrowAmount);
            if (newStFlow == 0) break;

            // Supply new stFLOW as collateral
            _supplyCollateral(newStFlow);

            remainingToBorrow = remainingToBorrow > borrowAmount ? remainingToBorrow - borrowAmount : 0;
            iteration++;

            emit LoopIteration(iteration, borrowAmount, newStFlow);
        }
    }

    /// @notice Supply stFLOW as collateral to More.Markets
    function _supplyCollateral(uint256 amount) internal {
        stFlowToken.approve(address(lendingPool), amount);
        lendingPool.supply(STFLOW, amount, address(this), 0);
        totalStFLOWSupplied += amount;
    }

    /// @notice Rebalance position if needed
    function _rebalancePosition() internal {
        (uint256 currentLeverage, ) = _getPositionMetrics();

        if (currentLeverage > targetLeverage) {
            _reduceLeverage();
        } else if (currentLeverage < (targetLeverage * 90) / 100) {
            _increaseLeverage();
        }

        emit LeverageAdjusted(currentLeverage, targetLeverage);
    }

    /// @notice Reduce leverage by repaying debt
    function _reduceLeverage() internal {
        (uint256 totalCollateral, uint256 totalDebt, , , , ) = 
            lendingPool.getUserAccountData(address(this));

        if (totalDebt == 0) return;

        // Calculate how much debt to repay to reach target leverage
        uint256 targetDebt = totalCollateral - (totalCollateral * 1e18 / targetLeverage);
        uint256 debtToRepay = totalDebt > targetDebt ? totalDebt - targetDebt : 0;

        if (debtToRepay > 0) {
            // Withdraw stFLOW collateral
            uint256 stFlowToWithdraw = (debtToRepay * 110) / 100; // 10% buffer
            
            try lendingPool.withdraw(STFLOW, stFlowToWithdraw, address(this)) {
                // Convert stFLOW to WFLOW for repayment
                uint256 wflowForRepay = _convertStFLOWToWFLOW(stFlowToWithdraw);
                
                if (wflowForRepay > 0) {
                    // Repay debt
                    wflowToken.approve(address(lendingPool), wflowForRepay);
                    lendingPool.repay(WFLOW, wflowForRepay, VARIABLE_RATE, address(this));
                    totalWFLOWBorrowed = totalWFLOWBorrowed > wflowForRepay ? 
                        totalWFLOWBorrowed - wflowForRepay : 0;
                }
            } catch {
                // Withdrawal failed, skip reduction
            }
        }
    }

    /// @notice Increase leverage by borrowing more
    function _increaseLeverage() internal {
        (uint256 totalCollateral, uint256 totalDebt, uint256 availableBorrows, , , ) = 
            lendingPool.getUserAccountData(address(this));

        // Calculate how much more to borrow
        uint256 targetDebt = totalCollateral - (totalCollateral * 1e18 / targetLeverage);
        uint256 additionalBorrow = targetDebt > totalDebt ? targetDebt - totalDebt : 0;

        uint256 safeBorrow = Math.min(additionalBorrow, (availableBorrows * 70) / 100);

        if (safeBorrow >= 1e15) { // Minimum 0.001 WFLOW
            // Borrow WFLOW
            lendingPool.borrow(WFLOW, safeBorrow, VARIABLE_RATE, 0, address(this));
            totalWFLOWBorrowed += safeBorrow;

            // Convert to stFLOW and supply
            uint256 newStFlow = _convertWFLOWToStFLOW(safeBorrow);
            if (newStFlow > 0) {
                _supplyCollateral(newStFlow);
            }
        }
    }

    /// @notice Unwind entire position and return USDC
    function _unwindPosition() internal returns (uint256 recoveredUSDC) {
        uint256 iterations = 0;
        
        while (totalWFLOWBorrowed > 0 && iterations < 10) {
            (, uint256 totalDebt, , , , ) = lendingPool.getUserAccountData(address(this));
            
            if (totalDebt == 0) break;

            // Withdraw stFLOW to repay debt
            uint256 stFlowToWithdraw = totalDebt + (totalDebt / 5); // 20% buffer
            
            try lendingPool.withdraw(STFLOW, stFlowToWithdraw, address(this)) {
                uint256 wflowForRepay = _convertStFLOWToWFLOW(stFlowToWithdraw);
                
                if (wflowForRepay > 0) {
                    wflowToken.approve(address(lendingPool), wflowForRepay);
                    lendingPool.repay(WFLOW, type(uint256).max, VARIABLE_RATE, address(this));
                }
            } catch {
                break;
            }
            
            iterations++;
        }

        // Withdraw remaining stFLOW
        try lendingPool.withdraw(STFLOW, type(uint256).max, address(this)) {
            // Successfully withdrew
        } catch {
            // Partial withdrawal
        }

        // Convert all tokens to USDC
        _convertAllToUSDC();
        recoveredUSDC = usdcToken.balanceOf(address(this));

        // Reset tracking
        totalStFLOWSupplied = 0;
        totalWFLOWBorrowed = 0;
    }

    // ====================================================================
    // TOKEN CONVERSION FUNCTIONS
    // ====================================================================

    /// @notice Convert USDC to stFLOW via WFLOW
    function _convertUSDCToStFLOW(uint256 usdcAmount) internal returns (uint256 stFlowAmount) {
        // USDC -> WFLOW -> stFLOW
        uint256 wflowAmount = _swapTokens(USDC, WFLOW, usdcAmount);
        if (wflowAmount > 0) {
            stFlowAmount = _swapTokens(WFLOW, STFLOW, wflowAmount);
        }
        
        emit TokenSwapped(USDC, STFLOW, usdcAmount, stFlowAmount);
    }

    /// @notice Convert WFLOW to stFLOW
    function _convertWFLOWToStFLOW(uint256 wflowAmount) internal returns (uint256 stFlowAmount) {
        stFlowAmount = _swapTokens(WFLOW, STFLOW, wflowAmount);
        emit TokenSwapped(WFLOW, STFLOW, wflowAmount, stFlowAmount);
    }

    /// @notice Convert stFLOW to WFLOW
    function _convertStFLOWToWFLOW(uint256 stFlowAmount) internal returns (uint256 wflowAmount) {
        wflowAmount = _swapTokens(STFLOW, WFLOW, stFlowAmount);
        emit TokenSwapped(STFLOW, WFLOW, stFlowAmount, wflowAmount);
    }

    /// @notice Convert all loose tokens to USDC
    function _convertAllToUSDC() internal {
        // Convert stFLOW to USDC
        uint256 stFlowBalance = stFlowToken.balanceOf(address(this));
        if (stFlowBalance > 0) {
            uint256 wflowFromStFlow = _swapTokens(STFLOW, WFLOW, stFlowBalance);
            if (wflowFromStFlow > 0) {
                _swapTokens(WFLOW, USDC, wflowFromStFlow);
            }
        }

        // Convert WFLOW to USDC
        uint256 wflowBalance = wflowToken.balanceOf(address(this));
        if (wflowBalance > 0) {
            _swapTokens(WFLOW, USDC, wflowBalance);
        }

        // Convert native FLOW to USDC
        if (address(this).balance > 0) {
            wflowToken.deposit{value: address(this).balance}();
            uint256 wrappedAmount = wflowToken.balanceOf(address(this));
            if (wrappedAmount > 0) {
                _swapTokens(WFLOW, USDC, wrappedAmount);
            }
        }
    }

    /// @notice Generic token swap function
    function _swapTokens(address tokenIn, address tokenOut, uint256 amountIn) 
        internal 
        returns (uint256 amountOut) 
    {
        if (amountIn == 0) return 0;

        IERC20(tokenIn).approve(address(router), amountIn);

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        try router.getAmountsOut(amountIn, path) returns (uint256[] memory amounts) {
            uint256 minAmountOut = (amounts[1] * (BASIS_POINTS - maxSlippage)) / BASIS_POINTS;

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
        } catch {
            amountOut = 0;
        }
    }

    // ====================================================================
    // HELPER FUNCTIONS
    // ====================================================================

    /// @notice Check if position should be rebalanced
    function _shouldRebalance(uint256 currentLev, uint256 healthFactor) 
        internal 
        view 
        returns (bool) 
    {
        // Rebalance if leverage drifts by more than 15%
        uint256 leverageDiff = currentLev > targetLeverage ? 
            currentLev - targetLeverage : targetLeverage - currentLev;
        bool leverageOutOfRange = leverageDiff > (targetLeverage * 15) / 100;

        // Rebalance if health factor is too low or too high
        bool healthOutOfRange = healthFactor < minHealthFactor || 
            healthFactor > (targetHealthFactor * 120) / 100;

        return leverageOutOfRange || healthOutOfRange;
    }

    /// @notice Get current position metrics
    function _getPositionMetrics() internal view returns (uint256 leverage, uint256 healthFactor) {
        (uint256 totalCollateral, uint256 totalDebt, , , , uint256 hf) = 
            lendingPool.getUserAccountData(address(this));

        healthFactor = hf;

        if (totalDebt == 0) {
            leverage = 1e18;
        } else {
            leverage = (totalCollateral * 1e18) / (totalCollateral - totalDebt);
        }
    }

    /// @notice Check health factor
    function _checkHealthFactor() internal view {
        (, , , , , uint256 healthFactor) = lendingPool.getUserAccountData(address(this));
        require(healthFactor >= (minHealthFactor * 95) / 100, "Health factor too low");
    }

    /// @notice Calculate yield from position
    function _calculateYield() internal view returns (uint256) {
        (uint256 totalCollateral, uint256 totalDebt, , , , ) = 
            lendingPool.getUserAccountData(address(this));
        
        uint256 netPosition = totalCollateral > totalDebt ? totalCollateral - totalDebt : 0;
        
        // Simple yield calculation
        return netPosition > totalUSDCDeployed ? netPosition - totalUSDCDeployed : 0;
    }

    /// @notice Realize yield by withdrawing excess
    function _realizeYield(uint256 yieldAmount) internal {
        // Withdraw small amount of stFLOW representing yield
        uint256 yieldToWithdraw = (yieldAmount * 5) / 100; // 5% of calculated yield
        
        try lendingPool.withdraw(STFLOW, yieldToWithdraw, address(this)) {
            // Successfully withdrew yield
        } catch {
            // Yield withdrawal failed
        }
    }

    // ====================================================================
    // ENHANCED STRATEGY INTERFACE
    // ====================================================================

    function getHealthFactor() external view returns (uint256) {
        (, , , , , uint256 healthFactor) = lendingPool.getUserAccountData(address(this));
        return healthFactor;
    }

    function getLeverageRatio() external view returns (uint256) {
        (uint256 leverage, ) = _getPositionMetrics();
        return leverage;
    }

    function getPositionValue() external view returns (uint256 collateral, uint256 debt) {
        (collateral, debt, , , , ) = lendingPool.getUserAccountData(address(this));
    }

    function checkLiquidationRisk() external view returns (bool atRisk, uint256 buffer) {
        (, , , , , uint256 healthFactor) = lendingPool.getUserAccountData(address(this));
        atRisk = healthFactor <= minHealthFactor;
        buffer = healthFactor > minHealthFactor ? healthFactor - minHealthFactor : 0;
    }

    function getMaxWithdrawable() external view returns (uint256) {
        (uint256 totalCollateral, uint256 totalDebt, , , , ) = 
            lendingPool.getUserAccountData(address(this));
        return totalCollateral > totalDebt ? totalCollateral - totalDebt : 0;
    }

    function emergencyDelever() external onlyRole(AGENT_ROLE) nonReentrant {
        _reduceLeverage();
    }

    function adjustLeverage(uint256 newTarget, uint256) external onlyRole(AGENT_ROLE) {
        require(newTarget <= maxLeverage && newTarget >= 1e18, "Invalid leverage");
        targetLeverage = newTarget;
        _rebalancePosition();
    }

    function rebalance(bytes calldata) external onlyRole(AGENT_ROLE) nonReentrant {
        _rebalancePosition();
    }

    function setRiskParameters(uint256 _maxLev, uint256 _targetHF, uint256 _minHF) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(_maxLev >= 1e18 && _maxLev <= 5e18, "Invalid max leverage");
        require(_targetHF > _minHF && _minHF >= 12e17, "Invalid health factors");
        
        maxLeverage = _maxLev;
        targetHealthFactor = _targetHF;
        minHealthFactor = _minHF;
    }

    // ====================================================================
    // VIEW FUNCTIONS
    // ====================================================================

    function getBalance() external view returns (uint256) {
        (uint256 totalCollateral, uint256 totalDebt, , , , ) = 
            lendingPool.getUserAccountData(address(this));
        return totalCollateral > totalDebt ? totalCollateral - totalDebt : 0;
    }

    function getPerformanceMetrics() external view returns (
        uint256 totalDeployed,
        uint256 totalHarvestedAmount,
        uint256 harvestsCount,
        uint256 currentLeverage,
        uint256 currentHealthFactor
    ) {
        (currentLeverage, currentHealthFactor) = _getPositionMetrics();
        return (totalUSDCDeployed, totalHarvested, harvestCount, currentLeverage, currentHealthFactor);
    }

    function getTokenBalances() external view returns (
        uint256 usdc,
        uint256 stFlow,
        uint256 wflow,
        uint256 nativeFlow
    ) {
        return (
            usdcToken.balanceOf(address(this)),
            stFlowToken.balanceOf(address(this)),
            wflowToken.balanceOf(address(this)),
            address(this).balance
        );
    }

    // ====================================================================
    // ADMIN FUNCTIONS
    // ====================================================================

    function setPaused(bool paused) external onlyRole(DEFAULT_ADMIN_ROLE) {
        strategyPaused = paused;
    }

    function setMaxSlippage(uint256 _maxSlippage) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_maxSlippage <= 1000, "Slippage too high");
        maxSlippage = _maxSlippage;
    }

    function emergencyWithdrawToken(address token, uint256 amount) 
        external 
        onlyRole(EMERGENCY_ROLE) 
    {
        require(emergencyMode, "Not emergency");
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    function emergencyWithdrawETH() external onlyRole(EMERGENCY_ROLE) {
        require(emergencyMode, "Not emergency");
        payable(msg.sender).transfer(address(this).balance);
    }

    // IStrategy interface
    function underlyingToken() external view returns (address) {
        return USDC;
    }

    function protocol() external view returns (address) {
        return address(lendingPool);
    }

    function paused() external view returns (bool) {
        return strategyPaused;
    }
}