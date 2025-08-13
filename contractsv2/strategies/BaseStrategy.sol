// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import "../interfaces/IStrategies.sol";

/// @title BaseStrategy - Base implementation for all yield strategies
/// @notice Provides common functionality and security features for strategy contracts
abstract contract BaseStrategy is IStrategies, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant STRATEGY_ROLE = keccak256("STRATEGY_ROLE");
    bytes32 public constant HARVESTER_ROLE = keccak256("HARVESTER_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    IERC20 public immutable assetToken;
    address public immutable protocolAddress;
    address public vault;
    bool public strategyPaused;
    string public strategyName;
    
    // Strategy metrics
    uint256 public totalDeployed;
    uint256 public totalHarvested;
    uint256 public lastHarvestTime;
    uint256 public harvestCount;
    
    // Risk and performance tracking
    uint256 public maxSlippage = 300; // 3% default
    uint256 public maxSingleDeployment = 1000000 * 10**6; // 1M USDC default
    uint256 public minHarvestAmount = 1 * 10**6; // 1 USDC minimum

    // Events
    event StrategyExecuted(uint256 amount, bytes data);
    event StrategyHarvested(uint256 harvested, uint256 totalHarvested);
    event EmergencyExitExecuted(uint256 recoveredAmount);
    event StrategyPaused();
    event StrategyUnpaused();

    constructor(
        address _asset,
        address _protocolAddress,
        address _vault,
        string memory _name
    ) {
        require(_asset != address(0), "Invalid asset");
        require(_protocolAddress != address(0), "Invalid protocol");
        require(_vault != address(0), "Invalid vault");

        assetToken = IERC20(_asset);
        protocolAddress = _protocolAddress;
        vault = _vault;
        strategyName = _name;
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(STRATEGY_ROLE, _vault);
        _grantRole(HARVESTER_ROLE, msg.sender);
    }

    modifier onlyVault() {
        require(msg.sender == vault, "Only vault can call");
        _;
    }

    modifier whenNotPaused() {
        require(!strategyPaused, "Strategy is paused");
        _;
    }

    modifier onlyHarvester() {
        require(hasRole(HARVESTER_ROLE, msg.sender), "Not authorized harvester");
        _;
    }

    function execute(uint256 amount, bytes calldata data) external virtual override onlyVault nonReentrant whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");
        require(amount <= maxSingleDeployment, "Amount exceeds max deployment");
        
        assetToken.safeTransferFrom(msg.sender, address(this), amount);
        _executeStrategy(amount, data);
        
        totalDeployed += amount;
        emit StrategyExecuted(amount, data);
        emit Deposit(amount);
    }

    function harvest(bytes calldata data) external virtual override onlyHarvester nonReentrant whenNotPaused {
        uint256 balanceBefore = assetToken.balanceOf(address(this));
        _harvestRewards(data);
        
        uint256 harvested = assetToken.balanceOf(address(this)) - balanceBefore;
        
        if (harvested >= minHarvestAmount) {
            _transferToVault(harvested);
            
            totalHarvested += harvested;
            lastHarvestTime = block.timestamp;
            harvestCount++;
            
            emit StrategyHarvested(harvested, totalHarvested);
            emit Harvest(harvested);
        }
    }

    function emergencyExit(bytes calldata data) external virtual override onlyRole(EMERGENCY_ROLE) nonReentrant {
        strategyPaused = true;
        
        uint256 recovered = _emergencyWithdraw(data);
        
        uint256 remainingBalance = assetToken.balanceOf(address(this));
        if (remainingBalance > 0) {
            _transferToVault(remainingBalance);
            recovered += remainingBalance;
        }
        
        emit EmergencyExitExecuted(recovered);
        emit EmergencyExit(recovered);
    }

    function getBalance() external view virtual override returns (uint256) {
        return assetToken.balanceOf(address(this));
    }

    function underlyingToken() external view virtual override returns (address) {
        return address(assetToken);
    }

    function protocol() external view virtual override returns (address) {
        return protocolAddress;
    }

    function paused() external view virtual override returns (bool) {
        return strategyPaused;
    }

    function setPaused(bool pauseState) external virtual override onlyRole(DEFAULT_ADMIN_ROLE) {
        strategyPaused = pauseState;
        if (pauseState) {
            emit StrategyPaused();
        } else {
            emit StrategyUnpaused();
        }
    }

    // Virtual functions to be implemented by derived strategies
    function _executeStrategy(uint256 amount, bytes calldata data) internal virtual;
    function _harvestRewards(bytes calldata data) internal virtual;
    function _emergencyWithdraw(bytes calldata data) internal virtual returns (uint256 recovered);

    function _transferToVault(uint256 amount) internal {
        if (amount > 0) {
            assetToken.safeTransfer(vault, amount);
        }
    }

    function _getAssetBalance() internal view returns (uint256) {
        return assetToken.balanceOf(address(this));
    }

    // Admin functions
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        strategyPaused = true;
        emit StrategyPaused();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        strategyPaused = false;
        emit StrategyUnpaused();
    }

    function setMaxSlippage(uint256 newSlippage) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newSlippage <= 1000, "Slippage too high");
        maxSlippage = newSlippage;
    }

    function setMaxSingleDeployment(uint256 newMax) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxSingleDeployment = newMax;
    }

    function setMinHarvestAmount(uint256 newMin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minHarvestAmount = newMin;
    }

    function grantHarvesterRole(address harvester) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(HARVESTER_ROLE, harvester);
    }

    function revokeHarvesterRole(address harvester) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(HARVESTER_ROLE, harvester);
    }

    // View functions for strategy info
    function getStrategyInfo() external view returns (
        string memory name,
        address asset,
        address protocolAddr,
        uint256 totalDep,
        uint256 totalHarv,
        uint256 lastHarvest,
        bool isPaused
    ) {
        return (
            strategyName,
            address(assetToken),
            protocolAddress,
            totalDeployed,
            totalHarvested,
            lastHarvestTime,
            strategyPaused
        );
    }

    function getPerformanceMetrics() external view returns (
        uint256 totalDeployedAmount,
        uint256 totalHarvestedAmount,
        uint256 harvestsCount,
        uint256 avgHarvestAmount,
        uint256 lastHarvestTimestamp
    ) {
        uint256 avgHarvest = harvestCount > 0 ? totalHarvested / harvestCount : 0;
        
        return (
            totalDeployed,
            totalHarvested,
            harvestCount,
            avgHarvest,
            lastHarvestTime
        );
    }

    // Required interface implementations (stubs for unused functions)
    function setVault(address) external virtual override {}
    function addRewardToken(address) external virtual override {}
    function claimRewards(bytes calldata) external virtual override {}
    function queryProtocol(bytes4, bytes calldata) external view virtual override returns (bytes memory) { return ""; }
    function knownRewardTokens(address) external view virtual override returns (bool) { return false; }
    function rewardTokensList() external view virtual override returns (address[] memory) { 
        return new address[](0); 
    }
    function depositSelector() external pure virtual override returns (bytes4) { return bytes4(0); }
    function withdrawSelector() external pure virtual override returns (bytes4) { return bytes4(0); }
    function claimSelector() external pure virtual override returns (bytes4) { return bytes4(0); }
    function getBalanceSelector() external pure virtual override returns (bytes4) { return bytes4(0); }
}