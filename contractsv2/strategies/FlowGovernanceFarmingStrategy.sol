// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./BaseStrategy.sol";

// Governance interfaces for Flow ecosystem protocols
interface IGovernanceToken {
    function delegate(address delegatee) external;
    function delegates(address account) external view returns (address);
    function getCurrentVotes(address account) external view returns (uint256);
    function getPriorVotes(address account, uint256 blockNumber) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IGovernanceDAO {
    struct Proposal {
        uint256 id;
        address proposer;
        uint256 startTime;
        uint256 endTime;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        bool executed;
        bool canceled;
        string description;
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
    }

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) external returns (uint256 proposalId);

    function castVote(uint256 proposalId, uint8 support) external returns (uint256 balance);
    function castVoteWithReason(uint256 proposalId, uint8 support, string calldata reason) external returns (uint256 balance);
    
    function getProposal(uint256 proposalId) external view returns (Proposal memory);
    function getActiveProposals() external view returns (uint256[] memory);
    function getVotingPower(address account) external view returns (uint256);
    function getProposalThreshold() external view returns (uint256);
}

// Vote escrow interface (ve-tokenomics)
interface IVoteEscrow {
    function createLock(uint256 amount, uint256 unlockTime) external;
    function increaseLockAmount(uint256 amount) external;
    function increaseLockTime(uint256 unlockTime) external;
    function withdraw() external;
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function locked(address account) external view returns (uint256 amount, uint256 end);
    function getVotingPower(address account) external view returns (uint256);
}

// Bribe and incentive interfaces
interface IBribeMarketplace {
    struct BribeOffer {
        uint256 offerId;
        uint256 proposalId;
        address bribeToken;
        uint256 totalAmount;
        uint256 perVoteAmount;
        uint8 supportDirection; // 0=against, 1=for, 2=abstain
        uint256 deadline;
        address creator;
        bool active;
        uint256 claimedAmount;
    }

    function createBribe(
        uint256 proposalId,
        address bribeToken,
        uint256 totalAmount,
        uint8 supportDirection,
        uint256 deadline
    ) external returns (uint256 offerId);

    function claimBribe(uint256 offerId, uint256 proposalId, uint8 voteDirection) external returns (uint256 amount);
    function getBribeOffers(uint256 proposalId) external view returns (BribeOffer[] memory);
    function calculateBribeReward(uint256 offerId, address voter) external view returns (uint256);
}

// Protocol fee sharing interface
interface IProtocolFeeSharing {
    function claimFees(address protocol, address token) external returns (uint256 amount);
    function getClaimableeFees(address protocol, address token, address user) external view returns (uint256);
    function getFeeShares(address user) external view returns (uint256 shares, uint256 totalShares);
    function stakeFeeShares(uint256 amount) external;
    function unstakeFeeShares(uint256 amount) external;
}

