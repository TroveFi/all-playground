// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

interface IPunchSwapRouter {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
    
    function getAmountsOut(uint256 amountIn, address[] calldata path) 
        external view returns (uint256[] memory amounts);
}

interface IWFLOW {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

/// @title SwapStrategy - Token swaps via PunchSwap DEX
/// @notice Implements your swap scripts (swap_1_usdc_to_wflow.js, etc.)
contract SwapStrategy is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    // ====================================================================
    // CONSTANTS
    // ====================================================================
    address public constant PUNCH_SWAP_ROUTER = 0xf45AFe28fd5519d5f8C1d4787a4D5f724C0eFa4d;
    address public constant NATIVE_FLOW = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public constant WFLOW = 0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e;
    
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");
    
    uint256 public constant DEFAULT_SLIPPAGE = 200; // 2%
    
    // ====================================================================
    // STATE VARIABLES
    // ====================================================================
    address public vault;
    uint256 public totalSwaps;
    mapping(address => mapping(address => uint256)) public swapVolume; // from => to => volume
    
    // ====================================================================
    // EVENTS
    // ====================================================================
    event Swapped(address indexed from, address indexed to, uint256 amountIn, uint256 amountOut);
    
    // ====================================================================
    // CONSTRUCTOR
    // ====================================================================
    constructor(address _vault) {
        require(_vault != address(0), "Invalid vault");
        vault = _vault;
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(VAULT_ROLE, _vault);
        _grantRole(AGENT_ROLE, msg.sender);
    }
    
    // ====================================================================
    // SWAP FUNCTIONS
    // ====================================================================
    
    /// @notice Execute token swap
    /// @param asset Input token
    /// @param amount Amount to swap
    /// @param data Encoded swap parameters (outputToken, minAmountOut, path)
    function executeWithAsset(
        address asset,
        uint256 amount,
        bytes calldata data
    ) external payable onlyRole(VAULT_ROLE) nonReentrant returns (uint256) {
        require(amount > 0, "Amount must be positive");
        
        (address outputToken, uint256 minAmountOut, address[] memory path) = 
            abi.decode(data, (address, uint256, address[]));
        
        require(path.length >= 2, "Invalid path");
        require(path[0] == asset, "Path mismatch");
        require(path[path.length - 1] == outputToken, "Output mismatch");
        
        uint256 amountOut;
        
        if (asset == NATIVE_FLOW) {
            // Wrap FLOW → WFLOW first
            IWFLOW(WFLOW).deposit{value: amount}();
            path[0] = WFLOW;
            amountOut = _swap(WFLOW, amount, outputToken, minAmountOut, path);
        } else {
            amountOut = _swap(asset, amount, outputToken, minAmountOut, path);
        }
        
        totalSwaps++;
        swapVolume[asset][outputToken] += amount;
        
        emit Swapped(asset, outputToken, amount, amountOut);
        return amountOut;
    }
    
    function _swap(
        address inputToken,
        uint256 amountIn,
        address outputToken,
        uint256 minAmountOut,
        address[] memory path
    ) internal returns (uint256) {
        // Approve router
        IERC20(inputToken).safeApprove(PUNCH_SWAP_ROUTER, amountIn);
        
        // Execute swap
        uint256[] memory amounts = IPunchSwapRouter(PUNCH_SWAP_ROUTER).swapExactTokensForTokens(
            amountIn,
            minAmountOut,
            path,
            address(this),
            block.timestamp + 300
        );
        
        uint256 amountOut = amounts[amounts.length - 1];
        
        // If output is WFLOW and we want native FLOW, unwrap it
        if (outputToken == NATIVE_FLOW && path[path.length - 1] == WFLOW) {
            IWFLOW(WFLOW).withdraw(amountOut);
        }
        
        return amountOut;
    }
    
