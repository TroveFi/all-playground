// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

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

contract MinimalArbitrageStrategy is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    IERC20 public immutable baseToken;
    IPunchSwapRouter public immutable router;
    address public vault;
    bool public strategyPaused;

    // Flow EVM addresses
    address public constant PUNCH_SWAP_ROUTER = 0xf45AFe28fd5519d5f8C1d4787a4D5f724C0eFa4d;
    address public constant WFLOW = 0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e;
    address public constant USDC = 0xF1815bd50389c46847f0Bda824eC8da914045D14;
    address public constant USDT = 0x674843C06FF83502ddb4D37c2E09C01cdA38cbc8;

    // Strategy tracking
    uint256 public totalDeployed;
    uint256 public totalHarvested;
    uint256 public lastHarvestTime;

    // Settings
    uint256 public minProfitThreshold = 1 * 10**6; // 1 USDC
    uint256 public maxSlippage = 300; // 3%

    event StrategyExecuted(uint256 amount, bytes data);
    event StrategyHarvested(uint256 harvested, uint256 totalHarvested);
    event ArbitrageExecuted(address tokenA, address tokenB, uint256 profit);

    constructor(address _baseToken, address _vault) {
        require(_baseToken != address(0), "Invalid base token");
        require(_vault != address(0), "Invalid vault");

        baseToken = IERC20(_baseToken);
        vault = _vault;
        router = IPunchSwapRouter(PUNCH_SWAP_ROUTER);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(VAULT_ROLE, _vault);
    }

    modifier onlyVault() {
        require(msg.sender == vault, "Only vault can call");
        _;
    }

    modifier whenNotPaused() {
        require(!strategyPaused, "Strategy is paused");
        _;
    }

    function execute(uint256 amount, bytes calldata data) 
        external 
        onlyVault 
        nonReentrant 
        whenNotPaused
    {
        require(amount > 0, "Amount must be greater than 0");

        baseToken.safeTransferFrom(msg.sender, address(this), amount);
        totalDeployed += amount;

        // Simple arbitrage execution - look for USDC/USDT price differences
        _executeSimpleArbitrage();

        emit StrategyExecuted(amount, data);
    }

    function harvest(bytes calldata data) 
        external 
        onlyVault 
        nonReentrant 
        whenNotPaused
        returns (uint256 harvestedAmount)
    {
        uint256 balanceBefore = baseToken.balanceOf(address(this));

        // Execute simple arbitrage opportunities
        _executeSimpleArbitrage();

        harvestedAmount = baseToken.balanceOf(address(this)) - balanceBefore;
        
        if (harvestedAmount > 0) {
            baseToken.safeTransfer(vault, harvestedAmount);
            totalHarvested += harvestedAmount;
            lastHarvestTime = block.timestamp;
        }

        emit StrategyHarvested(harvestedAmount, totalHarvested);
        return harvestedAmount;
    }

    function emergencyExit(bytes calldata data) 
        external 
        onlyRole(EMERGENCY_ROLE) 
        nonReentrant 
    {
        strategyPaused = true;

        // Convert any USDT back to USDC
        uint256 usdtBalance = IERC20(USDT).balanceOf(address(this));
        if (usdtBalance > 0) {
            _swapToken(USDT, address(baseToken), usdtBalance);
        }

        // Transfer all base tokens to vault
        uint256 finalBalance = baseToken.balanceOf(address(this));
        if (finalBalance > 0) {
            baseToken.safeTransfer(vault, finalBalance);
        }
    }

    function _executeSimpleArbitrage() internal {
        // Simple USDC/USDT arbitrage
        uint256 testAmount = 1000 * 10**6; // 1000 USDC
        uint256 availableAmount = baseToken.balanceOf(address(this));
        
        if (availableAmount < testAmount) return;

        // Check USDC -> USDT price
        uint256 usdtOut = _getAmountOut(address(baseToken), USDT, testAmount);
        
        if (usdtOut > testAmount + minProfitThreshold) {
            // Profitable: USDC -> USDT -> USDC
            uint256 actualAmount = availableAmount / 2; // Use half
            
            bool success1 = _swapToken(address(baseToken), USDT, actualAmount);
            if (success1) {
                uint256 usdtReceived = IERC20(USDT).balanceOf(address(this));
                bool success2 = _swapToken(USDT, address(baseToken), usdtReceived);
                
                if (success2) {
                    uint256 profit = baseToken.balanceOf(address(this)) - (availableAmount - actualAmount);
                    if (profit > 0) {
                        emit ArbitrageExecuted(address(baseToken), USDT, profit);
                    }
                }
            }
        }
    }

    function _swapToken(address tokenIn, address tokenOut, uint256 amountIn) internal returns (bool) {
        if (amountIn == 0) return false;
        
        IERC20(tokenIn).safeApprove(PUNCH_SWAP_ROUTER, amountIn);
        
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        
        uint256 minAmountOut = (_getAmountOut(tokenIn, tokenOut, amountIn) * (10000 - maxSlippage)) / 10000;
        
        try router.swapExactTokensForTokens(
            amountIn,
            minAmountOut,
            path,
            address(this),
            block.timestamp + 300
        ) {
            return true;
        } catch {
            return false;
        }
    }

    function _getAmountOut(address tokenIn, address tokenOut, uint256 amountIn) internal view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        
        try router.getAmountsOut(amountIn, path) returns (uint256[] memory amounts) {
            return amounts[1];
        } catch {
            return 0;
        }
    }

    // Enhanced strategy interface functions
    function getHealthFactor() external pure returns (uint256) {
        return type(uint256).max;
    }

    function getLeverageRatio() external pure returns (uint256) {
        return 1e18;
    }

    function getPositionValue() external view returns (uint256 collateral, uint256 debt) {
        collateral = baseToken.balanceOf(address(this));
        debt = 0;
    }

    function checkLiquidationRisk() external pure returns (bool atRisk, uint256 buffer) {
        atRisk = false;
        buffer = type(uint256).max;
    }

    function getMaxWithdrawable() external view returns (uint256) {
        return baseToken.balanceOf(address(this));
    }

    function adjustLeverage(uint256 targetRatio, uint256 maxSlippageParam) external onlyRole(AGENT_ROLE) {
        require(targetRatio == 1e18, "Only 1x leverage supported");
    }

    function emergencyDelever() external onlyRole(AGENT_ROLE) {
        // Convert any non-base tokens back to base
        uint256 usdtBalance = IERC20(USDT).balanceOf(address(this));
        if (usdtBalance > 0) {
            _swapToken(USDT, address(baseToken), usdtBalance);
        }
    }

    function rebalance(bytes calldata rebalanceData) external onlyRole(AGENT_ROLE) {
        // Simple rebalance - convert everything back to base token
        this.emergencyDelever();
    }

    function setRiskParameters(
        uint256 maxLeverage,
        uint256 targetHealthFactor,
        uint256 liquidationBuffer
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(maxLeverage == 1e18, "Only 1x leverage supported");
    }

    function getBalance() external view returns (uint256) {
        uint256 baseBalance = baseToken.balanceOf(address(this));
        uint256 usdtBalance = IERC20(USDT).balanceOf(address(this));
        
        // Add USDT value (assume 1:1 with USDC)
        return baseBalance + usdtBalance;
    }

    function getPerformanceMetrics() external view returns (
        uint256 totalDeployedAmount,
        uint256 totalHarvestedAmount,
        uint256 totalArbitrageProfit,
        uint256 arbitrageSuccessRate,
        uint256 avgProfitPerTrade,
        uint256 lastHarvestTimestamp
    ) {
        return (
            totalDeployed,
            totalHarvested,
            totalHarvested, // Use total harvested as profit proxy
            10000, // 100% success rate (simplified)
            totalHarvested / (totalHarvested > 0 ? 1 : 1), // Avoid division by zero
            lastHarvestTime
        );
    }

    function setMinProfitThreshold(uint256 _minProfitThreshold) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minProfitThreshold = _minProfitThreshold;
    }

    function setPaused(bool paused) external onlyRole(DEFAULT_ADMIN_ROLE) {
        strategyPaused = paused;
    }

    // IStrategy interface compatibility
    function underlyingToken() external view returns (address) {
        return address(baseToken);
    }

    function protocol() external pure returns (address) {
        return PUNCH_SWAP_ROUTER;
    }

    function paused() external view returns (bool) {
        return strategyPaused;
    }

    receive() external payable {}
}