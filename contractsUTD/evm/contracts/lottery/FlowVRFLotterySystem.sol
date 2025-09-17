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

/// @title FlowVRFLotterySystem - VRF-powered lottery system for yield distribution
/// @notice Uses Flow's Cadence Arch VRF to fairly select lottery winners
/// @dev Integrated with vault system for automated yield lottery distribution
contract FlowVRFLotterySystem is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    // ====================================================================
    // ROLES & CONSTANTS
    // ====================================================================
    
    bytes32 public constant LOTTERY_MANAGER_ROLE = keccak256("LOTTERY_MANAGER_ROLE");
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");

    // Flow's Cadence Arch VRF precompile address
    address public constant CADENCE_ARCH_VRF = 0x0000000000000000000000010000000000000001;

    // ====================================================================
    // STRUCTS & ENUMS
    // ====================================================================
    
    struct LotteryRound {
        uint256 roundId;
        uint256 startTime;
        uint256 endTime;
        uint256 prizePool;
        uint256 winnersCount;
        address[] participants;
        address[] winners;
        uint256[] winnerPrizes;
        bool isActive;
        bool isFinalized;
        uint256 vrfRandomness;
        bytes32 vrfSeed;
        uint256 totalParticipants;
        mapping(address => bool) hasParticipated;
        mapping(address => uint256) participantWeight; // For weighted lotteries
    }

    struct ParticipantInfo {
        uint256[] participatingRounds;
        uint256 totalPrizesWon;
        uint256 lastParticipationTime;
        uint256 winCount;
        bool isEligible;
    }

    struct LotteryConfig {
        uint256 minParticipants;
        uint256 maxParticipants;
        uint256 minWinners;
        uint256 maxWinners;
        uint256 minPrizePool;
        uint256 roundDuration;
        bool weightedLottery; // Whether to use participant weights
        bool requiresDeposit; // Whether participants need active deposits
    }

    enum LotteryType {
        EQUAL_CHANCE,    // All participants have equal chance
        WEIGHTED,        // Based on deposit amounts
        TIERED,          // Multiple prize tiers
        STREAK_BONUS     // Bonus for consecutive participation
    }

    // ====================================================================
    // STATE VARIABLES
    // ====================================================================
    
    ICadenceArchVRF public immutable cadenceVRF;
    IERC20 public immutable prizeToken;
    address public vault;
    
    // Lottery state
    mapping(uint256 => LotteryRound) public lotteryRounds;
    mapping(address => ParticipantInfo) public participantInfo;
    uint256 public currentRoundId;
    uint256 public totalRounds;
    
    // Configuration
    LotteryConfig public lotteryConfig;
    LotteryType public lotteryType = LotteryType.WEIGHTED;
    
    // Participant tracking
    address[] public allParticipants;
    mapping(address => bool) public isRegisteredParticipant;
    
    // Prize distribution
    uint256[] public prizeDistribution = [5000, 3000, 2000]; // 50%, 30%, 20% for top 3 winners
    uint256 public constant TOTAL_DISTRIBUTION = 10000; // 100% in basis points
    
    // Emergency and security
    bool public lotteryPaused = false;
    bool public emergencyMode = false;
    uint256 public lastRandomnessUsed;
    mapping(bytes32 => bool) public usedRandomnessSeeds;

    // ====================================================================
    // EVENTS
    // ====================================================================
    
    event LotteryRoundStarted(
        uint256 indexed roundId,
        uint256 startTime,
        uint256 endTime,
        uint256 prizePool
    );
    
    event ParticipantAdded(
        uint256 indexed roundId,
        address indexed participant,
        uint256 weight,
        uint256 totalParticipants
    );
    
    event LotteryDrawExecuted(
        uint256 indexed roundId,
        bytes32 vrfSeed,
        uint256 vrfRandomness,
        address[] winners,
        uint256[] prizes
    );
    
    event PrizeDistributed(
        uint256 indexed roundId,
        address indexed winner,
        uint256 prize,
        uint256 winnerIndex
    );
    
    event LotteryRoundFinalized(
        uint256 indexed roundId,
        uint256 totalParticipants,
        uint256 totalPrizeDistributed
    );
    
    event ParticipantRegistered(address indexed participant);
    event LotteryConfigUpdated(uint256 minParticipants, uint256 maxParticipants, uint256 roundDuration);
    event EmergencyModeToggled(bool enabled);

    // ====================================================================
    // CONSTRUCTOR
    // ====================================================================
    
    constructor(
        address _prizeToken,
        address _vault
    ) {
        require(_prizeToken != address(0), "Invalid prize token");
        require(_vault != address(0), "Invalid vault");

        cadenceVRF = ICadenceArchVRF(CADENCE_ARCH_VRF);
        prizeToken = IERC20(_prizeToken);
        vault = _vault;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(LOTTERY_MANAGER_ROLE, msg.sender);
        _grantRole(VAULT_ROLE, _vault);

        // Initialize default lottery configuration
        lotteryConfig = LotteryConfig({
            minParticipants: 2,
            maxParticipants: 1000,
            minWinners: 1,
            maxWinners: 10,
            minPrizePool: 100 * 10**6, // 100 USDC minimum
            roundDuration: 30 days,
            weightedLottery: true,
            requiresDeposit: true
        });
    }

    // ====================================================================
    // MODIFIERS
    // ====================================================================
    
    modifier whenNotPaused() {
        require(!lotteryPaused, "Lottery is paused");
        _;
    }

    modifier whenNotEmergency() {
        require(!emergencyMode, "Emergency mode active");
        _;
    }

    modifier onlyVault() {
        require(msg.sender == vault, "Only vault can call");
        _;
    }

    modifier validRound(uint256 roundId) {
        require(roundId > 0 && roundId <= currentRoundId, "Invalid round ID");
        _;
    }

    // ====================================================================
    // LOTTERY MANAGEMENT
    // ====================================================================
    
    /// @notice Start a new lottery round
    /// @param prizePool Total prize pool for this round
    /// @param winnersCount Number of winners to select
    /// @param customDuration Custom duration (0 for default)
    function startLotteryRound(
        uint256 prizePool,
        uint256 winnersCount,
        uint256 customDuration
    ) external onlyRole(LOTTERY_MANAGER_ROLE) whenNotPaused whenNotEmergency {
        require(prizePool >= lotteryConfig.minPrizePool, "Prize pool too small");
        require(winnersCount >= lotteryConfig.minWinners && winnersCount <= lotteryConfig.maxWinners, "Invalid winners count");
        
        // Finalize previous round if exists
        if (currentRoundId > 0 && lotteryRounds[currentRoundId].isActive) {
            require(block.timestamp >= lotteryRounds[currentRoundId].endTime, "Previous round still active");
            _finalizeLotteryRound(currentRoundId);
        }

        // Create new round
        currentRoundId++;
        totalRounds++;
        
        uint256 duration = customDuration > 0 ? customDuration : lotteryConfig.roundDuration;
        uint256 endTime = block.timestamp + duration;

        LotteryRound storage round = lotteryRounds[currentRoundId];
        round.roundId = currentRoundId;
        round.startTime = block.timestamp;
        round.endTime = endTime;
        round.prizePool = prizePool;
        round.winnersCount = winnersCount;
        round.isActive = true;
        round.isFinalized = false;
        round.totalParticipants = 0;

        // Transfer prize pool from vault
        prizeToken.safeTransferFrom(vault, address(this), prizePool);

        emit LotteryRoundStarted(currentRoundId, block.timestamp, endTime, prizePool);
    }

    /// @notice Add participant to current lottery round
    /// @param participant Address of participant
    /// @param weight Participant's weight (deposit amount, etc.)
    function addParticipant(
        address participant,
        uint256 weight
    ) external onlyRole(VAULT_ROLE) whenNotPaused {
        require(currentRoundId > 0, "No active lottery round");
        require(participant != address(0), "Invalid participant");
        require(weight > 0, "Weight must be positive");

        LotteryRound storage round = lotteryRounds[currentRoundId];
        require(round.isActive, "Round not active");
        require(block.timestamp < round.endTime, "Round has ended");
        require(!round.hasParticipated[participant], "Already participated");
        require(round.totalParticipants < lotteryConfig.maxParticipants, "Max participants reached");

        // Add participant to round
        round.participants.push(participant);
        round.hasParticipated[participant] = true;
        round.participantWeight[participant] = weight;
        round.totalParticipants++;

        // Update participant info
        if (!isRegisteredParticipant[participant]) {
            allParticipants.push(participant);
            isRegisteredParticipant[participant] = true;
            emit ParticipantRegistered(participant);
        }

        participantInfo[participant].participatingRounds.push(currentRoundId);
        participantInfo[participant].lastParticipationTime = block.timestamp;
        participantInfo[participant].isEligible = true;

        emit ParticipantAdded(currentRoundId, participant, weight, round.totalParticipants);
    }

    /// @notice Execute lottery draw using VRF
    /// @param roundId Round to execute draw for
    function executeLotteryDraw(uint256 roundId) 
        external 
        onlyRole(LOTTERY_MANAGER_ROLE) 
        validRound(roundId) 
        nonReentrant 
        whenNotPaused 
    {
        LotteryRound storage round = lotteryRounds[roundId];
        require(round.isActive, "Round not active");
        require(block.timestamp >= round.endTime, "Round not ended yet");
        require(round.totalParticipants >= lotteryConfig.minParticipants, "Not enough participants");
        require(!round.isFinalized, "Round already finalized");

        // Generate enhanced VRF randomness
        uint256 baseRandomness = cadenceVRF.revertibleRandom();
        bytes32 vrfSeed = _generateEnhancedSeed(roundId, baseRandomness);
        
        // Ensure uniqueness
        require(!usedRandomnessSeeds[vrfSeed], "Randomness seed already used");
        usedRandomnessSeeds[vrfSeed] = true;

        round.vrfRandomness = baseRandomness;
        round.vrfSeed = vrfSeed;

        // Select winners using VRF
        address[] memory winners = _selectWinners(roundId, vrfSeed);
        uint256[] memory prizes = _calculatePrizes(round.prizePool, winners.length);

        // Store winners and prizes
        round.winners = winners;
        round.winnerPrizes = prizes;

        // Distribute prizes
        for (uint256 i = 0; i < winners.length; i++) {
            if (prizes[i] > 0) {
                prizeToken.safeTransfer(winners[i], prizes[i]);
                
                // Update winner stats
                participantInfo[winners[i]].totalPrizesWon += prizes[i];
                participantInfo[winners[i]].winCount++;
                
                emit PrizeDistributed(roundId, winners[i], prizes[i], i);
            }
        }

        lastRandomnessUsed = baseRandomness;

        emit LotteryDrawExecuted(roundId, vrfSeed, baseRandomness, winners, prizes);
        
        // Finalize the round
        _finalizeLotteryRound(roundId);
    }

    // ====================================================================
    // WINNER SELECTION LOGIC
    // ====================================================================
    
    function _selectWinners(uint256 roundId, bytes32 seed) internal view returns (address[] memory) {
        LotteryRound storage round = lotteryRounds[roundId];
        uint256 winnersCount = round.winnersCount;
        uint256 participantsCount = round.participants.length;
        
        if (participantsCount <= winnersCount) {
            // Everyone wins
            return round.participants;
        }

        address[] memory winners = new address[](winnersCount);
        bool[] memory selected = new bool[](participantsCount);
        
        if (lotteryType == LotteryType.EQUAL_CHANCE) {
            // Equal chance selection
            for (uint256 i = 0; i < winnersCount; i++) {
                uint256 randomIndex = uint256(keccak256(abi.encodePacked(seed, i))) % participantsCount;
                
                // Find next unselected participant
                while (selected[randomIndex]) {
                    randomIndex = (randomIndex + 1) % participantsCount;
                }
                
                winners[i] = round.participants[randomIndex];
                selected[randomIndex] = true;
            }
        } else if (lotteryType == LotteryType.WEIGHTED) {
            // Weighted selection based on participant weights
            winners = _selectWeightedWinners(roundId, seed, winnersCount);
        } else if (lotteryType == LotteryType.TIERED) {
            // Tiered selection with different prize levels
            winners = _selectTieredWinners(roundId, seed, winnersCount);
        }

        return winners;
    }

    function _selectWeightedWinners(uint256 roundId, bytes32 seed, uint256 winnersCount) 
        internal 
        view 
        returns (address[] memory) 
    {
        LotteryRound storage round = lotteryRounds[roundId];
        address[] memory participants = round.participants;
        
        // Calculate total weight
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < participants.length; i++) {
            totalWeight += round.participantWeight[participants[i]];
        }

        address[] memory winners = new address[](winnersCount);
        bool[] memory selected = new bool[](participants.length);
        
        for (uint256 w = 0; w < winnersCount; w++) {
            uint256 randomWeight = uint256(keccak256(abi.encodePacked(seed, w))) % totalWeight;
            uint256 currentWeight = 0;
            
            for (uint256 i = 0; i < participants.length; i++) {
                if (selected[i]) continue;
                
                currentWeight += round.participantWeight[participants[i]];
                
                if (randomWeight < currentWeight) {
                    winners[w] = participants[i];
                    selected[i] = true;
                    
                    // Adjust total weight for next selection
                    totalWeight -= round.participantWeight[participants[i]];
                    break;
                }
            }
        }

        return winners;
    }

    function _selectTieredWinners(uint256 roundId, bytes32 seed, uint256 winnersCount) 
        internal 
        view 
        returns (address[] memory) 
    {
        // Implement tiered selection logic
        // For now, fall back to weighted selection
        return _selectWeightedWinners(roundId, seed, winnersCount);
    }

    function _calculatePrizes(uint256 totalPrizePool, uint256 winnersCount) internal view returns (uint256[] memory) {
        uint256[] memory prizes = new uint256[](winnersCount);
        
        if (winnersCount == 1) {
            prizes[0] = totalPrizePool;
        } else if (winnersCount <= prizeDistribution.length) {
            // Use predefined distribution
            for (uint256 i = 0; i < winnersCount; i++) {
                prizes[i] = (totalPrizePool * prizeDistribution[i]) / TOTAL_DISTRIBUTION;
            }
        } else {
            // Equal distribution for many winners
            uint256 prizePerWinner = totalPrizePool / winnersCount;
            for (uint256 i = 0; i < winnersCount; i++) {
                prizes[i] = prizePerWinner;
            }
        }

        return prizes;
    }

    function _generateEnhancedSeed(uint256 roundId, uint256 baseRandomness) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(
            baseRandomness,
            roundId,
            block.timestamp,
            block.number,
            block.prevrandao,
            blockhash(block.number - 1),
            currentRoundId,
            totalRounds
        ));
    }

    function _finalizeLotteryRound(uint256 roundId) internal {
        LotteryRound storage round = lotteryRounds[roundId];
        round.isActive = false;
        round.isFinalized = true;

        uint256 totalDistributed = 0;
        for (uint256 i = 0; i < round.winnerPrizes.length; i++) {
            totalDistributed += round.winnerPrizes[i];
        }

        emit LotteryRoundFinalized(roundId, round.totalParticipants, totalDistributed);
    }

    // ====================================================================
    // VIEW FUNCTIONS
    // ====================================================================
    
    function getCurrentRound() external view returns (
        uint256 roundId,
        uint256 startTime,
        uint256 endTime,
        uint256 prizePool,
        uint256 winnersCount,
        uint256 totalParticipants,
        bool isActive,
        bool isFinalized
    ) {
        if (currentRoundId == 0) {
            return (0, 0, 0, 0, 0, 0, false, false);
        }

        LotteryRound storage round = lotteryRounds[currentRoundId];
        return (
            round.roundId,
            round.startTime,
            round.endTime,
            round.prizePool,
            round.winnersCount,
            round.totalParticipants,
            round.isActive,
            round.isFinalized
        );
    }

    function getRoundParticipants(uint256 roundId) external view validRound(roundId) returns (address[] memory) {
        return lotteryRounds[roundId].participants;
    }

    function getRoundWinners(uint256 roundId) external view validRound(roundId) returns (
        address[] memory winners,
        uint256[] memory prizes
    ) {
        LotteryRound storage round = lotteryRounds[roundId];
        return (round.winners, round.winnerPrizes);
    }

    function getParticipantInfo(address participant) external view returns (
        uint256[] memory participatingRounds,
        uint256 totalPrizesWon,
        uint256 lastParticipationTime,
        uint256 winCount,
        bool isEligible
    ) {
        ParticipantInfo storage info = participantInfo[participant];
        return (
            info.participatingRounds,
            info.totalPrizesWon,
            info.lastParticipationTime,
            info.winCount,
            info.isEligible
        );
    }

    function getParticipantWeight(uint256 roundId, address participant) external view returns (uint256) {
        return lotteryRounds[roundId].participantWeight[participant];
    }

    function hasParticipated(uint256 roundId, address participant) external view returns (bool) {
        return lotteryRounds[roundId].hasParticipated[participant];
    }

    function isRoundActive(uint256 roundId) external view returns (bool) {
        if (roundId == 0 || roundId > currentRoundId) return false;
        return lotteryRounds[roundId].isActive && block.timestamp < lotteryRounds[roundId].endTime;
    }

    function getAllParticipants() external view returns (address[] memory) {
        return allParticipants;
    }

    function getTotalRounds() external view returns (uint256) {
        return totalRounds;
    }

    // ====================================================================
    // ADMIN FUNCTIONS
    // ====================================================================
    
    function setLotteryConfig(
        uint256 minParticipants,
        uint256 maxParticipants,
        uint256 minWinners,
        uint256 maxWinners,
        uint256 minPrizePool,
        uint256 roundDuration,
        bool weightedLottery,
        bool requiresDeposit
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        lotteryConfig = LotteryConfig({
            minParticipants: minParticipants,
            maxParticipants: maxParticipants,
            minWinners: minWinners,
            maxWinners: maxWinners,
            minPrizePool: minPrizePool,
            roundDuration: roundDuration,
            weightedLottery: weightedLottery,
            requiresDeposit: requiresDeposit
        });

        emit LotteryConfigUpdated(minParticipants, maxParticipants, roundDuration);
    }

    function setLotteryType(LotteryType _lotteryType) external onlyRole(DEFAULT_ADMIN_ROLE) {
        lotteryType = _lotteryType;
    }

    function setPrizeDistribution(uint256[] calldata distribution) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(distribution.length > 0, "Empty distribution");
        
        uint256 total = 0;
        for (uint256 i = 0; i < distribution.length; i++) {
            total += distribution[i];
        }
        require(total == TOTAL_DISTRIBUTION, "Distribution must sum to 10000");
        
        prizeDistribution = distribution;
    }

    function setParticipantEligibility(address participant, bool eligible) external onlyRole(LOTTERY_MANAGER_ROLE) {
        participantInfo[participant].isEligible = eligible;
    }

    function pauseLottery(bool paused) external onlyRole(DEFAULT_ADMIN_ROLE) {
        lotteryPaused = paused;
    }

    function setEmergencyMode(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emergencyMode = enabled;
        emit EmergencyModeToggled(enabled);
    }

    function emergencyFinalizeLottery(uint256 roundId) external onlyRole(DEFAULT_ADMIN_ROLE) validRound(roundId) {
        LotteryRound storage round = lotteryRounds[roundId];
        require(!round.isFinalized, "Already finalized");
        
        _finalizeLotteryRound(roundId);
    }

    function emergencyWithdrawPrizes(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(emergencyMode, "Not in emergency mode");
        prizeToken.safeTransfer(msg.sender, amount);
    }
}