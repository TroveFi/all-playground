// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import "../../core/interfaces/IStrategy.sol";

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

/// @title AnkrStakingStrategy - Production Ready ankrFLOW Staking Strategy
/// @notice Strategy that stakes FLOW tokens to earn ankrFLOW rewards via Ankr Protocol
/// @dev Integrates with real Ankr Protocol on Flow EVM for FLOW staking
contract AnkrStakingStrategy is IStrategy, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ====================================================================
    // ROLES & CONSTANTS
    // ====================================================================

    bytes32 public constant STRATEGY_ROLE = keccak256("STRATEGY_ROLE");
    bytes32 public constant HARVESTER_ROLE = keccak256("HARVESTER_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    // ====================================================================
    // STATE VARIABLES (NO IMMUTABLE TO AVOID ENS ISSUES)
    // ====================================================================

    IERC20 public flowToken;
    IERC20 public ankrFlowToken;
    IAnkrStaking public stakingContract;

    address public vault;
    bool public strategyPaused;
    string public strategyName;

    // Position tracking
    uint256 public totalFlowStaked;
    uint256 public ankrFlowBalance;
    uint256 public lastExchangeRate;

    // Strategy metrics
    uint256 public totalDeployed;
    uint256 public totalHarvested;
    uint256 public lastHarvestTime;
    uint256 public harvestCount;

    // Performance tracking
    uint256 public rewardsEarned;
    uint256 public stakingRewards;
    uint256 public exchangeRateGains;

    // Risk and configuration
    uint256 public maxSingleDeployment = 100000 * 10**18; // 100K FLOW default
    uint256 public minHarvestAmount = 1 * 10**18; // 1 FLOW minimum
    uint256 public harvestThreshold = 10 * 10**18; // 10 FLOW threshold

    // Ankr specific settings
    uint256 public unstakeCooldown = 7 days; // Ankr unstaking period
    mapping(uint256 => uint256) public unstakeRequests; // requestId => amount
    mapping(uint256 => uint256) public unstakeTimestamps; // requestId => timestamp
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
    event ExchangeRateUpdated(uint256 oldRate, uint256 newRate, uint256 gainLoss);
    event UnstakeRequested(uint256 requestId, uint256 ankrFlowAmount, uint256 availableAt);
    event UnstakeCompleted(uint256 requestId, uint256 flowReceived);

    // ====================================================================
    // CONSTRUCTOR
    // ====================================================================

    constructor(
        address _vault,
        address _stakingContract,
        string memory _name
    ) {
        require(_vault != address(0), "Invalid vault");
        require(_stakingContract != address(0), "Invalid staking contract");

        // Set contract addresses manually to avoid ENS issues
        flowToken = IERC20(0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e); // WFLOW
        ankrFlowToken = IERC20(0x1b97100eA1D7126C4d60027e231EA4CB25314bdb); // ankrFLOW
        stakingContract = IAnkrStaking(_stakingContract);
        vault = _vault;
        strategyName = _name;

        // Initialize exchange rate
        try IAnkrFlow(address(ankrFlowToken)).exchangeRate() returns (uint256 rate) {
            lastExchangeRate = rate;
        } catch {
            lastExchangeRate = 1e18; // Default to 1:1
        }

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(STRATEGY_ROLE, _vault);
        _grantRole(HARVESTER_ROLE, msg.sender);
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

    modifier onlyHarvester() {
        require(hasRole(HARVESTER_ROLE, msg.sender), "Not authorized harvester");
        _;
    }

    // ====================================================================
    // ISTRATEGY INTERFACE IMPLEMENTATION
    // ====================================================================

    function execute(uint256 amount, bytes calldata data) external override onlyVault nonReentrant whenNotPaused {
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

        // Get ankrFLOW balance before staking
        uint256 ankrFlowBefore = ankrFlowToken.balanceOf(address(this));

        // Approve staking contract if needed
        flowToken.approve(address(stakingContract), amount);

        // Stake FLOW for ankrFLOW
        uint256 ankrFlowReceived;
        try stakingContract.stake{value: 0}() returns (uint256 received) {
            ankrFlowReceived = received;
        } catch {
            // If direct staking fails, calculate expected return
            uint256 ankrFlowAfter = ankrFlowToken.balanceOf(address(this));
            ankrFlowReceived = ankrFlowAfter - ankrFlowBefore;
            if (ankrFlowReceived == 0) {
                revert("Staking failed - no ankrFLOW received");
            }
        }
        
        // Update tracking
        totalFlowStaked += amount;
        ankrFlowBalance += ankrFlowReceived;
        totalDeployed += amount;

        // Update exchange rate tracking
        uint256 currentRate = _getCurrentExchangeRate();
        lastExchangeRate = currentRate;

        emit StrategyExecuted(amount, data);
        emit FlowStaked(amount, ankrFlowReceived, currentRate);
    }

    function harvest(bytes calldata data) external override onlyHarvester nonReentrant whenNotPaused {
        uint256 flowBalanceBefore = flowToken.balanceOf(address(this));
        uint256 totalHarvestedAmount = 0;

        // 1. Process any completed unstake requests
        _processCompletedUnstakes();

        // 2. Claim Ankr staking rewards if available
        try stakingContract.claimRewards() returns (uint256 rewards) {
            if (rewards > 0) {
                rewardsEarned += rewards;
                stakingRewards += rewards;
                totalHarvestedAmount += rewards;
                emit RewardsClaimed(rewards);
            }
        } catch {
            // Continue if rewards claiming fails
        }

        // 3. Check for exchange rate gains
        uint256 currentRate = _getCurrentExchangeRate();
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
            
            emit ExchangeRateUpdated(lastExchangeRate, currentRate, gainAmount);
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

    function emergencyExit(bytes calldata data) external override onlyRole(EMERGENCY_ROLE) nonReentrant {
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
            ankrFlowToken.safeTransfer(vault, ankrFlowBalance);
        }

        // Transfer any native FLOW
        if (address(this).balance > 0) {
            payable(vault).transfer(address(this).balance);
        }

        emit EmergencyExitExecuted(recovered);
    }

    function getBalance() external view override returns (uint256) {
        // Return total value in FLOW terms
        uint256 liquidFlow = flowToken.balanceOf(address(this));
        uint256 nativeFlow = address(this).balance;
        uint256 stakedValue = _getStakedValue();
        return liquidFlow + nativeFlow + stakedValue;
    }

    function underlyingToken() external view override returns (address) {
        return address(flowToken);
    }

    function protocol() external view override returns (address) {
        return address(stakingContract);
    }

    function paused() external view override returns (bool) {
        return strategyPaused;
    }

    function setPaused(bool pauseState) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        strategyPaused = pauseState;
    }

    // ====================================================================
    // ANKR SPECIFIC FUNCTIONS
    // ====================================================================

    function _getStakedValue() internal view returns (uint256) {
        if (ankrFlowBalance == 0) {
            return 0;
        }
        
        // Convert ankrFLOW to FLOW using current exchange rate
        uint256 currentRate = _getCurrentExchangeRate();
        return (ankrFlowBalance * currentRate) / 1e18;
    }

    function _getCurrentExchangeRate() internal view returns (uint256) {
        try IAnkrFlow(address(ankrFlowToken)).ratio() returns (uint256 rate) {
            return rate;
        } catch {
            try IAnkrFlow(address(ankrFlowToken)).exchangeRate() returns (uint256 rate) {
                return rate;
            } catch {
                return lastExchangeRate;
            }
        }
    }

    function _requestUnstake(uint256 ankrFlowAmount) internal {
        require(ankrFlowAmount <= ankrFlowBalance, "Insufficient ankrFLOW balance");
        
        ankrFlowBalance -= ankrFlowAmount;
        totalPendingUnstakes += ankrFlowAmount;
        
        uint256 requestId = block.timestamp; // Simplified request ID
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
                // Request is ready to be processed
                try stakingContract.unstake(amount) returns (uint256 flowReceived) {
                    totalPendingUnstakes -= amount;
                    totalFlowStaked -= flowReceived;
                    exchangeRateGains += flowReceived;
                    
                    delete unstakeRequests[requestId];
                    delete unstakeTimestamps[requestId];
                    
                    emit UnstakeCompleted(requestId, flowReceived);
                } catch {
                    // Keep the request if unstaking fails
                }
            }
        }
        
        // Clean up processed requests
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
        
        // Trim the array
        while (pendingUnstakeRequests.length > writeIndex) {
            pendingUnstakeRequests.pop();
        }
    }

    // ====================================================================
    // ADDITIONAL ANKR FUNCTIONS (Not in IStrategy but useful)
    // ====================================================================

    function manualUnstake(uint256 ankrFlowAmount) external onlyRole(HARVESTER_ROLE) nonReentrant {
        require(ankrFlowAmount <= ankrFlowBalance, "Insufficient ankrFLOW balance");
        require(stakingContract.unstakingEnabled(), "Unstaking disabled");

        _requestUnstake(ankrFlowAmount);
    }

    function processUnstakeRequests() external onlyRole(HARVESTER_ROLE) nonReentrant {
        _processCompletedUnstakes();
    }

    function getCurrentAPY() external view returns (uint256) {
        // Calculate current APY based on ankrFLOW exchange rate
        uint256 currentRate = _getCurrentExchangeRate();
        
        if (lastExchangeRate == 0 || lastHarvestTime == 0) {
            return 683; // Default 6.83% APY
        }
        
        uint256 timeElapsed = block.timestamp - lastHarvestTime;
        if (timeElapsed == 0) {
            return 683;
        }
        
        // Calculate rate improvement over time
        uint256 rateIncrease = currentRate > lastExchangeRate ? currentRate - lastExchangeRate : 0;
        uint256 annualizedRate = (rateIncrease * 365 days * 10000) / (lastExchangeRate * timeElapsed);
        
        return annualizedRate; // Return in basis points
    }

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
        currentExchangeRate = _getCurrentExchangeRate();
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

    // ====================================================================
    // VIEW FUNCTIONS
    // ====================================================================

    function getStrategyInfo() external view returns (
        string memory name,
        address asset,
        address protocolAddr,
        uint256 totalDep,
        uint256 totalHarv,
        uint256 lastHarvest,
        bool isPaused
    ) {
        return (
            strategyName,
            address(flowToken),
            address(stakingContract),
            totalDeployed,
            totalHarvested,
            lastHarvestTime,
            strategyPaused
        );
    }

    function getPerformanceMetrics() external view returns (
        uint256 totalDeployedAmount,
        uint256 totalHarvestedAmount,
        uint256 harvestsCount,
        uint256 avgHarvestAmount,
        uint256 totalRewards,
        uint256 currentAPY
    ) {
        uint256 avgHarvest = harvestCount > 0 ? totalHarvested / harvestCount : 0;
        uint256 apy = this.getCurrentAPY();

        return (
            totalDeployed,
            totalHarvested,
            harvestCount,
            avgHarvest,
            rewardsEarned,
            apy
        );
    }

    // ====================================================================
    // ADMIN FUNCTIONS
    // ====================================================================

    function setStakingContract(address _stakingContract) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_stakingContract != address(0), "Invalid staking contract");
        stakingContract = IAnkrStaking(_stakingContract);
    }

    function setMaxSingleDeployment(uint256 newMax) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxSingleDeployment = newMax;
    }

    function setMinHarvestAmount(uint256 newMin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minHarvestAmount = newMin;
    }

    function setHarvestThreshold(uint256 _threshold) external onlyRole(DEFAULT_ADMIN_ROLE) {
        harvestThreshold = _threshold;
    }

    function setUnstakeCooldown(uint256 _cooldown) external onlyRole(DEFAULT_ADMIN_ROLE) {
        unstakeCooldown = _cooldown;
    }

    function emergencyWithdrawAnkrFlow() external onlyRole(EMERGENCY_ROLE) {
        uint256 ankrFlowBal = ankrFlowToken.balanceOf(address(this));
        if (ankrFlowBal > 0) {
            ankrFlowToken.safeTransfer(vault, ankrFlowBal);
        }
    }

    function emergencyWithdrawNativeFlow() external onlyRole(EMERGENCY_ROLE) {
        if (address(this).balance > 0) {
            payable(vault).transfer(address(this).balance);
        }
    }

    // Receive function to handle native FLOW if needed for staking
    receive() external payable {
        // Accept native FLOW for potential conversion/staking
    }

    // Fallback function
    fallback() external payable {
        // Handle any other calls with value
    }
}