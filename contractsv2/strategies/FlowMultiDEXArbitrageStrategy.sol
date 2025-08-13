// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./BaseStrategy.sol";

// Multiple DEX interfaces for arbitrage on Flow
interface IDEXRouter {
    function getAmountsOut(uint amountIn, address[] calldata path)
        external view returns (uint[] memory amounts);
    
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
}

interface IDEXFactory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

/// @title FlowMultiDEXArbitrageStrategy - Arbitrage across Flow DEXs
/// @notice Arbitrage strategy across BloctoSwap, PunchSwap, and Trado.one
contract FlowMultiDEXArbitrageStrategy is BaseStrategy {
    using SafeERC20 for IERC20;

    // DEX Router addresses on Flow (you'll need to get these)
    address public constant BLOCTO_ROUTER = address(0); // TODO: Get real BloctoSwap router
    address public constant PUNCH_ROUTER = address(0); // TODO: Get real PunchSwap router  
    address public constant TRADO_ROUTER = address(0); // TODO: Get real Trado.one router

    struct DEXInfo {
        string name;
        address router;
        address factory;
        bool active;
        uint256 fee; // Fee in basis points
    }

    mapping(uint256 => DEXInfo) public dexes;
    uint256 public dexCount = 3;
    
    IERC20 public immutable tokenA; // Primary trading pair token
    IERC20 public immutable tokenB; // Secondary trading pair token
    
    // Arbitrage settings
    uint256 public minProfitBasisPoints = 50; // 0.5% minimum profit
    uint256 public maxSlippage = 200; // 2% max slippage
    uint256 public maxGasPrice = 50 gwei; // Maximum gas price for profitable trades
    
    // Arbitrage tracking
    uint256 public totalArbitrageCount;
    uint256 public totalArbitrageProfit;
    uint256 public lastArbitrageTime;
    
    event ArbitrageExecuted(
        uint256 indexed tradeId,
        address indexed dexFrom,
        address indexed dexTo,
        uint256 amountIn,
        uint256 profit
    );
    
    event ArbitrageOpportunityFound(
        address indexed dexFrom,
        address indexed dexTo,
        uint256 expectedProfit,
        uint256 amountRequired
    );

    constructor(
        address _asset,
        address _tokenA,
        address _tokenB,
        address _vault,
        string memory _name
    ) BaseStrategy(_asset, address(0), _vault, _name) {
        require(_tokenA != address(0), "Invalid tokenA");
        require(_tokenB != address(0), "Invalid tokenB");
        
        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
        
        // Initialize DEX information
        _initializeDEXes();
    }

    function _initializeDEXes() internal {
        // BloctoSwap
        dexes[0] = DEXInfo({
            name: "BloctoSwap",
            router: BLOCTO_ROUTER,
            factory: address(0), // TODO: Get factory address
            active: false, // Set to true when addresses are available
            fee: 30 // 0.3% fee
        });

        // PunchSwap
        dexes[1] = DEXInfo({
            name: "PunchSwap",
            router: PUNCH_ROUTER,
            factory: address(0), // TODO: Get factory address
            active: false,
            fee: 25 // 0.25% fee
        });

        // Trado.one
        dexes[2] = DEXInfo({
            name: "Trado.one",
            router: TRADO_ROUTER,
            factory: address(0), // TODO: Get factory address
            active: false,
            fee: 30 // 0.3% fee
        });
    }

    function _executeStrategy(uint256 amount, bytes calldata data) internal override {
        // Decode trading pair if provided
        (address tradingTokenA, address tradingTokenB) = data.length > 0 
            ? abi.decode(data, (address, address))
            : (address(tokenA), address(tokenB));
        
        // Look for arbitrage opportunities
        _scanForArbitrage(amount, tradingTokenA, tradingTokenB);
    }

    function _scanForArbitrage(uint256 amount, address _tokenA, address _tokenB) internal {
        // Check all DEX pairs for arbitrage opportunities
        for (uint256 i = 0; i < dexCount; i++) {
            for (uint256 j = 0; j < dexCount; j++) {
                if (i != j && dexes[i].active && dexes[j].active) {
                    _checkArbitrageOpportunity(i, j, amount, _tokenA, _tokenB);
                }
            }
        }
    }

    function _checkArbitrageOpportunity(
        uint256 dexFromIndex,
        uint256 dexToIndex,
        uint256 amount,
        address _tokenA,
        address _tokenB
    ) internal {
        DEXInfo memory dexFrom = dexes[dexFromIndex];
        DEXInfo memory dexTo = dexes[dexToIndex];
        
        // Get price on first DEX (buy tokenB with tokenA)
        address[] memory pathBuy = new address[](2);
        pathBuy[0] = _tokenA;
        pathBuy[1] = _tokenB;
        
        uint256[] memory amountsFromDex = _getAmountsOut(dexFrom.router, amount, pathBuy);
        if (amountsFromDex.length == 0) return;
        
        uint256 tokenBReceived = amountsFromDex[amountsFromDex.length - 1];
        
        // Get price on second DEX (sell tokenB for tokenA)
        address[] memory pathSell = new address[](2);
        pathSell[0] = _tokenB;
        pathSell[1] = _tokenA;
        
        uint256[] memory amountsToDex = _getAmountsOut(dexTo.router, tokenBReceived, pathSell);
        if (amountsToDex.length == 0) return;
        
        uint256 tokenAReceived = amountsToDex[amountsToDex.length - 1];
        
        // Calculate profit
        if (tokenAReceived > amount) {
            uint256 profit = tokenAReceived - amount;
            uint256 profitBasisPoints = (profit * 10000) / amount;
            
            if (profitBasisPoints >= minProfitBasisPoints && tx.gasprice <= maxGasPrice) {
                emit ArbitrageOpportunityFound(dexFrom.router, dexTo.router, profit, amount);
                
                // Execute arbitrage if we have sufficient balance
                if (IERC20(_tokenA).balanceOf(address(this)) >= amount) {
                    _executeArbitrage(dexFromIndex, dexToIndex, amount, pathBuy, pathSell, profit);
                }
            }
        }
    }

    function _executeArbitrage(
        uint256 dexFromIndex,
        uint256 dexToIndex,
        uint256 amount,
        address[] memory pathBuy,
        address[] memory pathSell,
        uint256 expectedProfit
    ) internal {
        DEXInfo memory dexFrom = dexes[dexFromIndex];
        DEXInfo memory dexTo = dexes[dexToIndex];
        
        // Step 1: Buy tokenB on first DEX
        IERC20(pathBuy[0]).approve(dexFrom.router, amount);
        
        try IDEXRouter(dexFrom.router).swapExactTokensForTokens(
            amount,
            0, // Accept any amount of tokenB
            pathBuy,
            address(this),
            block.timestamp + 300
        ) returns (uint256[] memory amounts1) {
            
            uint256 tokenBReceived = amounts1[amounts1.length - 1];
            
            // Step 2: Sell tokenB on second DEX
            IERC20(pathSell[0]).approve(dexTo.router, tokenBReceived);
            
            try IDEXRouter(dexTo.router).swapExactTokensForTokens(
                tokenBReceived,
                amount, // Must get back at least original amount
                pathSell,
                address(this),
                block.timestamp + 300
            ) returns (uint256[] memory amounts2) {
                
                uint256 tokenAReceived = amounts2[amounts2.length - 1];
                uint256 actualProfit = tokenAReceived > amount ? tokenAReceived - amount : 0;
                
                if (actualProfit > 0) {
                    totalArbitrageCount++;
                    totalArbitrageProfit += actualProfit;
                    lastArbitrageTime = block.timestamp;
                    
                    emit ArbitrageExecuted(
                        totalArbitrageCount,
                        dexFrom.router,
                        dexTo.router,
                        amount,
                        actualProfit
                    );
                }
                
            } catch {
                // Second swap failed, we might be stuck with tokenB
                // In a real implementation, would need recovery mechanism
            }
            
        } catch {
            // First swap failed
        }
    }

    function _harvestRewards(bytes calldata) internal override {
        // For arbitrage strategy, harvesting means looking for new opportunities
        uint256 balance = assetToken.balanceOf(address(this));
        
        if (balance >= minHarvestAmount) {
            _scanForArbitrage(balance, address(tokenA), address(tokenB));
        }
        
        // Also scan for reverse arbitrage
        uint256 tokenABalance = tokenA.balanceOf(address(this));
        if (tokenABalance > 0) {
            _scanForArbitrage(tokenABalance, address(tokenA), address(assetToken));
        }
        
        uint256 tokenBBalance = tokenB.balanceOf(address(this));
        if (tokenBBalance > 0) {
            _scanForArbitrage(tokenBBalance, address(tokenB), address(assetToken));
        }
    }

    function _emergencyWithdraw(bytes calldata) internal override returns (uint256 recovered) {
        // Convert all tokens back to asset token through best available DEX
        uint256 assetBalance = assetToken.balanceOf(address(this));
        uint256 tokenABalance = tokenA.balanceOf(address(this));
        uint256 tokenBBalance = tokenB.balanceOf(address(this));
        
        recovered = assetBalance;
        
        // Convert tokenA to asset token
        if (tokenABalance > 0 && address(tokenA) != address(assetToken)) {
            uint256 convertedA = _convertToAssetToken(address(tokenA), tokenABalance);
            recovered += convertedA;
        }
        
        // Convert tokenB to asset token  
        if (tokenBBalance > 0 && address(tokenB) != address(assetToken)) {
            uint256 convertedB = _convertToAssetToken(address(tokenB), tokenBBalance);
            recovered += convertedB;
        }
        
        return recovered;
    }

    function _convertToAssetToken(address fromToken, uint256 amount) internal returns (uint256) {
        if (fromToken == address(assetToken)) return amount;
        
        // Find best DEX for conversion
        uint256 bestOutput = 0;
        uint256 bestDexIndex = 0;
        
        address[] memory path = new address[](2);
        path[0] = fromToken;
        path[1] = address(assetToken);
        
        for (uint256 i = 0; i < dexCount; i++) {
            if (dexes[i].active) {
                uint256[] memory amounts = _getAmountsOut(dexes[i].router, amount, path);
                if (amounts.length > 0 && amounts[amounts.length - 1] > bestOutput) {
                    bestOutput = amounts[amounts.length - 1];
                    bestDexIndex = i;
                }
            }
        }
        
        if (bestOutput > 0) {
            IERC20(fromToken).approve(dexes[bestDexIndex].router, amount);
            
            try IDEXRouter(dexes[bestDexIndex].router).swapExactTokensForTokens(
                amount,
                0,
                path,
                address(this),
                block.timestamp + 300
            ) returns (uint256[] memory amounts) {
                return amounts[amounts.length - 1];
            } catch {
                return 0;
            }
        }
        
        return 0;
    }

    function _getAmountsOut(address router, uint256 amountIn, address[] memory path) 
        internal view returns (uint256[] memory) {
        try IDEXRouter(router).getAmountsOut(amountIn, path) returns (uint256[] memory amounts) {
            return amounts;
        } catch {
            return new uint256[](0);
        }
    }

    function getBalance() external view override returns (uint256) {
        uint256 total = assetToken.balanceOf(address(this));
        
        // Add estimated value of other tokens held
        uint256 tokenABalance = tokenA.balanceOf(address(this));
        uint256 tokenBBalance = tokenB.balanceOf(address(this));
        
        // For simplicity, assume 1:1 conversion (in reality would get market rates)
        if (address(tokenA) != address(assetToken)) {
            total += tokenABalance; // Simplified valuation
        }
        
        if (address(tokenB) != address(assetToken)) {
            total += tokenBBalance; // Simplified valuation
        }
        
        return total;
    }

    // Manual arbitrage execution
    function manualArbitrage(
        uint256 dexFromIndex,
        uint256 dexToIndex,
        uint256 amount,
        address[] calldata pathBuy,
        address[] calldata pathSell
    ) external onlyRole(HARVESTER_ROLE) {
        require(dexFromIndex < dexCount && dexToIndex < dexCount, "Invalid DEX index");
        require(pathBuy.length >= 2 && pathSell.length >= 2, "Invalid paths");
        
        _executeArbitrage(dexFromIndex, dexToIndex, amount, pathBuy, pathSell, 0);
    }

    // Admin functions
    function updateDEX(
        uint256 index,
        string calldata name,
        address router,
        address factory,
        bool active,
        uint256 fee
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(index < dexCount, "Invalid DEX index");
        
        dexes[index] = DEXInfo({
            name: name,
            router: router,
            factory: factory,
            active: active,
            fee: fee
        });
    }

    function setMinProfitBasisPoints(uint256 _minProfit) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_minProfit <= 1000, "Profit threshold too high"); // Max 10%
        minProfitBasisPoints = _minProfit;
    }

    function setMaxSlippage(uint256 _maxSlippage) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_maxSlippage <= 1000, "Slippage too high"); // Max 10%
        maxSlippage = _maxSlippage;
    }

    function setMaxGasPrice(uint256 _maxGasPrice) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxGasPrice = _maxGasPrice;
    }

    // View functions
    function getArbitrageStats() external view returns (
        uint256 totalTrades,
        uint256 totalProfit,
        uint256 lastTradeTime,
        uint256 avgProfit
    ) {
        totalTrades = totalArbitrageCount;
        totalProfit = totalArbitrageProfit;
        lastTradeTime = lastArbitrageTime;
        avgProfit = totalTrades > 0 ? totalProfit / totalTrades : 0;
    }

    function checkArbitrageOpportunity(
        uint256 amount,
        address _tokenA,
        address _tokenB
    ) external view returns (
        bool opportunityExists,
        uint256 bestDexFrom,
        uint256 bestDexTo,
        uint256 expectedProfit
    ) {
        uint256 maxProfit = 0;
        
        for (uint256 i = 0; i < dexCount; i++) {
            for (uint256 j = 0; j < dexCount; j++) {
                if (i != j && dexes[i].active && dexes[j].active) {
                    // Simulate arbitrage calculation
                    address[] memory pathBuy = new address[](2);
                    pathBuy[0] = _tokenA;
                    pathBuy[1] = _tokenB;
                    
                    uint256[] memory amountsFrom = _getAmountsOut(dexes[i].router, amount, pathBuy);
                    if (amountsFrom.length == 0) continue;
                    
                    address[] memory pathSell = new address[](2);
                    pathSell[0] = _tokenB;
                    pathSell[1] = _tokenA;
                    
                    uint256[] memory amountsTo = _getAmountsOut(dexes[j].router, amountsFrom[amountsFrom.length - 1], pathSell);
                    if (amountsTo.length == 0) continue;
                    
                    uint256 finalAmount = amountsTo[amountsTo.length - 1];
                    if (finalAmount > amount) {
                        uint256 profit = finalAmount - amount;
                        if (profit > maxProfit) {
                            maxProfit = profit;
                            bestDexFrom = i;
                            bestDexTo = j;
                        }
                    }
                }
            }
        }
        
        opportunityExists = maxProfit >= (amount * minProfitBasisPoints) / 10000;
        expectedProfit = maxProfit;
    }
}