/// @title FlowGovernanceFarmingStrategy - Advanced Governance Token Optimization
/// @notice Sophisticated strategy for maximizing governance token yields through voting, bribes, and fee sharing
contract FlowGovernanceFarmingStrategy is BaseStrategy, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Protocol addresses (you'll need real addresses)
    address public constant FLOW_GOVERNANCE_DAO = address(0); // Flow DAO
    address public constant INCREMENTFI_DAO = address(0); // IncrementFi governance
    address public constant MOREMARKET_DAO = address(0); // More.Markets governance
    address public constant BRIBE_MARKETPLACE = address(0); // Bribe marketplace
    address public constant PROTOCOL_FEE_SHARING = address(0); // Protocol fee sharing

    // Governance token addresses
    address public constant FLOW_TOKEN = address(0); // FLOW governance token
    address public constant INCREMENTFI_TOKEN = address(0); // IncrementFi governance token
    address public constant MOREMARKET_TOKEN = address(0); // More.Markets governance token

    struct ProtocolGovernance {
        string protocolName;
        address daoAddress;
        address governanceToken;
        address voteEscrow;
        uint256 totalStaked;
        uint256 votingPower;
        uint256 feesEarned;
        uint256 bribesEarned;
        uint256 lastVoteTime;
        bool autoVoteEnabled;
        uint8 defaultVoteDirection; // 0=against, 1=for, 2=abstain
        uint256 minProposalValue; // Minimum value to vote on
    }

    struct GovernancePosition {
        bytes32 positionId;
        address protocol;
        address governanceToken;
        uint256 stakedAmount;
        uint256 lockEndTime;
        uint256 votingPower;
        uint256 accruedFees;
        uint256 accruedBribes;
        uint256 lastRewardClaim;
        bool isVeToken; // Is this a vote-escrowed position
        GovernanceStrategy strategy;
    }

    enum GovernanceStrategy {
        PASSIVE_HOLDING,    // Just hold tokens for fees
        ACTIVE_VOTING,      // Actively vote on proposals
        BRIBE_MAXIMIZATION, // Optimize for bribe rewards
        FEE_MAXIMIZATION,   // Optimize for protocol fees
        DELEGATION_FARMING, // Delegate to high-performing voters
        PROPOSAL_CREATION   // Create proposals for ecosystem benefit
    }

    struct VotingDecision {
        uint256 proposalId;
        address protocol;
        uint8 voteDirection;
        uint256 votingPower;
        string reason;
        uint256 expectedBribe;
        uint256 actualBribe;
        uint256 timestamp;
        bool automated;
    }

    struct BribeOpportunity {
        uint256 offerId;
        uint256 proposalId;
        address protocol;
        address bribeToken;
        uint256 expectedReward;
        uint8 requiredVoteDirection;
        uint256 deadline;
        uint256 confidence; // 0-10000
        bool claimed;
    }

    // State variables
    mapping(address => ProtocolGovernance) public protocolGovernance;
    mapping(bytes32 => GovernancePosition) public governancePositions;
    mapping(uint256 => VotingDecision) public votingHistory;
    mapping(bytes32 => BribeOpportunity) public bribeOpportunities;
    
    address[] public supportedProtocols;
    bytes32[] public activePositions;
    uint256[] public votingDecisionIds;
    bytes32[] public activeBribeOpportunities;
    
    // Performance tracking
    uint256 public totalGovernanceTokensEarned;
    uint256 public totalFeesEarned;
    uint256 public totalBribesEarned;
    uint256 public totalVotesCast;
    uint256 public totalProposalsCreated;
    uint256 public positionCounter;
    uint256 public votingDecisionCounter;
    
    // Strategy configuration
    struct GovernanceConfig {
        uint256 maxVeTokenLockTime; // Maximum lock time for ve-tokens
        uint256 minVotingThreshold; // Minimum voting power to participate
        uint256 bribeMinimumReward; // Minimum bribe reward to consider
        uint256 autoVoteThreshold; // Threshold for automatic voting
        bool enableBribeHunting; // Enable bribe opportunity scanning
        bool enableAutoVoting; // Enable automatic voting
        bool enableProposalCreation; // Enable creating proposals
        bool enableFeeOptimization; // Enable fee share optimization
        uint256 delegationStrategy; // 0=none, 1=delegate to top performers
    }
    
    GovernanceConfig public governanceConfig;
    
    // Vote delegation tracking
    mapping(address => address) public delegatedTo;
    mapping(address => uint256) public delegatorPerformance;
    
    // Proposal tracking
    mapping(uint256 => bool) public ourProposals;
    mapping(address => uint256[]) public protocolProposals;

    event GovernancePositionCreated(bytes32 indexed positionId, address protocol, uint256 amount, GovernanceStrategy strategy);
    event VoteCast(uint256 indexed proposalId, address indexed protocol, uint8 voteDirection, uint256 votingPower, uint256 bribeReward);
    event BribeOpportunityFound(bytes32 indexed opportunityId, uint256 proposalId, uint256 expectedReward);
    event BribeClaimed(bytes32 indexed opportunityId, uint256 actualReward);
    event ProtocolFeesClaimed(address indexed protocol, address indexed token, uint256 amount);
    event ProposalCreated(uint256 indexed proposalId, address indexed protocol, string description);
    event VotingPowerDelegated(address indexed protocol, address indexed delegatee, uint256 votingPower);
    event GovernanceRewardsHarvested(address indexed protocol, uint256 fees, uint256 bribes, uint256 govTokens);

    constructor(
        address _asset,
        address _vault,
        string memory _name
    ) BaseStrategy(_asset, FLOW_GOVERNANCE_DAO, _vault, _name) {
        // Initialize governance configuration
        governanceConfig = GovernanceConfig({
            maxVeTokenLockTime: 4 * 365 days, // 4 years max lock
            minVotingThreshold: 1000 * 10**18, // 1000 tokens minimum
            bribeMinimumReward: 10 * 10**6, // 10 USDC minimum bribe
            autoVoteThreshold: 10000 * 10**18, // 10K tokens for auto-voting
            enableBribeHunting: true,
            enableAutoVoting: true,
            enableProposalCreation: false, // Start disabled
            enableFeeOptimization: true,
            delegationStrategy: 1 // Delegate to top performers
        });
        
        _initializeProtocolGovernance();
    }

    function _initializeProtocolGovernance() internal {
        // Flow DAO
        protocolGovernance[FLOW_GOVERNANCE_DAO] = ProtocolGovernance({
            protocolName: "Flow DAO",
            daoAddress: FLOW_GOVERNANCE_DAO,
            governanceToken: FLOW_TOKEN,
            voteEscrow: address(0), // If Flow has ve-tokenomics
            totalStaked: 0,
            votingPower: 0,
            feesEarned: 0,
            bribesEarned: 0,
            lastVoteTime: 0,
            autoVoteEnabled: true,
            defaultVoteDirection: 1, // Default to "for"
            minProposalValue: 100000 * 10**18 // 100K FLOW minimum
        });

        // IncrementFi DAO
        protocolGovernance[INCREMENTFI_DAO] = ProtocolGovernance({
            protocolName: "IncrementFi",
            daoAddress: INCREMENTFI_DAO,
            governanceToken: INCREMENTFI_TOKEN,
            voteEscrow: address(0),
            totalStaked: 0,
            votingPower: 0,
            feesEarned: 0,
            bribesEarned: 0,
            lastVoteTime: 0,
            autoVoteEnabled: true,
            defaultVoteDirection: 1,
            minProposalValue: 50000 * 10**18 // 50K tokens minimum
        });

        // More.Markets DAO
        protocolGovernance[MOREMARKET_DAO] = ProtocolGovernance({
            protocolName: "More.Markets",
            daoAddress: MOREMARKET_DAO,
            governanceToken: MOREMARKET_TOKEN,
            voteEscrow: address(0),
            totalStaked: 0,
            votingPower: 0,
            feesEarned: 0,
            bribesEarned: 0,
            lastVoteTime: 0,
            autoVoteEnabled: true,
            defaultVoteDirection: 1,
            minProposalValue: 25000 * 10**18 // 25K tokens minimum
        });

        supportedProtocols = [FLOW_GOVERNANCE_DAO, INCREMENTFI_DAO, MOREMARKET_DAO];
    }

    function _executeStrategy(uint256 amount, bytes calldata data) internal override {
        // Decode governance parameters
        (GovernanceStrategy strategy, address targetProtocol, uint256 lockTime) = data.length > 0 
            ? abi.decode(data, (GovernanceStrategy, address, uint256))
            : (GovernanceStrategy.ACTIVE_VOTING, FLOW_GOVERNANCE_DAO, 365 days);

        // Create governance position
        bytes32 positionId = _createGovernancePosition(targetProtocol, amount, strategy, lockTime);
        
        // Scan for immediate opportunities
        _scanGovernanceOpportunities();
        
        // Execute strategy-specific actions
        if (strategy == GovernanceStrategy.BRIBE_MAXIMIZATION) {
            _optimizeForBribes(positionId);
        } else if (strategy == GovernanceStrategy.FEE_MAXIMIZATION) {
            _optimizeForFees(positionId);
        } else if (strategy == GovernanceStrategy.DELEGATION_FARMING) {
            _optimizeForDelegation(positionId);
        }
    }

    function _createGovernancePosition(
        address protocol,
        uint256 amount,
        GovernanceStrategy strategy,
        uint256 lockTime
    ) internal returns (bytes32 positionId) {
        require(_isProtocolSupported(protocol), "Protocol not supported");
        
        positionId = keccak256(abi.encodePacked(
            protocol,
            strategy,
            block.timestamp,
            positionCounter++
        ));
        
        ProtocolGovernance storage protocolGov = protocolGovernance[protocol];
        address governanceToken = protocolGov.governanceToken;
        
        // Transfer governance tokens to this contract
        IERC20(governanceToken).transferFrom(msg.sender, address(this), amount);
        
        // Handle vote escrow if available
        bool isVeToken = false;
        uint256 votingPower = amount;
        uint256 lockEndTime = 0;
        
        if (protocolGov.voteEscrow != address(0) && lockTime > 0) {
            // Create vote escrow lock
            IERC20(governanceToken).approve(protocolGov.voteEscrow, amount);
            IVoteEscrow(protocolGov.voteEscrow).createLock(amount, block.timestamp + lockTime);
            
            isVeToken = true;
            lockEndTime = block.timestamp + lockTime;
            votingPower = IVoteEscrow(protocolGov.voteEscrow).getVotingPower(address(this));
        }
        
        // Create position record
        governancePositions[positionId] = GovernancePosition({
            positionId: positionId,
            protocol: protocol,
            governanceToken: governanceToken,
            stakedAmount: amount,
            lockEndTime: lockEndTime,
            votingPower: votingPower,
            accruedFees: 0,
            accruedBribes: 0,
            lastRewardClaim: block.timestamp,
            isVeToken: isVeToken,
            strategy: strategy
        });
        
        activePositions.push(positionId);
        
        // Update protocol governance stats
        protocolGov.totalStaked += amount;
        protocolGov.votingPower += votingPower;
        
        emit GovernancePositionCreated(positionId, protocol, amount, strategy);
        
        return positionId;
    }

    function _scanGovernanceOpportunities() internal {
        // Scan for active proposals across all protocols
        for (uint256 i = 0; i < supportedProtocols.length; i++) {
            address protocol = supportedProtocols[i];
            _scanProtocolProposals(protocol);
        }
        
        // Scan for bribe opportunities
        if (governanceConfig.enableBribeHunting) {
            _scanBribeOpportunities();
        }
    }

    function _scanProtocolProposals(address protocol) internal {
        IGovernanceDAO dao = IGovernanceDAO(protocol);
        
        try dao.getActiveProposals() returns (uint256[] memory activeProposals) {
            for (uint256 i = 0; i < activeProposals.length; i++) {
                uint256 proposalId = activeProposals[i];
                _evaluateProposal(protocol, proposalId);
            }
        } catch {
            // Failed to get active proposals
        }
    }

    function _evaluateProposal(address protocol, uint256 proposalId) internal {
        IGovernanceDAO dao = IGovernanceDAO(protocol);
        ProtocolGovernance storage protocolGov = protocolGovernance[protocol];
        
        try dao.getProposal(proposalId) returns (IGovernanceDAO.Proposal memory proposal) {
            // Skip if proposal is too small or already ended
            if (block.timestamp >= proposal.endTime) return;
            
            uint256 ourVotingPower = dao.getVotingPower(address(this));
            if (ourVotingPower < protocolGov.minProposalValue) return;
            
            // Determine optimal vote direction
            uint8 voteDirection = _determineVoteDirection(protocol, proposal);
            
            // Check for bribe opportunities
            uint256 expectedBribe = _checkBribeReward(proposalId, voteDirection);
            
            // Auto-vote if enabled and criteria met
            if (protocolGov.autoVoteEnabled && 
                governanceConfig.enableAutoVoting && 
                ourVotingPower >= governanceConfig.autoVoteThreshold) {
                
                _castVote(protocol, proposalId, voteDirection, expectedBribe, true);
            }
        } catch {
            // Failed to get proposal details
        }
    }

    function _determineVoteDirection(
        address protocol,
        IGovernanceDAO.Proposal memory proposal
    ) internal view returns (uint8) {
        ProtocolGovernance storage protocolGov = protocolGovernance[protocol];
        
        // Simplified decision logic - in reality would be much more sophisticated
        // Could integrate with AI oracle for decision making
        
        // Check if it's our proposal
        if (ourProposals[proposal.id]) {
            return 1; // Vote for our own proposals
        }
        
        // Check proposal value/impact
        if (proposal.targets.length > 0) {
            // Analyze proposal content (simplified)
            // In reality would parse calldata and analyze impact
            
            // Default to protocol's default vote direction
            return protocolGov.defaultVoteDirection;
        }
        
        return protocolGov.defaultVoteDirection;
    }

    function _checkBribeReward(uint256 proposalId, uint8 voteDirection) internal view returns (uint256) {
        if (!governanceConfig.enableBribeHunting) return 0;
        
        try IBribeMarketplace(BRIBE_MARKETPLACE).getBribeOffers(proposalId) returns (
            IBribeMarketplace.BribeOffer[] memory offers
        ) {
            uint256 totalExpectedReward = 0;
            
            for (uint256 i = 0; i < offers.length; i++) {
                IBribeMarketplace.BribeOffer memory offer = offers[i];
                
                if (offer.active && 
                    offer.supportDirection == voteDirection && 
                    block.timestamp <= offer.deadline) {
                    
                    uint256 reward = IBribeMarketplace(BRIBE_MARKETPLACE).calculateBribeReward(offer.offerId, address(this));
                    totalExpectedReward += reward;
                }
            }
            
            return totalExpectedReward;
        } catch {
            return 0;
        }
    }

    function _castVote(
        address protocol,
        uint256 proposalId,
        uint8 voteDirection,
        uint256 expectedBribe,
        bool automated
    ) internal {
        IGovernanceDAO dao = IGovernanceDAO(protocol);
        
        try dao.castVoteWithReason(
            proposalId,
            voteDirection,
            automated ? "Automated vote via FlowGovernanceStrategy" : "Manual strategic vote"
        ) returns (uint256 votingPower) {
            
            // Record voting decision
            votingDecisionCounter++;
            votingHistory[votingDecisionCounter] = VotingDecision({
                proposalId: proposalId,
                protocol: protocol,
                voteDirection: voteDirection,
                votingPower: votingPower,
                reason: automated ? "Auto-vote" : "Manual-vote",
                expectedBribe: expectedBribe,
                actualBribe: 0, // Will be updated when claimed
                timestamp: block.timestamp,
                automated: automated
            });
            
            votingDecisionIds.push(votingDecisionCounter);
            totalVotesCast++;
            
            // Update protocol stats
            protocolGovernance[protocol].lastVoteTime = block.timestamp;
            
            emit VoteCast(proposalId, protocol, voteDirection, votingPower, expectedBribe);
            
            // Try to claim bribe immediately if available
            if (expectedBribe > 0) {
                _claimAvailableBribes(proposalId, voteDirection);
            }
            
        } catch {
            // Vote casting failed
        }
    }

    function _claimAvailableBribes(uint256 proposalId, uint8 voteDirection) internal {
        try IBribeMarketplace(BRIBE_MARKETPLACE).getBribeOffers(proposalId) returns (
            IBribeMarketplace.BribeOffer[] memory offers
        ) {
            for (uint256 i = 0; i < offers.length; i++) {
                IBribeMarketplace.BribeOffer memory offer = offers[i];
                
                if (offer.active && offer.supportDirection == voteDirection) {
                    try IBribeMarketplace(BRIBE_MARKETPLACE).claimBribe(offer.offerId, proposalId, voteDirection) returns (uint256 amount) {
                        if (amount > 0) {
                            totalBribesEarned += amount;
                            
                            // Update voting decision with actual bribe
                            if (votingDecisionCounter > 0) {
                                votingHistory[votingDecisionCounter].actualBribe += amount;
                            }
                            
                            emit BribeClaimed(keccak256(abi.encodePacked(offer.offerId, proposalId)), amount);
                        }
                    } catch {
                        // Bribe claim failed
                    }
                }
            }
        } catch {
            // Failed to get bribe offers
        }
    }

    function _scanBribeOpportunities() internal {
        // Scan active proposals for bribe opportunities
        for (uint256 i = 0; i < supportedProtocols.length; i++) {
            address protocol = supportedProtocols[i];
            IGovernanceDAO dao = IGovernanceDAO(protocol);
            
            try dao.getActiveProposals() returns (uint256[] memory activeProposals) {
                for (uint256 j = 0; j < activeProposals.length; j++) {
                    uint256 proposalId = activeProposals[j];
                    _scanProposalBribes(protocol, proposalId);
                }
            } catch {
                // Failed to scan proposals
            }
        }
    }

    function _scanProposalBribes(address protocol, uint256 proposalId) internal {
        try IBribeMarketplace(BRIBE_MARKETPLACE).getBribeOffers(proposalId) returns (
            IBribeMarketplace.BribeOffer[] memory offers
        ) {
            for (uint256 i = 0; i < offers.length; i++) {
                IBribeMarketplace.BribeOffer memory offer = offers[i];
                
                if (offer.active && block.timestamp <= offer.deadline) {
                    uint256 expectedReward = IBribeMarketplace(BRIBE_MARKETPLACE).calculateBribeReward(offer.offerId, address(this));
                    
                    if (expectedReward >= governanceConfig.bribeMinimumReward) {
                        bytes32 opportunityId = keccak256(abi.encodePacked(offer.offerId, proposalId, protocol));
                        
                        bribeOpportunities[opportunityId] = BribeOpportunity({
                            offerId: offer.offerId,
                            proposalId: proposalId,
                            protocol: protocol,
                            bribeToken: offer.bribeToken,
                            expectedReward: expectedReward,
                            requiredVoteDirection: offer.supportDirection,
                            deadline: offer.deadline,
                            confidence: 8500, // 85% confidence
                            claimed: false
                        });
                        
                        activeBribeOpportunities.push(opportunityId);
                        
                        emit BribeOpportunityFound(opportunityId, proposalId, expectedReward);
                    }
                }
            }
        } catch {
            // Failed to scan bribes
        }
    }

    function _optimizeForBribes(bytes32 positionId) internal {
        // Focus on maximizing bribe rewards
        GovernancePosition storage position = governancePositions[positionId];
        
        // Vote on all proposals with available bribes
        for (uint256 i = 0; i < activeBribeOpportunities.length; i++) {
            bytes32 opportunityId = activeBribeOpportunities[i];
            BribeOpportunity storage opportunity = bribeOpportunities[opportunityId];
            
            if (!opportunity.claimed && 
                opportunity.protocol == position.protocol &&
                block.timestamp <= opportunity.deadline) {
                
                _castVote(
                    opportunity.protocol,
                    opportunity.proposalId,
                    opportunity.requiredVoteDirection,
                    opportunity.expectedReward,
                    true
                );
                
                opportunity.claimed = true;
            }
        }
    }

    function _optimizeForFees(bytes32 positionId) internal {
        // Focus on maximizing protocol fee sharing
        GovernancePosition storage position = governancePositions[positionId];
        
        // Stake in fee sharing contracts if available
        IProtocolFeeSharing feeSharing = IProtocolFeeSharing(PROTOCOL_FEE_SHARING);
        
        // Check claimable fees
        try feeSharing.getClaimableeFees(position.protocol, address(assetToken), address(this)) returns (uint256 claimable) {
            if (claimable > 0) {
                feeSharing.claimFees(position.protocol, address(assetToken));
                position.accruedFees += claimable;
                totalFeesEarned += claimable;
                
                emit ProtocolFeesClaimed(position.protocol, address(assetToken), claimable);
            }
        } catch {
            // Fee claiming failed
        }
    }

    function _optimizeForDelegation(bytes32 positionId) internal {
        // Delegate voting power to high-performing voters
        GovernancePosition storage position = governancePositions[positionId];
        
        if (governanceConfig.delegationStrategy == 1) {
            // Find top-performing delegatee
            address bestDelegatee = _findBestDelegatee(position.protocol);
            
            if (bestDelegatee != address(0) && bestDelegatee != address(this)) {
                IGovernanceToken(position.governanceToken).delegate(bestDelegatee);
                delegatedTo[position.protocol] = bestDelegatee;
                
                emit VotingPowerDelegated(position.protocol, bestDelegatee, position.votingPower);
            }
        }
    }

    function _findBestDelegatee(address protocol) internal view returns (address) {
        // Simplified - in reality would analyze on-chain voting performance
        // Could integrate with analytics to find most profitable voters
        return address(0); // Return best delegatee based on performance analysis
    }

    function _harvestRewards(bytes calldata) internal override {
        // Harvest rewards from all active governance positions
        for (uint256 i = 0; i < activePositions.length; i++) {
            bytes32 positionId = activePositions[i];
            _harvestGovernanceRewards(positionId);
        }
        
        // Scan for new opportunities
        _scanGovernanceOpportunities();
        
        // Clean up expired bribe opportunities
        _cleanupExpiredBribes();
    }

    function _harvestGovernanceRewards(bytes32 positionId) internal {
        GovernancePosition storage position = governancePositions[positionId];
        
        uint256 feesHarvested = 0;
        uint256 bribesHarvested = 0;
        uint256 govTokensHarvested = 0;
        
        // Claim protocol fees
        IProtocolFeeSharing feeSharing = IProtocolFeeSharing(PROTOCOL_FEE_SHARING);
        try feeSharing.claimFees(position.protocol, address(assetToken)) returns (uint256 fees) {
            feesHarvested = fees;
            position.accruedFees += fees;
            totalFeesEarned += fees;
        } catch {
            // Fee claim failed
        }
        
        // Claim any pending bribes
        for (uint256 i = 0; i < activeBribeOpportunities.length; i++) {
            bytes32 opportunityId = activeBribeOpportunities[i];
            BribeOpportunity storage opportunity = bribeOpportunities[opportunityId];
            
            if (!opportunity.claimed && opportunity.protocol == position.protocol) {
                try IBribeMarketplace(BRIBE_MARKETPLACE).claimBribe(
                    opportunity.offerId,
                    opportunity.proposalId,
                    opportunity.requiredVoteDirection
                ) returns (uint256 bribeAmount) {
                    bribesHarvested += bribeAmount;
                    position.accruedBribes += bribeAmount;
                    totalBribesEarned += bribeAmount;
                    opportunity.claimed = true;
                } catch {
                    // Bribe claim failed
                }
            }
        }
        
        // Update last reward claim time
        position.lastRewardClaim = block.timestamp;
        
        if (feesHarvested > 0 || bribesHarvested > 0 || govTokensHarvested > 0) {
            emit GovernanceRewardsHarvested(position.protocol, feesHarvested, bribesHarvested, govTokensHarvested);
        }
    }

    function _cleanupExpiredBribes() internal {
        uint256 activeCount = 0;
        
        // Count non-expired opportunities
        for (uint256 i = 0; i < activeBribeOpportunities.length; i++) {
            bytes32 opportunityId = activeBribeOpportunities[i];
            BribeOpportunity memory opportunity = bribeOpportunities[opportunityId];
            
            if (!opportunity.claimed && block.timestamp <= opportunity.deadline) {
                activeCount++;
            }
        }
        
        // Create new array with only active opportunities
        bytes32[] memory newActiveBribes = new bytes32[](activeCount);
        uint256 index = 0;
        
        for (uint256 i = 0; i < activeBribeOpportunities.length; i++) {
            bytes32 opportunityId = activeBribeOpportunities[i];
            BribeOpportunity memory opportunity = bribeOpportunities[opportunityId];
            
            if (!opportunity.claimed && block.timestamp <= opportunity.deadline) {
                newActiveBribes[index] = opportunityId;
                index++;
            }
        }
        
        activeBribeOpportunities = newActiveBribes;
    }

    function _emergencyWithdraw(bytes calldata) internal override returns (uint256 recovered) {
        uint256 totalRecovered = 0;
        
        // Withdraw from all governance positions
        for (uint256 i = 0; i < activePositions.length; i++) {
            bytes32 positionId = activePositions[i];
            totalRecovered += _emergencyWithdrawPosition(positionId);
        }
        
        // Add liquid balance
        totalRecovered += assetToken.balanceOf(address(this));
        
        return totalRecovered;
    }

    function _emergencyWithdrawPosition(bytes32 positionId) internal returns (uint256 recovered) {
        GovernancePosition storage position = governancePositions[positionId];
        
        if (position.isVeToken && position.lockEndTime > block.timestamp) {
            // Can't withdraw locked ve-tokens early
            return 0;
        }
        
        // Withdraw from vote escrow if unlocked
        if (position.isVeToken && block.timestamp >= position.lockEndTime) {
            ProtocolGovernance storage protocolGov = protocolGovernance[position.protocol];
            try IVoteEscrow(protocolGov.voteEscrow).withdraw() {
                recovered = position.stakedAmount;
            } catch {
                // Withdrawal failed
            }
        } else {
            // Transfer governance tokens back
            IERC20(position.governanceToken).transfer(vault, position.stakedAmount);
            recovered = position.stakedAmount;
        }
        
        return recovered;
    }

    function getBalance() external view override returns (uint256) {
        uint256 totalBalance = assetToken.balanceOf(address(this));
        
        // Add value of all governance positions
        for (uint256 i = 0; i < activePositions.length; i++) {
            bytes32 positionId = activePositions[i];
            GovernancePosition memory position = governancePositions[positionId];
            
            // Add staked amount (simplified valuation)
            totalBalance += position.stakedAmount;
            totalBalance += position.accruedFees;
            totalBalance += position.accruedBribes;
        }
        
        return totalBalance;
    }

    function _isProtocolSupported(address protocol) internal view returns (bool) {
        for (uint256 i = 0; i < supportedProtocols.length; i++) {
            if (supportedProtocols[i] == protocol) {
                return true;
            }
        }
        return false;
    }

    // Manual functions
    function manualVote(address protocol, uint256 proposalId, uint8 voteDirection) external onlyRole(HARVESTER_ROLE) {
        uint256 expectedBribe = _checkBribeReward(proposalId, voteDirection);
        _castVote(protocol, proposalId, voteDirection, expectedBribe, false);
    }

    function manualClaimBribes(uint256 proposalId) external onlyRole(HARVESTER_ROLE) {
        for (uint8 direction = 0; direction <= 2; direction++) {
            _claimAvailableBribes(proposalId, direction);
        }
    }

    function manualHarvestPosition(bytes32 positionId) external onlyRole(HARVESTER_ROLE) {
        _harvestGovernanceRewards(positionId);
    }

    // Admin functions
    function updateGovernanceConfig(
        uint256 maxLockTime,
        uint256 minVotingThreshold,
        uint256 bribeMinReward,
        bool enableBribes,
        bool enableAutoVoting,
        bool enableProposals
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        governanceConfig.maxVeTokenLockTime = maxLockTime;
        governanceConfig.minVotingThreshold = minVotingThreshold;
        governanceConfig.bribeMinimumReward = bribeMinReward;
        governanceConfig.enableBribeHunting = enableBribes;
        governanceConfig.enableAutoVoting = enableAutoVoting;
        governanceConfig.enableProposalCreation = enableProposals;
    }

    function addProtocol(
        string calldata name,
        address daoAddress,
        address governanceToken,
        address voteEscrow,
        uint8 defaultVoteDirection
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        protocolGovernance[daoAddress] = ProtocolGovernance({
            protocolName: name,
            daoAddress: daoAddress,
            governanceToken: governanceToken,
            voteEscrow: voteEscrow,
            totalStaked: 0,
            votingPower: 0,
            feesEarned: 0,
            bribesEarned: 0,
            lastVoteTime: 0,
            autoVoteEnabled: true,
            defaultVoteDirection: defaultVoteDirection,
            minProposalValue: 10000 * 10**18
        });
        
        supportedProtocols.push(daoAddress);
    }

    function updateProtocolSettings(
        address protocol,
        bool autoVoteEnabled,
        uint8 defaultVoteDirection,
        uint256 minProposalValue
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_isProtocolSupported(protocol), "Protocol not supported");
        
        ProtocolGovernance storage protocolGov = protocolGovernance[protocol];
        protocolGov.autoVoteEnabled = autoVoteEnabled;
        protocolGov.defaultVoteDirection = defaultVoteDirection;
        protocolGov.minProposalValue = minProposalValue;
    }

    // View functions
    function getGovernancePerformance() external view returns (
        uint256 totalGovTokens,
        uint256 totalFees,
        uint256 totalBribes,
        uint256 totalVotes,
        uint256 totalProposals,
        uint256 activePositionCount
    ) {
        totalGovTokens = totalGovernanceTokensEarned;
        totalFees = totalFeesEarned;
        totalBribes = totalBribesEarned;
        totalVotes = totalVotesCast;
        totalProposals = totalProposalsCreated;
        activePositionCount = activePositions.length;
    }

    function getGovernancePosition(bytes32 positionId) external view returns (GovernancePosition memory) {
        return governancePositions[positionId];
    }

    function getProtocolGovernance(address protocol) external view returns (ProtocolGovernance memory) {
        return protocolGovernance[protocol];
    }

    function getActivePositions() external view returns (GovernancePosition[] memory) {
        GovernancePosition[] memory positions = new GovernancePosition[](activePositions.length);
        
        for (uint256 i = 0; i < activePositions.length; i++) {
            positions[i] = governancePositions[activePositions[i]];
        }
        
        return positions;
    }

    function getVotingHistory(uint256 limit) external view returns (VotingDecision[] memory) {
        uint256 length = votingDecisionIds.length > limit ? limit : votingDecisionIds.length;
        VotingDecision[] memory decisions = new VotingDecision[](length);
        
        for (uint256 i = 0; i < length; i++) {
            uint256 index = votingDecisionIds.length - 1 - i; // Most recent first
            decisions[i] = votingHistory[votingDecisionIds[index]];
        }
        
        return decisions;
    }

    function getActiveBribeOpportunities() external view returns (BribeOpportunity[] memory) {
        BribeOpportunity[] memory opportunities = new BribeOpportunity[](activeBribeOpportunities.length);
        
        for (uint256 i = 0; i < activeBribeOpportunities.length; i++) {
            opportunities[i] = bribeOpportunities[activeBribeOpportunities[i]];
        }
        
        return opportunities;
    }

    function getSupportedProtocols() external view returns (address[] memory) {
        return supportedProtocols;
    }

    // Handle ETH for transaction fees
    receive() external payable {}
}