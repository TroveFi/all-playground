// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./BaseStrategy.sol";

// Flash loan provider interfaces
interface IFlashLoanProvider {
    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external;

    function getFlashLoanPremium() external view returns (uint256);
    function getAvailableLiquidity(address asset) external view returns (uint256);
}

// Multi-DEX interfaces for arbitrage
interface IDEXAggregator {
    struct SwapParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 amountOutMin;
        address[] exchanges;
        bytes[] swapData;
    }

    function getAmountOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address exchange
    ) external view returns (uint256 amountOut);

    function executeSwap(SwapParams calldata params) external returns (uint256 amountOut);
    
    function findBestPath(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (
        address bestExchange,
        uint256 bestAmountOut,
        bytes memory swapData
    );
}

// Liquidation interface
interface ILiquidationEngine {
    struct LiquidationData {
        address protocol;
        address borrower;
        address collateralAsset;
        address debtAsset;
        uint256 collateralAmount;
        uint256 debtAmount;
        uint256 liquidationThreshold;
        uint256 healthFactor;
        uint256 liquidationBonus;
    }

    function getLiquidationOpportunities(
        address[] calldata protocols,
        uint256 minProfitThreshold
    ) external view returns (LiquidationData[] memory opportunities);

    function executeLiquidation(
        address protocol,
        address borrower,
        address collateralAsset,
        address debtAsset,
        uint256 debtToCover
    ) external returns (uint256 collateralReceived);
}

// Interest rate arbitrage interface
interface IInterestRateArbitrage {
    function getOptimalBorrowLendPair(
        address asset,
        uint256 amount
    ) external view returns (
        address borrowProtocol,
        address lendProtocol,
        uint256 borrowRate,
        uint256 lendRate,
        uint256 netAPY
    );

    function executeBorrowLendArbitrage(
        address asset,
        uint256 amount,
        address borrowProtocol,
        address lendProtocol
    ) external returns (uint256 profit);
}

