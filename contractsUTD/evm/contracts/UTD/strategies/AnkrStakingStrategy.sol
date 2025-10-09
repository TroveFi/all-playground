// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title AnkrStakingStrategy - Stake FLOW with Ankr to receive ankrFLOW
/// @notice Strategy for basic Ankr staking (your Ankr-MORE-1-loop.js logic)
contract AnkrStakingStrategy is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    // ====================================================================
    // CONSTANTS
    // ====================================================================
    address public constant NATIVE_FLOW = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public constant ANKR_FLOW_TOKEN = 0x1b97100eA1D7126C4d60027e231EA4CB25314bdb;
    address public constant FLOW_STAKING_POOL = 0xFE8189A3016cb6A3668b8ccdAC520CE572D4287a;
    
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");
    
    // ====================================================================
    // STATE VARIABLES
    // ====================================================================
    address public vault;
    uint256 public totalStaked;
    uint256 public totalAnkrFlowReceived;
    
    // ====================================================================
    // EVENTS
    // ====================================================================
    event Staked(uint256 flowAmount, uint256 ankrFlowReceived);
    event Harvested(uint256 ankrFlowAmount);
    event EmergencyExit(uint256 ankrFlowRecovered);
    
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
    // STRATEGY FUNCTIONS
    // ====================================================================
    
    /// @notice Execute staking: FLOW → ankrFLOW
    function executeWithAsset(
        address asset,
        uint256 amount,
        bytes calldata /* data */
    ) external payable onlyRole(VAULT_ROLE) nonReentrant returns (uint256) {
        require(asset == NATIVE_FLOW, "Only native FLOW supported");
        require(msg.value == amount, "Amount mismatch");
        require(amount > 0, "Amount must be positive");
        
        uint256 ankrBalanceBefore = IERC20(ANKR_FLOW_TOKEN).balanceOf(address(this));
        
        // Stake FLOW with Ankr
        (bool success, ) = FLOW_STAKING_POOL.call{value: amount}(
            abi.encodeWithSignature("stakeCerts()")
        );
        require(success, "Ankr staking failed");
        
        uint256 ankrBalanceAfter = IERC20(ANKR_FLOW_TOKEN).balanceOf(address(this));
        uint256 ankrFlowReceived = ankrBalanceAfter - ankrBalanceBefore;
        
        totalStaked += amount;
        totalAnkrFlowReceived += ankrFlowReceived;
        
        emit Staked(amount, ankrFlowReceived);
        return ankrFlowReceived;
    }
    
    /// @notice Harvest ankrFLOW back to vault
    function harvest(bytes calldata /* data */) 
        external 
        onlyRole(AGENT_ROLE) 
        nonReentrant 
        returns (uint256) 
    {
        uint256 ankrBalance = IERC20(ANKR_FLOW_TOKEN).balanceOf(address(this));
        require(ankrBalance > 0, "Nothing to harvest");
        
        // Transfer ankrFLOW back to vault
        IERC20(ANKR_FLOW_TOKEN).safeTransfer(vault, ankrBalance);
        
        emit Harvested(ankrBalance);
        return ankrBalance;
    }
    
    /// @notice Emergency exit - return all ankrFLOW
    function emergencyExit(bytes calldata /* data */) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
        nonReentrant 
        returns (uint256) 
    {
        uint256 ankrBalance = IERC20(ANKR_FLOW_TOKEN).balanceOf(address(this));
        
        if (ankrBalance > 0) {
            IERC20(ANKR_FLOW_TOKEN).safeTransfer(vault, ankrBalance);
        }
        
        emit EmergencyExit(ankrBalance);
        return ankrBalance;
    }
    
    // ====================================================================
    // VIEW FUNCTIONS
    // ====================================================================
    function getBalance() external view returns (uint256) {
        return IERC20(ANKR_FLOW_TOKEN).balanceOf(address(this));
    }
    
    function underlyingToken() external pure returns (address) {
        return NATIVE_FLOW;
    }
    
    function strategyType() external pure returns (string memory) {
        return "AnkrStaking";
    }
    
    function getStakingMetrics() external view returns (
        uint256 totalStaked_,
        uint256 totalAnkrFlowReceived_,
        uint256 currentAnkrBalance,
        uint256 exchangeRate
    ) {
        currentAnkrBalance = IERC20(ANKR_FLOW_TOKEN).balanceOf(address(this));
        
        exchangeRate = totalAnkrFlowReceived > 0 
            ? (totalStaked * 1e18) / totalAnkrFlowReceived 
            : 1e18;
        
        return (totalStaked, totalAnkrFlowReceived, currentAnkrBalance, exchangeRate);
    }
    
    // ====================================================================
    // RECEIVE FUNCTIONS
    // ====================================================================
    receive() external payable {}
}