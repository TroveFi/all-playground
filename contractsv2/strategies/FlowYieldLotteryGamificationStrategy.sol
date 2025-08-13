// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./BaseStrategy.sol";

// Flow VRF interface for true randomness
interface IFlowVRF {
    function requestRandomness(bytes32 keyHash, uint256 fee) external returns (bytes32 requestId);
    function fulfillRandomness(bytes32 requestId, uint256 randomness) external;
    function getRandomSeed() external view returns (uint256);
    function isRequestComplete(bytes32 requestId) external view returns (bool);
}

// Achievement and milestone system
interface IAchievementSystem {
    struct Achievement {
        bytes32 achievementId;
        string name;
        string description;
        uint256 rewardAmount;
        uint256 rewardMultiplier;
        bool isClaimed;
        uint256 unlockedAt;
    }

    function unlockAchievement(address user, bytes32 achievementId) external;
    function claimAchievementReward(bytes32 achievementId) external returns (uint256 reward);
    function getUserAchievements(address user) external view returns (Achievement[] memory);
    function checkMilestone(address user, uint256 amount, uint256 duration) external;
}

// Social features interface
interface ISocialFeatures {
    function createGroup(string calldata name, uint256 minStake) external returns (bytes32 groupId);
    function joinGroup(bytes32 groupId) external;
    function getGroupMultiplier(bytes32 groupId) external view returns (uint256);
    function getReferralBonus(address referrer, address referee) external view returns (uint256);
    function updateGroupPerformance(bytes32 groupId, uint256 totalYield) external;
}

