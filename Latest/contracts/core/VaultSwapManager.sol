// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IUniversalRouter {
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

interface IIncrementRouter {
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

interface ITradoRouter {
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

/// @title MultiDEXAggregator - Optimal routing across Flow EVM DEXs
/// @notice Finds best rates across KittyPunch, Increment, and Trado
contract MultiDEXAggregator is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");

    enum DEXType { KITTYPUNCH, INCREMENT, TRADO }

    struct DEXInfo {
        address router;
        DEXType dexType;
        bool active;
        uint256 gasEstimate;
        string name;
    }

    struct SwapQuote {
        address dex;
        DEXType dexType;
        uint256 amountOut;
        uint256 gasEstimate;
        uint256 netOutput; // amountOut adjusted for gas costs
        address[] path;
    }

    struct SwapParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
        uint16 slippageBps;
        uint32 deadline;
        bool useGasOptimization;
    }

    // DEX registry
    mapping(address => DEXInfo) public dexRegistry;
    address[] public activeDEXs;
    
    // Gas price oracle (simplified)
    uint256 public gasPrice = 1 gwei; // Update via oracle or admin
    
    // Events
    event DEXAdded(address indexed dex, DEXType dexType, string name);
    event DEXStatusUpdated(address indexed dex, bool active);
    event SwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address dex,
        string dexName,
        uint256 gasUsed
    );
    event BestQuoteFound(
        address indexed dex,
        uint256 amountOut,
        uint256 gasEstimate,
        uint256 netOutput
    );

    constructor(address _vault) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(VAULT_ROLE, _vault);
        
        // Initialize with known Flow EVM DEXs
        _addDEX(
            0xf45AFe28fd5519d5f8C1d4787a4D5f724C0eFa4d, // PunchSwapV2Router
            DEXType.KITTYPUNCH,
            "KittyPunch",
            150000
        );
        
        // Add other DEXs when addresses are available
        // _addDEX(INCREMENT_ROUTER, DEXType.INCREMENT, "Increment", 160000);
        // _addDEX(TRADO_ROUTER, DEXType.TRADO, "Trado", 140000);
    }

    /// @notice Add a new DEX to the aggregator
    function addDEX(
        address router,
        DEXType dexType,
        string calldata name,
        uint256 gasEstimate
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _addDEX(router, dexType, name, gasEstimate);
    }

    function _addDEX(
        address router,
        DEXType dexType,
        string memory name,
        uint256 gasEstimate
    ) internal {
        require(router != address(0), "Invalid router");
        
        dexRegistry[router] = DEXInfo({
            router: router,
            dexType: dexType,
            active: true,
            gasEstimate: gasEstimate,
            name: name
        });
        
        activeDEXs.push(router);
        emit DEXAdded(router, dexType, name);
    }

    /// @notice Get the best swap quote across all DEXs
    function getBestQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        bool useGasOptimization
    ) external view returns (SwapQuote memory bestQuote) {
        require(amountIn > 0, "Invalid amount");
        
        uint256 bestNetOutput = 0;
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        for (uint256 i = 0; i < activeDEXs.length; i++) {
            address dexRouter = activeDEXs[i];
            DEXInfo memory dexInfo = dexRegistry[dexRouter];
            
            if (!dexInfo.active) continue;

            try IUniversalRouter(dexRouter).getAmountsOut(amountIn, path) 
                returns (uint256[] memory amounts) {
                
                uint256 amountOut = amounts[1];
                uint256 netOutput = amountOut;
                
                if (useGasOptimization) {
                    // Subtract estimated gas cost in token terms
                    uint256 gasCost = dexInfo.gasEstimate * gasPrice;
                    // Convert gas cost to tokenOut terms (simplified)
                    // In practice, you'd need a price oracle
                    netOutput = amountOut > gasCost ? amountOut - gasCost : 0;
                }
                
                if (netOutput > bestNetOutput) {
                    bestNetOutput = netOutput;
                    bestQuote = SwapQuote({
                        dex: dexRouter,
                        dexType: dexInfo.dexType,
                        amountOut: amountOut,
                        gasEstimate: dexInfo.gasEstimate,
                        netOutput: netOutput,
                        path: path
                    });
                }
            } catch {
                // DEX doesn't support this pair, continue
                continue;
            }
        }
        
        require(bestQuote.dex != address(0), "No viable route found");
    }

    /// @notice Execute optimal swap across multiple DEXs
    function executeOptimalSwap(SwapParams calldata params)
        external
        onlyRole(AGENT_ROLE)
        nonReentrant
        returns (uint256 amountOut)
    {
        SwapQuote memory bestQuote = this.getBestQuote(
            params.tokenIn,
            params.tokenOut,
            params.amountIn,
            params.useGasOptimization
        );

        require(bestQuote.amountOut >= params.minAmountOut, "Insufficient output");

        uint256 gasStart = gasleft();
        
        IERC20 tokenIn = IERC20(params.tokenIn);
        IERC20 tokenOut = IERC20(params.tokenOut);
        
        // Transfer tokens from vault
        tokenIn.safeTransferFrom(msg.sender, address(this), params.amountIn);
        
        // Approve the selected DEX
        tokenIn.forceApprove(bestQuote.dex, params.amountIn);
        
        // Execute swap on best DEX
        uint256[] memory amounts;
        if (bestQuote.dexType == DEXType.KITTYPUNCH) {
            amounts = IUniversalRouter(bestQuote.dex).swapExactTokensForTokens(
                params.amountIn,
                params.minAmountOut,
                bestQuote.path,
                msg.sender, // Send back to vault
                block.timestamp + params.deadline
            );
        }
        // Add other DEX types as needed
        
        amountOut = amounts[1];
        uint256 gasUsed = gasStart - gasleft();
        
        emit SwapExecuted(
            params.tokenIn,
            params.tokenOut,
            params.amountIn,
            amountOut,
            bestQuote.dex,
            dexRegistry[bestQuote.dex].name,
            gasUsed
        );
        
        emit BestQuoteFound(
            bestQuote.dex,
            bestQuote.amountOut,
            bestQuote.gasEstimate,
            bestQuote.netOutput
        );
    }

    /// @notice Split large trades across multiple DEXs for better rates
    function executeSplitSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256[] calldata splits, // Percentage allocations (basis points)
        uint32 deadline
    ) external onlyRole(AGENT_ROLE) nonReentrant returns (uint256 totalAmountOut) {
        require(splits.length <= activeDEXs.length, "Too many splits");
        
        uint256 totalSplit = 0;
        for (uint256 i = 0; i < splits.length; i++) {
            totalSplit += splits[i];
        }
        require(totalSplit == 10000, "Splits must total 100%");
        
        IERC20 tokenIn_ = IERC20(tokenIn);
        tokenIn_.safeTransferFrom(msg.sender, address(this), amountIn);
        
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        
        for (uint256 i = 0; i < splits.length && i < activeDEXs.length; i++) {
            if (splits[i] == 0) continue;
            
            address dexRouter = activeDEXs[i];
            if (!dexRegistry[dexRouter].active) continue;
            
            uint256 splitAmount = (amountIn * splits[i]) / 10000;
            
            try IUniversalRouter(dexRouter).getAmountsOut(splitAmount, path) 
                returns (uint256[] memory amounts) {
                
                tokenIn_.forceApprove(dexRouter, splitAmount);
                
                uint256[] memory swapAmounts = IUniversalRouter(dexRouter)
                    .swapExactTokensForTokens(
                        splitAmount,
                        0, // No minimum for individual splits
                        path,
                        msg.sender,
                        block.timestamp + deadline
                    );
                
                totalAmountOut += swapAmounts[1];
            } catch {
                // If one DEX fails, continue with others
                continue;
            }
        }
        
        require(totalAmountOut >= minAmountOut, "Total output insufficient");
    }

    /// @notice Update DEX status (active/inactive)
    function setDEXStatus(address dex, bool active) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        dexRegistry[dex].active = active;
        emit DEXStatusUpdated(dex, active);
    }

    /// @notice Update gas price for optimization calculations
    function updateGasPrice(uint256 newGasPrice) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        gasPrice = newGasPrice;
    }

    /// @notice Get all active DEXs
    function getActiveDEXs() external view returns (address[] memory) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < activeDEXs.length; i++) {
            if (dexRegistry[activeDEXs[i]].active) {
                activeCount++;
            }
        }
        
        address[] memory active = new address[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < activeDEXs.length; i++) {
            if (dexRegistry[activeDEXs[i]].active) {
                active[index] = activeDEXs[i];
                index++;
            }
        }
        
        return active;
    }

    /// @notice Emergency token recovery
    function emergencyWithdraw(address token, uint256 amount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        IERC20(token).safeTransfer(msg.sender, amount);
    }
}