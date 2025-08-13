// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

// Strategy interfaces
import "./strategies/BaseStrategy.sol";
import "./interfaces/IRiskOracle.sol";
import "./interfaces/IStrategyRegistry.sol";
import "./interfaces/IYieldAggregator.sol";

/// @title EnhancedVaultOrchestrator - Multi-Strategy Yield Vault
/// @notice Advanced vault that orchestrates multiple yield strategies with AI optimization and risk management
contract EnhancedVaultOrchestrator is ERC4626, AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant STRATEGY_ROLE = keccak256("STRATEGY_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    bytes32 public constant REBALANCER_ROLE = keccak256("REBALANCER_ROLE");

    // Strategy types available
    enum StrategyType {
        INCREMENTFI_DEX,          // IncrementFi DEX strategy
        MORE_MARKETS_LENDING,     // More.Markets lending with looping
        STURDY_FINANCE,           // Sturdy.Finance interest-free borrowing
        ANKR_STAKING,             // Ankr liquid staking
        MULTI_DEX_ARBITRAGE,      // Multi-DEX arbitrage
        CELER_CROSS_CHAIN,        // Cross-chain via Celer
        NFT_YIELD_FARMING,        // NFT-powered yield
        VALIDATOR_OPERATIONS,     // Flow validator & MEV
        AI_PREDICTIVE,            // AI/ML predictive strategy
        CROSS_CHAIN_MEGA,         // Cross-chain mega strategy
        DELTA_NEUTRAL,            // Delta-neutral strategies
        FLASH_LOAN_ARBITRAGE,     // Flash loan arbitrage
        YIELD_LOTTERY_GAMING,     // Gamified yield with lotteries
        GOVERNANCE_FARMING        // Governance token farming
    }

    struct StrategyInfo {
        address strategyAddress;
        StrategyType strategyType;
        string name;
        uint256 allocation; // Percentage allocation (basis points)
        uint256 totalAssets;
        uint256 lastHarvestTime;
        uint256 cumulativeReturns;
        uint256 riskScore; // 0-10000 scale
        bool active;
        bool emergency;
        uint256 maxAllocation; // Maximum allowed allocation
        uint256 performanceScore; // Performance-based scoring
    }

    struct VaultConfig {
        uint256 maxStrategies;
        uint256 rebalanceThreshold; // Threshold for rebalancing
        uint256 maxRiskScore; // Maximum risk score allowed
        uint256 emergencyExitThreshold; // Emergency exit trigger
        uint256 performanceFee; // Performance fee in basis points
        uint256 managementFee; // Management fee in basis points
        bool enableAutoRebalancing;
        bool enableEmergencyMode;
        bool enableYieldCompounding;
        uint256 minDepositAmount;
        uint256 maxDepositAmount;
    }

    struct AllocationTarget {
        StrategyType strategyType;
        uint256 targetAllocation;
        uint256 minAllocation;
        uint256 maxAllocation;
        uint256 priority; // Higher priority gets allocated first
    }

    struct PerformanceMetrics {
        uint256 totalValueLocked;
        uint256 totalReturnsGenerated;
        uint256 totalFeesCollected;
        uint256 totalUsersServed;
        uint256 averageAPY;
        uint256 sharpeRatio;
        uint256 maxDrawdown;
        uint256 winRate;
        uint256 totalRebalances;
        uint256 emergencyExits;
    }

    struct UserPosition {
        uint256 depositTime;
        uint256 initialDeposit;
        uint256 lastInteractionTime;
        uint256 totalRewardsEarned;
        uint256 riskTolerance; // User's risk tolerance
        StrategyType[] preferredStrategies;
        bool isVIP; // VIP users get enhanced features
    }

    // State variables
    mapping(StrategyType => StrategyInfo) public strategies;
    mapping(address => UserPosition) public userPositions;
    mapping(StrategyType => AllocationTarget) public allocationTargets;
    
    StrategyType[] public activeStrategies;
    address[] public strategyAddresses;
    
    VaultConfig public vaultConfig;
    PerformanceMetrics public performanceMetrics;
    
    // Oracle integrations
    IRiskOracle public riskOracle;
    IStrategyRegistry public strategyRegistry;
    IYieldAggregator public yieldAggregator;
    
    // Fee management
    address public treasury;
    address public performanceFeeRecipient;
    uint256 public lastPerformanceFeeCollection;
    uint256 public totalFeesCollected;
    
    // Emergency management
    bool public emergencyMode;
    uint256 public emergencyTriggeredAt;
    mapping(address => bool) public emergencyWhitelist;
    
    // Yield tracking
    uint256 public totalYieldGenerated;
    uint256 public lastYieldDistribution;
    uint256 public yieldReserveFund;
    
    // Advanced features
    bool public aiOptimizationEnabled = true;
    uint256 public lastRebalanceTime;
    uint256 public rebalanceCount;

    // Events
    event StrategyAdded(StrategyType indexed strategyType, address indexed strategyAddress, uint256 maxAllocation);
    event StrategyRemoved(StrategyType indexed strategyType, address indexed strategyAddress);
    event AllocationUpdated(StrategyType indexed strategyType, uint256 oldAllocation, uint256 newAllocation);
    event RebalanceExecuted(uint256 totalValue, uint256 strategiesRebalanced, uint256 gasCost);
    event EmergencyModeActivated(string reason, uint256 triggeredAt);
    event EmergencyModeDeactivated(uint256 deactivatedAt);
    event PerformanceFeesCollected(uint256 amount, address recipient);
    event YieldHarvested(uint256 totalYield, uint256 strategiesHarvested);
    event UserDeposit(address indexed user, uint256 amount, uint256 shares, StrategyType[] preferredStrategies);
    event UserWithdraw(address indexed user, uint256 amount, uint256 shares);
    event StrategyEmergencyExit(StrategyType indexed strategyType, uint256 recoveredAssets, string reason);

    constructor(
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
        address _treasury,
        address _riskOracle,
        address _strategyRegistry,
        address _yieldAggregator
    ) ERC4626(_asset) ERC20(_name, _symbol) {
        require(_treasury != address(0), "Invalid treasury");
        require(_riskOracle != address(0), "Invalid risk oracle");
        
        treasury = _treasury;
        performanceFeeRecipient = _treasury;
        riskOracle = IRiskOracle(_riskOracle);
        strategyRegistry = IStrategyRegistry(_strategyRegistry);
        yieldAggregator = IYieldAggregator(_yieldAggregator);
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, msg.sender);
        _grantRole(REBALANCER_ROLE, msg.sender);
        
        // Initialize vault configuration
        vaultConfig = VaultConfig({
            maxStrategies: 14, // All strategy types
            rebalanceThreshold: 500, // 5% threshold
            maxRiskScore: 7000, // 70% max risk
            emergencyExitThreshold: 8500, // 85% threshold
            performanceFee: 3000, // 30% performance fee
            managementFee: 200, // 2% annual management fee
            enableAutoRebalancing: true,
            enableEmergencyMode: true,
            enableYieldCompounding: true,
            minDepositAmount: 100 * 10**6, // 100 USDC minimum
            maxDepositAmount: 10000000 * 10**6 // 10M USDC maximum
        });
        
        _initializeDefaultAllocations();
    }

    function _initializeDefaultAllocations() internal {
        // Conservative default allocations
        allocationTargets[StrategyType.MORE_MARKETS_LENDING] = AllocationTarget({
            strategyType: StrategyType.MORE_MARKETS_LENDING,
            targetAllocation: 2000, // 20%
            minAllocation: 1000,
            maxAllocation: 3000,
            priority: 1
        });
        
        allocationTargets[StrategyType.ANKR_STAKING] = AllocationTarget({
            strategyType: StrategyType.ANKR_STAKING,
            targetAllocation: 1500, // 15%
            minAllocation: 500,
            maxAllocation: 2500,
            priority: 2
        });
        
        allocationTargets[StrategyType.INCREMENTFI_DEX] = AllocationTarget({
            strategyType: StrategyType.INCREMENTFI_DEX,
            targetAllocation: 1500, // 15%
            minAllocation: 500,
            maxAllocation: 2000,
            priority: 3
        });
        
        allocationTargets[StrategyType.GOVERNANCE_FARMING] = AllocationTarget({
            strategyType: StrategyType.GOVERNANCE_FARMING,
            targetAllocation: 1000, // 10%
            minAllocation: 500,
            maxAllocation: 1500,
            priority: 4
        });
        
        allocationTargets[StrategyType.CROSS_CHAIN_MEGA] = AllocationTarget({
            strategyType: StrategyType.CROSS_CHAIN_MEGA,
            targetAllocation: 1000, // 10%
            minAllocation: 0,
            maxAllocation: 2000,
            priority: 5
        });
        
        allocationTargets[StrategyType.AI_PREDICTIVE] = AllocationTarget({
            strategyType: StrategyType.AI_PREDICTIVE,
            targetAllocation: 800, // 8%
            minAllocation: 0,
            maxAllocation: 1500,
            priority: 6
        });
        
        allocationTargets[StrategyType.DELTA_NEUTRAL] = AllocationTarget({
            strategyType: StrategyType.DELTA_NEUTRAL,
            targetAllocation: 700, // 7%
            minAllocation: 0,
            maxAllocation: 1000,
            priority: 7
        });
        
        allocationTargets[StrategyType.NFT_YIELD_FARMING] = AllocationTarget({
            strategyType: StrategyType.NFT_YIELD_FARMING,
            targetAllocation: 500, // 5%
            minAllocation: 0,
            maxAllocation: 1000,
            priority: 8
        });
        
        allocationTargets[StrategyType.FLASH_LOAN_ARBITRAGE] = AllocationTarget({
            strategyType: StrategyType.FLASH_LOAN_ARBITRAGE,
            targetAllocation: 300, // 3%
            minAllocation: 0,
            maxAllocation: 500,
            priority: 9
        });
        
        allocationTargets[StrategyType.YIELD_LOTTERY_GAMING] = AllocationTarget({
            strategyType: StrategyType.YIELD_LOTTERY_GAMING,
            targetAllocation: 200, // 2%
            minAllocation: 0,
            maxAllocation: 500,
            priority: 10
        });
    }

    // Override deposit to add custom logic
    function deposit(uint256 assets, address receiver) public virtual override nonReentrant whenNotPaused returns (uint256) {
        require(assets >= vaultConfig.minDepositAmount, "Below minimum deposit");
        require(assets <= vaultConfig.maxDepositAmount, "Above maximum deposit");
        require(!emergencyMode, "Emergency mode active");
        
        // Update user position
        _updateUserPosition(receiver, assets);
        
        // Execute deposit
        uint256 shares = super.deposit(assets, receiver);
        
        // Trigger rebalancing if needed
        if (vaultConfig.enableAutoRebalancing) {
            _checkAndRebalance();
        }
        
        // Update metrics
        performanceMetrics.totalUsersServed++;
        
        emit UserDeposit(receiver, assets, shares, userPositions[receiver].preferredStrategies);
        
        return shares;
    }

    // Override withdraw to add custom logic
    function withdraw(uint256 assets, address receiver, address owner) public virtual override nonReentrant returns (uint256) {
        // Execute withdrawal
        uint256 shares = super.withdraw(assets, receiver, owner);
        
        // Update user position
        userPositions[owner].lastInteractionTime = block.timestamp;
        
        emit UserWithdraw(owner, assets, shares);
        
        return shares;
    }

    function _updateUserPosition(address user, uint256 depositAmount) internal {
        UserPosition storage position = userPositions[user];
        
        if (position.depositTime == 0) {
            position.depositTime = block.timestamp;
            position.initialDeposit = depositAmount;
            position.riskTolerance = 5000; // Default 50% risk tolerance
        }
        
        position.lastInteractionTime = block.timestamp;
    }

    // Enhanced deposit with strategy preferences
    function depositWithPreferences(
        uint256 assets,
        address receiver,
        StrategyType[] calldata preferredStrategies,
        uint256 riskTolerance
    ) external returns (uint256 shares) {
        require(riskTolerance <= 10000, "Invalid risk tolerance");
        
        // Update user preferences
        UserPosition storage position = userPositions[receiver];
        position.preferredStrategies = preferredStrategies;
        position.riskTolerance = riskTolerance;
        
        // Use AI optimization if enabled
        if (aiOptimizationEnabled) {
            _optimizeAllocationForUser(receiver, assets);
        }
        
        return deposit(assets, receiver);
    }

    function _optimizeAllocationForUser(address user, uint256 amount) internal {
        UserPosition storage position = userPositions[user];
        
        // Get AI-optimized allocation
        try yieldAggregator.calculateOptimalAllocation(
            address(asset()),
            amount,
            position.riskTolerance
        ) returns (
            address[] memory strategies,
            uint256[] memory allocations,
            uint256 expectedAPY
        ) {
            _updateAllocationsBasedOnAI(strategies, allocations, expectedAPY);
        } catch {
            // AI optimization failed, use default allocations
        }
    }

    function _updateAllocationsBasedOnAI(
        address[] memory aiStrategies,
        uint256[] memory aiAllocations,
        uint256 expectedAPY
    ) internal {
        // Update allocations based on AI recommendations
        // This is a simplified implementation
        for (uint256 i = 0; i < aiStrategies.length && i < aiAllocations.length; i++) {
            // Find matching strategy and update allocation
            // Implementation would map AI strategies to our strategy types
        }
    }

    // Strategy management
    function addStrategy(
        StrategyType strategyType,
        address strategyAddress,
        uint256 maxAllocation
    ) external onlyRole(MANAGER_ROLE) {
        require(strategyAddress != address(0), "Invalid strategy address");
        require(maxAllocation <= 10000, "Invalid max allocation");
        require(!strategies[strategyType].active, "Strategy already exists");
        require(activeStrategies.length < vaultConfig.maxStrategies, "Too many strategies");
        
        // Get risk assessment
        (uint256 riskScore, string memory riskLevel, bool approved,) = 
            riskOracle.assessStrategyRisk(strategyAddress);
        
        require(approved, "Strategy not approved by risk oracle");
        require(riskScore <= vaultConfig.maxRiskScore, "Strategy too risky");
        
        strategies[strategyType] = StrategyInfo({
            strategyAddress: strategyAddress,
            strategyType: strategyType,
            name: BaseStrategy(strategyAddress).strategyName(),
            allocation: 0,
            totalAssets: 0,
            lastHarvestTime: block.timestamp,
            cumulativeReturns: 0,
            riskScore: riskScore,
            active: true,
            emergency: false,
            maxAllocation: maxAllocation,
            performanceScore: 5000 // Default 50% performance score
        });
        
        activeStrategies.push(strategyType);
        strategyAddresses.push(strategyAddress);
        
        // Grant strategy role
        _grantRole(STRATEGY_ROLE, strategyAddress);
        
        emit StrategyAdded(strategyType, strategyAddress, maxAllocation);
    }

    function removeStrategy(StrategyType strategyType) external onlyRole(MANAGER_ROLE) {
        require(strategies[strategyType].active, "Strategy not active");
        
        // Emergency exit from strategy
        _emergencyExitStrategy(strategyType, "Strategy removal");
        
        // Mark as inactive
        strategies[strategyType].active = false;
        
        // Remove from active strategies array
        _removeFromActiveStrategies(strategyType);
        
        emit StrategyRemoved(strategyType, strategies[strategyType].strategyAddress);
    }

    function _removeFromActiveStrategies(StrategyType strategyType) internal {
        for (uint256 i = 0; i < activeStrategies.length; i++) {
            if (activeStrategies[i] == strategyType) {
                activeStrategies[i] = activeStrategies[activeStrategies.length - 1];
                activeStrategies.pop();
                break;
            }
        }
    }

    // Rebalancing logic
    function rebalance() external onlyRole(REBALANCER_ROLE) nonReentrant {
        _executeRebalance();
    }

    function _checkAndRebalance() internal {
        if (!vaultConfig.enableAutoRebalancing) return;
        if (block.timestamp < lastRebalanceTime + 4 hours) return; // Min 4 hours between rebalances
        
        bool shouldRebalance = _shouldRebalance();
        if (shouldRebalance) {
            _executeRebalance();
        }
    }

    function _shouldRebalance() internal view returns (bool) {
        uint256 totalValue = totalAssets();
        if (totalValue == 0) return false;
        
        // Check if any strategy has drifted beyond threshold
        for (uint256 i = 0; i < activeStrategies.length; i++) {
            StrategyType strategyType = activeStrategies[i];
            StrategyInfo storage strategy = strategies[strategyType];
            AllocationTarget storage target = allocationTargets[strategyType];
            
            if (!strategy.active) continue;
            
            uint256 currentAllocation = (strategy.totalAssets * 10000) / totalValue;
            uint256 targetAllocation = target.targetAllocation;
            
            uint256 deviation = currentAllocation > targetAllocation 
                ? currentAllocation - targetAllocation 
                : targetAllocation - currentAllocation;
            
            if (deviation >= vaultConfig.rebalanceThreshold) {
                return true;
            }
        }
        
        return false;
    }

    function _executeRebalance() internal {
        uint256 gasStart = gasleft();
        uint256 totalValue = totalAssets();
        uint256 strategiesRebalanced = 0;
        
        if (totalValue == 0) return;
        
        // Calculate target allocations
        uint256[] memory targetAmounts = new uint256[](activeStrategies.length);
        
        for (uint256 i = 0; i < activeStrategies.length; i++) {
            StrategyType strategyType = activeStrategies[i];
            AllocationTarget storage target = allocationTargets[strategyType];
            
            if (strategies[strategyType].active) {
                targetAmounts[i] = (totalValue * target.targetAllocation) / 10000;
            }
        }
        
        // Execute rebalancing
        for (uint256 i = 0; i < activeStrategies.length; i++) {
            StrategyType strategyType = activeStrategies[i];
            StrategyInfo storage strategy = strategies[strategyType];
            
            if (!strategy.active) continue;
            
            uint256 currentAmount = strategy.totalAssets;
            uint256 targetAmount = targetAmounts[i];
            
            if (currentAmount != targetAmount) {
                _rebalanceStrategy(strategyType, currentAmount, targetAmount);
                strategiesRebalanced++;
            }
        }
        
        // Update metrics
        lastRebalanceTime = block.timestamp;
        rebalanceCount++;
        performanceMetrics.totalRebalances++;
        
        uint256 gasUsed = gasStart - gasleft();
        
        emit RebalanceExecuted(totalValue, strategiesRebalanced, gasUsed);
    }

    function _rebalanceStrategy(
        StrategyType strategyType,
        uint256 currentAmount,
        uint256 targetAmount
    ) internal {
        StrategyInfo storage strategy = strategies[strategyType];
        address strategyAddress = strategy.strategyAddress;
        
        if (targetAmount > currentAmount) {
            // Need to deposit more to strategy
            uint256 depositAmount = targetAmount - currentAmount;
            uint256 availableAssets = IERC20(asset()).balanceOf(address(this));
            
            if (availableAssets >= depositAmount) {
                IERC20(asset()).safeTransfer(strategyAddress, depositAmount);
                strategy.totalAssets += depositAmount;
                strategy.allocation = (strategy.totalAssets * 10000) / totalAssets();
            }
        } else if (targetAmount < currentAmount) {
            // Need to withdraw from strategy
            uint256 withdrawAmount = currentAmount - targetAmount;
            
            try BaseStrategy(strategyAddress).emergencyExit("") {
                // Emergency exit to withdraw funds
                strategy.totalAssets = targetAmount;
                strategy.allocation = (strategy.totalAssets * 10000) / totalAssets();
            } catch {
                // Withdrawal failed
            }
        }
        
        emit AllocationUpdated(strategyType, currentAmount, targetAmount);
    }

    // Yield harvesting
    function harvestAll() external onlyRole(REBALANCER_ROLE) {
        _harvestAllStrategies();
    }

    function _harvestAllStrategies() internal {
        uint256 totalYield = 0;
        uint256 strategiesHarvested = 0;
        
        for (uint256 i = 0; i < activeStrategies.length; i++) {
            StrategyType strategyType = activeStrategies[i];
            StrategyInfo storage strategy = strategies[strategyType];
            
            if (strategy.active && !strategy.emergency) {
                uint256 yieldHarvested = _harvestStrategy(strategyType);
                totalYield += yieldHarvested;
                if (yieldHarvested > 0) {
                    strategiesHarvested++;
                }
            }
        }
        
        // Update yield metrics
        totalYieldGenerated += totalYield;
        lastYieldDistribution = block.timestamp;
        
        // Collect performance fees
        if (totalYield > 0) {
            _collectPerformanceFees(totalYield);
        }
        
        emit YieldHarvested(totalYield, strategiesHarvested);
    }

    function _harvestStrategy(StrategyType strategyType) internal returns (uint256) {
        StrategyInfo storage strategy = strategies[strategyType];
        address strategyAddress = strategy.strategyAddress;
        
        uint256 balanceBefore = IERC20(asset()).balanceOf(address(this));
        
        try BaseStrategy(strategyAddress).harvest("") {
            uint256 balanceAfter = IERC20(asset()).balanceOf(address(this));
            uint256 yield = balanceAfter > balanceBefore ? balanceAfter - balanceBefore : 0;
            
            strategy.cumulativeReturns += yield;
            strategy.lastHarvestTime = block.timestamp;
            
            return yield;
        } catch {
            // Harvest failed
            return 0;
        }
    }

    function _collectPerformanceFees(uint256 totalYield) internal {
        uint256 performanceFee = (totalYield * vaultConfig.performanceFee) / 10000;
        
        if (performanceFee > 0) {
            IERC20(asset()).safeTransfer(performanceFeeRecipient, performanceFee);
            totalFeesCollected += performanceFee;
            lastPerformanceFeeCollection = block.timestamp;
            
            emit PerformanceFeesCollected(performanceFee, performanceFeeRecipient);
        }
    }

    // Emergency management
    function activateEmergencyMode(string calldata reason) external onlyRole(EMERGENCY_ROLE) {
        emergencyMode = true;
        emergencyTriggeredAt = block.timestamp;
        _pause();
        
        emit EmergencyModeActivated(reason, block.timestamp);
    }

    function deactivateEmergencyMode() external onlyRole(EMERGENCY_ROLE) {
        emergencyMode = false;
        _unpause();
        
        emit EmergencyModeDeactivated(block.timestamp);
    }

    function emergencyExitStrategy(StrategyType strategyType, string calldata reason) 
        external onlyRole(EMERGENCY_ROLE) {
        _emergencyExitStrategy(strategyType, reason);
    }

    function _emergencyExitStrategy(StrategyType strategyType, string memory reason) internal {
        StrategyInfo storage strategy = strategies[strategyType];
        
        if (!strategy.active) return;
        
        address strategyAddress = strategy.strategyAddress;
        uint256 balanceBefore = IERC20(asset()).balanceOf(address(this));
        
        try BaseStrategy(strategyAddress).emergencyExit("") returns (uint256 recovered) {
            strategy.emergency = true;
            strategy.totalAssets = 0;
            strategy.allocation = 0;
            
            uint256 balanceAfter = IERC20(asset()).balanceOf(address(this));
            uint256 actualRecovered = balanceAfter > balanceBefore ? balanceAfter - balanceBefore : 0;
            
            performanceMetrics.emergencyExits++;
            
            emit StrategyEmergencyExit(strategyType, actualRecovered, reason);
        } catch {
            // Emergency exit failed
            strategy.emergency = true;
        }
    }

    // View functions for total assets
    function totalAssets() public view virtual override returns (uint256) {
        uint256 total = IERC20(asset()).balanceOf(address(this));
        
        // Add assets in all active strategies
        for (uint256 i = 0; i < activeStrategies.length; i++) {
            StrategyType strategyType = activeStrategies[i];
            StrategyInfo storage strategy = strategies[strategyType];
            
            if (strategy.active && !strategy.emergency) {
                try BaseStrategy(strategy.strategyAddress).getBalance() returns (uint256 balance) {
                    total += balance;
                } catch {
                    // Use stored value if call fails
                    total += strategy.totalAssets;
                }
            }
        }
        
        return total;
    }

    // Performance analytics
    function getVaultPerformance() external view returns (PerformanceMetrics memory) {
        PerformanceMetrics memory metrics = performanceMetrics;
        
        // Calculate current metrics
        metrics.totalValueLocked = totalAssets();
        metrics.totalReturnsGenerated = totalYieldGenerated;
        metrics.totalFeesCollected = totalFeesCollected;
        
        // Calculate APY (simplified)
        if (metrics.totalValueLocked > 0 && totalSupply() > 0) {
            // This is a simplified APY calculation
            metrics.averageAPY = (totalYieldGenerated * 365 days * 10000) / 
                               (metrics.totalValueLocked * (block.timestamp - emergencyTriggeredAt + 1));
        }
        
        return metrics;
    }

    function getStrategyAllocations() external view returns (
        StrategyType[] memory strategyTypes,
        uint256[] memory allocations,
        uint256[] memory totalAssets_,
        uint256[] memory riskScores
    ) {
        uint256 length = activeStrategies.length;
        strategyTypes = new StrategyType[](length);
        allocations = new uint256[](length);
        totalAssets_ = new uint256[](length);
        riskScores = new uint256[](length);
        
        for (uint256 i = 0; i < length; i++) {
            StrategyType strategyType = activeStrategies[i];
            StrategyInfo storage strategy = strategies[strategyType];
            
            strategyTypes[i] = strategyType;
            allocations[i] = strategy.allocation;
            totalAssets_[i] = strategy.totalAssets;
            riskScores[i] = strategy.riskScore;
        }
    }

    function getUserPosition(address user) external view returns (UserPosition memory) {
        return userPositions[user];
    }

    // Admin functions
    function updateVaultConfig(VaultConfig calldata newConfig) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newConfig.maxStrategies <= 20, "Too many strategies");
        require(newConfig.performanceFee <= 5000, "Performance fee too high"); // Max 50%
        require(newConfig.managementFee <= 1000, "Management fee too high"); // Max 10%
        
        vaultConfig = newConfig;
    }

    function updateAllocationTarget(
        StrategyType strategyType,
        uint256 targetAllocation,
        uint256 minAllocation,
        uint256 maxAllocation,
        uint256 priority
    ) external onlyRole(MANAGER_ROLE) {
        require(targetAllocation <= 10000, "Invalid target allocation");
        require(minAllocation <= targetAllocation, "Invalid min allocation");
        require(maxAllocation >= targetAllocation, "Invalid max allocation");
        
        allocationTargets[strategyType] = AllocationTarget({
            strategyType: strategyType,
            targetAllocation: targetAllocation,
            minAllocation: minAllocation,
            maxAllocation: maxAllocation,
            priority: priority
        });
    }

    function setTreasury(address newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newTreasury != address(0), "Invalid treasury");
        treasury = newTreasury;
    }

    function setPerformanceFeeRecipient(address newRecipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newRecipient != address(0), "Invalid recipient");
        performanceFeeRecipient = newRecipient;
    }

    function setAIOptimization(bool enabled) external onlyRole(MANAGER_ROLE) {
        aiOptimizationEnabled = enabled;
    }

    function upgradeStrategy(StrategyType strategyType, address newStrategyAddress) 
        external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(strategies[strategyType].active, "Strategy not active");
        
        // Emergency exit from old strategy
        _emergencyExitStrategy(strategyType, "Strategy upgrade");
        
        // Update strategy address
        strategies[strategyType].strategyAddress = newStrategyAddress;
        strategies[strategyType].emergency = false;
        
        // Grant role to new strategy
        _grantRole(STRATEGY_ROLE, newStrategyAddress);
    }

    // Emergency recovery
    function emergencyRecoverToken(address token, uint256 amount) 
        external onlyRole(EMERGENCY_ROLE) {
        require(token != address(asset()), "Cannot recover vault asset");
        IERC20(token).safeTransfer(treasury, amount);
    }

    // Pause/unpause
    function pause() external onlyRole(EMERGENCY_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(EMERGENCY_ROLE) {
        _unpause();
    }
}