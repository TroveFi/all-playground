// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface ICadenceArchVRF {
    function revertibleRandom() external view returns (uint256 randomValue);
}

interface IFlowVRFLotterySystem {
    function addParticipant(address participant, uint256 weight) external;
    function startLotteryRound(uint256 prizePool, uint256 winnersCount, uint256 customDuration) external;
    function getCurrentRound() external view returns (
        uint256 roundId,
        uint256 startTime,
        uint256 endTime,
        uint256 prizePool,
        uint256 winnersCount,
        uint256 totalParticipants,
        bool isActive,
        bool isFinalized
    );
}

contract LotteryManager is AccessControl, ReentrancyGuard {
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");

    address public constant CADENCE_ARCH_VRF = 0x0000000000000000000000010000000000000001;
    
    ICadenceArchVRF public immutable cadenceVRF;
    IFlowVRFLotterySystem public lotterySystem;
    address public vault;

    struct LotteryRound {
        uint256 roundId;
        uint256 startTime;
        uint256 endTime;
        uint256 totalParticipants;
        bool isActive;
        bool isFinalized;
        mapping(address => bool) participants;
        mapping(address => uint256) participantWeights;
    }

    mapping(uint256 => LotteryRound) public lotteryRounds;
    mapping(address => uint256[]) public userParticipatingRounds;
    uint256 public currentRoundId;

    uint256 public lotteryDuration = 30 days;
    uint256 public minWinnersCount = 1;
    uint256 public maxWinnersCount = 10;

    event ParticipantAdded(uint256 indexed roundId, address indexed participant, uint256 weight);
    event LotteryRoundStarted(uint256 indexed roundId, uint256 startTime, uint256 endTime);
    event LotteryRoundFinalized(uint256 indexed roundId, uint256 totalParticipants);

    constructor(address _vault, address _lotterySystem) {
        require(_vault != address(0), "Invalid vault");
        require(_lotterySystem != address(0), "Invalid lottery system");

        vault = _vault;
        lotterySystem = IFlowVRFLotterySystem(_lotterySystem);
        cadenceVRF = ICadenceArchVRF(CADENCE_ARCH_VRF);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(VAULT_ROLE, _vault);

        _startNewRound();
    }

    modifier onlyVault() {
        require(hasRole(VAULT_ROLE, msg.sender), "Only vault can call");
        _;
    }

    function addParticipant(address participant, uint256 weight) external onlyVault {
        require(participant != address(0), "Invalid participant");
        require(weight > 0, "Weight must be positive");
        require(currentRoundId > 0, "No active round");

        LotteryRound storage round = lotteryRounds[currentRoundId];
        require(round.isActive, "Round not active");
        require(block.timestamp < round.endTime, "Round has ended");
        require(!round.participants[participant], "Already participating");

        round.participants[participant] = true;
        round.participantWeights[participant] = weight;
        round.totalParticipants++;
        
        userParticipatingRounds[participant].push(currentRoundId);

        // Add to external lottery system
        try lotterySystem.addParticipant(participant, weight) {} catch {}

        emit ParticipantAdded(currentRoundId, participant, weight);
    }

    function startNewRound() external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!lotteryRounds[currentRoundId].isActive || block.timestamp >= lotteryRounds[currentRoundId].endTime, "Current round still active");

        if (currentRoundId > 0) {
            _finalizeRound(currentRoundId);
        }

        _startNewRound();
    }

    function finalizeRound(uint256 roundId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(lotteryRounds[roundId].isActive, "Round not active");
        require(block.timestamp >= lotteryRounds[roundId].endTime, "Round not ended");

        _finalizeRound(roundId);
    }

    function _startNewRound() internal {
        currentRoundId++;

        LotteryRound storage round = lotteryRounds[currentRoundId];
        round.roundId = currentRoundId;
        round.startTime = block.timestamp;
        round.endTime = block.timestamp + lotteryDuration;
        round.totalParticipants = 0;
        round.isActive = true;
        round.isFinalized = false;

        // Start round in external lottery system
        try lotterySystem.startLotteryRound(0, minWinnersCount, lotteryDuration) {} catch {}

        emit LotteryRoundStarted(currentRoundId, block.timestamp, block.timestamp + lotteryDuration);
    }

    function _finalizeRound(uint256 roundId) internal {
        LotteryRound storage round = lotteryRounds[roundId];
        round.isActive = false;
        round.isFinalized = true;

        emit LotteryRoundFinalized(roundId, round.totalParticipants);
    }

    function getCurrentRound() external view returns (
        uint256 roundId,
        bool isActive,
        uint256 participants,
        uint256 prizePool
    ) {
        if (currentRoundId == 0) {
            return (0, false, 0, 0);
        }

        LotteryRound storage round = lotteryRounds[currentRoundId];
        return (round.roundId, round.isActive, round.totalParticipants, 0);
    }

    function isUserParticipating(address user, uint256 roundId) external view returns (bool) {
        return lotteryRounds[roundId].participants[user];
    }

    function getUserParticipatingRounds(address user) external view returns (uint256[] memory) {
        return userParticipatingRounds[user];
    }

    function setLotterySettings(
        uint256 _lotteryDuration,
        uint256 _minWinnersCount,
        uint256 _maxWinnersCount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        lotteryDuration = _lotteryDuration;
        minWinnersCount = _minWinnersCount;
        maxWinnersCount = _maxWinnersCount;
    }

    function setLotterySystem(address _lotterySystem) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_lotterySystem != address(0), "Invalid lottery system");
        lotterySystem = IFlowVRFLotterySystem(_lotterySystem);
    }
}