/// @title FlowYieldLotteryGamificationStrategy - Gamified Yield with Lottery System
/// @notice Revolutionary gamified yield farming with lotteries, achievements, and social features
contract FlowYieldLotteryGamificationStrategy is BaseStrategy, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // VRF and gamification addresses
    address public constant FLOW_VRF = address(0); // Flow VRF coordinator
    address public constant ACHIEVEMENT_SYSTEM = address(0); // Achievement contract
    address public constant SOCIAL_FEATURES = address(0); // Social features contract

    IFlowVRF public immutable flowVRF;
    IAchievementSystem public immutable achievementSystem;
    ISocialFeatures public immutable socialFeatures;

    // Lottery system
    struct LotteryRound {
        uint256 roundId;
        uint256 startTime;
        uint256 endTime;
        uint256 totalPrizePool;
        uint256 totalEntries;
        uint256 entryFee;
        address[] participants;
        mapping(address => uint256) userEntries;
        mapping(address => uint256) userWeights; // Based on stake amount and duration
        bool drawn;
        address[] winners;
        uint256[] winnerAmounts;
        bytes32 vrfRequestId;
        LotteryType lotteryType;
    }

    enum LotteryType {
        WEEKLY_MEGA,     // Weekly big lottery
        DAILY_BOOST,     // Daily smaller lottery
        FLASH_LOTTERY,   // Short-term high-frequency
        MILESTONE_BONUS, // Triggered by milestones
        SOCIAL_GROUP,    // Group-based lottery
        ACHIEVEMENT_UNLOCK // Achievement-based lottery
    }

    struct UserGameStats {
        uint256 totalStaked;
        uint256 stakingStartTime;
        uint256 totalYieldEarned;
        uint256 lotteryEntriesTotal;
        uint256 lotteryWinningsTotal;
        uint256 achievementsUnlocked;
        uint256 referralsCount;
        uint256 currentStreak; // Consecutive days staked
        uint256 longestStreak;
        uint256 multiplierLevel; // User's multiplier level
        bytes32 currentGroup; // Social group membership
        address referrer;
        uint256 lastActivityTime;
    }

    struct YieldMultiplier {
        uint256 baseMultiplier; // 10000 = 1x
        uint256 loyaltyBonus; // Based on staking duration
        uint256 volumeBonus; // Based on staking amount
        uint256 socialBonus; // Based on group participation
        uint256 achievementBonus; // Based on achievements
        uint256 lotteryBonus; // Based on lottery participation
        uint256 streakBonus; // Based on daily activity streak
        uint256 totalMultiplier; // Combined multiplier
    }

    struct GameConfig {
        uint256 weeklyLotteryFee; // Entry fee for weekly lottery
        uint256 dailyLotteryFee; // Entry fee for daily lottery
        uint256 lotteryPoolPercentage; // % of yield that goes to lottery pool
        uint256 maxMultiplier; // Maximum total multiplier allowed
        uint256 streakBonusRate; // Bonus per day of streak
        uint256 loyaltyBonusRate; // Bonus per day of staking
        uint256 achievementMultiplier; // Multiplier per achievement
        bool enableSocialFeatures; // Enable group features
        bool enableLotterySystem; // Enable lottery system
        bool enableAchievements; // Enable achievement system
    }

    // State variables
    mapping(uint256 => LotteryRound) public lotteryRounds;
    mapping(address => UserGameStats) public userStats;
    mapping(address => YieldMultiplier) public userMultipliers;
    mapping(bytes32 => uint256) public vrfRequestToRound;
    
    uint256 public currentRoundId;
    uint256 public totalLotteryPool;
    uint256 public totalPlayersEver;
    uint256 public totalLotteryWinnings;
    
    GameConfig public gameConfig;
    
    // Lottery pools by type
    mapping(LotteryType => uint256) public lotteryPools;
    mapping(LotteryType => uint256) public lastLotteryTime;
    
    // Special events
    uint256 public yieldBoostEventEnd;
    uint256 public currentYieldBoostMultiplier = 10000; // 1x default
    
    // Achievement tracking
    mapping(address => mapping(bytes32 => bool)) public userAchievements;
    mapping(bytes32 => uint256) public achievementRewards;

    // Events
    event LotteryRoundStarted(uint256 indexed roundId, LotteryType lotteryType, uint256 prizePool);
    event LotteryEntryPurchased(address indexed user, uint256 indexed roundId, uint256 entries, uint256 weight);
    event LotteryDrawn(uint256 indexed roundId, address[] winners, uint256[] amounts);
    event YieldMultiplierUpdated(address indexed user, uint256 oldMultiplier, uint256 newMultiplier);
    event AchievementUnlocked(address indexed user, bytes32 indexed achievementId, uint256 reward);
    event StreakBonusEarned(address indexed user, uint256 streak, uint256 bonus);
    event SocialGroupJoined(address indexed user, bytes32 indexed groupId, uint256 bonus);
    event YieldBoostEventStarted(uint256 multiplier, uint256 duration);
    event FlashLotteryTriggered(uint256 prizeAmount, uint256 participants);

    constructor(
        address _asset,
        address _vault,
        string memory _name
    ) BaseStrategy(_asset, FLOW_VRF, _vault, _name) {
        flowVRF = IFlowVRF(FLOW_VRF);
        achievementSystem = IAchievementSystem(ACHIEVEMENT_SYSTEM);
        socialFeatures = ISocialFeatures(SOCIAL_FEATURES);
        
        // Initialize game configuration
        gameConfig = GameConfig({
            weeklyLotteryFee: 1 * 10**6, // 1 USDC
            dailyLotteryFee: 0.1 * 10**6, // 0.1 USDC
            lotteryPoolPercentage: 1000, // 10%
            maxMultiplier: 50000, // 5x max
            streakBonusRate: 50, // 0.5% per day
            loyaltyBonusRate: 10, // 0.1% per day
            achievementMultiplier: 500, // 5% per achievement
            enableSocialFeatures: true,
            enableLotterySystem: true,
            enableAchievements: true
        });
        
        _initializeAchievements();
        _startInitialLotteries();
    }

    function _initializeAchievements() internal {
        // Define achievement rewards
        achievementRewards[keccak256("FIRST_STAKE")] = 10 * 10**6; // 10 USDC
        achievementRewards[keccak256("WEEK_WARRIOR")] = 50 * 10**6; // 50 USDC
        achievementRewards[keccak256("MONTH_MASTER")] = 200 * 10**6; // 200 USDC
        achievementRewards[keccak256("YEAR_LEGEND")] = 1000 * 10**6; // 1000 USDC
        achievementRewards[keccak256("LOTTERY_WINNER")] = 25 * 10**6; // 25 USDC
        achievementRewards[keccak256("SOCIAL_BUTTERFLY")] = 30 * 10**6; // 30 USDC
        achievementRewards[keccak256("STREAK_MASTER")] = 100 * 10**6; // 100 USDC
        achievementRewards[keccak256("WHALE_STATUS")] = 500 * 10**6; // 500 USDC
    }

    function _startInitialLotteries() internal {
        _startLotteryRound(LotteryType.WEEKLY_MEGA);
        _startLotteryRound(LotteryType.DAILY_BOOST);
    }

    function _executeStrategy(uint256 amount, bytes calldata data) internal override {
        // Decode gamification parameters
        (bool joinLottery, bytes32 groupId, address referrer) = data.length > 0 
            ? abi.decode(data, (bool, bytes32, address))
            : (true, bytes32(0), address(0));

        // Initialize or update user stats
        _updateUserStats(msg.sender, amount, referrer);
        
        // Calculate and apply yield multipliers
        _calculateYieldMultipliers(msg.sender);
        
        // Handle lottery entries
        if (joinLottery && gameConfig.enableLotterySystem) {
            _handleLotteryEntries(msg.sender, amount);
        }
        
        // Handle social features
        if (groupId != bytes32(0) && gameConfig.enableSocialFeatures) {
            _handleSocialFeatures(msg.sender, groupId);
        }
        
        // Check achievements
        if (gameConfig.enableAchievements) {
            _checkAndUnlockAchievements(msg.sender, amount);
        }
        
        // Apply yield boost if active
        uint256 boostedAmount = _applyYieldBoost(amount, msg.sender);
        
        // Update player count
        if (userStats[msg.sender].totalStaked == 0) {
            totalPlayersEver++;
        }
        
        // Execute base yield farming with boosted amount
        _executeBaseYieldFarming(boostedAmount);
    }

    function _updateUserStats(address user, uint256 amount, address referrer) internal {
        UserGameStats storage stats = userStats[user];
        
        if (stats.stakingStartTime == 0) {
            stats.stakingStartTime = block.timestamp;
            stats.referrer = referrer;
            
            // First stake achievement
            _unlockAchievement(user, keccak256("FIRST_STAKE"));
        }
        
        stats.totalStaked += amount;
        stats.lastActivityTime = block.timestamp;
        
        // Update streak
        if (block.timestamp <= stats.lastActivityTime + 2 days) {
            stats.currentStreak++;
            if (stats.currentStreak > stats.longestStreak) {
                stats.longestStreak = stats.currentStreak;
            }
        } else {
            stats.currentStreak = 1; // Reset streak
        }
        
        // Streak bonuses
        if (stats.currentStreak == 7) {
            _unlockAchievement(user, keccak256("WEEK_WARRIOR"));
            emit StreakBonusEarned(user, stats.currentStreak, achievementRewards[keccak256("WEEK_WARRIOR")]);
        } else if (stats.currentStreak == 30) {
            _unlockAchievement(user, keccak256("MONTH_MASTER"));
            emit StreakBonusEarned(user, stats.currentStreak, achievementRewards[keccak256("MONTH_MASTER")]);
        } else if (stats.currentStreak == 365) {
            _unlockAchievement(user, keccak256("YEAR_LEGEND"));
            emit StreakBonusEarned(user, stats.currentStreak, achievementRewards[keccak256("YEAR_LEGEND")]);
        }
    }

    function _calculateYieldMultipliers(address user) internal {
        UserGameStats storage stats = userStats[user];
        YieldMultiplier storage multiplier = userMultipliers[user];
        
        uint256 oldTotalMultiplier = multiplier.totalMultiplier;
        
        // Base multiplier
        multiplier.baseMultiplier = 10000; // 1x
        
        // Loyalty bonus (based on staking duration)
        uint256 stakingDays = (block.timestamp - stats.stakingStartTime) / 1 days;
        multiplier.loyaltyBonus = stakingDays * gameConfig.loyaltyBonusRate;
        
        // Volume bonus (based on staking amount)
        if (stats.totalStaked >= 1000000 * 10**6) { // 1M+ USDC
            multiplier.volumeBonus = 2000; // 20% bonus
            _checkWhaleStatus(user);
        } else if (stats.totalStaked >= 100000 * 10**6) { // 100K+ USDC
            multiplier.volumeBonus = 1000; // 10% bonus
        } else if (stats.totalStaked >= 10000 * 10**6) { // 10K+ USDC
            multiplier.volumeBonus = 500; // 5% bonus
        } else {
            multiplier.volumeBonus = 0;
        }
        
        // Social bonus
        if (stats.currentGroup != bytes32(0)) {
            multiplier.socialBonus = socialFeatures.getGroupMultiplier(stats.currentGroup);
        }
        
        // Achievement bonus
        multiplier.achievementBonus = stats.achievementsUnlocked * gameConfig.achievementMultiplier;
        
        // Lottery bonus (for active lottery participants)
        if (stats.lotteryEntriesTotal > 0) {
            multiplier.lotteryBonus = 200; // 2% bonus for lottery participation
        }
        
        // Streak bonus
        multiplier.streakBonus = stats.currentStreak * gameConfig.streakBonusRate;
        
        // Calculate total multiplier
        multiplier.totalMultiplier = multiplier.baseMultiplier + 
                                    multiplier.loyaltyBonus + 
                                    multiplier.volumeBonus + 
                                    multiplier.socialBonus + 
                                    multiplier.achievementBonus + 
                                    multiplier.lotteryBonus + 
                                    multiplier.streakBonus;
        
        // Cap at maximum multiplier
        if (multiplier.totalMultiplier > gameConfig.maxMultiplier) {
            multiplier.totalMultiplier = gameConfig.maxMultiplier;
        }
        
        if (multiplier.totalMultiplier != oldTotalMultiplier) {
            emit YieldMultiplierUpdated(user, oldTotalMultiplier, multiplier.totalMultiplier);
        }
    }

    function _handleLotteryEntries(address user, uint256 amount) internal {
        uint256 weight = _calculateLotteryWeight(user, amount);
        
        // Enter weekly lottery
        uint256 weeklyRoundId = _getActiveRoundId(LotteryType.WEEKLY_MEGA);
        if (weeklyRoundId > 0) {
            _enterLottery(user, weeklyRoundId, 1, weight);
        }
        
        // Enter daily lottery if user has enough balance
        if (assetToken.balanceOf(user) >= gameConfig.dailyLotteryFee) {
            uint256 dailyRoundId = _getActiveRoundId(LotteryType.DAILY_BOOST);
            if (dailyRoundId > 0) {
                _enterLottery(user, dailyRoundId, 1, weight);
            }
        }
        
        // Trigger flash lottery randomly
        if (_shouldTriggerFlashLottery()) {
            _triggerFlashLottery(amount);
        }
    }

    function _calculateLotteryWeight(address user, uint256 amount) internal view returns (uint256) {
        UserGameStats storage stats = userStats[user];
        YieldMultiplier storage multiplier = userMultipliers[user];
        
        // Base weight from amount
        uint256 baseWeight = amount / 10**6; // 1 weight per USDC
        
        // Apply multipliers
        uint256 multipliedWeight = (baseWeight * multiplier.totalMultiplier) / 10000;
        
        // Bonus for long-term stakers
        uint256 loyaltyWeight = (stats.longestStreak * baseWeight) / 100;
        
        return multipliedWeight + loyaltyWeight;
    }

    function _enterLottery(address user, uint256 roundId, uint256 entries, uint256 weight) internal {
        LotteryRound storage round = lotteryRounds[roundId];
        
        require(block.timestamp < round.endTime, "Lottery round ended");
        require(!round.drawn, "Lottery already drawn");
        
        // Charge entry fee
        uint256 entryFee = round.entryFee * entries;
        assetToken.transferFrom(user, address(this), entryFee);
        
        // Add to lottery pool
        round.totalPrizePool += entryFee;
        totalLotteryPool += entryFee;
        
        // Record user entry
        if (round.userEntries[user] == 0) {
            round.participants.push(user);
        }
        
        round.userEntries[user] += entries;
        round.userWeights[user] += weight;
        round.totalEntries += entries;
        
        // Update user stats
        userStats[user].lotteryEntriesTotal += entries;
        
        emit LotteryEntryPurchased(user, roundId, entries, weight);
    }

    function _shouldTriggerFlashLottery() internal view returns (bool) {
        // Trigger flash lottery 1% of the time
        uint256 random = uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty))) % 100;
        return random == 0;
    }

    function _triggerFlashLottery(uint256 triggerAmount) internal {
        uint256 prizeAmount = triggerAmount / 10; // 10% of trigger amount
        
        if (prizeAmount >= 10 * 10**6) { // Minimum 10 USDC prize
            uint256 newRoundId = _startLotteryRound(LotteryType.FLASH_LOTTERY);
            lotteryRounds[newRoundId].totalPrizePool = prizeAmount;
            lotteryRounds[newRoundId].endTime = block.timestamp + 1 hours; // 1 hour duration
            
            emit FlashLotteryTriggered(prizeAmount, 0);
        }
    }

    function _handleSocialFeatures(address user, bytes32 groupId) internal {
        if (userStats[user].currentGroup != groupId) {
            try socialFeatures.joinGroup(groupId) {
                userStats[user].currentGroup = groupId;
                
                // Social achievement
                if (!userAchievements[user][keccak256("SOCIAL_BUTTERFLY")]) {
                    _unlockAchievement(user, keccak256("SOCIAL_BUTTERFLY"));
                }
                
                uint256 groupBonus = socialFeatures.getGroupMultiplier(groupId);
                emit SocialGroupJoined(user, groupId, groupBonus);
            } catch {
                // Group join failed
            }
        }
    }

    function _checkAndUnlockAchievements(address user, uint256 amount) internal {
        UserGameStats storage stats = userStats[user];
        
        // Whale status achievement
        if (stats.totalStaked >= 1000000 * 10**6 && !userAchievements[user][keccak256("WHALE_STATUS")]) {
            _unlockAchievement(user, keccak256("WHALE_STATUS"));
        }
        
        // Streak master achievement
        if (stats.currentStreak >= 100 && !userAchievements[user][keccak256("STREAK_MASTER")]) {
            _unlockAchievement(user, keccak256("STREAK_MASTER"));
        }
    }

    function _checkWhaleStatus(address user) internal {
        if (!userAchievements[user][keccak256("WHALE_STATUS")]) {
            _unlockAchievement(user, keccak256("WHALE_STATUS"));
        }
    }

    function _unlockAchievement(address user, bytes32 achievementId) internal {
        if (!userAchievements[user][achievementId]) {
            userAchievements[user][achievementId] = true;
            userStats[user].achievementsUnlocked++;
            
            uint256 reward = achievementRewards[achievementId];
            if (reward > 0) {
                // Mint reward tokens or transfer from treasury
                _mintReward(user, reward);
            }
            
            emit AchievementUnlocked(user, achievementId, reward);
        }
    }

    function _applyYieldBoost(uint256 amount, address user) internal view returns (uint256) {
        uint256 userMultiplier = userMultipliers[user].totalMultiplier;
        uint256 boostedAmount = (amount * userMultiplier) / 10000;
        
        // Apply global yield boost if active
        if (block.timestamp <= yieldBoostEventEnd) {
            boostedAmount = (boostedAmount * currentYieldBoostMultiplier) / 10000;
        }
        
        return boostedAmount;
    }

    function _executeBaseYieldFarming(uint256 amount) internal {
        // Allocate percentage to lottery pools
        uint256 lotteryAllocation = (amount * gameConfig.lotteryPoolPercentage) / 10000;
        
        // Distribute to different lottery pools
        lotteryPools[LotteryType.WEEKLY_MEGA] += (lotteryAllocation * 50) / 100; // 50%
        lotteryPools[LotteryType.DAILY_BOOST] += (lotteryAllocation * 30) / 100; // 30%
        lotteryPools[LotteryType.FLASH_LOTTERY] += (lotteryAllocation * 20) / 100; // 20%
        
        // Rest goes to actual yield farming
        uint256 farmingAmount = amount - lotteryAllocation;
        
        // Execute yield farming strategy (simplified)
        // In reality, would deploy to actual yield strategies
    }

    function _startLotteryRound(LotteryType lotteryType) internal returns (uint256 roundId) {
        currentRoundId++;
        roundId = currentRoundId;
        
        LotteryRound storage round = lotteryRounds[roundId];
        round.roundId = roundId;
        round.startTime = block.timestamp;
        round.lotteryType = lotteryType;
        
        if (lotteryType == LotteryType.WEEKLY_MEGA) {
            round.endTime = block.timestamp + 7 days;
            round.entryFee = gameConfig.weeklyLotteryFee;
            round.totalPrizePool = lotteryPools[LotteryType.WEEKLY_MEGA];
            lotteryPools[LotteryType.WEEKLY_MEGA] = 0; // Reset pool
        } else if (lotteryType == LotteryType.DAILY_BOOST) {
            round.endTime = block.timestamp + 1 days;
            round.entryFee = gameConfig.dailyLotteryFee;
            round.totalPrizePool = lotteryPools[LotteryType.DAILY_BOOST];
            lotteryPools[LotteryType.DAILY_BOOST] = 0; // Reset pool
        } else if (lotteryType == LotteryType.FLASH_LOTTERY) {
            round.endTime = block.timestamp + 1 hours;
            round.entryFee = 0; // Free entry
        }
        
        lastLotteryTime[lotteryType] = block.timestamp;
        
        emit LotteryRoundStarted(roundId, lotteryType, round.totalPrizePool);
    }

    function _getActiveRoundId(LotteryType lotteryType) internal view returns (uint256) {
        // Find active round of given type
        for (uint256 i = currentRoundId; i > 0; i--) {
            LotteryRound storage round = lotteryRounds[i];
            if (round.lotteryType == lotteryType && 
                block.timestamp < round.endTime && 
                !round.drawn) {
                return i;
            }
        }
        return 0;
    }

    function _harvestRewards(bytes calldata) internal override {
        // Check for lottery rounds that need to be drawn
        _checkAndDrawLotteries();
        
        // Start new lottery rounds if needed
        _checkAndStartNewLotteries();
        
        // Update all users' multipliers based on time-based bonuses
        // In practice, this would be done more efficiently
    }

    function _checkAndDrawLotteries() internal {
        for (uint256 i = 1; i <= currentRoundId; i++) {
            LotteryRound storage round = lotteryRounds[i];
            
            if (!round.drawn && block.timestamp >= round.endTime && round.totalEntries > 0) {
                _requestLotteryDraw(i);
            }
        }
    }

    function _requestLotteryDraw(uint256 roundId) internal {
        LotteryRound storage round = lotteryRounds[roundId];
        
        // Request randomness from Flow VRF
        bytes32 requestId = flowVRF.requestRandomness(keccak256("lottery"), 0.1 ether);
        round.vrfRequestId = requestId;
        vrfRequestToRound[requestId] = roundId;
    }

    function fulfillRandomness(bytes32 requestId, uint256 randomness) external {
        require(msg.sender == address(flowVRF), "Only VRF can fulfill");
        
        uint256 roundId = vrfRequestToRound[requestId];
        LotteryRound storage round = lotteryRounds[roundId];
        
        require(!round.drawn, "Already drawn");
        
        _drawLottery(roundId, randomness);
    }

    function _drawLottery(uint256 roundId, uint256 randomness) internal {
        LotteryRound storage round = lotteryRounds[roundId];
        
        // Calculate number of winners based on lottery type
        uint256 numWinners = 1;
        if (round.lotteryType == LotteryType.WEEKLY_MEGA) {
            numWinners = 3; // Top 3 winners
        } else if (round.lotteryType == LotteryType.DAILY_BOOST) {
            numWinners = 1; // Single winner
        }
        
        // Select winners based on weighted random selection
        address[] memory winners = new address[](numWinners);
        uint256[] memory winnerAmounts = new uint256[](numWinners);
        
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < round.participants.length; i++) {
            totalWeight += round.userWeights[round.participants[i]];
        }
        
        for (uint256 w = 0; w < numWinners && round.participants.length > 0; w++) {
            uint256 winningNumber = uint256(keccak256(abi.encode(randomness, w))) % totalWeight;
            uint256 currentWeight = 0;
            
            for (uint256 i = 0; i < round.participants.length; i++) {
                address participant = round.participants[i];
                currentWeight += round.userWeights[participant];
                
                if (currentWeight >= winningNumber) {
                    winners[w] = participant;
                    
                    // Calculate prize amount
                    if (numWinners == 1) {
                        winnerAmounts[w] = round.totalPrizePool;
                    } else {
                        // Progressive prizes: 50%, 30%, 20%
                        if (w == 0) winnerAmounts[w] = (round.totalPrizePool * 50) / 100;
                        else if (w == 1) winnerAmounts[w] = (round.totalPrizePool * 30) / 100;
                        else winnerAmounts[w] = (round.totalPrizePool * 20) / 100;
                    }
                    
                    // Transfer prize
                    assetToken.transfer(participant, winnerAmounts[w]);
                    
                    // Update stats
                    userStats[participant].lotteryWinningsTotal += winnerAmounts[w];
                    totalLotteryWinnings += winnerAmounts[w];
                    
                    // Lottery winner achievement
                    _unlockAchievement(participant, keccak256("LOTTERY_WINNER"));
                    
                    // Remove winner from future selections in this round
                    totalWeight -= round.userWeights[participant];
                    break;
                }
            }
        }
        
        round.winners = winners;
        round.winnerAmounts = winnerAmounts;
        round.drawn = true;
        
        emit LotteryDrawn(roundId, winners, winnerAmounts);
    }

    function _checkAndStartNewLotteries() internal {
        // Start new weekly lottery if needed
        if (block.timestamp >= lastLotteryTime[LotteryType.WEEKLY_MEGA] + 7 days) {
            _startLotteryRound(LotteryType.WEEKLY_MEGA);
        }
        
        // Start new daily lottery if needed
        if (block.timestamp >= lastLotteryTime[LotteryType.DAILY_BOOST] + 1 days) {
            _startLotteryRound(LotteryType.DAILY_BOOST);
        }
    }

    function _mintReward(address user, uint256 amount) internal {
        // In a real implementation, would mint governance tokens or transfer from treasury
        // For simplicity, just track the reward
        userStats[user].totalYieldEarned += amount;
    }

    function _emergencyWithdraw(bytes calldata) internal override returns (uint256 recovered) {
        return assetToken.balanceOf(address(this));
    }

    function getBalance() external view override returns (uint256) {
        return assetToken.balanceOf(address(this));
    }

    // Public functions for users
    function enterLottery(uint256 roundId, uint256 entries) external {
        require(entries > 0, "Must enter at least 1 ticket");
        
        uint256 weight = _calculateLotteryWeight(msg.sender, userStats[msg.sender].totalStaked);
        _enterLottery(msg.sender, roundId, entries, weight);
    }

    function claimAchievementReward(bytes32 achievementId) external {
        require(userAchievements[msg.sender][achievementId], "Achievement not unlocked");
        
        uint256 reward = achievementRewards[achievementId];
        if (reward > 0) {
            _mintReward(msg.sender, reward);
        }
    }

    function joinSocialGroup(bytes32 groupId) external {
        socialFeatures.joinGroup(groupId);
        userStats[msg.sender].currentGroup = groupId;
        
        uint256 groupBonus = socialFeatures.getGroupMultiplier(groupId);
        emit SocialGroupJoined(msg.sender, groupId, groupBonus);
    }

    // Admin functions
    function startYieldBoostEvent(uint256 multiplier, uint256 duration) external onlyRole(DEFAULT_ADMIN_ROLE) {
        currentYieldBoostMultiplier = multiplier;
        yieldBoostEventEnd = block.timestamp + duration;
        
        emit YieldBoostEventStarted(multiplier, duration);
    }

    function updateGameConfig(
        uint256 weeklyFee,
        uint256 dailyFee,
        uint256 lotteryPercentage,
        uint256 maxMultiplier,
        bool enableLotteries,
        bool enableAchievements,
        bool enableSocial
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        gameConfig.weeklyLotteryFee = weeklyFee;
        gameConfig.dailyLotteryFee = dailyFee;
        gameConfig.lotteryPoolPercentage = lotteryPercentage;
        gameConfig.maxMultiplier = maxMultiplier;
        gameConfig.enableLotterySystem = enableLotteries;
        gameConfig.enableAchievements = enableAchievements;
        gameConfig.enableSocialFeatures = enableSocial;
    }

    function addAchievement(bytes32 achievementId, uint256 reward) external onlyRole(DEFAULT_ADMIN_ROLE) {
        achievementRewards[achievementId] = reward;
    }

    function manualDrawLottery(uint256 roundId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 randomness = flowVRF.getRandomSeed();
        _drawLottery(roundId, randomness);
    }

    // View functions
    function getUserStats(address user) external view returns (UserGameStats memory) {
        return userStats[user];
    }

    function getUserMultipliers(address user) external view returns (YieldMultiplier memory) {
        return userMultipliers[user];
    }

    function getLotteryRound(uint256 roundId) external view returns (
        uint256 id,
        uint256 startTime,
        uint256 endTime,
        uint256 totalPrizePool,
        uint256 totalEntries,
        uint256 entryFee,
        bool drawn,
        LotteryType lotteryType
    ) {
        LotteryRound storage round = lotteryRounds[roundId];
        return (
            round.roundId,
            round.startTime,
            round.endTime,
            round.totalPrizePool,
            round.totalEntries,
            round.entryFee,
            round.drawn,
            round.lotteryType
        );
    }

    function getActiveLotteryRounds() external view returns (uint256[] memory) {
        uint256 activeCount = 0;
        
        // Count active rounds
        for (uint256 i = 1; i <= currentRoundId; i++) {
            LotteryRound storage round = lotteryRounds[i];
            if (!round.drawn && block.timestamp < round.endTime) {
                activeCount++;
            }
        }
        
        // Collect active round IDs
        uint256[] memory activeRounds = new uint256[](activeCount);
        uint256 index = 0;
        
        for (uint256 i = 1; i <= currentRoundId; i++) {
            LotteryRound storage round = lotteryRounds[i];
            if (!round.drawn && block.timestamp < round.endTime) {
                activeRounds[index] = i;
                index++;
            }
        }
        
        return activeRounds;
    }

    function getGameStats() external view returns (
        uint256 totalPlayers,
        uint256 totalLotteryPool_,
        uint256 totalWinnings,
        uint256 currentRound,
        bool yieldBoostActive,
        uint256 boostMultiplier
    ) {
        totalPlayers = totalPlayersEver;
        totalLotteryPool_ = totalLotteryPool;
        totalWinnings = totalLotteryWinnings;
        currentRound = currentRoundId;
        yieldBoostActive = block.timestamp <= yieldBoostEventEnd;
        boostMultiplier = currentYieldBoostMultiplier;
    }

    function getUserAchievementStatus(address user, bytes32 achievementId) external view returns (bool unlocked, uint256 reward) {
        unlocked = userAchievements[user][achievementId];
        reward = achievementRewards[achievementId];
    }

    // Handle native FLOW for VRF fees
    receive() external payable {}
}