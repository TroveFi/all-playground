// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "../interfaces/IStrategies.sol";
import "../oracles/IRiskOracle.sol";
import "../oracles/IStrategyRegistry.sol";
import "../oracles/IYieldAggregator.sol";

/// @title EnhancedVault - Advanced Multi-Strategy Yield Optimization Vault
/// @notice ERC4626-compliant vault with ML-powered strategy selection and risk management
/// @dev Integrates with RiskOracle, StrategyRegistry, and YieldAggregator for maximum yield
contract EnhancedVault is Ownable, ERC20, AccessControl, ReentrancyGuard, IERC4626 {
    using SafeERC20 for IERC20;

    // ====================================================================
    // ROLES & CONSTANTS
    // ====================================================================

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");
    bytes32 public constant STRATEGY_ROLE = keccak256("STRATEGY_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    // ====================================================================
    // STATE VARIABLES
    // ====================================================================

    IERC20 private immutable _asset;
    
    // Core protocol integrations
    IRiskOracle public riskOracle;
    IStrategyRegistry public strategyRegistry;
    IYieldAggregator public yieldAggregator;
    
    // Strategy management
    address[] public strategies;
    mapping(address => bool) public isStrategy;
    mapping(address => uint256) public strategyAllocations; // Current allocation in each strategy
    mapping(address => uint256) public strategyTargetAllocations; // Target allocation percentages (basis points)
    
    // Enhanced vault parameters
    struct VaultConfig {
        uint256 maxRiskTolerance; // Maximum acceptable risk score (0-10000)
        uint256 rebalanceThreshold; // Minimum yield improvement to trigger rebalance (basis points)
        uint256 maxSingleStrategyAllocation; // Maximum allocation to single strategy (basis points)
        uint256 reserveRatio; // Percentage to keep as liquid reserves (basis points)
        uint256 performanceFee; // Performance fee (basis points)
        uint256 managementFee; // Annual management fee (basis points)
        bool autoRebalanceEnabled; // Whether automatic rebalancing is enabled
        uint256 rebalanceInterval; // Minimum time between rebalances
    }
    
    VaultConfig public vaultConfig;
    
    // Performance tracking
    struct PerformanceMetrics {
        uint256 totalYieldGenerated;
        uint256 totalFeesCollected;
        uint256 netAssetValue;
        uint256 sharpeRatio;
        uint256 maxDrawdown;
        uint256 lastRebalanceTime;
        uint256 successfulRebalances;
        uint256 failedRebalances;
    }
    
    PerformanceMetrics public performanceMetrics;
    
    // Revenue sharing and tokenomics
    address public treasury;
    address public buyBackContract; // Contract for buy-back and burn mechanism
    mapping(address => uint256) public userLastDepositTime;
    mapping(address => uint256) public userLifetimeRewards;
    
    // Cross-chain and bridging
    address public bridge; // LayerZero bridge contract
    mapping(uint16 => bool) public supportedChains; // Supported chain IDs
    mapping(uint16 => uint256) public chainAllocations; // Current allocations per chain
    
    // Emergency and safety
    bool public emergencyMode;
    mapping(address => bool) public blacklistedStrategies;
    uint256 public emergencyExitThreshold = 8000; // 80% risk score triggers emergency
    
    // ====================================================================
    // EVENTS
    // ====================================================================

    event StrategyAdded(address indexed strategy, uint256 targetAllocation);
    event StrategyRemoved(address indexed strategy);
    event StrategyRebalanced(address indexed strategy, uint256 oldAllocation, uint256 newAllocation);
    event AutoRebalanceExecuted(uint256 oldYield, uint256 newYield, uint256 gasCost);
    event EmergencyModeActivated(string reason);
    event EmergencyModeDeactivated();
    event PerformanceFeeCollected(uint256 amount, address recipient);
    event CrossChainDeployment(uint16 chainId, address strategy, uint256 amount);
    event YieldHarvested(uint256 totalYield, uint256 performanceFee);

    // ====================================================================
    // ERRORS
    // ====================================================================

    error InvalidStrategy();
    error StrategyAlreadyExists();
    error StrategyDoesNotExist();
    error InsufficientBalance();
    error InvalidAddress();
    error EmergencyModeActive();
    error RiskToleranceExceeded();
    error RebalanceTooSoon();
    error InvalidAllocation();

    // ====================================================================
    // CONSTRUCTOR
    // ====================================================================

    constructor(
        IERC20 assetToken,
        string memory name,
        string memory symbol,
        address _manager,
        address _agent,
        address _treasury,
        address _riskOracle,
        address _strategyRegistry,
        address _yieldAggregator
    ) ERC20(name, symbol) Ownable(msg.sender) {
        require(address(assetToken) != address(0), "Invalid asset");
        require(_manager != address(0), "Invalid manager");
        require(_agent != address(0), "Invalid agent");
        require(_treasury != address(0), "Invalid treasury");

        _asset = assetToken;
        treasury = _treasury;
        riskOracle = IRiskOracle(_riskOracle);
        strategyRegistry = IStrategyRegistry(_strategyRegistry);
        yieldAggregator = IYieldAggregator(_yieldAggregator);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setRoleAdmin(MANAGER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(AGENT_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(STRATEGY_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(EMERGENCY_ROLE, DEFAULT_ADMIN_ROLE);

        _grantRole(MANAGER_ROLE, _manager);
        _grantRole(AGENT_ROLE, _agent);
        _grantRole(EMERGENCY_ROLE, msg.sender);

        // Initialize with conservative settings
        vaultConfig = VaultConfig({
            maxRiskTolerance: 6000, // 60%
            rebalanceThreshold: 500, // 5%
            maxSingleStrategyAllocation: 4000, // 40%
            reserveRatio: 1000, // 10%
            performanceFee: 3000, // 30%
            managementFee: 200, // 2%
            autoRebalanceEnabled: false, // Start manual
            rebalanceInterval: 6 hours
        });
    }

    // ====================================================================
    // ERC4626 IMPLEMENTATION (Enhanced)
    // ====================================================================

    function asset() public view virtual override returns (address) {
        return address(_asset);
    }

    function totalAssets() public view virtual override returns (uint256) {
        uint256 assetsInStrategies = 0;
        for (uint i = 0; i < strategies.length; i++) {
            if (!blacklistedStrategies[strategies[i]]) {
                assetsInStrategies += IStrategies(strategies[i]).getBalance();
            }
        }
        return _asset.balanceOf(address(this)) + assetsInStrategies;
    }

    function convertToShares(uint256 assetsValue) public view virtual override returns (uint256) {
        return _convertToShares(assetsValue, Math.Rounding.Down);
    }

    function convertToAssets(uint256 sharesValue) public view virtual override returns (uint256) {
        return _convertToAssets(sharesValue, Math.Rounding.Down);
    }

    function maxDeposit(address) public view virtual override returns (uint256) {
        return emergencyMode ? 0 : type(uint256).max;
    }

    function previewDeposit(uint256 assetsValue) public view virtual override returns (uint256) {
        return _convertToShares(assetsValue, Math.Rounding.Down);
    }

    function deposit(uint256 assetsValue, address receiver) public virtual override nonReentrant returns (uint256 shares) {
        if (emergencyMode) revert EmergencyModeActive();
        
        shares = previewDeposit(assetsValue);
        _deposit(assetsValue, shares, receiver);
        
        // Track user deposit time for performance fee calculations
        userLastDepositTime[receiver] = block.timestamp;
        
        // Trigger auto-rebalance if enabled
        if (vaultConfig.autoRebalanceEnabled) {
            _checkAndRebalance();
        }
        
        return shares;
    }

    function maxMint(address) public view virtual override returns (uint256) {
        return emergencyMode ? 0 : type(uint256).max;
    }

    function previewMint(uint256 sharesValue) public view virtual override returns (uint256) {
        return _convertToAssets(sharesValue, Math.Rounding.Up);
    }

    function mint(uint256 sharesValue, address receiver) public virtual override nonReentrant returns (uint256 assets) {
        if (emergencyMode) revert EmergencyModeActive();
        
        assets = previewMint(sharesValue);
        _deposit(assets, sharesValue, receiver);
        userLastDepositTime[receiver] = block.timestamp;
        
        if (vaultConfig.autoRebalanceEnabled) {
            _checkAndRebalance();
        }
        
        return assets;
    }

    function maxWithdraw(address owner) public view virtual override returns (uint256) {
        return _convertToAssets(balanceOf(owner), Math.Rounding.Down);
    }

    function previewWithdraw(uint256 assetsValue) public view virtual override returns (uint256) {
        return _convertToShares(assetsValue, Math.Rounding.Up);
    }

    function withdraw(uint256 assetsValue, address receiver, address owner) public virtual override nonReentrant returns (uint256 shares) {
        shares = previewWithdraw(assetsValue);
        _withdraw(assetsValue, shares, receiver, owner);
        return shares;
    }

    function maxRedeem(address owner) public view virtual override returns (uint256) {
        return balanceOf(owner);
    }

    function previewRedeem(uint256 sharesValue) public view virtual override returns (uint256) {
        return _convertToAssets(sharesValue, Math.Rounding.Down);
    }

    function redeem(uint256 sharesValue, address receiver, address owner) public virtual override nonReentrant returns (uint256 assets) {
        assets = previewRedeem(sharesValue);
        _withdraw(assets, sharesValue, receiver, owner);
        return assets;
    }

    // ====================================================================
    // ENHANCED STRATEGY MANAGEMENT
    // ====================================================================

    function addStrategy(
        address _strategy,
        uint256 _targetAllocation
    ) external onlyRole(MANAGER_ROLE) {
        if (_strategy == address(0)) revert InvalidAddress();
        if (isStrategy[_strategy]) revert StrategyAlreadyExists();
        if (_targetAllocation > 10000) revert InvalidAllocation();

        // Risk assessment before adding strategy
        (uint256 riskScore,, bool approved,) = riskOracle.assessStrategyRisk(_strategy);
        if (riskScore > vaultConfig.maxRiskTolerance) revert RiskToleranceExceeded();
        if (!approved) revert InvalidStrategy();

        isStrategy[_strategy] = true;
        strategies.push(_strategy);
        strategyTargetAllocations[_strategy] = _targetAllocation;

        emit StrategyAdded(_strategy, _targetAllocation);
    }

    function removeStrategy(address _strategy) external onlyRole(MANAGER_ROLE) {
        if (!isStrategy[_strategy]) revert StrategyDoesNotExist();

        // Emergency exit from strategy
        _emergencyExitStrategy(_strategy);

        isStrategy[_strategy] = false;
        strategyTargetAllocations[_strategy] = 0;

        // Remove from strategies array
        for (uint256 i = 0; i < strategies.length; i++) {
            if (strategies[i] == _strategy) {
                strategies[i] = strategies[strategies.length - 1];
                strategies.pop();
                break;
            }
        }

        emit StrategyRemoved(_strategy);
    }

    function deployToOptimalStrategy(
        uint256 amount,
        uint256 maxRiskTolerance,
        bool allowCrossChain
    ) external onlyRole(AGENT_ROLE) nonReentrant returns (bytes32 allocationId) {
        if (emergencyMode) revert EmergencyModeActive();
        if (_asset.balanceOf(address(this)) < amount) revert InsufficientBalance();

        // Get optimal allocation from YieldAggregator
        (
            address[] memory optimalStrategies,
            uint256[] memory allocations,
            uint256 totalExpectedReturn
        ) = yieldAggregator.calculateOptimalAllocation(
            address(_asset),
            amount,
            maxRiskTolerance
        );

        if (optimalStrategies.length == 0) {
            revert InvalidStrategy();
        }

        // Deploy to optimal strategies
        for (uint i = 0; i < optimalStrategies.length; i++) {
            if (allocations[i] > 0) {
                _deployToStrategy(optimalStrategies[i], allocations[i]);
                strategyAllocations[optimalStrategies[i]] += allocations[i];
            }
        }

        // Generate allocation ID for tracking
        allocationId = keccak256(abi.encodePacked(
            block.timestamp,
            msg.sender,
            amount,
            totalExpectedReturn
        ));

        return allocationId;
    }

    function _deployToStrategy(address strategy, uint256 amount) internal {
        if (!isStrategy[strategy] || blacklistedStrategies[strategy]) {
            revert InvalidStrategy();
        }

        _asset.approve(strategy, amount);
        IStrategies(strategy).execute(amount, "");
    }

    function rebalanceStrategies() external onlyRole(AGENT_ROLE) nonReentrant {
        if (emergencyMode) revert EmergencyModeActive();
        if (block.timestamp < performanceMetrics.lastRebalanceTime + vaultConfig.rebalanceInterval) {
            revert RebalanceTooSoon();
        }

        uint256 totalAssetsBefore = totalAssets();
        
        // Get optimal allocation for current balance
        (
            address[] memory optimalStrategies,
            uint256[] memory newAllocations,
            uint256 expectedYield
        ) = yieldAggregator.calculateOptimalAllocation(
            address(_asset),
            totalAssetsBefore,
            vaultConfig.maxRiskTolerance
        );

        // Check if rebalance is beneficial
        uint256 currentYield = _calculateCurrentYield();
        if (expectedYield <= currentYield + vaultConfig.rebalanceThreshold) {
            return; // Not worth rebalancing
        }

        // Execute rebalance
        _executeRebalance(optimalStrategies, newAllocations);
        
        performanceMetrics.lastRebalanceTime = block.timestamp;
        performanceMetrics.successfulRebalances++;
        
        emit AutoRebalanceExecuted(currentYield, expectedYield, tx.gasprice * gasleft());
    }

    function _executeRebalance(
        address[] memory optimalStrategies,
        uint256[] memory newAllocations
    ) internal {
        // First, withdraw from over-allocated strategies
        for (uint i = 0; i < strategies.length; i++) {
            address strategy = strategies[i];
            uint256 currentAllocation = strategyAllocations[strategy];
            uint256 targetAllocation = 0;
            
            // Find target allocation for this strategy
            for (uint j = 0; j < optimalStrategies.length; j++) {
                if (optimalStrategies[j] == strategy) {
                    targetAllocation = newAllocations[j];
                    break;
                }
            }
            
            if (currentAllocation > targetAllocation) {
                uint256 withdrawAmount = currentAllocation - targetAllocation;
                _withdrawFromStrategy(strategy, withdrawAmount);
                strategyAllocations[strategy] = targetAllocation;
            }
        }
        
        // Then, deploy to under-allocated strategies
        for (uint i = 0; i < optimalStrategies.length; i++) {
            address strategy = optimalStrategies[i];
            uint256 targetAllocation = newAllocations[i];
            uint256 currentAllocation = strategyAllocations[strategy];
            
            if (targetAllocation > currentAllocation) {
                uint256 deployAmount = targetAllocation - currentAllocation;
                if (_asset.balanceOf(address(this)) >= deployAmount) {
                    _deployToStrategy(strategy, deployAmount);
                    strategyAllocations[strategy] = targetAllocation;
                }
            }
        }
    }

    function _withdrawFromStrategy(address strategy, uint256 amount) internal {
        try IStrategies(strategy).emergencyExit("") {
            // Strategy should transfer funds back to vault
        } catch {
            // Mark strategy as blacklisted if withdrawal fails
            blacklistedStrategies[strategy] = true;
        }
    }

    // ====================================================================
    // YIELD HARVESTING & PERFORMANCE FEES
    // ====================================================================

    function harvestAllStrategies() external onlyRole(AGENT_ROLE) nonReentrant {
        uint256 totalYieldBefore = performanceMetrics.totalYieldGenerated;
        
        for (uint i = 0; i < strategies.length; i++) {
            if (!blacklistedStrategies[strategies[i]]) {
                try IStrategies(strategies[i]).harvest("") {
                    // Harvest successful
                } catch {
                    // Log harvest failure but continue
                }
            }
        }
        
        uint256 newYield = performanceMetrics.totalYieldGenerated - totalYieldBefore;
        
        if (newYield > 0) {
            uint256 performanceFee = (newYield * vaultConfig.performanceFee) / 10000;
            if (performanceFee > 0) {
                _asset.safeTransfer(treasury, performanceFee);
                performanceMetrics.totalFeesCollected += performanceFee;
                emit PerformanceFeeCollected(performanceFee, treasury);
            }
            
            emit YieldHarvested(newYield, performanceFee);
        }
    }

    function _calculateCurrentYield() internal view returns (uint256) {
        // Calculate weighted average yield across all strategies
        uint256 totalAllocation = 0;
        uint256 weightedYield = 0;
        
        for (uint i = 0; i < strategies.length; i++) {
            address strategy = strategies[i];
            uint256 allocation = strategyAllocations[strategy];
            
            if (allocation > 0 && !blacklistedStrategies[strategy]) {
                // Get strategy yield from registry
                try strategyRegistry.getStrategyByName(
                    IStrategies(strategy).underlyingToken(),
                    30302 // Flow chain ID
                ) returns (
                    address,
                    uint16,
                    string memory,
                    string memory,
                    uint256 currentAPY,
                    uint256,
                    uint256,
                    uint256,
                    uint256,
                    bool,
                    bool,
                    uint256,
                    bytes memory
                ) {
                    weightedYield += (currentAPY * allocation);
                    totalAllocation += allocation;
                } catch {
                    // Skip if strategy data unavailable
                }
            }
        }
        
        return totalAllocation > 0 ? weightedYield / totalAllocation : 0;
    }

    // ====================================================================
    // EMERGENCY & RISK MANAGEMENT
    // ====================================================================

    function activateEmergencyMode(string calldata reason) external onlyRole(EMERGENCY_ROLE) {
        emergencyMode = true;
        
        // Emergency exit from all strategies
        for (uint i = 0; i < strategies.length; i++) {
            _emergencyExitStrategy(strategies[i]);
        }
        
        emit EmergencyModeActivated(reason);
    }

    function deactivateEmergencyMode() external onlyRole(EMERGENCY_ROLE) {
        emergencyMode = false;
        emit EmergencyModeDeactivated();
    }

    function _emergencyExitStrategy(address strategy) internal {
        try IStrategies(strategy).emergencyExit("") {
            strategyAllocations[strategy] = 0;
        } catch {
            blacklistedStrategies[strategy] = true;
        }
    }

    function _checkAndRebalance() internal {
        if (!vaultConfig.autoRebalanceEnabled) return;
        
        // Check if any strategy has exceeded risk tolerance
        for (uint i = 0; i < strategies.length; i++) {
            address strategy = strategies[i];
            if (blacklistedStrategies[strategy]) continue;
            
            try riskOracle.assessStrategyRisk(strategy) returns (
                uint256 riskScore,
                string memory,
                bool approved,
                uint256
            ) {
                if (riskScore > emergencyExitThreshold) {
                    _emergencyExitStrategy(strategy);
                    blacklistedStrategies[strategy] = true;
                } else if (riskScore > vaultConfig.maxRiskTolerance && approved) {
                    // Reduce allocation to this strategy
                    uint256 currentAllocation = strategyAllocations[strategy];
                    uint256 newAllocation = currentAllocation / 2; // Reduce by 50%
                    
                    if (currentAllocation > newAllocation) {
                        _withdrawFromStrategy(strategy, currentAllocation - newAllocation);
                        strategyAllocations[strategy] = newAllocation;
                    }
                }
            } catch {
                // Skip risk check if oracle unavailable
            }
        }
        
        // Trigger rebalance if interval has passed
        if (block.timestamp >= performanceMetrics.lastRebalanceTime + vaultConfig.rebalanceInterval) {
            try this.rebalanceStrategies() {
                // Rebalance successful
            } catch {
                performanceMetrics.failedRebalances++;
            }
        }
    }

    // ====================================================================
    // CROSS-CHAIN FUNCTIONALITY
    // ====================================================================

    function setBridge(address _bridge) external onlyRole(DEFAULT_ADMIN_ROLE) {
        bridge = _bridge;
    }

    function addSupportedChain(uint16 chainId) external onlyRole(MANAGER_ROLE) {
        supportedChains[chainId] = true;
    }

    function deployToCrossChainStrategy(
        uint16 chainId,
        uint256 amount,
        bytes calldata bridgeData
    ) external onlyRole(AGENT_ROLE) {
        require(supportedChains[chainId], "Chain not supported");
        require(bridge != address(0), "Bridge not set");
        require(_asset.balanceOf(address(this)) >= amount, "Insufficient balance");
        
        // Transfer to bridge for cross-chain deployment
        _asset.safeTransfer(bridge, amount);
        
        chainAllocations[chainId] += amount;
        emit CrossChainDeployment(chainId, bridge, amount);
    }

    // ====================================================================
    // INTERNAL HELPERS
    // ====================================================================

    function _deposit(uint256 assetsValue, uint256 sharesValue, address receiver) internal {
        require(receiver != address(0), "Deposit to zero address");
        require(assetsValue > 0, "Deposit zero assets");

        _asset.safeTransferFrom(msg.sender, address(this), assetsValue);
        _mint(receiver, sharesValue);
        emit Deposit(msg.sender, receiver, assetsValue, sharesValue);
    }

    function _withdraw(uint256 assetsValue, uint256 sharesValue, address receiver, address owner) internal {
        require(receiver != address(0), "Withdraw to zero address");
        require(assetsValue > 0, "Withdraw zero assets");

        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, sharesValue);
        }

        // Check if we need to withdraw from strategies
        uint256 liquidBalance = _asset.balanceOf(address(this));
        if (liquidBalance < assetsValue) {
            uint256 needed = assetsValue - liquidBalance;
            _withdrawFromStrategiesProportionally(needed);
        }

        _burn(owner, sharesValue);
        _asset.safeTransfer(receiver, assetsValue);
        emit Withdraw(msg.sender, receiver, owner, assetsValue, sharesValue);
    }

    function _withdrawFromStrategiesProportionally(uint256 totalNeeded) internal {
        uint256 totalInStrategies = 0;
        
        // Calculate total in strategies
        for (uint i = 0; i < strategies.length; i++) {
            if (!blacklistedStrategies[strategies[i]]) {
                totalInStrategies += strategyAllocations[strategies[i]];
            }
        }
        
        if (totalInStrategies == 0) return;
        
        // Withdraw proportionally from each strategy
        for (uint i = 0; i < strategies.length; i++) {
            address strategy = strategies[i];
            if (!blacklistedStrategies[strategy]) {
                uint256 strategyAllocation = strategyAllocations[strategy];
                uint256 withdrawAmount = (totalNeeded * strategyAllocation) / totalInStrategies;
                
                if (withdrawAmount > 0) {
                    _withdrawFromStrategy(strategy, withdrawAmount);
                    strategyAllocations[strategy] -= withdrawAmount;
                }
            }
        }
    }

    function _convertToShares(uint256 assetsValue, Math.Rounding rounding) internal view returns (uint256) {
        uint256 supply = totalSupply();
        return (supply == 0) ? assetsValue : Math.mulDiv(assetsValue, supply, totalAssets(), rounding);
    }

    function _convertToAssets(uint256 sharesValue, Math.Rounding rounding) internal view returns (uint256) {
        uint256 supply = totalSupply();
        return (supply == 0) ? sharesValue : Math.mulDiv(sharesValue, totalAssets(), supply, rounding);
    }

    // ====================================================================
    // ADMIN FUNCTIONS
    // ====================================================================

    function updateVaultConfig(
        uint256 _maxRiskTolerance,
        uint256 _rebalanceThreshold,
        uint256 _maxSingleStrategyAllocation,
        uint256 _reserveRatio,
        uint256 _performanceFee,
        uint256 _managementFee,
        bool _autoRebalanceEnabled,
        uint256 _rebalanceInterval
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        vaultConfig = VaultConfig({
            maxRiskTolerance: _maxRiskTolerance,
            rebalanceThreshold: _rebalanceThreshold,
            maxSingleStrategyAllocation: _maxSingleStrategyAllocation,
            reserveRatio: _reserveRatio,
            performanceFee: _performanceFee,
            managementFee: _managementFee,
            autoRebalanceEnabled: _autoRebalanceEnabled,
            rebalanceInterval: _rebalanceInterval
        });
    }

    function updateOracles(
        address _riskOracle,
        address _strategyRegistry,
        address _yieldAggregator
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_riskOracle != address(0)) riskOracle = IRiskOracle(_riskOracle);
        if (_strategyRegistry != address(0)) strategyRegistry = IStrategyRegistry(_strategyRegistry);
        if (_yieldAggregator != address(0)) yieldAggregator = IYieldAggregator(_yieldAggregator);
    }

    function setTreasury(address _treasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_treasury != address(0), "Invalid treasury");
        treasury = _treasury;
    }

    function setBuyBackContract(address _buyBackContract) external onlyRole(DEFAULT_ADMIN_ROLE) {
        buyBackContract = _buyBackContract;
    }

    // ====================================================================
    // VIEW FUNCTIONS
    // ====================================================================

    function getStrategies() external view returns (address[] memory) {
        return strategies;
    }

    function getStrategyAllocations() external view returns (address[] memory, uint256[] memory) {
        uint256[] memory allocations = new uint256[](strategies.length);
        for (uint i = 0; i < strategies.length; i++) {
            allocations[i] = strategyAllocations[strategies[i]];
        }
        return (strategies, allocations);
    }

    function getPerformanceMetrics() external view returns (PerformanceMetrics memory) {
        return performanceMetrics;
    }

    function getVaultConfig() external view returns (VaultConfig memory) {
        return vaultConfig;
    }

    function getHealthScore() external view returns (uint256 healthScore, string memory status) {
        // Calculate overall vault health based on strategy risks and performance
        uint256 totalRisk = 0;
        uint256 totalAllocation = 0;
        
        for (uint i = 0; i < strategies.length; i++) {
            address strategy = strategies[i];
            uint256 allocation = strategyAllocations[strategy];
            
            if (allocation > 0 && !blacklistedStrategies[strategy]) {
                try riskOracle.assessStrategyRisk(strategy) returns (
                    uint256 riskScore,
                    string memory,
                    bool,
                    uint256
                ) {
                    totalRisk += (riskScore * allocation);
                    totalAllocation += allocation;
                } catch {
                    // Assume medium risk if assessment fails
                    totalRisk += (5000 * allocation);
                    totalAllocation += allocation;
                }
            }
        }
        
        healthScore = totalAllocation > 0 ? 10000 - (totalRisk / totalAllocation) : 10000;
        
        if (healthScore >= 8000) {
            status = "EXCELLENT";
        } else if (healthScore >= 6000) {
            status = "GOOD";
        } else if (healthScore >= 4000) {
            status = "FAIR";
        } else if (healthScore >= 2000) {
            status = "POOR";
        } else {
            status = "CRITICAL";
        }
    }
}