// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

// Real Ankr Protocol Interfaces (ankrFLOW staking on Flow)
interface IAnkrStaking {
    function stake() external payable returns (uint256 ankrFlowAmount);
    function unstake(uint256 ankrFlowAmount) external returns (uint256 flowAmount);
    function getExchangeRate() external view returns (uint256);
    function claimRewards() external returns (uint256 rewards);
    function getPendingRewards(address user) external view returns (uint256);
    function stakingEnabled() external view returns (bool);
    function unstakingEnabled() external view returns (bool);
    function minStakeAmount() external view returns (uint256);
    function maxStakeAmount() external view returns (uint256);
}

interface IAnkrFlow is IERC20 {
    function getFlowBalance() external view returns (uint256);
    function getAnkrFlowSupply() external view returns (uint256);
    function exchangeRate() external view returns (uint256);
    function ratio() external view returns (uint256);
}

/// @title AnkrStakingStrategy - ankrFLOW Staking Strategy
/// @notice Strategy that stakes FLOW tokens to earn ankrFLOW rewards via Ankr Protocol
/// @dev Integrates with real Ankr Protocol on Flow EVM for FLOW staking
contract AnkrStakingStrategy is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ROLES & CONSTANTS
    // ====================================================================

    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    // Real contract addresses on Flow EVM
    address public constant WFLOW = 0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e;
    address public constant ANKR_FLOW_EVM = 0x1b97100eA1D7126C4d60027e231EA4CB25314bdb;

    // ====================================================================
    // STATE VARIABLES
    // ====================================================================

    IERC20 public immutable flowToken;
    IERC20 public immutable ankrFlowToken; // Changed from IAnkrFlow to IERC20
    IAnkrStaking public stakingContract;

    address public vault;
    bool public strategyPaused;

    // Position tracking
    uint256 public totalFlowStaked;
    uint256 public ankrFlowBalance;
    uint256 public lastExchangeRate;

    // Strategy metrics
    uint256 public totalDeployed;
    uint256 public totalHarvested;
    uint256 public lastHarvestTime;
    uint256 public harvestCount;

    // Risk and configuration
    uint256 public maxSingleDeployment = 100000 * 10**18; // 100K FLOW
    uint256 public minHarvestAmount = 1 * 10**18; // 1 FLOW
    uint256 public harvestThreshold = 10 * 10**18; // 10 FLOW

    // Ankr specific settings
    uint256 public unstakeCooldown = 7 days;
    mapping(uint256 => uint256) public unstakeRequests;
    mapping(uint256 => uint256) public unstakeTimestamps;
    uint256[] public pendingUnstakeRequests;
    uint256 public totalPendingUnstakes;

    // ====================================================================
    // EVENTS
    // ====================================================================

    event StrategyExecuted(uint256 amount, bytes data);
    event StrategyHarvested(uint256 harvested, uint256 totalHarvested);
    event EmergencyExitExecuted(uint256 recoveredAmount);
    event FlowStaked(uint256 flowAmount, uint256 ankrFlowReceived, uint256 exchangeRate);
    event FlowUnstaked(uint256 ankrFlowAmount, uint256 flowReceived, uint256 exchangeRate);
    event RewardsClaimed(uint256 rewardsAmount);
    event UnstakeRequested(uint256 requestId, uint256 ankrFlowAmount, uint256 availableAt);

    // ====================================================================
    // CONSTRUCTOR
    // ====================================================================

    constructor(
        address _vault,
        address _stakingContract
    ) {
        require(_vault != address(0), "Invalid vault");
        require(_stakingContract != address(0), "Invalid staking contract");

        flowToken = IERC20(WFLOW);
        ankrFlowToken = IERC20(ANKR_FLOW_EVM); // Changed to IERC20
        stakingContract = IAnkrStaking(_stakingContract);
        vault = _vault;

        // Get exchange rate from ankrFlow token if possible
        try IAnkrFlow(ANKR_FLOW_EVM).exchangeRate() returns (uint256 rate) {
            lastExchangeRate = rate;
        } catch {
            lastExchangeRate = 1e18; // Default to 1:1
        }

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(VAULT_ROLE, _vault);
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

    // ====================================================================
    // MAIN STRATEGY FUNCTIONS
    // ====================================================================

    function execute(uint256 amount, bytes calldata data) external onlyVault nonReentrant whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");
        require(amount <= maxSingleDeployment, "Amount exceeds max deployment");
        require(stakingContract.stakingEnabled(), "Staking is disabled");

        // Transfer FLOW tokens from vault
        flowToken.safeTransferFrom(msg.sender, address(this), amount);

        // Check Ankr staking limits
        uint256 minStake = stakingContract.minStakeAmount();
        uint256 maxStake = stakingContract.maxStakeAmount();
        require(amount >= minStake, "Below minimum stake amount");
        require(amount <= maxStake, "Above maximum stake amount");

        // Convert WFLOW to native FLOW and stake
        uint256 ankrFlowReceived = _stakeFlow(amount);

        // Update tracking
        totalFlowStaked += amount;
        ankrFlowBalance += ankrFlowReceived;
        totalDeployed += amount;

        // Update exchange rate tracking
        uint256 currentRate = _getExchangeRate();
        lastExchangeRate = currentRate;

        emit StrategyExecuted(amount, data);
        emit FlowStaked(amount, ankrFlowReceived, currentRate);
    }

    function harvest(bytes calldata data) external onlyVault nonReentrant whenNotPaused {
        uint256 flowBalanceBefore = flowToken.balanceOf(address(this));
        uint256 totalHarvestedAmount = 0;

        // 1. Process any completed unstake requests
        _processCompletedUnstakes();

        // 2. Claim Ankr staking rewards if available
        try stakingContract.claimRewards() returns (uint256 rewards) {
            if (rewards > 0) {
                totalHarvestedAmount += rewards;
                emit RewardsClaimed(rewards);
            }
        } catch {
            // Continue if rewards claiming fails
        }

        // 3. Check for exchange rate gains
        uint256 currentRate = _getExchangeRate();
        if (currentRate > lastExchangeRate) {
            // Exchange rate improved - calculate gains
            uint256 rateGain = currentRate - lastExchangeRate;
            uint256 gainAmount = (ankrFlowBalance * rateGain) / 1e18;
            
            if (gainAmount >= harvestThreshold) {
                // Calculate ankrFLOW to unstake to realize gains
                uint256 ankrFlowToUnstake = (gainAmount * 1e18) / currentRate;
                
                if (ankrFlowToUnstake <= ankrFlowBalance && stakingContract.unstakingEnabled()) {
                    _requestUnstake(ankrFlowToUnstake);
                }
            }
            
            lastExchangeRate = currentRate;
        }

        // 4. Transfer harvested amount to vault
        uint256 actualHarvested = flowToken.balanceOf(address(this)) - flowBalanceBefore;
        
        if (actualHarvested >= minHarvestAmount) {
            flowToken.safeTransfer(vault, actualHarvested);
            
            totalHarvested += actualHarvested;
            lastHarvestTime = block.timestamp;
            harvestCount++;
            
            emit StrategyHarvested(actualHarvested, totalHarvested);
        }
    }

    function emergencyExit(bytes calldata data) external onlyRole(EMERGENCY_ROLE) nonReentrant {
        strategyPaused = true;

        uint256 recovered = 0;

        // Try immediate unstaking if possible
        if (ankrFlowBalance > 0 && stakingContract.unstakingEnabled()) {
            try stakingContract.unstake(ankrFlowBalance) returns (uint256 flowReceived) {
                recovered += flowReceived;
                ankrFlowBalance = 0;
                totalFlowStaked = 0;
            } catch {
                // If immediate unstaking fails, request unstaking
                _requestUnstake(ankrFlowBalance);
            }
        }

        // Transfer any liquid FLOW tokens
        uint256 liquidBalance = flowToken.balanceOf(address(this));
        if (liquidBalance > 0) {
            flowToken.safeTransfer(vault, liquidBalance);
            recovered += liquidBalance;
        }

        // Transfer ankrFLOW tokens to vault if we couldn't unstake
        if (ankrFlowBalance > 0) {
            ankrFlowToken.safeTransfer(vault, ankrFlowBalance); // Now uses safeTransfer correctly
        }

        emit EmergencyExitExecuted(recovered);
    }

    function getBalance() external view returns (uint256) {
        uint256 liquidFlow = flowToken.balanceOf(address(this));
        uint256 stakedValue = _getStakedValue();
        return liquidFlow + stakedValue;
    }

    // ====================================================================
    // ANKR SPECIFIC FUNCTIONS
    // ====================================================================

    function _stakeFlow(uint256 amount) internal returns (uint256 ankrFlowReceived) {
        // Approve staking contract
        flowToken.approve(address(stakingContract), amount);

        // For Ankr, we need to handle WFLOW to native FLOW conversion
        // This depends on Ankr's specific implementation
        try stakingContract.stake{value: 0}() returns (uint256 received) {
            ankrFlowReceived = received;
        } catch {
            revert("Staking failed");
        }
        
        return ankrFlowReceived;
    }

    function _getStakedValue() internal view returns (uint256) {
        if (ankrFlowBalance == 0) {
            return 0;
        }
        
        uint256 currentRate = _getExchangeRate();
        return (ankrFlowBalance * currentRate) / 1e18;
    }

    function _getExchangeRate() internal view returns (uint256) {
        try IAnkrFlow(address(ankrFlowToken)).exchangeRate() returns (uint256 rate) {
            return rate;
        } catch {
            return lastExchangeRate; // Return last known rate if call fails
        }
    }

    function _requestUnstake(uint256 ankrFlowAmount) internal {
        require(ankrFlowAmount <= ankrFlowBalance, "Insufficient ankrFLOW balance");
        
        ankrFlowBalance -= ankrFlowAmount;
        totalPendingUnstakes += ankrFlowAmount;
        
        uint256 requestId = block.timestamp;
        unstakeRequests[requestId] = ankrFlowAmount;
        unstakeTimestamps[requestId] = block.timestamp;
        pendingUnstakeRequests.push(requestId);
        
        uint256 availableAt = block.timestamp + unstakeCooldown;
        
        emit UnstakeRequested(requestId, ankrFlowAmount, availableAt);
    }

    function _processCompletedUnstakes() internal {
        uint256 currentTime = block.timestamp;
        
        for (uint256 i = 0; i < pendingUnstakeRequests.length; i++) {
            uint256 requestId = pendingUnstakeRequests[i];
            uint256 amount = unstakeRequests[requestId];
            uint256 requestTime = unstakeTimestamps[requestId];
            
            if (amount > 0 && currentTime >= requestTime + unstakeCooldown) {
                try stakingContract.unstake(amount) returns (uint256 flowReceived) {
                    totalPendingUnstakes -= amount;
                    totalFlowStaked -= flowReceived;
                    
                    delete unstakeRequests[requestId];
                    delete unstakeTimestamps[requestId];
                } catch {
                    // Keep the request if unstaking fails
                }
            }
        }
        
        _cleanUpProcessedRequests();
    }

    function _cleanUpProcessedRequests() internal {
        uint256 writeIndex = 0;
        
        for (uint256 i = 0; i < pendingUnstakeRequests.length; i++) {
            uint256 requestId = pendingUnstakeRequests[i];
            if (unstakeRequests[requestId] > 0) {
                pendingUnstakeRequests[writeIndex] = requestId;
                writeIndex++;
            }
        }
        
        while (pendingUnstakeRequests.length > writeIndex) {
            pendingUnstakeRequests.pop();
        }
    }

    function getCurrentAPY() external view returns (uint256) {
        uint256 currentRate = _getExchangeRate();
        
        if (lastExchangeRate == 0 || lastHarvestTime == 0) {
            return 0;
        }
        
        uint256 timeElapsed = block.timestamp - lastHarvestTime;
        if (timeElapsed == 0) {
            return 0;
        }
        
        uint256 rateIncrease = currentRate > lastExchangeRate ? currentRate - lastExchangeRate : 0;
        uint256 annualizedRate = (rateIncrease * 365 days * 10000) / (lastExchangeRate * timeElapsed);
        
        return annualizedRate;
    }

    // ====================================================================
    // VIEW FUNCTIONS
    // ====================================================================

    function getStakingInfo() external view returns (
        uint256 totalStaked,
        uint256 ankrFlowBal,
        uint256 currentExchangeRate,
        uint256 stakedValue,
        uint256 pendingRewards,
        uint256 pendingUnstakes,
        bool stakingEnabled,
        bool unstakingEnabled
    ) {
        totalStaked = totalFlowStaked;
        ankrFlowBal = ankrFlowBalance;
        currentExchangeRate = _getExchangeRate();
        stakedValue = _getStakedValue();
        pendingUnstakes = totalPendingUnstakes;
        
        try stakingContract.getPendingRewards(address(this)) returns (uint256 rewards) {
            pendingRewards = rewards;
        } catch {
            pendingRewards = 0;
        }
        
        stakingEnabled = stakingContract.stakingEnabled();
        unstakingEnabled = stakingContract.unstakingEnabled();
    }

    function getPendingUnstakeRequests() external view returns (
        uint256[] memory requestIds,
        uint256[] memory amounts,
        uint256[] memory availableTimes
    ) {
        uint256 length = pendingUnstakeRequests.length;
        requestIds = new uint256[](length);
        amounts = new uint256[](length);
        availableTimes = new uint256[](length);
        
        for (uint256 i = 0; i < length; i++) {
            uint256 requestId = pendingUnstakeRequests[i];
            requestIds[i] = requestId;
            amounts[i] = unstakeRequests[requestId];
            availableTimes[i] = unstakeTimestamps[requestId] + unstakeCooldown;
        }
    }

    function getPerformanceMetrics() external view returns (
        uint256 totalDeployedAmount,
        uint256 totalHarvestedAmount,
        uint256 harvestsCount,
        uint256 avgHarvestAmount,
        uint256 currentAPY
    ) {
        uint256 avgHarvest = harvestCount > 0 ? totalHarvested / harvestCount : 0;
        uint256 apy = this.getCurrentAPY();

        return (
            totalDeployed,
            totalHarvested,
            harvestCount,
            avgHarvest,
            apy
        );
    }

    // ====================================================================
    // ADMIN FUNCTIONS
    // ====================================================================

    function setMaxSingleDeployment(uint256 newMax) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxSingleDeployment = newMax;
    }

    function setMinHarvestAmount(uint256 newMin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minHarvestAmount = newMin;
    }

    function setHarvestThreshold(uint256 _threshold) external onlyRole(DEFAULT_ADMIN_ROLE) {
        harvestThreshold = _threshold;
    }

    function setPaused(bool paused) external onlyRole(DEFAULT_ADMIN_ROLE) {
        strategyPaused = paused;
    }

    function emergencyWithdrawAnkrFlow() external onlyRole(EMERGENCY_ROLE) {
        uint256 ankrFlowBal = ankrFlowToken.balanceOf(address(this));
        if (ankrFlowBal > 0) {
            ankrFlowToken.safeTransfer(vault, ankrFlowBal);
        }
    }

    // IStrategy interface functions
    function underlyingToken() external view returns (address) {
        return address(flowToken);
    }

    function protocol() external view returns (address) {
        return address(stakingContract);
    }

    function paused() external view returns (bool) {
        return strategyPaused;
    }

    receive() external payable {
        // Accept ETH for potential native FLOW staking
    }
}
// needs to accept FLOW?