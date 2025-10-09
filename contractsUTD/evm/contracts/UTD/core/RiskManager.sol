// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

interface IPriceOracle {
    function getNormalizedPrice(address token) external view returns (uint256);
}

interface IVault {
    function totalValueLocked() external view returns (uint256);
    function totalPrincipal() external view returns (uint256);
    function getAssetBalance(address asset) external view returns (
        uint256 vaultBalance,
        uint256 strategyBalance,
        uint256 cadenceBalance,
        uint256 totalBalance
    );
}

/// @title RiskManager - Risk assessment and limits for the vault
/// @notice Monitors vault health, concentration risk, and strategy limits
contract RiskManager is AccessControl {
    
    // ====================================================================
    // ROLES
    // ====================================================================
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");
    bytes32 public constant RISK_ADMIN_ROLE = keccak256("RISK_ADMIN_ROLE");
    
    // ====================================================================
    // STRUCTS
    // ====================================================================
    struct RiskLimits {
        uint256 maxSingleAssetConcentration; // Max % of TVL in single asset (basis points)
        uint256 maxStrategyAllocation;       // Max % to single strategy (basis points)
        uint256 maxLeverage;                 // Max leverage ratio (basis points, 10000 = 1x)
        uint256 minHealthFactor;             // Minimum health factor (basis points)
        uint256 maxDrawdown;                 // Max acceptable drawdown (basis points)
        bool enforceChecks;                  // Whether to enforce risk checks
    }
    
    struct AssetRisk {
        uint256 riskScore;                   // Risk score 0-10000
        uint256 volatility;                  // Estimated volatility
        bool isStable;                       // Whether it's a stablecoin
        uint256 liquidityScore;              // Liquidity score 0-10000
    }
    
    struct StrategyRisk {
        uint256 riskLevel;                   // 1=LOW, 2=MEDIUM, 3=HIGH
        uint256 maxAllocation;               // Max allocation in basis points
        bool audited;                        // Whether strategy is audited
        uint256 tvlLimit;                    // Max TVL this strategy can handle
    }
    
    // ====================================================================
    // STATE VARIABLES
    // ====================================================================
    address public vault;
    IPriceOracle public priceOracle;
    
    RiskLimits public riskLimits;
    
    mapping(address => AssetRisk) public assetRisks;
    mapping(address => StrategyRisk) public strategyRisks;
    mapping(address => bool) public whitelistedAssets;
    mapping(address => bool) public whitelistedStrategies;
    
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant RISK_SCORE_MAX = 10000;
    
    bool public emergencyMode;
    
    // ====================================================================
    // EVENTS
    // ====================================================================
    event RiskLimitsUpdated(uint256 maxAssetConcentration, uint256 maxStrategyAllocation);
    event AssetRiskUpdated(address indexed asset, uint256 riskScore, bool isStable);
    event StrategyRiskUpdated(address indexed strategy, uint256 riskLevel, uint256 maxAllocation);
    event RiskCheckFailed(string reason, uint256 value, uint256 limit);
    event EmergencyModeToggled(bool enabled);
    
    // ====================================================================
    // CONSTRUCTOR
    // ====================================================================
    constructor(address _vault, address _priceOracle) {
        require(_vault != address(0), "Invalid vault");
        require(_priceOracle != address(0), "Invalid oracle");
        
        vault = _vault;
        priceOracle = IPriceOracle(_priceOracle);
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(VAULT_ROLE, _vault);
        _grantRole(RISK_ADMIN_ROLE, msg.sender);
        
        // Initialize default risk limits
        riskLimits = RiskLimits({
            maxSingleAssetConcentration: 3000,  // 30%
            maxStrategyAllocation: 2000,         // 20%
            maxLeverage: 15000,                  // 1.5x
            minHealthFactor: 15000,              // 1.5
            maxDrawdown: 2000,                   // 20%
            enforceChecks: true
        });
        
        _initializeDefaultAssetRisks();
    }
    
    // ====================================================================
    // INITIALIZATION
    // ====================================================================
    function _initializeDefaultAssetRisks() internal {
        // Stablecoins - Low risk
        _setAssetRisk(0x2aaBea2058b5aC2D339b163C6Ab6f2b6d53aabED, 100, true, 9000);  // USDF
        _setAssetRisk(0xF1815bd50389c46847f0Bda824eC8da914045D14, 150, true, 8500);  // STGUSD
        _setAssetRisk(0x674843C06FF83502ddb4D37c2E09C01cdA38cbc8, 100, true, 9500);  // USDT
        _setAssetRisk(0x7f27352D5F83Db87a5A3E00f4B07Cc2138D8ee52, 100, true, 9500);  // USDC.e
        
        // Native & Wrapped FLOW - Medium risk
        _setAssetRisk(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, 2500, false, 10000); // Native FLOW
        _setAssetRisk(0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e, 2500, false, 10000); // WFLOW
        
        // Liquid Staking Tokens - Medium risk
        _setAssetRisk(0x5598c0652B899EB40f169Dd5949BdBE0BF36ffDe, 3000, false, 7000);  // stFLOW
        _setAssetRisk(0x1b97100eA1D7126C4d60027e231EA4CB25314bdb, 3000, false, 7000);  // ankrFLOW
        
        // Volatile assets - Higher risk
        _setAssetRisk(0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590, 4000, false, 8000);  // WETH
        _setAssetRisk(0xA0197b2044D28b08Be34d98b23c9312158Ea9A18, 4500, false, 6000);  // cbBTC
    }
    
    function _setAssetRisk(
        address asset,
        uint256 riskScore,
        bool isStable,
        uint256 liquidityScore
    ) internal {
        assetRisks[asset] = AssetRisk({
            riskScore: riskScore,
            volatility: isStable ? 100 : riskScore,
            isStable: isStable,
            liquidityScore: liquidityScore
        });
        whitelistedAssets[asset] = true;
    }
    
    // ====================================================================
    // RISK CHECKS
    // ====================================================================
    function checkRisk() external view returns (bool healthy, uint256 riskScore) {
        if (!riskLimits.enforceChecks || emergencyMode) {
            return (true, 0);
        }
        
        IVault vaultContract = IVault(vault);
        uint256 tvl = vaultContract.totalValueLocked();
        
        if (tvl == 0) {
            return (true, 0);
        }
        
        // Calculate overall risk score (0-10000)
        uint256 overallRiskScore = _calculateOverallRisk();
        
        bool isHealthy = overallRiskScore < 7000; // Risk score below 70% is acceptable
        
        return (isHealthy, overallRiskScore);
    }
    
    function isWithinRiskLimits(uint256 amount) external view returns (bool) {
        if (!riskLimits.enforceChecks || emergencyMode) {
            return true;
        }
        
        IVault vaultContract = IVault(vault);
        uint256 tvl = vaultContract.totalValueLocked();
        
        if (tvl == 0) {
            return true;
        }
        
        // Check if single deposit is too large (> 10% of TVL)
        uint256 depositRatio = (amount * BASIS_POINTS) / tvl;
        if (depositRatio > 1000) { // 10%
            return false;
        }
        
        return true;
    }
    
    function checkAssetConcentration(address asset, uint256 amount) 
        external 
        view 
        returns (bool withinLimits, uint256 concentration) 
    {
        IVault vaultContract = IVault(vault);
        uint256 tvl = vaultContract.totalValueLocked();
        
        if (tvl == 0) {
            return (true, 0);
        }
        
        (, , , uint256 totalBalance) = vaultContract.getAssetBalance(asset);
        uint256 newTotal = totalBalance + amount;
        
        concentration = (newTotal * BASIS_POINTS) / tvl;
        withinLimits = concentration <= riskLimits.maxSingleAssetConcentration;
        
        return (withinLimits, concentration);
    }
    
    function checkStrategyAllocation(address strategy, uint256 amount) 
        external 
        view 
        returns (bool withinLimits, uint256 allocation) 
    {
        if (!strategyRisks[strategy].audited && amount > 0) {
            return (false, 0);
        }
        
        IVault vaultContract = IVault(vault);
        uint256 tvl = vaultContract.totalValueLocked();
        
        if (tvl == 0) {
            return (true, 0);
        }
        
        allocation = (amount * BASIS_POINTS) / tvl;
        
        uint256 maxAllowed = strategyRisks[strategy].maxAllocation;
        if (maxAllowed == 0) {
            maxAllowed = riskLimits.maxStrategyAllocation;
        }
        
        withinLimits = allocation <= maxAllowed;
        
        return (withinLimits, allocation);
    }
    
    function _calculateOverallRisk() internal view returns (uint256) {
        // Simplified risk calculation
        // In production, would aggregate risks from all positions
        
        IVault vaultContract = IVault(vault);
        uint256 tvl = vaultContract.totalValueLocked();
        uint256 principal = vaultContract.totalPrincipal();
        
        if (tvl == 0 || principal == 0) {
            return 0;
        }
        
        // Calculate leverage risk
        uint256 leverage = (tvl * BASIS_POINTS) / principal;
        uint256 leverageRisk = leverage > BASIS_POINTS 
            ? ((leverage - BASIS_POINTS) * 5000) / BASIS_POINTS 
            : 0;
        
        // Base risk score
        uint256 baseRisk = 1000; // 10% base risk
        
        return baseRisk + leverageRisk;
    }
    
    function performRiskCheck() external {
        (bool healthy, uint256 riskScore) = this.checkRisk();
        
        if (!healthy) {
            emit RiskCheckFailed("Overall risk too high", riskScore, 7000);
        }
    }
    
    // ====================================================================
    // RISK PARAMETER MANAGEMENT
    // ====================================================================
    function updateRiskLimits(
        uint256 maxAssetConcentration,
        uint256 maxStrategyAllocation,
        uint256 maxLeverage,
        uint256 minHealthFactor,
        uint256 maxDrawdown
    ) external onlyRole(RISK_ADMIN_ROLE) {
        require(maxAssetConcentration <= BASIS_POINTS, "Invalid asset concentration");
        require(maxStrategyAllocation <= BASIS_POINTS, "Invalid strategy allocation");
        require(maxLeverage >= BASIS_POINTS, "Invalid leverage");
        
        riskLimits.maxSingleAssetConcentration = maxAssetConcentration;
        riskLimits.maxStrategyAllocation = maxStrategyAllocation;
        riskLimits.maxLeverage = maxLeverage;
        riskLimits.minHealthFactor = minHealthFactor;
        riskLimits.maxDrawdown = maxDrawdown;
        
        emit RiskLimitsUpdated(maxAssetConcentration, maxStrategyAllocation);
    }
    
    function setAssetRisk(
        address asset,
        uint256 riskScore,
        uint256 volatility,
        bool isStable,
        uint256 liquidityScore
    ) external onlyRole(RISK_ADMIN_ROLE) {
        require(riskScore <= RISK_SCORE_MAX, "Invalid risk score");
        require(liquidityScore <= RISK_SCORE_MAX, "Invalid liquidity score");
        
        assetRisks[asset] = AssetRisk({
            riskScore: riskScore,
            volatility: volatility,
            isStable: isStable,
            liquidityScore: liquidityScore
        });
        
        whitelistedAssets[asset] = true;
        
        emit AssetRiskUpdated(asset, riskScore, isStable);
    }
    
    function setStrategyRisk(
        address strategy,
        uint256 riskLevel,
        uint256 maxAllocation,
        bool audited,
        uint256 tvlLimit
    ) external onlyRole(RISK_ADMIN_ROLE) {
        require(riskLevel >= 1 && riskLevel <= 3, "Invalid risk level");
        require(maxAllocation <= BASIS_POINTS, "Invalid max allocation");
        
        strategyRisks[strategy] = StrategyRisk({
            riskLevel: riskLevel,
            maxAllocation: maxAllocation,
            audited: audited,
            tvlLimit: tvlLimit
        });
        
        whitelistedStrategies[strategy] = true;
        
        emit StrategyRiskUpdated(strategy, riskLevel, maxAllocation);
    }
    
    function setEnforceChecks(bool enforce) external onlyRole(RISK_ADMIN_ROLE) {
        riskLimits.enforceChecks = enforce;
    }
    
    function setEmergencyMode(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emergencyMode = enabled;
        emit EmergencyModeToggled(enabled);
    }
    
    // ====================================================================
    // VIEW FUNCTIONS
    // ====================================================================
    function getAssetRisk(address asset) external view returns (
        uint256 riskScore,
        uint256 volatility,
        bool isStable,
        uint256 liquidityScore,
        bool whitelisted
    ) {
        AssetRisk memory risk = assetRisks[asset];
        return (
            risk.riskScore,
            risk.volatility,
            risk.isStable,
            risk.liquidityScore,
            whitelistedAssets[asset]
        );
    }
    
    function getStrategyRisk(address strategy) external view returns (
        uint256 riskLevel,
        uint256 maxAllocation,
        bool audited,
        uint256 tvlLimit,
        bool whitelisted
    ) {
        StrategyRisk memory risk = strategyRisks[strategy];
        return (
            risk.riskLevel,
            risk.maxAllocation,
            risk.audited,
            risk.tvlLimit,
            whitelistedStrategies[strategy]
        );
    }
    
    function getRiskLimits() external view returns (
        uint256 maxAssetConcentration,
        uint256 maxStrategyAllocation,
        uint256 maxLeverage,
        uint256 minHealthFactor,
        uint256 maxDrawdown,
        bool enforceChecks
    ) {
        return (
            riskLimits.maxSingleAssetConcentration,
            riskLimits.maxStrategyAllocation,
            riskLimits.maxLeverage,
            riskLimits.minHealthFactor,
            riskLimits.maxDrawdown,
            riskLimits.enforceChecks
        );
    }
    
    function getRiskMetrics() external view returns (
        uint256 totalLeverage,
        uint256 avgHealthFactor,
        bool emergency
    ) {
        IVault vaultContract = IVault(vault);
        uint256 tvl = vaultContract.totalValueLocked();
        uint256 principal = vaultContract.totalPrincipal();
        
        totalLeverage = principal > 0 ? (tvl * BASIS_POINTS) / principal : BASIS_POINTS;
        avgHealthFactor = totalLeverage > 0 ? (BASIS_POINTS * BASIS_POINTS) / totalLeverage : BASIS_POINTS;
        emergency = emergencyMode;
        
        return (totalLeverage, avgHealthFactor, emergency);
    }
}