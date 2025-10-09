// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IVaultCore {
    function getUserPosition(address user) external view returns (
        uint256 totalShares,
        uint256 totalDeposited,
        uint256 lastDeposit,
        bool hasWithdrawalRequest,
        uint256 requestedAmount,
        bool yieldEligible,
        uint8 riskLevel
    );
    
    function getUserAssetBalance(address user, address asset) external view returns (uint256);
    
    function getAssetBalance(address asset) external view returns (
        uint256 vaultBalance,
        uint256 strategyBalance,
        uint256 cadenceBalance,
        uint256 totalBalance
    );
    
    function getVaultMetrics() external view returns (
        uint256 totalValueLocked,
        uint256 totalUsers,
        uint256 totalSupply,
        uint256 totalPrincipal,
        uint256 totalYieldGenerated,
        uint256 totalYieldDistributed,
        uint256 totalBridgedToCadence,
        uint256 totalBridgedFromCadence
    );
    
    function getSupportedAssets() external view returns (address[] memory);
    function getWhitelistedStrategies() external view returns (address[] memory);
    function getUserWithdrawalRequests(address user) external view returns (uint256[] memory);
}

interface IVaultExtension {
    function getUserDeposit(address user) external view returns (
        uint256 totalDeposited,
        uint256 currentBalance,
        uint256 firstDepositEpoch,
        uint256 lastDepositEpoch,
        uint8 riskLevel,
        uint256 vrfMultiplier,
        bool yieldEligible
    );
    
    function getUserEpochStatus(address user) external view returns (
        bool eligibleForCurrentEpoch,
        uint256 currentEpoch,
        uint256 timeRemaining,
        bool hasUnclaimedRewards,
        uint8 riskLevel
    );
    
    function getClaimableEpochs(address user) external view returns (uint256[] memory);
    
    function calculateUserReward(address user, uint256 epochNumber) external view returns (
        uint256 baseYield,
        uint256 vrfMultiplier,
        uint256 winProbability,
        uint256 potentialPayout
    );
    
    function getAvailableMultipliers() external view returns (
        uint256[] memory multipliers,
        uint256[] memory probabilities
    );
}

interface IPriceOracle {
    function getNormalizedPrice(address token) external view returns (uint256);
}

interface IRiskManager {
    function checkRisk() external view returns (bool healthy, uint256 riskScore);
    function getRiskMetrics() external view returns (
        uint256 totalLeverage,
        uint256 avgHealthFactor,
        bool emergency
    );
}

interface IStrategyManager {
    function getActiveStrategies() external view returns (address[] memory);
    function getStrategyInfo(address strategy) external view returns (
        string memory strategyType,
        address underlyingAsset,
        uint256 totalDeployed,
        uint256 totalHarvested,
        uint256 lastHarvestTime,
        bool active,
        bool emergency
    );
    function getStrategyPerformance(address strategy) external view returns (
        uint256 totalReturns,
        uint256 totalLosses,
        uint256 harvestCount,
        uint256 avgHarvestAmount,
        uint256 apy
    );
}

