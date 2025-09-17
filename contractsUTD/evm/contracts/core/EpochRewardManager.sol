// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title ICadenceArchVRF - Interface for Flow's Cadence Arch VRF precompile
interface ICadenceArchVRF {
    function revertibleRandom() external view returns (uint256 randomValue);
}

/// @title EpochRewardManager - Manages epoch-based rewards with VRF lottery
/// @notice Handles user deposits, risk levels, and VRF-powered reward distribution
contract EpochRewardManager is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    // ====================================================================
    // ROLES & CONSTANTS
    // ====================================================================
    
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant YIELD_MANAGER_ROLE = keccak256("YIELD_MANAGER_ROLE");
    
    // Flow's Cadence Arch VRF precompile address
    address public constant CADENCE_ARCH_VRF = 0x0000000000000000000000010000000000000001;
    
    // ====================================================================
    // ENUMS & STRUCTS
    // ====================================================================
    
    enum RiskLevel { LOW, MEDIUM, HIGH }
    
    struct UserDeposit {
        uint256 totalDeposited;           // Total amount ever deposited
        uint256 currentBalance;           // Current balance (can be withdrawn)
        uint256 firstDepositEpoch;        // Epoch of first deposit
        uint256 lastDepositEpoch;         // Epoch of last deposit
        RiskLevel riskLevel;              // User's chosen risk level
        uint256 timeWeightedBalance;      // Accumulated time-weighted balance
        uint256 lastUpdateEpoch;          // Last epoch when time weight was updated
        mapping(uint256 => bool) epochClaimed; // Track claims per epoch
    }
    
    struct EpochData {
        uint256 epochNumber;
        uint256 startTime;
        uint256 endTime;
        uint256 totalYieldPool;           // Total yield available for distribution
        uint256 totalDistributed;         // Amount distributed in this epoch
        uint256 participantCount;         // Number of eligible participants
        bool finalized;                   // Whether epoch is finalized
        mapping(address => bool) eligibleUsers; // Users eligible for this epoch
    }
    
    struct RewardCalculation {
        uint256 baseWeight;               // Weight from deposit amount
        uint256 timeWeight;               // Weight from time in vault
        uint256 riskMultiplier;           // Risk level multiplier
        uint256 totalWeight;              // Combined weight
        uint256 winProbability;           // Probability of winning (basis points)
        uint256 potentialPayout;          // Potential payout if win
    }
    
    // ====================================================================
    // STATE VARIABLES
    // ====================================================================
    
    ICadenceArchVRF public immutable cadenceVRF;
    address public vault;
    
    // Epoch management
    uint256 public currentEpoch;
    uint256 public epochDuration = 7 days;          // 1 week epochs
    uint256 public lastEpochStart;
    
    // User data
    mapping(address => UserDeposit) public userDeposits;
    mapping(uint256 => EpochData) public epochs;
    
    // Yield pool management
    uint256 public totalYieldPool;                  // Total accumulated yield
    uint256 public totalDistributedRewards;         // Total rewards distributed
    
    // Risk level configurations
    mapping(RiskLevel => uint256) public riskMultipliers; // Basis points
    mapping(RiskLevel => uint256) public baseProbabilities; // Basis points
    
    // Minimum balances for eligibility (18 decimals)
    mapping(address => uint256) public minimumBalances;
    
    // Asset tracking
    address[] public supportedAssets;
    mapping(address => bool) public isSupportedAsset;
    
    // Constants
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MAX_PROBABILITY = 5000;     // 50% max win probability
    uint256 public constant TIME_WEIGHT_MULTIPLIER = 100; // Time weight per epoch
    
    // ====================================================================
    // EVENTS
    // ====================================================================
    
    event UserDeposited(
        address indexed user, 
        address indexed asset, 
        uint256 amount, 
        uint256 epoch,
        RiskLevel riskLevel
    );
    
    event UserWithdrew(
        address indexed user, 
        address indexed asset, 
        uint256 amount, 
        uint256 remainingBalance
    );
    
    event EpochAdvanced(
        uint256 indexed newEpoch, 
        uint256 startTime, 
        uint256 yieldPool
    );
    
    event RewardClaimed(
        address indexed user, 
        uint256 indexed epoch, 
        bool won, 
        uint256 rewardAmount,
        uint256 randomValue
    );
    
    event YieldAdded(
        address indexed asset, 
        uint256 amount, 
        uint256 epoch,
        address indexed contributor
    );
    
    event RiskLevelChanged(
        address indexed user, 
        RiskLevel oldLevel, 
        RiskLevel newLevel
    );
    
    // ====================================================================
    // CONSTRUCTOR
    // ====================================================================
    
    constructor(address _vault) {
        require(_vault != address(0), "Invalid vault");
        
        vault = _vault;
        cadenceVRF = ICadenceArchVRF(CADENCE_ARCH_VRF);
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(VAULT_ROLE, _vault);
        _grantRole(YIELD_MANAGER_ROLE, msg.sender);
        
        // Initialize first epoch
        currentEpoch = 1;
        lastEpochStart = block.timestamp;
        
        // Initialize risk configurations
        riskMultipliers[RiskLevel.LOW] = 5000;      // 0.5x multiplier
        riskMultipliers[RiskLevel.MEDIUM] = 10000;  // 1.0x multiplier  
        riskMultipliers[RiskLevel.HIGH] = 20000;    // 2.0x multiplier
        
        baseProbabilities[RiskLevel.LOW] = 3000;    // 30% base probability
        baseProbabilities[RiskLevel.MEDIUM] = 2000; // 20% base probability
        baseProbabilities[RiskLevel.HIGH] = 1000;   // 10% base probability
        
        // Initialize epoch
        epochs[currentEpoch].epochNumber = currentEpoch;
        epochs[currentEpoch].startTime = block.timestamp;
        epochs[currentEpoch].endTime = block.timestamp + epochDuration;
    }
    
    // ====================================================================
    // MODIFIERS
    // ====================================================================
    
    modifier onlyVault() {
        require(hasRole(VAULT_ROLE, msg.sender), "Only vault can call");
        _;
    }
    
    modifier validAsset(address asset) {
        require(isSupportedAsset[asset], "Asset not supported");
        _;
    }
    
    // ====================================================================
    // DEPOSIT & WITHDRAWAL FUNCTIONS
    // ====================================================================
    
    /// @notice Record user deposit from vault
    function recordDeposit(
        address user, 
        address asset, 
        uint256 amount, 
        RiskLevel riskLevel
    ) external onlyVault validAsset(asset) nonReentrant {
        require(user != address(0), "Invalid user");
        require(amount > 0, "Amount must be positive");
        
        _advanceEpochIfNeeded();
        _updateTimeWeights(user);
        
        UserDeposit storage userDeposit = userDeposits[user];
        
        // Set risk level if first deposit or update if specified
        if (userDeposit.totalDeposited == 0) {
            userDeposit.firstDepositEpoch = currentEpoch;
            userDeposit.riskLevel = riskLevel;
        }
        
        userDeposit.totalDeposited += amount;
        userDeposit.currentBalance += amount;
        userDeposit.lastDepositEpoch = currentEpoch;
        userDeposit.lastUpdateEpoch = currentEpoch;
        
        // Update eligibility for future epochs (eligible from epoch+2)
        uint256 eligibilityEpoch = currentEpoch + 2;
        if (!epochs[eligibilityEpoch].eligibleUsers[user]) {
            epochs[eligibilityEpoch].eligibleUsers[user] = true;
            epochs[eligibilityEpoch].participantCount++;
        }
        
        emit UserDeposited(user, asset, amount, currentEpoch, riskLevel);
    }
    
    /// @notice Record user withdrawal (can only withdraw principal, not exceed total deposited)
    function recordWithdrawal(
        address user, 
        address asset, 
        uint256 amount
    ) external onlyVault validAsset(asset) nonReentrant returns (bool success) {
        require(user != address(0), "Invalid user");
        require(amount > 0, "Amount must be positive");
        
        _advanceEpochIfNeeded();
        _updateTimeWeights(user);
        
        UserDeposit storage userDeposit = userDeposits[user];
        
        // Can only withdraw up to total deposited (principal protection)
        require(amount <= userDeposit.currentBalance, "Insufficient balance");
        require(amount <= userDeposit.totalDeposited, "Cannot withdraw more than deposited");
        
        userDeposit.currentBalance -= amount;
        userDeposit.lastUpdateEpoch = currentEpoch;
        
        emit UserWithdrew(user, asset, amount, userDeposit.currentBalance);
        return true;
    }
    
    /// @notice Update user's time-weighted balance
    function _updateTimeWeights(address user) internal {
        UserDeposit storage userDeposit = userDeposits[user];
        
        if (userDeposit.currentBalance > 0 && userDeposit.lastUpdateEpoch < currentEpoch) {
            uint256 epochsPassed = currentEpoch - userDeposit.lastUpdateEpoch;
            userDeposit.timeWeightedBalance += userDeposit.currentBalance * epochsPassed * TIME_WEIGHT_MULTIPLIER;
        }
    }
    
    // ====================================================================
    // EPOCH MANAGEMENT
    // ====================================================================
    
    /// @notice Advance to next epoch if duration has passed
    function _advanceEpochIfNeeded() internal {
        if (block.timestamp >= lastEpochStart + epochDuration) {
            _advanceEpoch();
        }
    }
    
    /// @notice Manually advance epoch (admin function)
    function advanceEpoch() external onlyRole(ADMIN_ROLE) {
        _advanceEpoch();
    }
    
    function _advanceEpoch() internal {
        // Finalize current epoch
        epochs[currentEpoch].finalized = true;
        epochs[currentEpoch].endTime = block.timestamp;
        
        // Start new epoch
        currentEpoch++;
        lastEpochStart = block.timestamp;
        
        epochs[currentEpoch].epochNumber = currentEpoch;
        epochs[currentEpoch].startTime = block.timestamp;
        epochs[currentEpoch].endTime = block.timestamp + epochDuration;
        epochs[currentEpoch].totalYieldPool = totalYieldPool;
        
        emit EpochAdvanced(currentEpoch, block.timestamp, totalYieldPool);
    }
    
    // ====================================================================
    // REWARD CLAIMING WITH VRF
    // ====================================================================
    
    /// @notice Claim rewards for a specific epoch using VRF
    function claimEpochReward(uint256 epochNumber) external nonReentrant returns (bool won, uint256 rewardAmount) {
        require(epochNumber < currentEpoch, "Epoch not completed");
        require(epochNumber >= 1, "Invalid epoch");
        require(!userDeposits[msg.sender].epochClaimed[epochNumber], "Already claimed");
        require(isEligibleForEpoch(msg.sender, epochNumber), "Not eligible for epoch");
        
        // Mark as claimed first to prevent reentrancy
        userDeposits[msg.sender].epochClaimed[epochNumber] = true;
        
        // Calculate reward parameters
        RewardCalculation memory calc = calculateRewardParameters(msg.sender, epochNumber);
        
        // Generate VRF randomness
        uint256 randomValue = cadenceVRF.revertibleRandom();
        uint256 normalizedRandom = randomValue % BASIS_POINTS;
        
        // Determine if user wins based on probability
        won = normalizedRandom < calc.winProbability;
        
        if (won && calc.potentialPayout > 0) {
            // Ensure we don't exceed available yield pool
            uint256 availableYield = epochs[epochNumber].totalYieldPool - epochs[epochNumber].totalDistributed;
            rewardAmount = calc.potentialPayout > availableYield ? availableYield : calc.potentialPayout;
            
            if (rewardAmount > 0) {
                epochs[epochNumber].totalDistributed += rewardAmount;
                totalDistributedRewards += rewardAmount;
                totalYieldPool -= rewardAmount;
                
                // Transfer reward to user (handled by vault)
                // This will be called back to vault to execute transfer
            }
        }
        
        emit RewardClaimed(msg.sender, epochNumber, won, rewardAmount, randomValue);
        return (won, rewardAmount);
    }
    
    /// @notice Calculate reward parameters for a user in an epoch
    function calculateRewardParameters(
        address user, 
        uint256 epochNumber
    ) public view returns (RewardCalculation memory calc) {
        UserDeposit storage userDeposit = userDeposits[user];
        EpochData storage epoch = epochs[epochNumber];
        
        // Base weight from deposit amount
        calc.baseWeight = userDeposit.currentBalance;
        
        // Time weight based on how long funds have been in vault
        uint256 timeInVault = epochNumber > userDeposit.firstDepositEpoch ? 
            epochNumber - userDeposit.firstDepositEpoch : 0;
        calc.timeWeight = userDeposit.currentBalance * timeInVault * TIME_WEIGHT_MULTIPLIER;
        
        // Risk multiplier
        calc.riskMultiplier = riskMultipliers[userDeposit.riskLevel];
        
        // Total weight
        calc.totalWeight = (calc.baseWeight + calc.timeWeight) * calc.riskMultiplier / BASIS_POINTS;
        
        // Win probability (higher for lower risk, lower for higher risk)
        uint256 baseProbability = baseProbabilities[userDeposit.riskLevel];
        calc.winProbability = baseProbability + (calc.totalWeight / 1e18); // Adjust based on weight
        calc.winProbability = calc.winProbability > MAX_PROBABILITY ? MAX_PROBABILITY : calc.winProbability;
        
        // Potential payout (higher for higher risk)
        if (epoch.totalYieldPool > 0 && epoch.participantCount > 0) {
            uint256 baseShare = epoch.totalYieldPool / epoch.participantCount;
            calc.potentialPayout = baseShare * calc.riskMultiplier / BASIS_POINTS;
            
            // Apply weight bonus
            calc.potentialPayout = calc.potentialPayout * calc.totalWeight / (calc.baseWeight + 1);
        }
    }
    
    // ====================================================================
    // YIELD MANAGEMENT
    // ====================================================================
    
    /// @notice Add yield to the reward pool
    function addYield(address asset, uint256 amount) external onlyRole(YIELD_MANAGER_ROLE) validAsset(asset) {
        require(amount > 0, "Amount must be positive");
        
        totalYieldPool += amount;
        epochs[currentEpoch].totalYieldPool = totalYieldPool;
        
        emit YieldAdded(asset, amount, currentEpoch, msg.sender);
    }
    
    /// @notice Manual yield subsidy (for testing)
    function subsidizeYield(uint256 amount) external onlyRole(ADMIN_ROLE) {
        totalYieldPool += amount;
        epochs[currentEpoch].totalYieldPool = totalYieldPool;
        
        emit YieldAdded(address(0), amount, currentEpoch, msg.sender);
    }
    
    // ====================================================================
    // VIEW FUNCTIONS
    // ====================================================================
    
    /// @notice Check if user is eligible for epoch rewards
    function isEligibleForEpoch(address user, uint256 epochNumber) public view returns (bool) {
        UserDeposit storage userDeposit = userDeposits[user];
        
        // Must have deposited before epoch-1 (eligible from epoch+2 after deposit)
        if (userDeposit.firstDepositEpoch == 0 || userDeposit.firstDepositEpoch >= epochNumber - 1) {
            return false;
        }
        
        // Must have sufficient balance
        if (userDeposit.currentBalance < getMinimumBalance(user)) {
            return false;
        }
        
        return epochs[epochNumber].eligibleUsers[user];
    }
    
    /// @notice Check if user has claimed rewards for an epoch
    function hasClaimedEpoch(address user, uint256 epochNumber) external view returns (bool) {
        return userDeposits[user].epochClaimed[epochNumber];
    }
    
    /// @notice Get minimum balance required for user eligibility
    function getMinimumBalance(address user) public view returns (uint256) {
        // For now, return a default minimum - could be asset-specific
        return 1e18; // 1 token (18 decimals)
    }
    
    /// @notice Get user's current deposit information
    function getUserDeposit(address user) external view returns (
        uint256 totalDeposited,
        uint256 currentBalance,
        uint256 firstDepositEpoch,
        uint256 lastDepositEpoch,
        RiskLevel riskLevel,
        uint256 timeWeightedBalance
    ) {
        UserDeposit storage userDeposit = userDeposits[user];
        return (
            userDeposit.totalDeposited,
            userDeposit.currentBalance,
            userDeposit.firstDepositEpoch,
            userDeposit.lastDepositEpoch,
            userDeposit.riskLevel,
            userDeposit.timeWeightedBalance
        );
    }
    
    /// @notice Get epoch information
    function getEpochInfo(uint256 epochNumber) external view returns (
        uint256 startTime,
        uint256 endTime,
        uint256 totalYieldPool,
        uint256 totalDistributed,
        uint256 participantCount,
        bool finalized
    ) {
        EpochData storage epoch = epochs[epochNumber];
        return (
            epoch.startTime,
            epoch.endTime,
            epoch.totalYieldPool,
            epoch.totalDistributed,
            epoch.participantCount,
            epoch.finalized
        );
    }
    
    /// @notice Get current epoch status
    function getCurrentEpochStatus() external view returns (
        uint256 epochNumber,
        uint256 timeRemaining,
        uint256 yieldPool,
        uint256 participantCount
    ) {
        uint256 endTime = lastEpochStart + epochDuration;
        uint256 timeLeft = block.timestamp < endTime ? endTime - block.timestamp : 0;
        
        return (
            currentEpoch,
            timeLeft,
            epochs[currentEpoch].totalYieldPool,
            epochs[currentEpoch].participantCount
        );
    }
    
    // ====================================================================
    // ADMIN FUNCTIONS
    // ====================================================================
    
    /// @notice Set risk level for user
    function setUserRiskLevel(RiskLevel newRiskLevel) external {
        RiskLevel oldLevel = userDeposits[msg.sender].riskLevel;
        userDeposits[msg.sender].riskLevel = newRiskLevel;
        
        emit RiskLevelChanged(msg.sender, oldLevel, newRiskLevel);
    }
    
    /// @notice Add supported asset
    function addSupportedAsset(address asset, uint256 minimumBalance) external onlyRole(ADMIN_ROLE) {
        require(asset != address(0), "Invalid asset");
        require(!isSupportedAsset[asset], "Asset already supported");
        
        supportedAssets.push(asset);
        isSupportedAsset[asset] = true;
        minimumBalances[asset] = minimumBalance;
    }
    
    /// @notice Update epoch duration
    function setEpochDuration(uint256 newDuration) external onlyRole(ADMIN_ROLE) {
        require(newDuration >= 1 days && newDuration <= 30 days, "Invalid duration");
        epochDuration = newDuration;
    }
    
    /// @notice Update risk configurations
    function updateRiskConfig(
        RiskLevel riskLevel,
        uint256 multiplier,
        uint256 probability
    ) external onlyRole(ADMIN_ROLE) {
        require(multiplier <= 50000, "Multiplier too high"); // Max 5x
        require(probability <= MAX_PROBABILITY, "Probability too high");
        
        riskMultipliers[riskLevel] = multiplier;
        baseProbabilities[riskLevel] = probability;
    }
}