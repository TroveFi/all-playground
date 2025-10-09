// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

interface IMorePool {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf) external;
    function getUserAccountData(address user) external view returns (
        uint256 totalCollateralBase,
        uint256 totalDebtBase,
        uint256 availableBorrowsBase,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    );
}

interface IWFLOW {
    function withdraw(uint256 amount) external;
}

/// @title AnkrMORELoopingStrategy - Leveraged Ankr staking via MORE Markets
/// @notice Implements your Ankr-MORE-1-loop.js, 2-loop.js, 3-loop.js strategies
contract AnkrMORELoopingStrategy is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    // ====================================================================
    // CONSTANTS
    // ====================================================================
    address public constant NATIVE_FLOW = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public constant ANKR_FLOW_TOKEN = 0x1b97100eA1D7126C4d60027e231EA4CB25314bdb;
    address public constant WFLOW_TOKEN = 0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e;
    address public constant FLOW_STAKING_POOL = 0xFE8189A3016cb6A3668b8ccdAC520CE572D4287a;
    address public constant MORE_POOL = 0xbC92aaC2DBBF42215248B5688eB3D3d2b32F2c8d;
    
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");
    
    uint256 public constant SAFETY_BUFFER = 85; // 85% of available borrow capacity
    
    // ====================================================================
    // STATE VARIABLES
    // ====================================================================
    address public vault;
    uint256 public totalFlowStaked;
    uint256 public totalAnkrFlowReceived;
    uint256 public totalFlowBorrowed;
    uint256 public loopCount;
    
    // ====================================================================
    // EVENTS
    // ====================================================================
    event LoopExecuted(uint256 loopNumber, uint256 flowStaked, uint256 ankrFlowReceived, uint256 flowBorrowed);
    event PositionUnwound(uint256 ankrFlowWithdrawn, uint256 flowRepaid);
    event HealthFactorWarning(uint256 healthFactor);
    
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
    
    /// @notice Execute looping strategy
    /// @param asset Input asset address (must be NATIVE_FLOW)
    /// @param amount Amount of FLOW to start with
    /// @param data Encoded number of loops to execute (1, 2, or 3)
    /// @return Total ankrFLOW received
    function executeWithAsset(
        address asset,
        uint256 amount,
        bytes calldata data
    ) external payable onlyRole(VAULT_ROLE) nonReentrant returns (uint256) {
        require(asset == NATIVE_FLOW, "Only native FLOW");
        require(msg.value == amount, "Amount mismatch");
        
        uint256 numLoops = abi.decode(data, (uint256));
        require(numLoops >= 1 && numLoops <= 3, "Loops must be 1-3");
        
        uint256 flowForNextLoop = amount;
        
        for (uint256 i = 0; i < numLoops; i++) {
            if (flowForNextLoop == 0) break;
            
            flowForNextLoop = _executeSingleLoop(flowForNextLoop, i + 1);
            
            // Check health factor after each loop
            (, , , , , uint256 healthFactor) = IMorePool(MORE_POOL).getUserAccountData(address(this));
            
            if (healthFactor < 1.3e18 && healthFactor > 0) {
                emit HealthFactorWarning(healthFactor);
                if (i < numLoops - 1) {
                    break; // Stop looping if HF too low
                }
            }
        }
        
        // Final stake of last borrowed amount
        if (flowForNextLoop > 0) {
            _stakeWithAnkr(flowForNextLoop);
        }
        
        return totalAnkrFlowReceived;
    }
    
    /// @notice Execute a single loop iteration
    /// @param flowAmount Amount of FLOW to stake in this loop
    /// @param loopNumber Current loop number (for event emission)
    /// @return Amount of FLOW borrowed for next loop
    function _executeSingleLoop(uint256 flowAmount, uint256 loopNumber) internal returns (uint256) {
        // STEP 1: Stake FLOW → ankrFLOW
        uint256 ankrFlowReceived = _stakeWithAnkr(flowAmount);
        
        // STEP 2: Supply ankrFLOW to MORE
        _supplyToMORE(ankrFlowReceived);
        
        // STEP 3: Check borrowing capacity
        (, , uint256 availableBorrowsBase, , , uint256 healthFactor) = 
            IMorePool(MORE_POOL).getUserAccountData(address(this));
        
        if (availableBorrowsBase < 0.01e8) {
            emit LoopExecuted(loopNumber, flowAmount, ankrFlowReceived, 0);
            return 0;
        }
        
        // STEP 4: Borrow WFLOW (use safety buffer)
        uint256 wflowToBorrow = (availableBorrowsBase * SAFETY_BUFFER) / 100;
        wflowToBorrow = wflowToBorrow * 1e10; // Convert from 8 decimals to 18
        
        IMorePool(MORE_POOL).borrow(WFLOW_TOKEN, wflowToBorrow, 2, 0, address(this));
        
        // STEP 5: Unwrap WFLOW → FLOW
        IWFLOW(WFLOW_TOKEN).withdraw(wflowToBorrow);
        
        totalFlowBorrowed += wflowToBorrow;
        loopCount++;
        
        emit LoopExecuted(loopNumber, flowAmount, ankrFlowReceived, wflowToBorrow);
        
        return wflowToBorrow;
    }
    
    /// @notice Stake FLOW with Ankr to receive ankrFLOW
    /// @param flowAmount Amount of FLOW to stake
    /// @return Amount of ankrFLOW received
    function _stakeWithAnkr(uint256 flowAmount) internal returns (uint256) {
        uint256 ankrBalanceBefore = IERC20(ANKR_FLOW_TOKEN).balanceOf(address(this));
        
        (bool success, ) = FLOW_STAKING_POOL.call{value: flowAmount}(
            abi.encodeWithSignature("stakeCerts()")
        );
        require(success, "Ankr staking failed");
        
        uint256 ankrBalanceAfter = IERC20(ANKR_FLOW_TOKEN).balanceOf(address(this));
        uint256 ankrFlowReceived = ankrBalanceAfter - ankrBalanceBefore;
        
        totalFlowStaked += flowAmount;
        totalAnkrFlowReceived += ankrFlowReceived;
        
        return ankrFlowReceived;
    }
    
    /// @notice Supply ankrFLOW to MORE Markets as collateral
    /// @param ankrFlowAmount Amount of ankrFLOW to supply
    function _supplyToMORE(uint256 ankrFlowAmount) internal {
        IERC20(ANKR_FLOW_TOKEN).safeApprove(MORE_POOL, ankrFlowAmount);
        IMorePool(MORE_POOL).supply(ANKR_FLOW_TOKEN, ankrFlowAmount, address(this), 0);
    }
    
    /// @notice Harvest rewards (not applicable for this strategy)
    /// @param data Unused parameter
    /// @return Always returns 0 as looping strategy doesn't harvest separately
    function harvest(bytes calldata data) 
        external 
        view 
        onlyRole(AGENT_ROLE) 
        returns (uint256) 
    {
        // Looping strategy doesn't harvest separately
        // Yield is inherent in the leverage
        return 0;
    }
    
    /// @notice Emergency exit: Unwind entire position
    /// @param data Unused parameter
    /// @return Amount of ankrFLOW returned to vault
    function emergencyExit(bytes calldata data) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
        nonReentrant 
        returns (uint256) 
    {
        // This would require:
        // 1. Withdraw ankrFLOW from MORE
        // 2. Swap ankrFLOW → FLOW (via DEX or unstake)
        // 3. Repay WFLOW debt
        // 4. Return remaining to vault
        
        // Simplified: Just return ankrFLOW balance
        uint256 ankrBalance = IERC20(ANKR_FLOW_TOKEN).balanceOf(address(this));
        if (ankrBalance > 0) {
            IERC20(ANKR_FLOW_TOKEN).safeTransfer(vault, ankrBalance);
        }
        
        return ankrBalance;
    }
    
    // ====================================================================
    // VIEW FUNCTIONS
    // ====================================================================
    
    /// @notice Get strategy's ankrFLOW balance
    /// @return Current ankrFLOW balance
    function getBalance() external view returns (uint256) {
        return IERC20(ANKR_FLOW_TOKEN).balanceOf(address(this));
    }
    
    /// @notice Get underlying token address
    /// @return Address of NATIVE_FLOW
    function underlyingToken() external pure returns (address) {
        return NATIVE_FLOW;
    }
    
    /// @notice Get strategy type identifier
    /// @return Strategy type string
    function strategyType() external pure returns (string memory) {
        return "AnkrMORELooping";
    }
    
    /// @notice Get comprehensive looping metrics
    /// @return totalFlowStaked_ Total FLOW staked across all loops
    /// @return totalAnkrFlowReceived_ Total ankrFLOW received
    /// @return totalFlowBorrowed_ Total FLOW borrowed from MORE
    /// @return loopCount_ Number of loops executed
    /// @return leverage Current leverage ratio
    /// @return healthFactor Current health factor from MORE
    function getLoopingMetrics() external view returns (
        uint256 totalFlowStaked_,
        uint256 totalAnkrFlowReceived_,
        uint256 totalFlowBorrowed_,
        uint256 loopCount_,
        uint256 leverage,
        uint256 healthFactor
    ) {
        (, , , , , uint256 hf) = IMorePool(MORE_POOL).getUserAccountData(address(this));
        
        uint256 lev = totalFlowStaked > 0 && totalFlowBorrowed > 0
            ? (totalFlowStaked * 1e18) / (totalFlowStaked - totalFlowBorrowed)
            : 1e18;
        
        return (
            totalFlowStaked,
            totalAnkrFlowReceived,
            totalFlowBorrowed,
            loopCount,
            lev,
            hf
        );
    }
    
    // ====================================================================
    // RECEIVE FUNCTIONS
    // ====================================================================
    receive() external payable {}
}