/// @title FlowFlashLoanArbitrageStrategy - Zero-Capital Arbitrage Engine
/// @notice Advanced flash loan strategy for arbitrage, liquidations, and rate opportunities
contract FlowFlashLoanArbitrageStrategy is BaseStrategy, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Protocol addresses (you'll need real addresses)
    address public constant FLASH_LOAN_PROVIDER = address(0); // Flash loan provider on Flow
    address public constant DEX_AGGREGATOR = address(0); // DEX aggregator
    address public constant LIQUIDATION_ENGINE = address(0); // Liquidation engine
    address public constant INTEREST_RATE_ARB = address(0); // Interest rate arbitrage

    IFlashLoanProvider public immutable flashLoanProvider;
    IDEXAggregator public immutable dexAggregator;
    ILiquidationEngine public immutable liquidationEngine;
    IInterestRateArbitrage public immutable interestRateArb;

    // Arbitrage types
    enum ArbitrageType {
        DEX_ARBITRAGE,         // Price differences across DEXs
        LIQUIDATION_ARB,       // Profitable liquidations
        INTEREST_RATE_ARB,     // Borrow/lend rate differences
        TRIANGULAR_ARB,        // Multi-token arbitrage
        COLLATERAL_SWAP_ARB,   // Collateral optimization
        BASIS_ARB              // Spot/futures basis arbitrage
    }

    struct ArbitrageOpportunity {
        bytes32 opportunityId;
        ArbitrageType arbType;
        address[] assets;
        uint256[] amounts;
        uint256 expectedProfit;
        uint256 gasEstimate;
        uint256 flashLoanFee;
        uint256 confidence; // 0-10000
        uint256 timeWindow; // Valid until block
        bool executed;
        bytes strategyData;
    }

    struct FlashLoanData {
        ArbitrageType arbType;
        address[] assets;
        uint256[] amounts;
        uint256 expectedProfit;
        address initiator;
        bytes strategyData;
    }

    struct ArbitrageExecution {
        bytes32 opportunityId;
        uint256 timestamp;
        uint256 actualProfit;
        uint256 gasUsed;
        uint256 flashLoanFee;
        bool successful;
        string failureReason;
    }

    // Configuration
    struct ArbitrageConfig {
        uint256 minProfitThreshold; // Minimum profit to execute
        uint256 maxFlashLoanAmount; // Maximum flash loan size
        uint256 maxGasPrice; // Maximum gas price for execution
        uint256 slippageTolerance; // Maximum slippage tolerance
        uint256 confidenceThreshold; // Minimum confidence to execute
        bool enableAutoExecution; // Auto-execute profitable opportunities
        bool enableLiquidations; // Enable liquidation arbitrage
        bool enableInterestRateArb; // Enable interest rate arbitrage
        uint256 maxPositions; // Maximum concurrent positions
    }

    // State variables
    mapping(bytes32 => ArbitrageOpportunity) public opportunities;
    mapping(bytes32 => ArbitrageExecution) public executions;
    bytes32[] public activeOpportunities;
    bytes32[] public executionHistory;
    
    ArbitrageConfig public arbitrageConfig;
    
    // Performance tracking
    uint256 public totalArbitrageProfit;
    uint256 public totalFlashLoanFees;
    uint256 public totalGasSpent;
    uint256 public successfulArbitrages;
    uint256 public failedArbitrages;
    uint256 public totalOpportunitiesFound;
    
    // Risk management
    uint256 public maxLossPerTrade;
    uint256 public dailyLossLimit;
    uint256 public dailyLosses;
    uint256 public lastResetTime;
    
    // MEV protection
    mapping(address => bool) public authorizedCallers;
    uint256 public frontrunProtectionDelay;

    event ArbitrageOpportunityFound(
        bytes32 indexed opportunityId,
        ArbitrageType arbType,
        uint256 expectedProfit,
        uint256 confidence
    );
    
    event FlashLoanExecuted(
        bytes32 indexed opportunityId,
        address[] assets,
        uint256[] amounts,
        uint256 actualProfit
    );
    
    event ArbitrageCompleted(
        bytes32 indexed opportunityId,
        uint256 profit,
        uint256 gasUsed,
        bool successful
    );
    
    event LiquidationExecuted(
        address indexed protocol,
        address indexed borrower,
        uint256 collateralReceived,
        uint256 profit
    );

    constructor(
        address _asset,
        address _vault,
        string memory _name
    ) BaseStrategy(_asset, FLASH_LOAN_PROVIDER, _vault, _name) {
        flashLoanProvider = IFlashLoanProvider(FLASH_LOAN_PROVIDER);
        dexAggregator = IDEXAggregator(DEX_AGGREGATOR);
        liquidationEngine = ILiquidationEngine(LIQUIDATION_ENGINE);
        interestRateArb = IInterestRateArbitrage(INTEREST_RATE_ARB);
        
        // Initialize arbitrage configuration
        arbitrageConfig = ArbitrageConfig({
            minProfitThreshold: 10 * 10**6, // 10 USDC minimum
            maxFlashLoanAmount: 1000000 * 10**6, // 1M USDC max
            maxGasPrice: 100 gwei,
            slippageTolerance: 300, // 3%
            confidenceThreshold: 8000, // 80%
            enableAutoExecution: true,
            enableLiquidations: true,
            enableInterestRateArb: true,
            maxPositions: 5
        });
        
        maxLossPerTrade = 1000 * 10**6; // 1000 USDC max loss per trade
        dailyLossLimit = 5000 * 10**6; // 5000 USDC daily loss limit
        frontrunProtectionDelay = 1; // 1 block delay
        
        authorizedCallers[msg.sender] = true;
    }

    function _executeStrategy(uint256 amount, bytes calldata data) internal override {
        // Decode arbitrage parameters
        (ArbitrageType arbType, bool forceExecution, uint256 minProfit) = data.length > 0 
            ? abi.decode(data, (ArbitrageType, bool, uint256))
            : (ArbitrageType.DEX_ARBITRAGE, false, arbitrageConfig.minProfitThreshold);

        // Scan for arbitrage opportunities
        _scanForOpportunities(amount, arbType, minProfit);
        
        // Execute profitable opportunities
        if (arbitrageConfig.enableAutoExecution || forceExecution) {
            _executeArbitrageOpportunities();
        }
    }

    function _scanForOpportunities(uint256 amount, ArbitrageType arbType, uint256 minProfit) internal {
        if (arbType == ArbitrageType.DEX_ARBITRAGE) {
            _scanDEXArbitrage(amount, minProfit);
        } else if (arbType == ArbitrageType.LIQUIDATION_ARB && arbitrageConfig.enableLiquidations) {
            _scanLiquidationOpportunities(minProfit);
        } else if (arbType == ArbitrageType.INTEREST_RATE_ARB && arbitrageConfig.enableInterestRateArb) {
            _scanInterestRateOpportunities(amount, minProfit);
        } else if (arbType == ArbitrageType.TRIANGULAR_ARB) {
            _scanTriangularArbitrage(amount, minProfit);
        }
    }

    function _scanDEXArbitrage(uint256 amount, uint256 minProfit) internal {
        // Scan for price differences across DEXs
        address[] memory tokens = new address[](3);
        tokens[0] = address(assetToken);
        tokens[1] = address(0); // WETH
        tokens[2] = address(0); // FLOW
        
        for (uint256 i = 0; i < tokens.length; i++) {
            for (uint256 j = 0; j < tokens.length; j++) {
                if (i != j && tokens[i] != address(0) && tokens[j] != address(0)) {
                    _checkDEXPriceDifference(tokens[i], tokens[j], amount, minProfit);
                }
            }
        }
    }

    function _checkDEXPriceDifference(
        address tokenIn,
        address tokenOut,
        uint256 amount,
        uint256 minProfit
    ) internal {
        // Get prices from different DEXs
        address[] memory exchanges = new address[](3);
        exchanges[0] = address(0); // IncrementFi
        exchanges[1] = address(0); // BloctoSwap
        exchanges[2] = address(0); // PunchSwap
        
        uint256 bestBuyPrice = 0;
        uint256 bestSellPrice = 0;
        address bestBuyExchange;
        address bestSellExchange;
        
        for (uint256 i = 0; i < exchanges.length; i++) {
            if (exchanges[i] == address(0)) continue;
            
            try dexAggregator.getAmountOut(tokenIn, tokenOut, amount, exchanges[i]) returns (uint256 amountOut) {
                if (amountOut > bestBuyPrice) {
                    bestBuyPrice = amountOut;
                    bestBuyExchange = exchanges[i];
                }
            } catch {
                // Price query failed
            }
            
            try dexAggregator.getAmountOut(tokenOut, tokenIn, bestBuyPrice, exchanges[i]) returns (uint256 amountBack) {
                if (amountBack > bestSellPrice) {
                    bestSellPrice = amountBack;
                    bestSellExchange = exchanges[i];
                }
            } catch {
                // Price query failed
            }
        }
        
        // Calculate profit
        if (bestSellPrice > amount) {
            uint256 grossProfit = bestSellPrice - amount;
            uint256 flashLoanFee = _calculateFlashLoanFee(amount);
            
            if (grossProfit > flashLoanFee + minProfit) {
                uint256 netProfit = grossProfit - flashLoanFee;
                _createArbitrageOpportunity(
                    ArbitrageType.DEX_ARBITRAGE,
                    tokenIn,
                    tokenOut,
                    amount,
                    netProfit,
                    bestBuyExchange,
                    bestSellExchange
                );
            }
        }
    }

    function _scanLiquidationOpportunities(uint256 minProfit) internal {
        if (!arbitrageConfig.enableLiquidations) return;
        
        address[] memory protocols = new address[](3);
        protocols[0] = address(0); // More.Markets
        protocols[1] = address(0); // Sturdy.Finance
        protocols[2] = address(0); // Other lending protocol
        
        try liquidationEngine.getLiquidationOpportunities(protocols, minProfit) returns (
            ILiquidationEngine.LiquidationData[] memory liquidations
        ) {
            for (uint256 i = 0; i < liquidations.length; i++) {
                ILiquidationEngine.LiquidationData memory liq = liquidations[i];
                
                uint256 profit = _calculateLiquidationProfit(liq);
                if (profit >= minProfit) {
                    _createLiquidationOpportunity(liq, profit);
                }
            }
        } catch {
            // Liquidation scan failed
        }
    }

    function _scanInterestRateOpportunities(uint256 amount, uint256 minProfit) internal {
        if (!arbitrageConfig.enableInterestRateArb) return;
        
        try interestRateArb.getOptimalBorrowLendPair(address(assetToken), amount) returns (
            address borrowProtocol,
            address lendProtocol,
            uint256 borrowRate,
            uint256 lendRate,
            uint256 netAPY
        ) {
            if (netAPY > 500) { // 5% minimum net APY
                uint256 dailyProfit = (amount * netAPY) / (365 * 10000);
                
                if (dailyProfit >= minProfit) {
                    _createInterestRateArbOpportunity(
                        amount,
                        borrowProtocol,
                        lendProtocol,
                        netAPY,
                        dailyProfit
                    );
                }
            }
        } catch {
            // Interest rate arbitrage scan failed
        }
    }

    function _scanTriangularArbitrage(uint256 amount, uint256 minProfit) internal {
        // Triangular arbitrage: A -> B -> C -> A
        address tokenA = address(assetToken);
        address tokenB = address(0); // WETH
        address tokenC = address(0); // FLOW
        
        if (tokenB == address(0) || tokenC == address(0)) return;
        
        // Check A -> B -> C -> A path
        try dexAggregator.getAmountOut(tokenA, tokenB, amount, address(0)) returns (uint256 amountB) {
            if (amountB > 0) {
                try dexAggregator.getAmountOut(tokenB, tokenC, amountB, address(0)) returns (uint256 amountC) {
                    if (amountC > 0) {
                        try dexAggregator.getAmountOut(tokenC, tokenA, amountC, address(0)) returns (uint256 finalAmount) {
                            if (finalAmount > amount) {
                                uint256 profit = finalAmount - amount;
                                uint256 flashLoanFee = _calculateFlashLoanFee(amount);
                                
                                if (profit > flashLoanFee + minProfit) {
                                    _createTriangularArbOpportunity(
                                        tokenA, tokenB, tokenC,
                                        amount, profit - flashLoanFee
                                    );
                                }
                            }
                        } catch {}
                    }
                } catch {}
            }
        } catch {}
    }

    function _createArbitrageOpportunity(
        ArbitrageType arbType,
        address tokenIn,
        address tokenOut,
        uint256 amount,
        uint256 expectedProfit,
        address buyExchange,
        address sellExchange
    ) internal {
        bytes32 opportunityId = keccak256(abi.encodePacked(
            arbType,
            tokenIn,
            tokenOut,
            amount,
            block.timestamp
        ));
        
        address[] memory assets = new address[](2);
        assets[0] = tokenIn;
        assets[1] = tokenOut;
        
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        
        bytes memory strategyData = abi.encode(buyExchange, sellExchange);
        
        opportunities[opportunityId] = ArbitrageOpportunity({
            opportunityId: opportunityId,
            arbType: arbType,
            assets: assets,
            amounts: amounts,
            expectedProfit: expectedProfit,
            gasEstimate: 500000, // Estimated gas
            flashLoanFee: _calculateFlashLoanFee(amount),
            confidence: 8500, // 85% confidence
            timeWindow: block.number + 5, // Valid for 5 blocks
            executed: false,
            strategyData: strategyData
        });
        
        activeOpportunities.push(opportunityId);
        totalOpportunitiesFound++;
        
        emit ArbitrageOpportunityFound(opportunityId, arbType, expectedProfit, 8500);
    }

    function _createLiquidationOpportunity(
        ILiquidationEngine.LiquidationData memory liq,
        uint256 expectedProfit
    ) internal {
        bytes32 opportunityId = keccak256(abi.encodePacked(
            "LIQUIDATION",
            liq.protocol,
            liq.borrower,
            block.timestamp
        ));
        
        address[] memory assets = new address[](2);
        assets[0] = liq.debtAsset;
        assets[1] = liq.collateralAsset;
        
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = liq.debtAmount;
        
        bytes memory strategyData = abi.encode(liq);
        
        opportunities[opportunityId] = ArbitrageOpportunity({
            opportunityId: opportunityId,
            arbType: ArbitrageType.LIQUIDATION_ARB,
            assets: assets,
            amounts: amounts,
            expectedProfit: expectedProfit,
            gasEstimate: 600000,
            flashLoanFee: _calculateFlashLoanFee(liq.debtAmount),
            confidence: 9000, // 90% confidence for liquidations
            timeWindow: block.number + 3, // Urgent - valid for 3 blocks
            executed: false,
            strategyData: strategyData
        });
        
        activeOpportunities.push(opportunityId);
        totalOpportunitiesFound++;
        
        emit ArbitrageOpportunityFound(opportunityId, ArbitrageType.LIQUIDATION_ARB, expectedProfit, 9000);
    }

    function _createInterestRateArbOpportunity(
        uint256 amount,
        address borrowProtocol,
        address lendProtocol,
        uint256 netAPY,
        uint256 dailyProfit
    ) internal {
        bytes32 opportunityId = keccak256(abi.encodePacked(
            "INTEREST_RATE_ARB",
            borrowProtocol,
            lendProtocol,
            block.timestamp
        ));
        
        address[] memory assets = new address[](1);
        assets[0] = address(assetToken);
        
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        
        bytes memory strategyData = abi.encode(borrowProtocol, lendProtocol, netAPY);
        
        opportunities[opportunityId] = ArbitrageOpportunity({
            opportunityId: opportunityId,
            arbType: ArbitrageType.INTEREST_RATE_ARB,
            assets: assets,
            amounts: amounts,
            expectedProfit: dailyProfit,
            gasEstimate: 400000,
            flashLoanFee: _calculateFlashLoanFee(amount),
            confidence: 7500, // 75% confidence
            timeWindow: block.number + 100, // Valid for longer
            executed: false,
            strategyData: strategyData
        });
        
        activeOpportunities.push(opportunityId);
        totalOpportunitiesFound++;
        
        emit ArbitrageOpportunityFound(opportunityId, ArbitrageType.INTEREST_RATE_ARB, dailyProfit, 7500);
    }

    function _createTriangularArbOpportunity(
        address tokenA,
        address tokenB,
        address tokenC,
        uint256 amount,
        uint256 expectedProfit
    ) internal {
        bytes32 opportunityId = keccak256(abi.encodePacked(
            "TRIANGULAR_ARB",
            tokenA,
            tokenB,
            tokenC,
            block.timestamp
        ));
        
        address[] memory assets = new address[](3);
        assets[0] = tokenA;
        assets[1] = tokenB;
        assets[2] = tokenC;
        
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        
        bytes memory strategyData = abi.encode(tokenA, tokenB, tokenC);
        
        opportunities[opportunityId] = ArbitrageOpportunity({
            opportunityId: opportunityId,
            arbType: ArbitrageType.TRIANGULAR_ARB,
            assets: assets,
            amounts: amounts,
            expectedProfit: expectedProfit,
            gasEstimate: 700000,
            flashLoanFee: _calculateFlashLoanFee(amount),
            confidence: 8000, // 80% confidence
            timeWindow: block.number + 3, // Valid for 3 blocks
            executed: false,
            strategyData: strategyData
        });
        
        activeOpportunities.push(opportunityId);
        totalOpportunitiesFound++;
        
        emit ArbitrageOpportunityFound(opportunityId, ArbitrageType.TRIANGULAR_ARB, expectedProfit, 8000);
    }

    function _executeArbitrageOpportunities() internal {
        for (uint256 i = 0; i < activeOpportunities.length; i++) {
            bytes32 opportunityId = activeOpportunities[i];
            ArbitrageOpportunity storage opportunity = opportunities[opportunityId];
            
            if (!opportunity.executed && 
                block.number <= opportunity.timeWindow &&
                opportunity.confidence >= arbitrageConfig.confidenceThreshold &&
                opportunity.expectedProfit >= arbitrageConfig.minProfitThreshold) {
                
                _executeFlashLoanArbitrage(opportunityId);
            }
        }
        
        _cleanupExpiredOpportunities();
    }

    function _executeFlashLoanArbitrage(bytes32 opportunityId) internal {
        ArbitrageOpportunity storage opportunity = opportunities[opportunityId];
        
        if (opportunity.executed) return;
        
        // Risk management checks
        if (!_riskManagementCheck(opportunity.amounts[0])) return;
        
        // Prepare flash loan data
        FlashLoanData memory flashLoanData = FlashLoanData({
            arbType: opportunity.arbType,
            assets: opportunity.assets,
            amounts: opportunity.amounts,
            expectedProfit: opportunity.expectedProfit,
            initiator: address(this),
            strategyData: opportunity.strategyData
        });
        
        bytes memory params = abi.encode(opportunityId, flashLoanData);
        
        // Execute flash loan
        uint256[] memory modes = new uint256[](opportunity.assets.length);
        // Mode 0 = no debt, just borrow and repay in same transaction
        
        try flashLoanProvider.flashLoan(
            address(this),
            opportunity.assets,
            opportunity.amounts,
            modes,
            address(this),
            params,
            0 // No referral
        ) {
            opportunity.executed = true;
            successfulArbitrages++;
            
            emit FlashLoanExecuted(
                opportunityId,
                opportunity.assets,
                opportunity.amounts,
                opportunity.expectedProfit
            );
        } catch Error(string memory reason) {
            failedArbitrages++;
            
            executions[opportunityId] = ArbitrageExecution({
                opportunityId: opportunityId,
                timestamp: block.timestamp,
                actualProfit: 0,
                gasUsed: gasleft(),
                flashLoanFee: opportunity.flashLoanFee,
                successful: false,
                failureReason: reason
            });
        }
    }

    // Flash loan callback
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        require(msg.sender == address(flashLoanProvider), "Invalid caller");
        require(initiator == address(this), "Invalid initiator");
        
        (bytes32 opportunityId, FlashLoanData memory flashLoanData) = abi.decode(params, (bytes32, FlashLoanData));
        
        uint256 actualProfit = 0;
        bool success = false;
        
        // Execute the arbitrage strategy
        if (flashLoanData.arbType == ArbitrageType.DEX_ARBITRAGE) {
            (success, actualProfit) = _executeDEXArbitrage(flashLoanData);
        } else if (flashLoanData.arbType == ArbitrageType.LIQUIDATION_ARB) {
            (success, actualProfit) = _executeLiquidationArbitrage(flashLoanData);
        } else if (flashLoanData.arbType == ArbitrageType.TRIANGULAR_ARB) {
            (success, actualProfit) = _executeTriangularArbitrage(flashLoanData);
        }
        
        // Record execution
        executions[opportunityId] = ArbitrageExecution({
            opportunityId: opportunityId,
            timestamp: block.timestamp,
            actualProfit: actualProfit,
            gasUsed: gasleft(),
            flashLoanFee: premiums[0],
            successful: success,
            failureReason: success ? "" : "Execution failed"
        });
        
        if (success) {
            totalArbitrageProfit += actualProfit;
            totalFlashLoanFees += premiums[0];
        } else {
            dailyLosses += amounts[0];
        }
        
        executionHistory.push(opportunityId);
        
        emit ArbitrageCompleted(opportunityId, actualProfit, gasleft(), success);
        
        // Approve repayment
        for (uint256 i = 0; i < assets.length; i++) {
            uint256 amountOwing = amounts[i] + premiums[i];
            IERC20(assets[i]).approve(address(flashLoanProvider), amountOwing);
        }
        
        return true;
    }

    function _executeDEXArbitrage(FlashLoanData memory flashLoanData) internal returns (bool success, uint256 profit) {
        (address buyExchange, address sellExchange) = abi.decode(flashLoanData.strategyData, (address, address));
        
        address tokenIn = flashLoanData.assets[0];
        address tokenOut = flashLoanData.assets[1];
        uint256 amount = flashLoanData.amounts[0];
        
        // Execute buy on first exchange
        IDEXAggregator.SwapParams memory buyParams = IDEXAggregator.SwapParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amount,
            amountOutMin: 0,
            exchanges: new address[](1),
            swapData: new bytes[](1)
        });
        buyParams.exchanges[0] = buyExchange;
        
        try dexAggregator.executeSwap(buyParams) returns (uint256 tokenOutAmount) {
            // Execute sell on second exchange
            IDEXAggregator.SwapParams memory sellParams = IDEXAggregator.SwapParams({
                tokenIn: tokenOut,
                tokenOut: tokenIn,
                amountIn: tokenOutAmount,
                amountOutMin: amount, // Must get back at least original amount
                exchanges: new address[](1),
                swapData: new bytes[](1)
            });
            sellParams.exchanges[0] = sellExchange;
            
            try dexAggregator.executeSwap(sellParams) returns (uint256 finalAmount) {
                if (finalAmount > amount) {
                    profit = finalAmount - amount;
                    success = true;
                }
            } catch {
                success = false;
            }
        } catch {
            success = false;
        }
    }

    function _executeLiquidationArbitrage(FlashLoanData memory flashLoanData) internal returns (bool success, uint256 profit) {
        ILiquidationEngine.LiquidationData memory liq = abi.decode(flashLoanData.strategyData, (ILiquidationEngine.LiquidationData));
        
        try liquidationEngine.executeLiquidation(
            liq.protocol,
            liq.borrower,
            liq.collateralAsset,
            liq.debtAsset,
            flashLoanData.amounts[0]
        ) returns (uint256 collateralReceived) {
            
            // Sell collateral for debt asset
            if (liq.collateralAsset != liq.debtAsset) {
                (address bestExchange, uint256 amountOut,) = dexAggregator.findBestPath(
                    liq.collateralAsset,
                    liq.debtAsset,
                    collateralReceived
                );
                
                IDEXAggregator.SwapParams memory swapParams = IDEXAggregator.SwapParams({
                    tokenIn: liq.collateralAsset,
                    tokenOut: liq.debtAsset,
                    amountIn: collateralReceived,
                    amountOutMin: flashLoanData.amounts[0],
                    exchanges: new address[](1),
                    swapData: new bytes[](1)
                });
                swapParams.exchanges[0] = bestExchange;
                
                try dexAggregator.executeSwap(swapParams) returns (uint256 finalAmount) {
                    if (finalAmount > flashLoanData.amounts[0]) {
                        profit = finalAmount - flashLoanData.amounts[0];
                        success = true;
                    }
                } catch {
                    success = false;
                }
            } else {
                if (collateralReceived > flashLoanData.amounts[0]) {
                    profit = collateralReceived - flashLoanData.amounts[0];
                    success = true;
                }
            }
            
            emit LiquidationExecuted(liq.protocol, liq.borrower, collateralReceived, profit);
        } catch {
            success = false;
        }
    }

    function _executeTriangularArbitrage(FlashLoanData memory flashLoanData) internal returns (bool success, uint256 profit) {
        (address tokenA, address tokenB, address tokenC) = abi.decode(flashLoanData.strategyData, (address, address, address));
        
        uint256 amountA = flashLoanData.amounts[0];
        
        // A -> B
        (address exchangeAB, uint256 amountB,) = dexAggregator.findBestPath(tokenA, tokenB, amountA);
        if (exchangeAB == address(0)) return (false, 0);
        
        IDEXAggregator.SwapParams memory swapAB = IDEXAggregator.SwapParams({
            tokenIn: tokenA,
            tokenOut: tokenB,
            amountIn: amountA,
            amountOutMin: 0,
            exchanges: new address[](1),
            swapData: new bytes[](1)
        });
        swapAB.exchanges[0] = exchangeAB;
        
        try dexAggregator.executeSwap(swapAB) returns (uint256 actualAmountB) {
            // B -> C
            (address exchangeBC, uint256 amountC,) = dexAggregator.findBestPath(tokenB, tokenC, actualAmountB);
            if (exchangeBC == address(0)) return (false, 0);
            
            IDEXAggregator.SwapParams memory swapBC = IDEXAggregator.SwapParams({
                tokenIn: tokenB,
                tokenOut: tokenC,
                amountIn: actualAmountB,
                amountOutMin: 0,
                exchanges: new address[](1),
                swapData: new bytes[](1)
            });
            swapBC.exchanges[0] = exchangeBC;
            
            try dexAggregator.executeSwap(swapBC) returns (uint256 actualAmountC) {
                // C -> A
                (address exchangeCA, uint256 finalAmountA,) = dexAggregator.findBestPath(tokenC, tokenA, actualAmountC);
                if (exchangeCA == address(0)) return (false, 0);
                
                IDEXAggregator.SwapParams memory swapCA = IDEXAggregator.SwapParams({
                    tokenIn: tokenC,
                    tokenOut: tokenA,
                    amountIn: actualAmountC,
                    amountOutMin: amountA,
                    exchanges: new address[](1),
                    swapData: new bytes[](1)
                });
                swapCA.exchanges[0] = exchangeCA;
                
                try dexAggregator.executeSwap(swapCA) returns (uint256 actualFinalAmountA) {
                    if (actualFinalAmountA > amountA) {
                        profit = actualFinalAmountA - amountA;
                        success = true;
                    }
                } catch {
                    success = false;
                }
            } catch {
                success = false;
            }
        } catch {
            success = false;
        }
    }

    function _calculateFlashLoanFee(uint256 amount) internal view returns (uint256) {
        uint256 feeBps = flashLoanProvider.getFlashLoanPremium();
        return (amount * feeBps) / 10000;
    }

    function _calculateLiquidationProfit(ILiquidationEngine.LiquidationData memory liq) internal pure returns (uint256) {
        // Simplified calculation - actual implementation would be more complex
        return (liq.collateralAmount * liq.liquidationBonus) / 10000;
    }

    function _riskManagementCheck(uint256 amount) internal returns (bool) {
        // Reset daily limits if needed
        if (block.timestamp > lastResetTime + 1 days) {
            dailyLosses = 0;
            lastResetTime = block.timestamp;
        }
        
        // Check limits
        if (amount > maxLossPerTrade) return false;
        if (dailyLosses + amount > dailyLossLimit) return false;
        if (tx.gasprice > arbitrageConfig.maxGasPrice) return false;
        
        return true;
    }

    function _cleanupExpiredOpportunities() internal {
        uint256 activeCount = 0;
        
        // Count non-expired opportunities
        for (uint256 i = 0; i < activeOpportunities.length; i++) {
            bytes32 opportunityId = activeOpportunities[i];
            ArbitrageOpportunity memory opportunity = opportunities[opportunityId];
            
            if (!opportunity.executed && block.number <= opportunity.timeWindow) {
                activeCount++;
            }
        }
        
        // Create new array with only active opportunities
        bytes32[] memory newActiveOpportunities = new bytes32[](activeCount);
        uint256 index = 0;
        
        for (uint256 i = 0; i < activeOpportunities.length; i++) {
            bytes32 opportunityId = activeOpportunities[i];
            ArbitrageOpportunity memory opportunity = opportunities[opportunityId];
            
            if (!opportunity.executed && block.number <= opportunity.timeWindow) {
                newActiveOpportunities[index] = opportunityId;
                index++;
            }
        }
        
        activeOpportunities = newActiveOpportunities;
    }

    function _harvestRewards(bytes calldata) internal override {
        // Continuously scan for new arbitrage opportunities
        _scanForOpportunities(
            arbitrageConfig.maxFlashLoanAmount,
            ArbitrageType.DEX_ARBITRAGE,
            arbitrageConfig.minProfitThreshold
        );
        
        // Execute any profitable opportunities found
        if (arbitrageConfig.enableAutoExecution) {
            _executeArbitrageOpportunities();
        }
    }

    function _emergencyWithdraw(bytes calldata) internal override returns (uint256 recovered) {
        // Flash loan arbitrage doesn't hold funds long-term
        return assetToken.balanceOf(address(this));
    }

    function getBalance() external view override returns (uint256) {
        return assetToken.balanceOf(address(this)) + totalArbitrageProfit;
    }

    // Manual execution functions
    function manualExecuteOpportunity(bytes32 opportunityId) external onlyRole(HARVESTER_ROLE) {
        require(!opportunities[opportunityId].executed, "Already executed");
        require(block.number <= opportunities[opportunityId].timeWindow, "Opportunity expired");
        
        _executeFlashLoanArbitrage(opportunityId);
    }

    function manualScanOpportunities(ArbitrageType arbType, uint256 amount) external onlyRole(HARVESTER_ROLE) {
        _scanForOpportunities(amount, arbType, arbitrageConfig.minProfitThreshold);
    }

    // Admin functions
    function updateArbitrageConfig(
        uint256 minProfit,
        uint256 maxFlashLoan,
        uint256 maxGasPrice,
        uint256 slippage,
        uint256 confidence,
        bool autoExecution
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        arbitrageConfig.minProfitThreshold = minProfit;
        arbitrageConfig.maxFlashLoanAmount = maxFlashLoan;
        arbitrageConfig.maxGasPrice = maxGasPrice;
        arbitrageConfig.slippageTolerance = slippage;
        arbitrageConfig.confidenceThreshold = confidence;
        arbitrageConfig.enableAutoExecution = autoExecution;
    }

    function setRiskLimits(uint256 maxLossPerTrade_, uint256 dailyLossLimit_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxLossPerTrade = maxLossPerTrade_;
        dailyLossLimit = dailyLossLimit_;
    }

    function addAuthorizedCaller(address caller) external onlyRole(DEFAULT_ADMIN_ROLE) {
        authorizedCallers[caller] = true;
    }

    function removeAuthorizedCaller(address caller) external onlyRole(DEFAULT_ADMIN_ROLE) {
        authorizedCallers[caller] = false;
    }

    // View functions
    function getArbitragePerformance() external view returns (
        uint256 totalProfit,
        uint256 totalFees,
        uint256 totalGas,
        uint256 successfulTrades,
        uint256 failedTrades,
        uint256 opportunitiesFound
    ) {
        totalProfit = totalArbitrageProfit;
        totalFees = totalFlashLoanFees;
        totalGas = totalGasSpent;
        successfulTrades = successfulArbitrages;
        failedTrades = failedArbitrages;
        opportunitiesFound = totalOpportunitiesFound;
    }

    function getActiveOpportunities() external view returns (ArbitrageOpportunity[] memory) {
        ArbitrageOpportunity[] memory activeOpps = new ArbitrageOpportunity[](activeOpportunities.length);
        
        for (uint256 i = 0; i < activeOpportunities.length; i++) {
            activeOpps[i] = opportunities[activeOpportunities[i]];
        }
        
        return activeOpps;
    }

    function getExecutionHistory(uint256 limit) external view returns (ArbitrageExecution[] memory) {
        uint256 length = executionHistory.length > limit ? limit : executionHistory.length;
        ArbitrageExecution[] memory execHist = new ArbitrageExecution[](length);
        
        for (uint256 i = 0; i < length; i++) {
            uint256 index = executionHistory.length - 1 - i; // Most recent first
            execHist[i] = executions[executionHistory[index]];
        }
        
        return execHist;
    }

    function getOpportunity(bytes32 opportunityId) external view returns (ArbitrageOpportunity memory) {
        return opportunities[opportunityId];
    }

    function getExecution(bytes32 opportunityId) external view returns (ArbitrageExecution memory) {
        return executions[opportunityId];
    }

    // Receive ETH for gas refunds
    receive() external payable {}
}