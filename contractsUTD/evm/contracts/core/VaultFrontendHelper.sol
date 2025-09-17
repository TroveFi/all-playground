// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Define the interface locally instead of importing
interface IEpochRewardManager {
    enum RiskLevel { LOW, MEDIUM, HIGH }
    
    function recordDeposit(address user, address asset, uint256 amount, RiskLevel riskLevel) external;
    function recordWithdrawal(address user, address asset, uint256 amount) external returns (bool success);
    function addYield(address asset, uint256 amount) external;
    function isEligibleForEpoch(address user, uint256 epochNumber) external view returns (bool);
    function hasClaimedEpoch(address user, uint256 epochNumber) external view returns (bool);
    function claimEpochReward(uint256 epochNumber) external returns (bool won, uint256 rewardAmount);
    function getCurrentEpochStatus() external view returns (uint256 epochNumber, uint256 timeRemaining, uint256 yieldPool, uint256 participantCount);
    function getUserDeposit(address user) external view returns (uint256 totalDeposited, uint256 currentBalance, uint256 firstDepositEpoch, uint256 lastDepositEpoch, RiskLevel riskLevel, uint256 timeWeightedBalance);
    function setUserRiskLevel(RiskLevel newRiskLevel) external;
    function calculateRewardParameters(address user, uint256 epochNumber) external view returns (uint256 baseWeight, uint256 timeWeight, uint256 riskMultiplier, uint256 totalWeight, uint256 winProbability, uint256 potentialPayout);
}

interface ITrueMultiAssetVault {
    function getUserEpochStatus(address user) external view returns (
        bool eligibleForCurrentEpoch,
        uint256 currentEpoch,
        uint256 timeRemaining,
        bool hasUnclaimedRewards,
        IEpochRewardManager.RiskLevel riskLevel
    );
    
    function getUserPosition(address user) external view returns (
        uint256 totalShares,
        uint256 lastDeposit,
        bool withdrawalRequested,
        uint256 withdrawalAvailableAt,
        IEpochRewardManager.RiskLevel riskLevel,
        uint256 totalDeposited
    );
    
    function getClaimableEpochs(address user) external view returns (uint256[] memory claimableEpochs);
    
    function getUserRewardParameters(address user, uint256 epochNumber) external view returns (
        uint256 baseWeight,
        uint256 timeWeight,
        uint256 riskMultiplier,
        uint256 totalWeight,
        uint256 winProbability,
        uint256 potentialPayout
    );
}