    /// @notice Agent function: Swap with automatic path finding
    function swapTokens(
        address fromToken,
        address toToken,
        uint256 amountIn,
        uint256 slippageBps
    ) external onlyRole(AGENT_ROLE) nonReentrant returns (uint256) {
        require(amountIn > 0, "Amount must be positive");
        
        // Build path (direct or via WFLOW)
        address[] memory path = _buildOptimalPath(fromToken, toToken);
        
        // Get expected output
        uint256[] memory amountsOut = IPunchSwapRouter(PUNCH_SWAP_ROUTER).getAmountsOut(amountIn, path);
        uint256 expectedOut = amountsOut[amountsOut.length - 1];
        
        // Calculate min output with slippage
        uint256 minOut = (expectedOut * (10000 - slippageBps)) / 10000;
        
        return _swap(fromToken, amountIn, toToken, minOut, path);
    }
    
    function _buildOptimalPath(address from, address to) internal pure returns (address[] memory) {
        // Direct path
        if (_hasDirectPool(from, to)) {
            address[] memory path = new address[](2);
            path[0] = from;
            path[1] = to;
            return path;
        }
        
        // Via WFLOW
        address[] memory path = new address[](3);
        path[0] = from;
        path[1] = WFLOW;
        path[2] = to;
        return path;
    }
    
    function _hasDirectPool(address from, address to) internal pure returns (bool) {
        // Simplified - in production would check actual pool existence
        // For now, assume WFLOW has direct pools with major tokens
        return (from == WFLOW || to == WFLOW);
    }
    
    /// @notice Harvest: Return swapped tokens to vault
    function harvest(bytes calldata data) 
        external 
        onlyRole(AGENT_ROLE) 
        nonReentrant 
        returns (uint256) 
    {
        address token = abi.decode(data, (address));
        
        uint256 balance;
        if (token == NATIVE_FLOW) {
            balance = address(this).balance;
            if (balance > 0) {
                payable(vault).transfer(balance);
            }
        } else {
            balance = IERC20(token).balanceOf(address(this));
            if (balance > 0) {
                IERC20(token).safeTransfer(vault, balance);
            }
        }
        
        return balance;
    }
    
    /// @notice Emergency exit: Return all tokens
    function emergencyExit(bytes calldata /* data */) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
        nonReentrant 
        returns (uint256) 
    {
        // Return native FLOW
        uint256 nativeBalance = address(this).balance;
        if (nativeBalance > 0) {
            payable(vault).transfer(nativeBalance);
        }
        
        // Return WFLOW
        uint256 wflowBalance = IERC20(WFLOW).balanceOf(address(this));
        if (wflowBalance > 0) {
            IERC20(WFLOW).safeTransfer(vault, wflowBalance);
        }
        
        return nativeBalance + wflowBalance;
    }
    
    // ====================================================================
    // VIEW FUNCTIONS
    // ====================================================================
    function getBalance() external view returns (uint256) {
        return address(this).balance + IERC20(WFLOW).balanceOf(address(this));
    }
    
    function underlyingToken() external pure returns (address) {
        return address(0); // Multi-token
    }
    
    function strategyType() external pure returns (string memory) {
        return "Swap";
    }
    
    function getSwapQuote(
        address fromToken,
        address toToken,
        uint256 amountIn
    ) external view returns (uint256 amountOut, address[] memory path) {
        path = _buildOptimalPath(fromToken, toToken);
        uint256[] memory amounts = IPunchSwapRouter(PUNCH_SWAP_ROUTER).getAmountsOut(amountIn, path);
        amountOut = amounts[amounts.length - 1];
        return (amountOut, path);
    }
    
    function getSwapMetrics() external view returns (
        uint256 totalSwaps_,
        uint256 nativeBalance,
        uint256 wflowBalance
    ) {
        return (
            totalSwaps,
            address(this).balance,
            IERC20(WFLOW).balanceOf(address(this))
        );
    }
    
    // ====================================================================
    // RECEIVE FUNCTIONS
    // ====================================================================
    receive() external payable {}
}