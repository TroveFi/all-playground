// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IStrategy {
    function executeWithAsset(address asset, uint256 amount, bytes calldata data) external payable returns (uint256);
    function harvest(bytes calldata data) external returns (uint256);
    function emergencyExit(bytes calldata data) external returns (uint256);
    function getBalance() external view returns (uint256);
    function underlyingToken() external view returns (address);
    function strategyType() external view returns (string memory);
}

/// @title StrategyManager - Manages all strategy executions for the vault
/// @notice Handles strategy deployment, harvesting, and tracking
contract StrategyManager is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    // ====================================================================
    // ROLES
    // ====================================================================
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    
    // ====================================================================
    // STRUCTS
    // ====================================================================
    struct StrategyInfo {
        address strategyAddress;
        string strategyType;
        address underlyingAsset;
        uint256 totalDeployed;
        uint256 totalHarvested;
        uint256 lastHarvestTime;
        uint256 lastDeployTime;
        bool active;
        bool emergency;
    }
    
    struct StrategyPerformance {
        uint256 totalReturns;
        uint256 totalLosses;
        uint256 harvestCount;
        uint256 avgHarvestAmount;
        uint256 lastAPY;
    }
    
    // ====================================================================
    // STATE VARIABLES
    // ====================================================================
    address public vault;
    
    mapping(address => StrategyInfo) public strategies;
    mapping(address => StrategyPerformance) public strategyPerformance;
    mapping(address => address[]) public assetStrategies; // asset => strategy addresses
    
    address[] public allStrategies;
    
    bool public emergencyMode;
    
    // ====================================================================
    // EVENTS
    // ====================================================================
    event StrategyRegistered(address indexed strategy, string strategyType, address indexed asset);
    event StrategyDeployed(address indexed strategy, address indexed asset, uint256 amount);
    event StrategyHarvested(address indexed strategy, uint256 amount, uint256 timestamp);
    event StrategyEmergencyExit(address indexed strategy, uint256 recovered);
    event StrategyStatusChanged(address indexed strategy, bool active);
    event EmergencyModeToggled(bool enabled);
    
    // ====================================================================
    // CONSTRUCTOR
    // ====================================================================
    constructor(address _vault) {
        require(_vault != address(0), "Invalid vault");
        
        vault = _vault;
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(VAULT_ROLE, _vault);
        _grantRole(EMERGENCY_ROLE, msg.sender);
    }
    
    // ====================================================================
    // MODIFIERS
    // ====================================================================
    modifier onlyVault() {
        require(hasRole(VAULT_ROLE, msg.sender), "Only vault");
        _;
    }
    
    modifier whenNotEmergency() {
        require(!emergencyMode, "Emergency mode active");
        _;
    }
    
    // ====================================================================
    // STRATEGY REGISTRATION
    // ====================================================================
    function registerStrategy(
        address strategy,
        string memory strategyType,
        address underlyingAsset
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(strategy != address(0), "Invalid strategy");
        require(strategies[strategy].strategyAddress == address(0), "Already registered");
        
        strategies[strategy] = StrategyInfo({
            strategyAddress: strategy,
            strategyType: strategyType,
            underlyingAsset: underlyingAsset,
            totalDeployed: 0,
            totalHarvested: 0,
            lastHarvestTime: 0,
            lastDeployTime: 0,
            active: true,
            emergency: false
        });
        
        allStrategies.push(strategy);
        assetStrategies[underlyingAsset].push(strategy);
        
        emit StrategyRegistered(strategy, strategyType, underlyingAsset);
    }
    
    // ====================================================================
    // STRATEGY EXECUTION
    // ====================================================================
    function executeStrategy(
        address strategy,
        address asset,
        uint256 amount,
        bytes calldata data
    ) external onlyVault nonReentrant whenNotEmergency returns (uint256) {
        require(strategies[strategy].active, "Strategy not active");
        require(strategies[strategy].underlyingAsset == asset, "Asset mismatch");
        require(amount > 0, "Amount must be positive");
        
        uint256 result;
        
        if (asset == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
            // Native FLOW
            result = IStrategy(strategy).executeWithAsset{value: amount}(asset, amount, data);
        } else {
            // ERC20
            IERC20(asset).safeTransferFrom(msg.sender, strategy, amount);
            result = IStrategy(strategy).executeWithAsset(asset, amount, data);
        }
        
        strategies[strategy].totalDeployed += amount;
        strategies[strategy].lastDeployTime = block.timestamp;
        
        emit StrategyDeployed(strategy, asset, amount);
        return result;
    }
    
    function deployToStrategies(
        address[] calldata strategyList,
        uint256[] calldata amounts,
        address asset
    ) external onlyVault nonReentrant whenNotEmergency {
        require(strategyList.length == amounts.length, "Length mismatch");
        
        for (uint256 i = 0; i < strategyList.length; i++) {
            if (amounts[i] > 0 && strategies[strategyList[i]].active) {
                this.executeStrategy(strategyList[i], asset, amounts[i], "");
            }
        }
    }
    
    // ====================================================================
    // HARVESTING
    // ====================================================================
    function harvestStrategy(
        address strategy,
        bytes calldata data
    ) external onlyVault nonReentrant returns (uint256) {
        require(strategies[strategy].active, "Strategy not active");
        
        uint256 harvestedAmount = IStrategy(strategy).harvest(data);
        
        if (harvestedAmount > 0) {
            strategies[strategy].totalHarvested += harvestedAmount;
            strategies[strategy].lastHarvestTime = block.timestamp;
            
            StrategyPerformance storage perf = strategyPerformance[strategy];
            perf.totalReturns += harvestedAmount;
            perf.harvestCount++;
            perf.avgHarvestAmount = perf.totalReturns / perf.harvestCount;
            
            emit StrategyHarvested(strategy, harvestedAmount, block.timestamp);
        }
        
        return harvestedAmount;
    }
    
    function harvestFromStrategies(
        address[] calldata strategyList,
        address asset
    ) external onlyVault nonReentrant returns (uint256 totalHarvested) {
        totalHarvested = 0;
        
        for (uint256 i = 0; i < strategyList.length; i++) {
            if (strategies[strategyList[i]].active && 
                strategies[strategyList[i]].underlyingAsset == asset) {
                try this.harvestStrategy(strategyList[i], "") returns (uint256 harvested) {
                    totalHarvested += harvested;
                } catch {
                    // Continue with other strategies if one fails
                }
            }
        }
        
        return totalHarvested;
    }
    
    // ====================================================================
    // EMERGENCY FUNCTIONS
    // ====================================================================
    function emergencyExitStrategy(address strategy) 
        external 
        onlyRole(EMERGENCY_ROLE) 
        nonReentrant 
        returns (uint256) 
    {
        require(strategies[strategy].strategyAddress != address(0), "Strategy not registered");
        
        strategies[strategy].emergency = true;
        strategies[strategy].active = false;
        
        uint256 recovered = IStrategy(strategy).emergencyExit("");
        
        emit StrategyEmergencyExit(strategy, recovered);
        return recovered;
    }
    
    function setEmergencyMode(bool enabled) external onlyRole(EMERGENCY_ROLE) {
        emergencyMode = enabled;
        emit EmergencyModeToggled(enabled);
    }
    
    // ====================================================================
    // STRATEGY MANAGEMENT
    // ====================================================================
    function setStrategyStatus(address strategy, bool active) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(strategies[strategy].strategyAddress != address(0), "Strategy not registered");
        strategies[strategy].active = active;
        emit StrategyStatusChanged(strategy, active);
    }
    
    // ====================================================================
    // VIEW FUNCTIONS
    // ====================================================================
    function getActiveStrategies() external view returns (address[] memory) {
        uint256 activeCount = 0;
        
        for (uint256 i = 0; i < allStrategies.length; i++) {
            if (strategies[allStrategies[i]].active) {
                activeCount++;
            }
        }
        
        address[] memory activeStrategies = new address[](activeCount);
        uint256 index = 0;
        
        for (uint256 i = 0; i < allStrategies.length; i++) {
            if (strategies[allStrategies[i]].active) {
                activeStrategies[index] = allStrategies[i];
                index++;
            }
        }
        
        return activeStrategies;
    }
    
    function getStrategiesForAsset(address asset) external view returns (address[] memory) {
        return assetStrategies[asset];
    }
    
    function getStrategyInfo(address strategy) external view returns (
        string memory strategyType,
        address underlyingAsset,
        uint256 totalDeployed,
        uint256 totalHarvested,
        uint256 lastHarvestTime,
        bool active,
        bool emergency
    ) {
        StrategyInfo memory info = strategies[strategy];
        return (
            info.strategyType,
            info.underlyingAsset,
            info.totalDeployed,
            info.totalHarvested,
            info.lastHarvestTime,
            info.active,
            info.emergency
        );
    }
    
    function getStrategyPerformance(address strategy) external view returns (
        uint256 totalReturns,
        uint256 totalLosses,
        uint256 harvestCount,
        uint256 avgHarvestAmount,
        uint256 apy
    ) {
        StrategyPerformance memory perf = strategyPerformance[strategy];
        StrategyInfo memory info = strategies[strategy];
        
        // Calculate simple APY if we have data
        uint256 calculatedAPY = 0;
        if (info.totalDeployed > 0 && info.lastHarvestTime > info.lastDeployTime) {
            uint256 timeElapsed = info.lastHarvestTime - info.lastDeployTime;
            if (timeElapsed > 0) {
                calculatedAPY = (info.totalHarvested * 365 days * 10000) / (info.totalDeployed * timeElapsed);
            }
        }
        
        return (
            perf.totalReturns,
            perf.totalLosses,
            perf.harvestCount,
            perf.avgHarvestAmount,
            calculatedAPY
        );
    }
    
    function getAllStrategies() external view returns (address[] memory) {
        return allStrategies;
    }
    
    function getTotalDeployedToStrategies(address asset) external view returns (uint256 total) {
        address[] memory assetStrats = assetStrategies[asset];
        total = 0;
        
        for (uint256 i = 0; i < assetStrats.length; i++) {
            if (strategies[assetStrats[i]].active) {
                total += strategies[assetStrats[i]].totalDeployed;
            }
        }
        
        return total;
    }
}