/// @title VaultFrontendHelper - Helper contract for frontend queries
/// @notice Provides aggregated data for frontend applications
contract VaultFrontendHelper {
    
    ITrueMultiAssetVault public immutable vault;
    IEpochRewardManager public immutable epochRewardManager;
    
    enum ClaimStatus { 
        NOT_ELIGIBLE,      // User not eligible for any epochs
        ELIGIBLE,          // User eligible but hasn't claimed
        ALREADY_CLAIMED,   // User already claimed for epoch
        NO_UNCLAIMED       // User has no unclaimed rewards
    }
    
    struct UserClaimInfo {
        ClaimStatus status;
        uint256[] claimableEpochs;
        uint256 currentEpoch;
        uint256 timeUntilNextEpoch;
        bool hasActiveDeposit;
        IEpochRewardManager.RiskLevel riskLevel;
        uint256 totalDeposited;
        uint256 eligibleEpochsCount;
    }
    
    struct EpochRewardInfo {
        uint256 epochNumber;
        bool isEligible;
        bool hasClaimed;
        bool canClaim;
        uint256 winProbability;
        uint256 potentialPayout;
        uint256 baseWeight;
        uint256 timeWeight;
        uint256 riskMultiplier;
    }
    
    constructor(address _vault, address _epochRewardManager) {
        require(_vault != address(0), "Invalid vault");
        require(_epochRewardManager != address(0), "Invalid epoch manager");
        
        vault = ITrueMultiAssetVault(_vault);
        epochRewardManager = IEpochRewardManager(_epochRewardManager);
    }
    
    /// @notice Get comprehensive claim status for a user
    function getUserClaimStatus(address user) external view returns (UserClaimInfo memory info) {
        // Get current epoch status from vault
        (
            bool eligibleForCurrent, 
            uint256 currentEpoch, 
            uint256 timeRemaining, 
            bool hasUnclaimed, 
            IEpochRewardManager.RiskLevel riskLevel
        ) = vault.getUserEpochStatus(user);
            
        // Get user position from vault
        (
            uint256 totalShares, 
            , 
            , 
            , 
            , 
            uint256 totalDeposited
        ) = vault.getUserPosition(user);
        
        info.currentEpoch = currentEpoch;
        info.timeUntilNextEpoch = timeRemaining;
        info.hasActiveDeposit = totalShares > 0;
        info.riskLevel = riskLevel;
        info.totalDeposited = totalDeposited;
        
        if (!info.hasActiveDeposit) {
            info.status = ClaimStatus.NOT_ELIGIBLE;
            info.claimableEpochs = new uint256[](0);
            return info;
        }
        
        // Get claimable epochs from vault
        info.claimableEpochs = vault.getClaimableEpochs(user);
        info.eligibleEpochsCount = info.claimableEpochs.length;
        
        // Determine status based on claimable epochs
        if (info.claimableEpochs.length > 0) {
            info.status = ClaimStatus.ELIGIBLE;
        } else if (hasUnclaimed) {
            info.status = ClaimStatus.ALREADY_CLAIMED;
        } else {
            info.status = ClaimStatus.NO_UNCLAIMED;
        }
    }
    
    /// @notice Check if user can claim specific epoch
    function canClaimEpoch(address user, uint256 epochNumber) external view returns (bool canClaim, string memory reason) {
        // Check if epoch is eligible
        if (!epochRewardManager.isEligibleForEpoch(user, epochNumber)) {
            return (false, "Not eligible for this epoch");
        }
        
        // Check if already claimed
        if (epochRewardManager.hasClaimedEpoch(user, epochNumber)) {
            return (false, "Already claimed for this epoch");
        }
        
        // Check if epoch is completed
        (uint256 currentEpoch, , , ) = epochRewardManager.getCurrentEpochStatus();
        if (epochNumber >= currentEpoch) {
            return (false, "Epoch not completed yet");
        }
        
        return (true, "Can claim");
    }
    
    /// @notice Get detailed reward information for a specific epoch
    function getEpochRewardInfo(address user, uint256 epochNumber) external view returns (EpochRewardInfo memory info) {
        info.epochNumber = epochNumber;
        info.isEligible = epochRewardManager.isEligibleForEpoch(user, epochNumber);
        info.hasClaimed = epochRewardManager.hasClaimedEpoch(user, epochNumber);
        
        (bool canClaim, ) = this.canClaimEpoch(user, epochNumber);
        info.canClaim = canClaim;
        
        if (info.isEligible) {
            // Get reward parameters from vault
            (
                uint256 baseWeight,
                uint256 timeWeight,
                uint256 riskMultiplier,
                ,
                uint256 winProbability,
                uint256 potentialPayout
            ) = vault.getUserRewardParameters(user, epochNumber);
            
            info.baseWeight = baseWeight;
            info.timeWeight = timeWeight;
            info.riskMultiplier = riskMultiplier;
            info.winProbability = winProbability;
            info.potentialPayout = potentialPayout;
        }
    }
    
    /// @notice Get batch claim status for multiple epochs
    function getBatchClaimStatus(address user, uint256[] calldata epochs) external view returns (
        bool[] memory canClaim,
        string[] memory reasons
    ) {
        canClaim = new bool[](epochs.length);
        reasons = new string[](epochs.length);
        
        for (uint256 i = 0; i < epochs.length; i++) {
            (canClaim[i], reasons[i]) = this.canClaimEpoch(user, epochs[i]);
        }
    }
    
    /// @notice Get batch reward information for multiple epochs
    function getBatchEpochRewardInfo(address user, uint256[] calldata epochs) external view returns (
        EpochRewardInfo[] memory rewardInfos
    ) {
        rewardInfos = new EpochRewardInfo[](epochs.length);
        
        for (uint256 i = 0; i < epochs.length; i++) {
            rewardInfos[i] = this.getEpochRewardInfo(user, epochs[i]);
        }
    }
    
    /// @notice Get all available epochs for claiming
    function getAvailableClaimEpochs(address user) external view returns (uint256[] memory availableEpochs) {
        return vault.getClaimableEpochs(user);
    }
    
    /// @notice Get current epoch information
    function getCurrentEpochInfo() external view returns (
        uint256 epochNumber,
        uint256 timeRemaining,
        uint256 yieldPool,
        uint256 participantCount
    ) {
        return epochRewardManager.getCurrentEpochStatus();
    }
    
    /// @notice Get user's risk level and deposit information - FIXED VERSION
    function getUserRiskProfile(address user) external view returns (
        IEpochRewardManager.RiskLevel currentRiskLevel,
        uint256 totalDeposited,
        uint256 currentBalance,
        uint256 firstDepositEpoch,
        uint256 lastDepositEpoch,
        uint256 timeWeightedBalance
    ) {
        // Get the data from epochRewardManager
        (
            uint256 totalDep,
            uint256 currBal,
            uint256 firstEpoch,
            uint256 lastEpoch,
            IEpochRewardManager.RiskLevel riskLvl,
            uint256 timeWeight
        ) = epochRewardManager.getUserDeposit(user);
        
        // Return in the correct order
        return (
            riskLvl,           // currentRiskLevel
            totalDep,          // totalDeposited
            currBal,           // currentBalance
            firstEpoch,        // firstDepositEpoch
            lastEpoch,         // lastDepositEpoch
            timeWeight         // timeWeightedBalance
        );
    }
    
    /// @notice Check if user has any positions in the vault
    function hasActivePosition(address user) external view returns (bool) {
        (uint256 totalShares, , , , , ) = vault.getUserPosition(user);
        return totalShares > 0;
    }
    
    /// @notice Get comprehensive user dashboard data
    function getUserDashboard(address user) external view returns (
        UserClaimInfo memory claimInfo,
        EpochRewardInfo[] memory recentEpochsInfo,
        uint256 totalClaimableRewards,
        uint256 estimatedNextEpochReward
    ) {
        // Get claim info
        claimInfo = this.getUserClaimStatus(user);
        
        // Get recent epochs info (last 5 claimable)
        uint256[] memory claimableEpochs = claimInfo.claimableEpochs;
        uint256 recentCount = claimableEpochs.length > 5 ? 5 : claimableEpochs.length;
        recentEpochsInfo = new EpochRewardInfo[](recentCount);
        
        totalClaimableRewards = 0;
        
        for (uint256 i = 0; i < recentCount; i++) {
            recentEpochsInfo[i] = this.getEpochRewardInfo(user, claimableEpochs[i]);
            totalClaimableRewards += recentEpochsInfo[i].potentialPayout;
        }
        
        // Estimate next epoch reward if user has active position
        if (claimInfo.hasActiveDeposit && claimInfo.currentEpoch > 0) {
            try this.getEpochRewardInfo(user, claimInfo.currentEpoch) returns (EpochRewardInfo memory nextInfo) {
                estimatedNextEpochReward = nextInfo.potentialPayout;
            } catch {
                estimatedNextEpochReward = 0;
            }
        }
    }
    
    /// @notice Get system-wide statistics
    function getSystemStats() external view returns (
        uint256 currentEpoch,
        uint256 timeUntilNextEpoch,
        uint256 totalYieldPool,
        uint256 totalParticipants,
        uint256 epochDuration
    ) {
        (currentEpoch, timeUntilNextEpoch, totalYieldPool, totalParticipants) = epochRewardManager.getCurrentEpochStatus();
        
        // Epoch duration is typically 7 days, but this could be made configurable
        epochDuration = 7 days;
    }
    
    /// @notice Get simplified user status for quick frontend checks
    function getQuickUserStatus(address user) external view returns (
        bool hasDeposit,
        uint256 claimableCount,
        IEpochRewardManager.RiskLevel riskLevel,
        uint256 nextClaimableEpoch
    ) {
        // Check if user has deposit
        hasDeposit = this.hasActivePosition(user);
        
        if (!hasDeposit) {
            return (false, 0, IEpochRewardManager.RiskLevel.MEDIUM, 0);
        }
        
        // Get claimable epochs
        uint256[] memory claimableEpochs = vault.getClaimableEpochs(user);
        claimableCount = claimableEpochs.length;
        
        // Get risk level from vault
        (, , , , riskLevel, ) = vault.getUserPosition(user);
        
        // Get next claimable epoch
        nextClaimableEpoch = claimableCount > 0 ? claimableEpochs[0] : 0;
    }
    
    /// @notice Get user's total potential rewards across all claimable epochs
    function getTotalPotentialRewards(address user) external view returns (uint256 totalPotential) {
        uint256[] memory claimableEpochs = vault.getClaimableEpochs(user);
        
        for (uint256 i = 0; i < claimableEpochs.length; i++) {
            try vault.getUserRewardParameters(user, claimableEpochs[i]) returns (
                uint256,
                uint256,
                uint256,
                uint256,
                uint256,
                uint256 potentialPayout
            ) {
                totalPotential += potentialPayout;
            } catch {
                // Skip if reward calculation fails
            }
        }
    }
}