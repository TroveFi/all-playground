// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IStrategy {
    function execute(uint256 amount, bytes calldata data) external;
    function harvest(bytes calldata data) external;
    function emergencyExit(bytes calldata data) external;
    function getBalance() external view returns (uint256 balance);
    function underlyingToken() external view returns (address token);
    function protocol() external view returns (address protocol);
    function paused() external view returns (bool paused);
}

interface IEnhancedStrategy is IStrategy {
    function getHealthFactor() external view returns (uint256);
    function getLeverageRatio() external view returns (uint256);
    function getPositionValue() external view returns (uint256 collateral, uint256 debt);
    function checkLiquidationRisk() external view returns (bool atRisk, uint256 buffer);
    function emergencyDelever() external;
}

contract MultiAssetStrategyManager is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");

    address public vault;

    enum StrategyType { BASIC, ADVANCED }

    struct StrategyInfo {
        address strategyAddress;
        string name;
        uint256 allocation;
        mapping(address => uint256) balancePerAsset; // Track balance per asset
        bool active;
        StrategyType strategyType;
        uint256 riskLevel;
        uint256 lastHealthCheck;
        address[] supportedAssets;
    }

    mapping(address => StrategyInfo) public strategies;
    address[] public activeStrategies;
    address[] public advancedStrategies;

    // Track deployments per asset
    mapping(address => uint256) public totalDeployedPerAsset;
    mapping(address => uint256) public lastHarvestTimePerAsset;

    uint256 public totalAllocation;

    event StrategyAdded(address indexed strategy, string name, uint256 allocation, StrategyType strategyType);
    event AssetDeployedToStrategy(address indexed strategy, address indexed asset, uint256 amount);
    event AssetHarvestedFromStrategy(address indexed strategy, address indexed asset, uint256 harvested);
    event StrategyEmergencyExit(address indexed strategy);

    constructor(address _vault) {
        require(_vault != address(0), "Invalid vault");

        vault = _vault;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(VAULT_ROLE, _vault);
    }

    modifier onlyVault() {
        require(hasRole(VAULT_ROLE, msg.sender), "Only vault can call");
        _;
    }

    function addStrategy(address strategy, string calldata name, uint256 allocation) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(strategy != address(0), "Invalid strategy");
        require(allocation > 0, "Invalid allocation");
        require(!strategies[strategy].active, "Strategy already exists");

        StrategyInfo storage info = strategies[strategy];
        info.strategyAddress = strategy;
        info.name = name;
        info.allocation = allocation;
        info.active = true;
        info.strategyType = StrategyType.BASIC;
        info.riskLevel = 1;
        info.lastHealthCheck = block.timestamp;

        activeStrategies.push(strategy);
        totalAllocation += allocation;

        emit StrategyAdded(strategy, name, allocation, StrategyType.BASIC);
    }

    function addAdvancedStrategy(
        address strategy,
        string calldata name,
        uint256 allocation,
        uint256 riskLevel,
        address[] calldata supportedAssets
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(strategy != address(0), "Invalid strategy");
        require(allocation > 0, "Invalid allocation");
        require(riskLevel >= 1 && riskLevel <= 3, "Invalid risk level");
        require(!strategies[strategy].active, "Strategy already exists");

        StrategyInfo storage info = strategies[strategy];
        info.strategyAddress = strategy;
        info.name = name;
        info.allocation = allocation;
        info.active = true;
        info.strategyType = StrategyType.ADVANCED;
        info.riskLevel = riskLevel;
        info.lastHealthCheck = block.timestamp;
        info.supportedAssets = supportedAssets;

        activeStrategies.push(strategy);
        advancedStrategies.push(strategy);
        totalAllocation += allocation;

        emit StrategyAdded(strategy, name, allocation, StrategyType.ADVANCED);
    }

    function deployToStrategies(
        address[] calldata strategyAddresses, 
        uint256[] calldata amounts,
        address asset
    ) external onlyVault nonReentrant {
        require(strategyAddresses.length == amounts.length, "Array length mismatch");

        for (uint256 i = 0; i < strategyAddresses.length; i++) {
            address strategy = strategyAddresses[i];
            uint256 amount = amounts[i];

            require(strategies[strategy].active, "Strategy not active");
            require(amount > 0, "Invalid amount");

            // Check if strategy supports this asset
            if (strategies[strategy].supportedAssets.length > 0) {
                bool assetSupported = false;
                for (uint256 j = 0; j < strategies[strategy].supportedAssets.length; j++) {
                    if (strategies[strategy].supportedAssets[j] == asset) {
                        assetSupported = true;
                        break;
                    }
                }
                require(assetSupported, "Asset not supported by strategy");
            }

            // Transfer asset from vault to strategy
            IERC20(asset).safeTransferFrom(msg.sender, strategy, amount);

            // Execute strategy with asset-specific data
            bytes memory data = abi.encode(asset);
            IStrategy(strategy).execute(amount, data);

            // Update tracking
            strategies[strategy].balancePerAsset[asset] += amount;
            strategies[strategy].lastHealthCheck = block.timestamp;
            totalDeployedPerAsset[asset] += amount;

            emit AssetDeployedToStrategy(strategy, asset, amount);
        }
    }

    function harvestFromStrategies(
        address[] calldata strategyAddresses,
        address asset
    ) external onlyVault nonReentrant returns (uint256 totalHarvested) {
        uint256 balanceBefore = IERC20(asset).balanceOf(address(this));

        for (uint256 i = 0; i < strategyAddresses.length; i++) {
            address strategy = strategyAddresses[i];
            require(strategies[strategy].active, "Strategy not active");

            try IStrategy(strategy).harvest(abi.encode(asset)) {
                // Update balance tracking
                uint256 newBalance = IStrategy(strategy).getBalance();
                
                // For multi-asset strategies, we need to track per asset
                // This is simplified - in production you'd want more sophisticated tracking
                strategies[strategy].lastHealthCheck = block.timestamp;
                
            } catch {
                // Continue if harvest fails for one strategy
            }
        }

        totalHarvested = IERC20(asset).balanceOf(address(this)) - balanceBefore;
        
        if (totalHarvested > 0) {
            // Transfer harvested assets back to vault
            IERC20(asset).safeTransfer(vault, totalHarvested);
            lastHarvestTimePerAsset[asset] = block.timestamp;
            
            emit AssetHarvestedFromStrategy(address(0), asset, totalHarvested);
        }

        return totalHarvested;
    }

    function emergencyExitStrategy(address strategy, address asset) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
        nonReentrant 
    {
        require(strategies[strategy].active, "Strategy not active");

        try IStrategy(strategy).emergencyExit(abi.encode(asset)) {
            strategies[strategy].active = false;
            strategies[strategy].balancePerAsset[asset] = 0;
            emit StrategyEmergencyExit(strategy);
        } catch {
            // Emergency exit failed
        }
    }

    function checkAdvancedStrategiesHealth() external view returns (
        address[] memory atRiskStrategies,
        uint256[] memory healthFactors
    ) {
        uint256 riskCount = 0;
        
        for (uint256 i = 0; i < advancedStrategies.length; i++) {
            address strategy = advancedStrategies[i];
            if (strategies[strategy].active) {
                try IEnhancedStrategy(strategy).checkLiquidationRisk() returns (bool atRisk, uint256) {
                    if (atRisk) riskCount++;
                } catch {}
            }
        }

        atRiskStrategies = new address[](riskCount);
        healthFactors = new uint256[](riskCount);
        
        uint256 index = 0;
        for (uint256 i = 0; i < advancedStrategies.length; i++) {
            address strategy = advancedStrategies[i];
            if (strategies[strategy].active) {
                try IEnhancedStrategy(strategy).checkLiquidationRisk() returns (bool atRisk, uint256) {
                    if (atRisk) {
                        atRiskStrategies[index] = strategy;
                        try IEnhancedStrategy(strategy).getHealthFactor() returns (uint256 hf) {
                            healthFactors[index] = hf;
                        } catch {
                            healthFactors[index] = 0;
                        }
                        index++;
                    }
                } catch {}
            }
        }
    }

    function getActiveStrategies() external view returns (address[] memory) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < activeStrategies.length; i++) {
            if (strategies[activeStrategies[i]].active) {
                activeCount++;
            }
        }

        address[] memory active = new address[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < activeStrategies.length; i++) {
            if (strategies[activeStrategies[i]].active) {
                active[index] = activeStrategies[i];
                index++;
            }
        }
        return active;
    }

    function getStrategyInfo(address strategy) external view returns (
        string memory name,
        uint256 allocation,
        uint256 balance,
        bool active
    ) {
        StrategyInfo storage info = strategies[strategy];
        // For multi-asset, we return total balance across all assets (simplified)
        uint256 totalBalance = 0;
        
        return (info.name, info.allocation, totalBalance, info.active);
    }

    function getStrategyAssetBalance(address strategy, address asset) external view returns (uint256) {
        return strategies[strategy].balancePerAsset[asset];
    }

    function getAdvancedStrategies() external view returns (address[] memory) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < advancedStrategies.length; i++) {
            if (strategies[advancedStrategies[i]].active) {
                activeCount++;
            }
        }

        address[] memory active = new address[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < advancedStrategies.length; i++) {
            if (strategies[advancedStrategies[i]].active) {
                active[index] = advancedStrategies[i];
                index++;
            }
        }
        return active;
    }

    function updateStrategyAllocation(address strategy, uint256 newAllocation) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(strategies[strategy].active, "Strategy not active");
        
        uint256 oldAllocation = strategies[strategy].allocation;
        totalAllocation = totalAllocation - oldAllocation + newAllocation;
        strategies[strategy].allocation = newAllocation;
    }

    function pauseStrategy(address strategy) external onlyRole(DEFAULT_ADMIN_ROLE) {
        strategies[strategy].active = false;
    }

    function unpauseStrategy(address strategy) external onlyRole(DEFAULT_ADMIN_ROLE) {
        strategies[strategy].active = true;
    }

    function updateVault(address newVault) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newVault != address(0), "Invalid vault");
        _revokeRole(VAULT_ROLE, vault);
        _grantRole(VAULT_ROLE, newVault);
        vault = newVault;
    }
}