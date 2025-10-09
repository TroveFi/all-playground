// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title ICadenceArchVRF - Flow's Cadence Arch VRF precompile
interface ICadenceArchVRF {
    function revertibleRandom() external view returns (uint256 randomValue);
}

/// @title VaultExtension - VRF lottery rewards & epoch management
contract VaultExtension is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    // ====================================================================
    // ROLES & CONSTANTS
    // ====================================================================
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant YIELD_MANAGER_ROLE = keccak256("YIELD_MANAGER_ROLE");
    
    address public constant CADENCE_ARCH_VRF = 0x0000000000000000000000010000000000000001;
    
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant TIME_WEIGHT_MULTIPLIER = 100;
    
    // ====================================================================
    // ENUMS & STRUCTS
    // ====================================================================
    enum RiskLevel { CONSERVATIVE, NORMAL, AGGRESSIVE }
    
    // VRF Risk Multiplier Options
    struct RiskMultiplier {
        uint256 multiplier;      // e.g., 2 for 2x, 10 for 10x, 100 for 100x
        uint256 probability;     // e.g., 5000 for 50%, 1000 for 10%, 100 for 1%
    }
    
    struct UserDeposit {
        uint256 totalDeposited;
        uint256 currentBalance;
        uint256 firstDepositEpoch;
        uint256 lastDepositEpoch;
        RiskLevel riskLevel;
        uint256 timeWeightedBalance;
        uint256 lastUpdateEpoch;
        uint256 vrfMultiplier;        // User's chosen VRF multiplier (1-100)
        bool yieldEligible;           // For subsidized accounts
        mapping(uint256 => bool) epochClaimed;
    }
    
    struct EpochData {
        uint256 epochNumber;
        uint256 startTime;
        uint256 endTime;
        uint256 totalYieldPool;
        uint256 totalDistributed;
        uint256 participantCount;
        bool finalized;
        mapping(address => bool) eligibleUsers;
        mapping(address => uint256) userYieldShare; // Base yield per user
    }
    
    struct RewardCalculation {
        uint256 baseYield;            // User's share of yield pool
        uint256 vrfMultiplier;        // Their chosen multiplier
        uint256 winProbability;       // Chance of winning
        uint256 potentialPayout;      // What they get if they win
        bool won;                     // VRF result
        uint256 actualPayout;         // Final amount
    }
    
    // ====================================================================
    // STATE VARIABLES
    // ====================================================================
    ICadenceArchVRF public immutable cadenceVRF;
    address public vault;
    
    // Epoch management
    uint256 public currentEpoch;
    uint256 public epochDuration = 7 days;
    uint256 public lastEpochStart;
    uint256 public epochsPerPayout = 4; // Monthly = 4 weekly epochs
    
    // User data
    mapping(address => UserDeposit) public userDeposits;
    mapping(uint256 => EpochData) private epochs;
    
    // Yield pool management
    uint256 public totalYieldPool;
    uint256 public totalDistributedRewards;
    uint256 public subsidizedYieldPool; // From non-eligible users
    
    // Asset tracking
    mapping(address => uint256) public assetYieldPools;
    
    // Available VRF multipliers
    mapping(uint256 => RiskMultiplier) public vrfMultipliers;
    
    // ====================================================================
    // EVENTS
    // ====================================================================
    event UserDeposited(address indexed user, address indexed asset, uint256 amount, uint256 epoch, RiskLevel riskLevel);
    event UserWithdrew(address indexed user, address indexed asset, uint256 amount);
    event EpochAdvanced(uint256 indexed newEpoch, uint256 startTime, uint256 yieldPool);
    event RewardClaimed(address indexed user, uint256 indexed epoch, bool won, uint256 baseYield, uint256 actualPayout, uint256 multiplier);
    event YieldAdded(address indexed asset, uint256 amount, uint256 epoch);
    event VRFMultiplierSet(address indexed user, uint256 multiplier);
    event YieldEligibilityChanged(address indexed user, bool eligible);
    
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
        
        currentEpoch = 1;
        lastEpochStart = block.timestamp;
        
        epochs[currentEpoch].epochNumber = currentEpoch;
        epochs[currentEpoch].startTime = block.timestamp;
        epochs[currentEpoch].endTime = block.timestamp + epochDuration;
        
        _initializeVRFMultipliers();
    }
    
    // ====================================================================
    // INITIALIZATION
    // ====================================================================
    function _initializeVRFMultipliers() internal {
        // 1x with 100% probability (guaranteed)
        vrfMultipliers[1] = RiskMultiplier({multiplier: 1, probability: 10000});
        
        // 2x with 50% probability
        vrfMultipliers[2] = RiskMultiplier({multiplier: 2, probability: 5000});
        
        // 5x with 20% probability
        vrfMultipliers[5] = RiskMultiplier({multiplier: 5, probability: 2000});
        
        // 10x with 10% probability
        vrfMultipliers[10] = RiskMultiplier({multiplier: 10, probability: 1000});
        
        // 50x with 2% probability
        vrfMultipliers[50] = RiskMultiplier({multiplier: 50, probability: 200});
        
        // 100x with 1% probability
        vrfMultipliers[100] = RiskMultiplier({multiplier: 100, probability: 100});
    }
    
    // ====================================================================
    // MODIFIERS
    // ====================================================================
    modifier onlyVault() {
        require(hasRole(VAULT_ROLE, msg.sender), "Only vault");
        _;
    }
    
    // ====================================================================
    // DEPOSIT & WITHDRAWAL
    // ====================================================================
    function recordDeposit(
        address user,
        address asset,
        uint256 amount,
        RiskLevel riskLevel
    ) external onlyVault nonReentrant {
        require(user != address(0), "Invalid user");
        require(amount > 0, "Amount must be positive");
        
        _advanceEpochIfNeeded();
        _updateTimeWeights(user);
        
        UserDeposit storage userDeposit = userDeposits[user];
        
        if (userDeposit.totalDeposited == 0) {
            userDeposit.firstDepositEpoch = currentEpoch;
            userDeposit.riskLevel = riskLevel;
            userDeposit.vrfMultiplier = 1; // Default to 1x (guaranteed)
            userDeposit.yieldEligible = true;
        }
        
        userDeposit.totalDeposited += amount;
        userDeposit.currentBalance += amount;
        userDeposit.lastDepositEpoch = currentEpoch;
        userDeposit.lastUpdateEpoch = currentEpoch;
        
        // Make eligible for next payout (4 epochs from now)
        uint256 eligibilityEpoch = currentEpoch + epochsPerPayout;
        if (!epochs[eligibilityEpoch].eligibleUsers[user]) {
            epochs[eligibilityEpoch].eligibleUsers[user] = true;
            epochs[eligibilityEpoch].participantCount++;
        }
        
        emit UserDeposited(user, asset, amount, currentEpoch, riskLevel);
    }
    
    function recordWithdrawal(
        address user,
        address asset,
        uint256 amount
    ) external onlyVault nonReentrant returns (bool) {
        require(user != address(0), "Invalid user");
        require(amount > 0, "Amount must be positive");
        
        _advanceEpochIfNeeded();
        _updateTimeWeights(user);
        
        UserDeposit storage userDeposit = userDeposits[user];
        require(amount <= userDeposit.currentBalance, "Insufficient balance");
        
        userDeposit.currentBalance -= amount;
        userDeposit.lastUpdateEpoch = currentEpoch;
        
        emit UserWithdrew(user, asset, amount);
        return true;
    }
    
    function _updateTimeWeights(address user) internal {
        UserDeposit storage userDeposit = userDeposits[user];
        
        if (userDeposit.currentBalance > 0 && userDeposit.lastUpdateEpoch < currentEpoch) {
            uint256 epochsPassed = currentEpoch - userDeposit.lastUpdateEpoch;
            userDeposit.timeWeightedBalance += userDeposit.currentBalance * epochsPassed * TIME_WEIGHT_MULTIPLIER;
        }
    }
    
    // ====================================================================
    // VRF MULTIPLIER SETTINGS
    // ====================================================================
    function setVRFMultiplier(uint256 multiplier) external {
        require(userDeposits[msg.sender].totalDeposited > 0, "No deposit");
        require(vrfMultipliers[multiplier].multiplier > 0, "Invalid multiplier");
        
        userDeposits[msg.sender].vrfMultiplier = multiplier;
        emit VRFMultiplierSet(msg.sender, multiplier);
    }
    
    function getAvailableMultipliers() external view returns (
        uint256[] memory multipliers,
        uint256[] memory probabilities
    ) {
        uint256[] memory mults = new uint256[](6);
        uint256[] memory probs = new uint256[](6);
        
        mults[0] = 1; probs[0] = vrfMultipliers[1].probability;
        mults[1] = 2; probs[1] = vrfMultipliers[2].probability;
        mults[2] = 5; probs[2] = vrfMultipliers[5].probability;
        mults[3] = 10; probs[3] = vrfMultipliers[10].probability;
        mults[4] = 50; probs[4] = vrfMultipliers[50].probability;
        mults[5] = 100; probs[5] = vrfMultipliers[100].probability;
        
        return (mults, probs);
    }
    
    // ====================================================================
    // EPOCH MANAGEMENT
    // ====================================================================
    function _advanceEpochIfNeeded() internal {
        if (block.timestamp >= lastEpochStart + epochDuration) {
            _advanceEpoch();
        }
    }
    
    function advanceEpoch() external onlyRole(ADMIN_ROLE) {
        _advanceEpoch();
    }
    
    function _advanceEpoch() internal {
        epochs[currentEpoch].finalized = true;
        epochs[currentEpoch].endTime = block.timestamp;
        
        currentEpoch++;
        lastEpochStart = block.timestamp;
        
        epochs[currentEpoch].epochNumber = currentEpoch;
        epochs[currentEpoch].startTime = block.timestamp;
        epochs[currentEpoch].endTime = block.timestamp + epochDuration;
        epochs[currentEpoch].totalYieldPool = totalYieldPool;
        
        emit EpochAdvanced(currentEpoch, block.timestamp, totalYieldPool);
    }
    
    // ====================================================================
    // YIELD MANAGEMENT
    // ====================================================================
    function addYield(address asset, uint256 amount) external onlyRole(YIELD_MANAGER_ROLE) {
        require(amount > 0, "Amount must be positive");
        
        totalYieldPool += amount;
        assetYieldPools[asset] += amount;
        epochs[currentEpoch].totalYieldPool = totalYieldPool;
        
        emit YieldAdded(asset, amount, currentEpoch);
    }
    
    function subsidizeYield(uint256 amount) external onlyRole(ADMIN_ROLE) {
        totalYieldPool += amount;
        subsidizedYieldPool += amount;
        epochs[currentEpoch].totalYieldPool = totalYieldPool;
        
        emit YieldAdded(address(0), amount, currentEpoch);
    }
    
    function setYieldEligibility(address user, bool eligible) external onlyRole(ADMIN_ROLE) {
        UserDeposit storage userDeposit = userDeposits[user];
        bool wasEligible = userDeposit.yieldEligible;
        userDeposit.yieldEligible = eligible;
        
        // If removing eligibility, add their would-be yield to subsidized pool
        if (wasEligible && !eligible && userDeposit.currentBalance > 0) {
            // Their yield will be redistributed in reward calculations
        }
        
        emit YieldEligibilityChanged(user, eligible);
    }
    
    // ====================================================================
    // REWARD CLAIMING WITH VRF
    // ====================================================================
    function claimEpochReward(address user, uint256 epochNumber) 
        external 
        onlyVault 
        nonReentrant 
        returns (bool won, uint256 rewardAmount) 
    {
        require(epochNumber < currentEpoch, "Epoch not completed");
        require(epochNumber % epochsPerPayout == 0, "Not a payout epoch");
        require(!userDeposits[user].epochClaimed[epochNumber], "Already claimed");
        require(isEligibleForEpoch(user, epochNumber), "Not eligible");
        require(userDeposits[user].yieldEligible, "Not yield eligible");
        
        userDeposits[user].epochClaimed[epochNumber] = true;
        
        RewardCalculation memory calc = _calculateReward(user, epochNumber);
        
        // Use VRF to determine if they won
        uint256 randomValue = cadenceVRF.revertibleRandom();
        uint256 normalizedRandom = randomValue % BASIS_POINTS;
        
        won = normalizedRandom < calc.winProbability;
        
        if (won) {
            rewardAmount = calc.potentialPayout;
            
            uint256 availableYield = epochs[epochNumber].totalYieldPool - epochs[epochNumber].totalDistributed;
            if (rewardAmount > availableYield) {
                rewardAmount = availableYield;
            }
            
            if (rewardAmount > 0) {
                epochs[epochNumber].totalDistributed += rewardAmount;
                totalDistributedRewards += rewardAmount;
                totalYieldPool -= rewardAmount;
            }
        } else {
            rewardAmount = 0;
        }
        
        emit RewardClaimed(user, epochNumber, won, calc.baseYield, rewardAmount, calc.vrfMultiplier);
        return (won, rewardAmount);
    }
    
    function _calculateReward(address user, uint256 epochNumber) 
        internal 
        view 
        returns (RewardCalculation memory calc) 
    {
        UserDeposit storage userDeposit = userDeposits[user];
        EpochData storage epoch = epochs[epochNumber];
        
        // Calculate user's base yield share (time-weighted)
        uint256 totalEligibleBalance = 0;
        // In production, would iterate through all eligible users
        // For now, simplified to user's proportion
        
        calc.baseYield = userDeposit.currentBalance > 0 && epoch.totalYieldPool > 0
            ? (epoch.totalYieldPool * userDeposit.currentBalance) / (totalEligibleBalance + userDeposit.currentBalance)
            : 0;
        
        // Apply VRF multiplier
        calc.vrfMultiplier = userDeposit.vrfMultiplier;
        RiskMultiplier memory multiplier = vrfMultipliers[calc.vrfMultiplier];
        
        calc.winProbability = multiplier.probability;
        calc.potentialPayout = calc.baseYield * multiplier.multiplier;
        
        return calc;
    }
    
    function calculateUserReward(address user, uint256 epochNumber) 
        external 
        view 
        returns (
            uint256 baseYield,
            uint256 vrfMultiplier,
            uint256 winProbability,
            uint256 potentialPayout
        ) 
    {
        RewardCalculation memory calc = _calculateReward(user, epochNumber);
        return (calc.baseYield, calc.vrfMultiplier, calc.winProbability, calc.potentialPayout);
    }
    
    // ====================================================================
    // VIEW FUNCTIONS
    // ====================================================================
    function isEligibleForEpoch(address user, uint256 epochNumber) public view returns (bool) {
        UserDeposit storage userDeposit = userDeposits[user];
        
        if (userDeposit.firstDepositEpoch == 0) {
            return false;
        }
        
        // Must have deposited at least epochsPerPayout epochs ago
        if (userDeposit.firstDepositEpoch + epochsPerPayout > epochNumber) {
            return false;
        }
        
        if (userDeposit.currentBalance == 0) {
            return false;
        }
        
        return epochs[epochNumber].eligibleUsers[user];
    }
    
    function getUserDeposit(address user) external view returns (
        uint256 totalDeposited,
        uint256 currentBalance,
        uint256 firstDepositEpoch,
        uint256 lastDepositEpoch,
        RiskLevel riskLevel,
        uint256 vrfMultiplier,
        bool yieldEligible
    ) {
        UserDeposit storage userDeposit = userDeposits[user];
        return (
            userDeposit.totalDeposited,
            userDeposit.currentBalance,
            userDeposit.firstDepositEpoch,
            userDeposit.lastDepositEpoch,
            userDeposit.riskLevel,
            userDeposit.vrfMultiplier,
            userDeposit.yieldEligible
        );
    }
    
    function getUserEpochStatus(address user) external view returns (
        bool eligibleForCurrentEpoch,
        uint256 currentEpoch_,
        uint256 timeRemaining,
        bool hasUnclaimedRewards,
        RiskLevel riskLevel
    ) {
        currentEpoch_ = currentEpoch;
        uint256 endTime = lastEpochStart + epochDuration;
        timeRemaining = block.timestamp < endTime ? endTime - block.timestamp : 0;
        
        eligibleForCurrentEpoch = isEligibleForEpoch(user, currentEpoch_);
        
        // Check for unclaimed rewards in past payout epochs
        hasUnclaimedRewards = false;
        for (uint256 i = epochsPerPayout; i < currentEpoch_; i += epochsPerPayout) {
            if (isEligibleForEpoch(user, i) && !userDeposits[user].epochClaimed[i]) {
                hasUnclaimedRewards = true;
                break;
            }
        }
        
        riskLevel = userDeposits[user].riskLevel;
    }
    
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
    
    function getClaimableEpochs(address user) external view returns (uint256[] memory) {
        uint256[] memory tempEpochs = new uint256[](currentEpoch / epochsPerPayout);
        uint256 count = 0;
        
        for (uint256 i = epochsPerPayout; i < currentEpoch; i += epochsPerPayout) {
            if (isEligibleForEpoch(user, i) && !userDeposits[user].epochClaimed[i]) {
                tempEpochs[count] = i;
                count++;
            }
        }
        
        uint256[] memory claimableEpochs = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            claimableEpochs[i] = tempEpochs[i];
        }
        
        return claimableEpochs;
    }
    
    // ====================================================================
    // ADMIN FUNCTIONS
    // ====================================================================
    function setEpochDuration(uint256 newDuration) external onlyRole(ADMIN_ROLE) {
        require(newDuration >= 1 days && newDuration <= 30 days, "Invalid duration");
        epochDuration = newDuration;
    }
    
    function setEpochsPerPayout(uint256 _epochsPerPayout) external onlyRole(ADMIN_ROLE) {
        require(_epochsPerPayout > 0 && _epochsPerPayout <= 12, "Invalid epochs per payout");
        epochsPerPayout = _epochsPerPayout;
    }
    
    function setVault(address _vault) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_vault != address(0), "Invalid vault");
        _revokeRole(VAULT_ROLE, vault);
        _grantRole(VAULT_ROLE, _vault);
        vault = _vault;
    }
    
    function processEpochRewards() external onlyRole(ADMIN_ROLE) {
        // Placeholder for batch processing if needed
        _advanceEpochIfNeeded();
    }
}