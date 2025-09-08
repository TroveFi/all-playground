// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import "./ArbitrageTypes.sol";

interface IArbitrageDEXManager {
    function swapOnPunchSwap(address tokenIn, address tokenOut, uint256 amountIn) external returns (bool success);
    function swapOnIncrement(address tokenIn, address tokenOut, uint256 amountIn) external returns (bool success);
    function getActiveDEXs() external view returns (address[] memory);
}

contract ArbitrageCore is AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant STRATEGY_ROLE = keccak256("STRATEGY_ROLE");

    IArbitrageDEXManager public dexManager;
    
    address public constant PUNCH_SWAP_V2_ROUTER = 0xf45AFe28fd5519d5f8C1d4787a4D5f724C0eFa4d;
    address public constant INCREMENT_ROUTER = 0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590;

    // Performance tracking
    uint256 public totalArbitrageAttempts;
    uint256 public successfulArbitrages;
    uint256 public failedArbitrages;

    event ArbitrageExecuted(
        ArbitrageTypes.ArbitrageType arbType,
        address tokenA, 
        address tokenB, 
        uint256 profit, 
        uint256 gasUsed,
        address dexA,
        address dexB
    );

    event TriangularArbitrageExecuted(
        address tokenA,
        address tokenB, 
        address tokenC,
        uint256 profit,
        address[] dexPath
    );

    constructor(address _dexManager) {
        require(_dexManager != address(0), "Invalid DEX manager");
        
        dexManager = IArbitrageDEXManager(_dexManager);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    modifier onlyStrategy() {
        require(hasRole(STRATEGY_ROLE, msg.sender), "Only strategy can call");
        _;
    }

    function executeArbitrageOpportunity(
        ArbitrageTypes.ArbitrageOpportunity memory opportunity,
        IERC20 baseToken
    ) external onlyStrategy returns (uint256 profit) {
        totalArbitrageAttempts++;
        uint256 balanceBefore = baseToken.balanceOf(msg.sender);
        
        try this.performArbitrageTrade(opportunity) {
            uint256 balanceAfter = baseToken.balanceOf(msg.sender);
            profit = balanceAfter > balanceBefore ? balanceAfter - balanceBefore : 0;
            
            if (profit > 0) {
                successfulArbitrages++;
                
                emit ArbitrageExecuted(
                    ArbitrageTypes.ArbitrageType.SIMPLE_DUAL_DEX,
                    opportunity.tokenA,
                    opportunity.tokenB,
                    profit,
                    opportunity.gasEstimate,
                    opportunity.dexA,
                    opportunity.dexB
                );
            }
        } catch {
            failedArbitrages++;
        }
        
        return profit;
    }

    function performArbitrageTrade(ArbitrageTypes.ArbitrageOpportunity memory opportunity) external {
        require(msg.sender == address(this), "Only self");
        
        // Step 1: Buy tokenB with tokenA on cheaper DEX
        uint256 inputAmount = Math.min(opportunity.inputAmount, IERC20(opportunity.tokenA).balanceOf(address(this)));
        
        if (opportunity.dexA == PUNCH_SWAP_V2_ROUTER) {
            dexManager.swapOnPunchSwap(opportunity.tokenA, opportunity.tokenB, inputAmount);
        } else {
            dexManager.swapOnIncrement(opportunity.tokenA, opportunity.tokenB, inputAmount);
        }
        
        // Step 2: Sell tokenB for tokenA on more expensive DEX
        uint256 tokenBBalance = IERC20(opportunity.tokenB).balanceOf(address(this));
        
        if (opportunity.dexB == PUNCH_SWAP_V2_ROUTER) {
            dexManager.swapOnPunchSwap(opportunity.tokenB, opportunity.tokenA, tokenBBalance);
        } else {
            dexManager.swapOnIncrement(opportunity.tokenB, opportunity.tokenA, tokenBBalance);
        }
    }

    function executeTriangularOpportunity(
        ArbitrageTypes.TriangularArbitrage memory opportunity
    ) external onlyStrategy returns (uint256 profit) {
        uint256 balanceBefore = IERC20(opportunity.tokenA).balanceOf(address(this));
        
        try this.performTriangularTrade(opportunity) {
            uint256 balanceAfter = IERC20(opportunity.tokenA).balanceOf(address(this));
            profit = balanceAfter > balanceBefore ? balanceAfter - balanceBefore : 0;
            
            if (profit > 0) {
                emit TriangularArbitrageExecuted(
                    opportunity.tokenA,
                    opportunity.tokenB,
                    opportunity.tokenC,
                    profit,
                    opportunity.dexPath
                );
            }
        } catch {
            // Triangular arbitrage failed
        }
        
        return profit;
    }

    function performTriangularTrade(ArbitrageTypes.TriangularArbitrage memory opportunity) external {
        require(msg.sender == address(this), "Only self");
        
        uint256 startAmount = Math.min(opportunity.minimumInput, IERC20(opportunity.tokenA).balanceOf(address(this)));
        
        // A -> B
        if (opportunity.dexPath[0] == PUNCH_SWAP_V2_ROUTER) {
            dexManager.swapOnPunchSwap(opportunity.tokenA, opportunity.tokenB, startAmount);
        } else {
            dexManager.swapOnIncrement(opportunity.tokenA, opportunity.tokenB, startAmount);
        }
        
        // B -> C
        uint256 tokenBBalance = IERC20(opportunity.tokenB).balanceOf(address(this));
        if (opportunity.dexPath[1] == PUNCH_SWAP_V2_ROUTER) {
            dexManager.swapOnPunchSwap(opportunity.tokenB, opportunity.tokenC, tokenBBalance);
        } else {
            dexManager.swapOnIncrement(opportunity.tokenB, opportunity.tokenC, tokenBBalance);
        }
        
        // C -> A
        uint256 tokenCBalance = IERC20(opportunity.tokenC).balanceOf(address(this));
        if (opportunity.dexPath[2] == PUNCH_SWAP_V2_ROUTER) {
            dexManager.swapOnPunchSwap(opportunity.tokenC, opportunity.tokenA, tokenCBalance);
        } else {
            dexManager.swapOnIncrement(opportunity.tokenC, opportunity.tokenA, tokenCBalance);
        }
    }

    function executeStFLOWArbitrageCycle(uint256 amount) external onlyStrategy returns (uint256 profit) {
        address WFLOW = 0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e;
        address STFLOW = 0x1b97100eA1D7126C4d60027e231EA4CB25314bdb;
        
        uint256 balanceBefore = IERC20(WFLOW).balanceOf(address(this));
        
        // FLOW -> stFLOW
        dexManager.swapOnPunchSwap(WFLOW, STFLOW, amount);
        
        // stFLOW -> FLOW (on different DEX)
        uint256 stFlowBalance = IERC20(STFLOW).balanceOf(address(this));
        dexManager.swapOnIncrement(STFLOW, WFLOW, stFlowBalance);
        
        uint256 balanceAfter = IERC20(WFLOW).balanceOf(address(this));
        profit = balanceAfter > balanceBefore ? balanceAfter - balanceBefore : 0;
        
        if (profit > 0) {
            emit ArbitrageExecuted(
                ArbitrageTypes.ArbitrageType.CROSS_ASSET_ARBITRAGE,
                WFLOW,
                STFLOW,
                profit,
                0,
                PUNCH_SWAP_V2_ROUTER,
                INCREMENT_ROUTER
            );
        }
    }

    function emergencyConvertToBase(address token, uint256 amount, address baseToken) 
        external 
        onlyStrategy 
        returns (uint256 converted) 
    {
        // Try PunchSwap first, then Increment
        dexManager.swapOnPunchSwap(token, baseToken, amount / 2);
        dexManager.swapOnIncrement(token, baseToken, amount / 2);
        
        converted = IERC20(baseToken).balanceOf(address(this));
    }

    function getPerformanceMetrics() external view returns (
        uint256 totalAttempts,
        uint256 successful,
        uint256 failed,
        uint256 successRate
    ) {
        uint256 rate = totalArbitrageAttempts > 0 ? 
            (successfulArbitrages * 10000) / totalArbitrageAttempts : 0;

        return (
            totalArbitrageAttempts,
            successfulArbitrages,
            failedArbitrages,
            rate
        );
    }
}