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

/// @title VaultExtension - Epoch-based rewards extension for TrueMultiAssetVault
/// @notice Handles VRF-powered lottery rewards, risk levels, and epoch management
contract VaultExtension is AccessControl, ReentrancyGuard {
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
        uint256 totalDeposited;           
        uint256 currentBalance;           
        uint256 firstDepositEpoch;        
        uint256 lastDepositEpoch;         
        RiskLevel riskLevel;              
        uint256 timeWeightedBalance;      
        uint256 lastUpdateEpoch;          
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
    }
    
    struct RewardCalculation {
        uint256 baseWeight;               
        uint256 timeWeight;               
        uint256 riskMultiplier;           
        uint256 totalWeight;              
        uint256 winProbability;           
        uint256 potentialPayout;          
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
    
    // User data
    mapping(address => UserDeposit) public userDeposits;
    mapping(uint256 => EpochData) public epochs;
    
    // Yield pool management
    uint256 public totalYieldPool;
    uint256 public totalDistributedRewards;
    
    // Risk level configurations
    mapping(RiskLevel => uint256) public riskMultipliers;
    mapping(RiskLevel => uint256) public baseProbabilities;
    
    // Asset tracking
    address[] public supportedAssets;
    mapping(address => bool) public isSupportedAsset;
    mapping(address => uint256) public minimumBalances;
    
    // Constants
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MAX_PROBABILITY = 5000;
    uint256 public constant TIME_WEIGHT_MULTIPLIER = 100;
    
    // ====================================================================
    // EVENTS
    // ====================================================================
    
    event UserDeposited(address indexed user, address indexed asset, uint256 amount, uint256 epoch, RiskLevel riskLevel);
    event UserWithdrew(address indexed user, address indexed asset, uint256 amount, uint256 remainingBalance);
    event EpochAdvanced(uint256 indexed newEpoch, uint256 startTime, uint256 yieldPool);
    event RewardClaimed(address indexed user, uint256 indexed epoch, bool won, uint256 rewardAmount, uint256 randomValue);
    event YieldAdded(address indexed asset, uint256 amount, uint256 epoch, address indexed contributor);
    event RiskLevelChanged(address indexed user, RiskLevel oldLevel, RiskLevel newLevel);
    
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
        
        // Add default supported assets
        _addSupportedAsset(0x2aaBea2058b5aC2D339b163C6Ab6f2b6d53aabED, 1e6);  // USDF
        _addSupportedAsset(0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e, 1e18); // WFLOW
        _addSupportedAsset(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, 1e18); // NATIVE_FLOW
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
        
        require(amount <= userDeposit.currentBalance, "Insufficient balance");
        require(amount <= userDeposit.totalDeposited, "Cannot withdraw more than deposited");
        
        userDeposit.currentBalance -= amount;
        userDeposit.lastUpdateEpoch = currentEpoch;
        
        emit UserWithdrew(user, asset, amount, userDeposit.currentBalance);
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
    // REWARD CLAIMING WITH VRF
    // ====================================================================
    
    function claimEpochReward(address user, uint256 epochNumber) external onlyVault nonReentrant returns (bool won, uint256 rewardAmount) {
        require(epochNumber < currentEpoch, "Epoch not completed");
        require(epochNumber >= 1, "Invalid epoch");
        require(!userDeposits[user].epochClaimed[epochNumber], "Already claimed");
        require(isEligibleForEpoch(user, epochNumber), "Not eligible for epoch");
        
        userDeposits[user].epochClaimed[epochNumber] = true;
        
        RewardCalculation memory calc = calculateRewardParameters(user, epochNumber);
        
        uint256 randomValue = cadenceVRF.revertibleRandom();
        uint256 normalizedRandom = randomValue % BASIS_POINTS;
        
        won = normalizedRandom < calc.winProbability;
        
        if (won && calc.potentialPayout > 0) {
            uint256 availableYield = epochs[epochNumber].totalYieldPool - epochs[epochNumber].totalDistributed;
            rewardAmount = calc.potentialPayout > availableYield ? availableYield : calc.potentialPayout;
            
            if (rewardAmount > 0) {
                epochs[epochNumber].totalDistributed += rewardAmount;
                totalDistributedRewards += rewardAmount;
                totalYieldPool -= rewardAmount;
            }
        }
        
        emit RewardClaimed(user, epochNumber, won, rewardAmount, randomValue);
        return (won, rewardAmount);
    }
    
    function calculateRewardParameters(
        address user, 
        uint256 epochNumber
    ) public view returns (RewardCalculation memory calc) {
        UserDeposit storage userDeposit = userDeposits[user];
        EpochData storage epoch = epochs[epochNumber];
        
        calc.baseWeight = userDeposit.currentBalance;
        
        uint256 timeInVault = epochNumber > userDeposit.firstDepositEpoch ? 
            epochNumber - userDeposit.firstDepositEpoch : 0;
        calc.timeWeight = userDeposit.currentBalance * timeInVault * TIME_WEIGHT_MULTIPLIER;
        
        calc.riskMultiplier = riskMultipliers[userDeposit.riskLevel];
        calc.totalWeight = (calc.baseWeight + calc.timeWeight) * calc.riskMultiplier / BASIS_POINTS;
        
        uint256 baseProbability = baseProbabilities[userDeposit.riskLevel];
        calc.winProbability = baseProbability + (calc.totalWeight / 1e18);
        calc.winProbability = calc.winProbability > MAX_PROBABILITY ? MAX_PROBABILITY : calc.winProbability;
        
        if (epoch.totalYieldPool > 0 && epoch.participantCount > 0) {
            uint256 baseShare = epoch.totalYieldPool / epoch.participantCount;
            calc.potentialPayout = baseShare * calc.riskMultiplier / BASIS_POINTS;
            calc.potentialPayout = calc.potentialPayout * calc.totalWeight / (calc.baseWeight + 1);
        }
    }
    
    // ====================================================================
    // YIELD MANAGEMENT
    // ====================================================================
    
    function addYield(address asset, uint256 amount) external onlyRole(YIELD_MANAGER_ROLE) validAsset(asset) {
        require(amount > 0, "Amount must be positive");
        
        totalYieldPool += amount;
        epochs[currentEpoch].totalYieldPool = totalYieldPool;
        
        emit YieldAdded(asset, amount, currentEpoch, msg.sender);
    }
    
    function subsidizeYield(uint256 amount) external onlyRole(ADMIN_ROLE) {
        totalYieldPool += amount;
        epochs[currentEpoch].totalYieldPool = totalYieldPool;
        
        emit YieldAdded(address(0), amount, currentEpoch, msg.sender);
    }
    
    // ====================================================================
    // RISK LEVEL MANAGEMENT
    // ====================================================================
    
    function updateUserRiskLevel(address user, RiskLevel newRiskLevel) external onlyVault {
        RiskLevel oldLevel = userDeposits[user].riskLevel;
        userDeposits[user].riskLevel = newRiskLevel;
        
        emit RiskLevelChanged(user, oldLevel, newRiskLevel);
    }
    
    function setUserRiskLevel(RiskLevel newRiskLevel) external {
        // This is called directly by users through the vault
        RiskLevel oldLevel = userDeposits[msg.sender].riskLevel;
        userDeposits[msg.sender].riskLevel = newRiskLevel;
        
        emit RiskLevelChanged(msg.sender, oldLevel, newRiskLevel);
    }
    
    // ====================================================================
    // VIEW FUNCTIONS
    // ====================================================================
    
    function isEligibleForEpoch(address user, uint256 epochNumber) public view returns (bool) {
        UserDeposit storage userDeposit = userDeposits[user];
        
        if (userDeposit.firstDepositEpoch == 0 || userDeposit.firstDepositEpoch >= epochNumber - 1) {
            return false;
        }
        
        if (userDeposit.currentBalance < getMinimumBalance(user)) {
            return false;
        }
        
        return epochs[epochNumber].eligibleUsers[user];
    }
    
    function hasClaimedEpoch(address user, uint256 epochNumber) external view returns (bool) {
        return userDeposits[user].epochClaimed[epochNumber];
    }
    
    function getMinimumBalance(address user) public view returns (uint256) {
        return 1e18; // 1 token (18 decimals)
    }
    
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
    
    // ====================================================================
    // VAULT INTERFACE FUNCTIONS
    // ====================================================================
    
    function getUserEpochStatus(address user) external view returns (
        bool eligibleForCurrentEpoch,
        uint256 currentEpoch_,
        uint256 timeRemaining,
        bool hasUnclaimedRewards,
        RiskLevel riskLevel
    ) {
        (currentEpoch_, timeRemaining, , ) = this.getCurrentEpochStatus();
        eligibleForCurrentEpoch = isEligibleForEpoch(user, currentEpoch_);
        
        hasUnclaimedRewards = false;
        for (uint256 i = 1; i < currentEpoch_; i++) {
            if (isEligibleForEpoch(user, i) && !userDeposits[user].epochClaimed[i]) {
                hasUnclaimedRewards = true;
                break;
            }
        }
        
        riskLevel = userDeposits[user].riskLevel;
    }
    
    function getClaimableEpochs(address user) external view returns (uint256[] memory claimableEpochs) {
        uint256[] memory tempEpochs = new uint256[](currentEpoch);
        uint256 count = 0;
        
        for (uint256 i = 1; i < currentEpoch; i++) {
            if (isEligibleForEpoch(user, i) && !userDeposits[user].epochClaimed[i]) {
                tempEpochs[count] = i;
                count++;
            }
        }
        
        claimableEpochs = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            claimableEpochs[i] = tempEpochs[i];
        }
    }
    
    function getUserRewardParameters(address user, uint256 epochNumber) external view returns (
        uint256 baseWeight,
        uint256 timeWeight,
        uint256 riskMultiplier,
        uint256 totalWeight,
        uint256 winProbability,
        uint256 potentialPayout
    ) {
        RewardCalculation memory calc = calculateRewardParameters(user, epochNumber);
        return (
            calc.baseWeight,
            calc.timeWeight,
            calc.riskMultiplier,
            calc.totalWeight,
            calc.winProbability,
            calc.potentialPayout
        );
    }
    
    // ====================================================================
    // ADMIN FUNCTIONS
    // ====================================================================
    
    function _addSupportedAsset(address asset, uint256 minimumBalance) internal {
        supportedAssets.push(asset);
        isSupportedAsset[asset] = true;
        minimumBalances[asset] = minimumBalance;
    }
    
    function addSupportedAsset(address asset, uint256 minimumBalance) external onlyRole(ADMIN_ROLE) {
        require(asset != address(0), "Invalid asset");
        require(!isSupportedAsset[asset], "Asset already supported");
        
        _addSupportedAsset(asset, minimumBalance);
    }
    
    function setEpochDuration(uint256 newDuration) external onlyRole(ADMIN_ROLE) {
        require(newDuration >= 1 days && newDuration <= 30 days, "Invalid duration");
        epochDuration = newDuration;
    }
    
    function updateRiskConfig(
        RiskLevel riskLevel,
        uint256 multiplier,
        uint256 probability
    ) external onlyRole(ADMIN_ROLE) {
        require(multiplier <= 50000, "Multiplier too high");
        require(probability <= MAX_PROBABILITY, "Probability too high");
        
        riskMultipliers[riskLevel] = multiplier;
        baseProbabilities[riskLevel] = probability;
    }
    
    function setVault(address _vault) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_vault != address(0), "Invalid vault");
        _revokeRole(VAULT_ROLE, vault);
        _grantRole(VAULT_ROLE, _vault);
        vault = _vault;
    }
}