/// @title VaultFrontendHelper - Aggregated queries for frontend
/// @notice Provides comprehensive data views for frontend applications
contract VaultFrontendHelper {
    
    IVaultCore public immutable vaultCore;
    IVaultExtension public immutable vaultExtension;
    IPriceOracle public immutable priceOracle;
    IRiskManager public immutable riskManager;
    IStrategyManager public immutable strategyManager;
    
    struct UserDashboard {
        uint256 totalShares;
        uint256 totalDepositedUSD;
        uint256 currentValueUSD;
        uint256 profitLossUSD;
        uint256 profitLossPercent;
        bool hasWithdrawalRequest;
        uint256 requestedWithdrawalAmount;
        bool yieldEligible;
        uint256 vrfMultiplier;
        uint256 claimableEpochsCount;
        uint256 estimatedYieldUSD;
        uint8 riskLevel;
        uint256 healthFactor;
    }
    
    struct VaultOverview {
        uint256 totalValueLockedUSD;
        uint256 totalUsers;
        uint256 totalYieldGenerated;
        uint256 totalYieldDistributed;
        uint256 currentAPY;
        uint256 vaultHealthScore;
        bool emergencyMode;
        uint256 totalBridgedToCadence;
        uint256 totalBridgedFromCadence;
    }
    
    struct AssetBreakdown {
        address asset;
        string symbol;
        uint256 vaultBalance;
        uint256 strategyBalance;
        uint256 cadenceBalance;
        uint256 totalBalance;
        uint256 totalValueUSD;
        uint256 percentOfVault;
    }
    
    struct StrategyOverview {
        address strategy;
        string strategyType;
        address underlyingAsset;
        uint256 totalDeployedUSD;
        uint256 totalHarvestedUSD;
        uint256 apy;
        bool active;
        uint256 performanceScore;
    }
    
    struct EpochRewardInfo {
        uint256 epochNumber;
        uint256 baseYield;
        uint256 vrfMultiplier;
        uint256 winProbability;
        uint256 potentialPayout;
        bool canClaim;
    }
    
    constructor(
        address _vaultCore,
        address _vaultExtension,
        address _priceOracle,
        address _riskManager,
        address _strategyManager
    ) {
        require(_vaultCore != address(0), "Invalid vault core");
        
        vaultCore = IVaultCore(_vaultCore);
        vaultExtension = IVaultExtension(_vaultExtension);
        priceOracle = IPriceOracle(_priceOracle);
        riskManager = IRiskManager(_riskManager);
        strategyManager = IStrategyManager(_strategyManager);
    }
    
    // ====================================================================
    // USER QUERIES
    // ====================================================================
    function getUserDashboard(address user) external view returns (UserDashboard memory dashboard) {
        (
            uint256 totalShares,
            uint256 totalDeposited,
            ,
            bool hasWithdrawalRequest,
            uint256 requestedAmount,
            bool yieldEligible,
            uint8 riskLevel
        ) = vaultCore.getUserPosition(user);
        
        dashboard.totalShares = totalShares;
        dashboard.hasWithdrawalRequest = hasWithdrawalRequest;
        dashboard.requestedWithdrawalAmount = requestedAmount;
        dashboard.yieldEligible = yieldEligible;
        dashboard.riskLevel = riskLevel;
        dashboard.totalDepositedUSD = totalDeposited;
        dashboard.currentValueUSD = totalDeposited;
        dashboard.profitLossUSD = 0;
        dashboard.profitLossPercent = 0;
        
        if (address(vaultExtension) != address(0)) {
            try vaultExtension.getUserDeposit(user) returns (
                uint256,
                uint256,
                uint256,
                uint256,
                uint8,
                uint256 vrfMultiplier,
                bool
            ) {
                dashboard.vrfMultiplier = vrfMultiplier;
            } catch {}
            
            try vaultExtension.getClaimableEpochs(user) returns (uint256[] memory claimableEpochs) {
                dashboard.claimableEpochsCount = claimableEpochs.length;
            } catch {}
        }
        
        if (address(riskManager) != address(0)) {
            try riskManager.getRiskMetrics() returns (
                uint256,
                uint256 avgHealthFactor,
                bool
            ) {
                dashboard.healthFactor = avgHealthFactor;
            } catch {}
        }
        
        return dashboard;
    }
    
    function getUserAssetBalances(address user, address[] calldata assets) 
        external 
        view 
        returns (uint256[] memory balances, uint256[] memory valuesUSD) 
    {
        balances = new uint256[](assets.length);
        valuesUSD = new uint256[](assets.length);
        
        for (uint256 i = 0; i < assets.length; i++) {
            balances[i] = vaultCore.getUserAssetBalance(user, assets[i]);
            
            if (address(priceOracle) != address(0)) {
                try priceOracle.getNormalizedPrice(assets[i]) returns (uint256 price) {
                    valuesUSD[i] = (balances[i] * price) / 1e18;
                } catch {
                    valuesUSD[i] = balances[i];
                }
            } else {
                valuesUSD[i] = balances[i];
            }
        }
        
        return (balances, valuesUSD);
    }
    
    function getUserRewardInfo(address user) 
        external 
        view 
        returns (EpochRewardInfo[] memory rewardInfos) 
    {
        if (address(vaultExtension) == address(0)) {
            return new EpochRewardInfo[](0);
        }
        
        uint256[] memory claimableEpochs = vaultExtension.getClaimableEpochs(user);
        rewardInfos = new EpochRewardInfo[](claimableEpochs.length);
        
        for (uint256 i = 0; i < claimableEpochs.length; i++) {
            (
                uint256 baseYield,
                uint256 vrfMultiplier,
                uint256 winProbability,
                uint256 potentialPayout
            ) = vaultExtension.calculateUserReward(user, claimableEpochs[i]);
            
            rewardInfos[i] = EpochRewardInfo({
                epochNumber: claimableEpochs[i],
                baseYield: baseYield,
                vrfMultiplier: vrfMultiplier,
                winProbability: winProbability,
                potentialPayout: potentialPayout,
                canClaim: true
            });
        }
        
        return rewardInfos;
    }
    
    // ====================================================================
    // VAULT OVERVIEW QUERIES
    // ====================================================================
    function getVaultOverview() external view returns (VaultOverview memory overview) {
        (
            uint256 tvl,
            uint256 totalUsers,
            ,
            ,
            uint256 totalYieldGenerated,
            uint256 totalYieldDistributed,
            uint256 totalBridgedToCadence,
            uint256 totalBridgedFromCadence
        ) = vaultCore.getVaultMetrics();
        
        overview.totalValueLockedUSD = tvl;
        overview.totalUsers = totalUsers;
        overview.totalYieldGenerated = totalYieldGenerated;
        overview.totalYieldDistributed = totalYieldDistributed;
        overview.totalBridgedToCadence = totalBridgedToCadence;
        overview.totalBridgedFromCadence = totalBridgedFromCadence;
        
        if (tvl > 0 && totalYieldGenerated > 0) {
            overview.currentAPY = (totalYieldGenerated * 365 days * 10000) / (tvl * 30 days);
        }
        
        if (address(riskManager) != address(0)) {
            try riskManager.checkRisk() returns (bool healthy, uint256 riskScore) {
                overview.vaultHealthScore = healthy ? 10000 - riskScore : riskScore;
            } catch {
                overview.vaultHealthScore = 5000;
            }
            
            try riskManager.getRiskMetrics() returns (
                uint256,
                uint256,
                bool emergency
            ) {
                overview.emergencyMode = emergency;
            } catch {}
        }
        
        return overview;
    }
    
    function getAssetBreakdowns() external view returns (AssetBreakdown[] memory breakdowns) {
        address[] memory assets = vaultCore.getSupportedAssets();
        breakdowns = new AssetBreakdown[](assets.length);
        
        (uint256 tvl, , , , , , , ) = vaultCore.getVaultMetrics();
        
        for (uint256 i = 0; i < assets.length; i++) {
            (
                uint256 vaultBalance,
                uint256 strategyBalance,
                uint256 cadenceBalance,
                uint256 totalBalance
            ) = vaultCore.getAssetBalance(assets[i]);
            
            uint256 valueUSD = totalBalance;
            if (address(priceOracle) != address(0)) {
                try priceOracle.getNormalizedPrice(assets[i]) returns (uint256 price) {
                    valueUSD = (totalBalance * price) / 1e18;
                } catch {}
            }
            
            breakdowns[i] = AssetBreakdown({
                asset: assets[i],
                symbol: _getAssetSymbol(assets[i]),
                vaultBalance: vaultBalance,
                strategyBalance: strategyBalance,
                cadenceBalance: cadenceBalance,
                totalBalance: totalBalance,
                totalValueUSD: valueUSD,
                percentOfVault: tvl > 0 ? (valueUSD * 10000) / tvl : 0
            });
        }
        
        return breakdowns;
    }
    
    function getStrategyOverviews() external view returns (StrategyOverview[] memory overviews) {
        if (address(strategyManager) == address(0)) {
            return new StrategyOverview[](0);
        }
        
        address[] memory strategies = strategyManager.getActiveStrategies();
        overviews = new StrategyOverview[](strategies.length);
        
        for (uint256 i = 0; i < strategies.length; i++) {
            (
                string memory strategyType,
                address underlyingAsset,
                uint256 totalDeployed,
                uint256 totalHarvested,
                ,
                bool active,
                
            ) = strategyManager.getStrategyInfo(strategies[i]);
            
            (
                ,
                ,
                ,
                ,
                uint256 apy
            ) = strategyManager.getStrategyPerformance(strategies[i]);
            
            uint256 performanceScore = totalDeployed > 0 
                ? (totalHarvested * 10000) / totalDeployed 
                : 0;
            
            overviews[i] = StrategyOverview({
                strategy: strategies[i],
                strategyType: strategyType,
                underlyingAsset: underlyingAsset,
                totalDeployedUSD: totalDeployed,
                totalHarvestedUSD: totalHarvested,
                apy: apy,
                active: active,
                performanceScore: performanceScore
            });
        }
        
        return overviews;
    }
    
    // ====================================================================
    // HELPER FUNCTIONS
    // ====================================================================
    function _getAssetSymbol(address asset) internal pure returns (string memory) {
        if (asset == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) return "FLOW";
        if (asset == 0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e) return "WFLOW";
        if (asset == 0x2aaBea2058b5aC2D339b163C6Ab6f2b6d53aabED) return "USDF";
        if (asset == 0xF1815bd50389c46847f0Bda824eC8da914045D14) return "STGUSD";
        if (asset == 0x674843C06FF83502ddb4D37c2E09C01cdA38cbc8) return "USDT";
        if (asset == 0x7f27352D5F83Db87a5A3E00f4B07Cc2138D8ee52) return "USDC.e";
        if (asset == 0x5598c0652B899EB40f169Dd5949BdBE0BF36ffDe) return "stFLOW";
        if (asset == 0x1b97100eA1D7126C4d60027e231EA4CB25314bdb) return "ankrFLOW";
        if (asset == 0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590) return "WETH";
        if (asset == 0xA0197b2044D28b08Be34d98b23c9312158Ea9A18) return "cbBTC";
        
        return "UNKNOWN";
    }
    
    function getVRFMultiplierOptions() external view returns (
        uint256[] memory multipliers,
        uint256[] memory probabilities,
        string[] memory descriptions
    ) {
        if (address(vaultExtension) == address(0)) {
            return (new uint256[](0), new uint256[](0), new string[](0));
        }
        
        (multipliers, probabilities) = vaultExtension.getAvailableMultipliers();
        
        descriptions = new string[](multipliers.length);
        descriptions[0] = "Guaranteed 1x";
        descriptions[1] = "50% chance for 2x";
        descriptions[2] = "20% chance for 5x";
        descriptions[3] = "10% chance for 10x";
        descriptions[4] = "2% chance for 50x";
        descriptions[5] = "1% chance for 100x";
        
        return (multipliers, probabilities, descriptions);
    }
}