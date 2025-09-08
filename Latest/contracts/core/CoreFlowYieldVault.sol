// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IMultiAssetManager {
    function depositAsset(address asset, uint256 amount, address receiver) external returns (uint256 baseAmount);
    function withdrawToAsset(address asset, uint256 baseAmount, address receiver) external returns (uint256 assetAmount);
    function convertToBase(address asset, uint256 amount) external returns (uint256 baseAmount);
    function getSupportedAssets() external view returns (address[] memory);
    function isAssetSupported(address asset) external view returns (bool);
}

interface IStrategyManager {
    function addStrategy(address strategy, string calldata name, uint256 allocation) external;
    function deployToStrategies(address[] calldata strategies, uint256[] calldata amounts) external;
    function harvestFromStrategies(address[] calldata strategies) external returns (uint256 totalHarvested);
    function getActiveStrategies() external view returns (address[] memory);
    function getStrategyInfo(address strategy) external view returns (string memory name, uint256 allocation, uint256 balance, bool active);
}

interface ILotteryManager {
    function addParticipant(address participant, uint256 weight) external;
    function startNewRound() external;
    function finalizeRound(uint256 roundId) external;
    function getCurrentRound() external view returns (uint256 roundId, bool isActive, uint256 participants, uint256 prizePool);
    function isUserParticipating(address user, uint256 roundId) external view returns (bool);
}

interface IRiskManager {
    function checkRisk() external view returns (bool healthy, uint256 riskScore);
    function performRiskCheck() external;
    function isWithinRiskLimits(uint256 amount) external view returns (bool);
    function getRiskMetrics() external view returns (uint256 totalLeverage, uint256 avgHealthFactor, bool emergency);
}

contract CoreFlowYieldVault is ERC20, AccessControl, ReentrancyGuard, IERC4626 {
    using SafeERC20 for IERC20;

    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    IERC20 private immutable _asset;
    
    // Component contracts
    IMultiAssetManager public multiAssetManager;
    IStrategyManager public strategyManager;
    ILotteryManager public lotteryManager;
    IRiskManager public riskManager;
    
    address public agentAddress;
    
    // Core vault state
    mapping(address => uint256) public userShares;
    mapping(address => uint256) public lastDepositTime;
    mapping(address => bool) public canWithdraw;
    mapping(address => uint256) public withdrawalRequestTime;
    
    // Vault settings
    uint256 public withdrawalDelay = 1 days;
    uint256 public managementFeeRate = 200; // 2%
    uint256 public performanceFeeRate = 1000; // 10%
    uint256 public lastFeeCollection;
    
    // Control flags
    bool public depositsEnabled = true;
    bool public withdrawalsEnabled = true;
    bool public emergencyMode = false;
    
    // Tracking variables
    uint256 public totalDeployed;
    uint256 public totalHarvestedAmount; // Renamed to avoid conflicts

    event UserDeposited(address indexed user, address asset, uint256 assetAmount, uint256 baseAmount, uint256 shares);
    event UserWithdrawalRequested(address indexed user, uint256 amount, uint256 availableAt);
    event UserWithdrawalExecuted(address indexed user, address asset, uint256 amount);
    event YieldHarvested(uint256 totalYield, uint256 managementFees, uint256 performanceFees);
    event EmergencyModeToggled(bool enabled);
    event ComponentUpdated(string component, address newAddress);

    constructor(
        string memory name,
        string memory symbol,
        address _baseAsset,
        address _agentAddress
    ) ERC20(name, symbol) {
        require(_baseAsset != address(0), "Invalid base asset");
        require(_agentAddress != address(0), "Invalid agent");

        _asset = IERC20(_baseAsset);
        agentAddress = _agentAddress;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(AGENT_ROLE, _agentAddress);

        lastFeeCollection = block.timestamp;
    }

    modifier whenNotEmergency() {
        require(!emergencyMode, "Emergency mode active");
        _;
    }

    modifier whenDepositsEnabled() {
        require(depositsEnabled, "Deposits disabled");
        _;
    }

    modifier whenWithdrawalsEnabled() {
        require(withdrawalsEnabled, "Withdrawals disabled");
        _;
    }

    modifier onlyAgent() {
        require(hasRole(AGENT_ROLE, msg.sender), "Only agent can call");
        _;
    }

    // ====================================================================
    // ERC4626 IMPLEMENTATION
    // ====================================================================

    function asset() public view virtual override returns (address) {
        return address(_asset);
    }

    function totalAssets() public view virtual override returns (uint256) {
        uint256 vaultBalance = _asset.balanceOf(address(this));
        uint256 strategyBalance = 0;
        
        if (address(strategyManager) != address(0)) {
            address[] memory strategies = strategyManager.getActiveStrategies();
            for (uint256 i = 0; i < strategies.length; i++) {
                (, , uint256 balance, bool active) = strategyManager.getStrategyInfo(strategies[i]);
                if (active) {
                    strategyBalance += balance;
                }
            }
        }
        
        return vaultBalance + strategyBalance;
    }

    function convertToShares(uint256 assets) public view virtual override returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Down);
    }

    function convertToAssets(uint256 shares) public view virtual override returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Down);
    }

    function maxDeposit(address) public view virtual override returns (uint256) {
        return depositsEnabled && !emergencyMode ? type(uint256).max : 0;
    }

    function previewDeposit(uint256 assets) public view virtual override returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Down);
    }

    function deposit(uint256 assets, address receiver) 
        public 
        virtual 
        override 
        nonReentrant 
        whenNotEmergency 
        whenDepositsEnabled 
        returns (uint256 shares) 
    {
        require(assets > 0, "Amount must be greater than 0");
        
        // Risk check if available
        if (address(riskManager) != address(0)) {
            require(riskManager.isWithinRiskLimits(assets), "Risk limits exceeded");
        }

        _asset.safeTransferFrom(msg.sender, address(this), assets);
        
        shares = _convertToShares(assets, Math.Rounding.Down);
        _mint(receiver, shares);

        userShares[receiver] += shares;
        lastDepositTime[receiver] = block.timestamp;
        totalDeployed += assets;

        // Add to lottery if available
        if (address(lotteryManager) != address(0)) {
            try lotteryManager.addParticipant(receiver, assets) {} catch {}
        }

        emit UserDeposited(receiver, address(_asset), assets, assets, shares);
        emit Deposit(msg.sender, receiver, assets, shares);
        
        return shares;
    }

    function maxMint(address receiver) public view virtual override returns (uint256) {
        return maxDeposit(receiver);
    }

    function previewMint(uint256 shares) public view virtual override returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Up);
    }

    function mint(uint256 shares, address receiver) 
        public 
        virtual 
        override 
        nonReentrant 
        whenNotEmergency 
        whenDepositsEnabled 
        returns (uint256 assets) 
    {
        assets = previewMint(shares);
        deposit(assets, receiver);
        return assets;
    }

    function maxWithdraw(address owner) public view virtual override returns (uint256) {
        if (!withdrawalsEnabled || emergencyMode || !canWithdraw[owner]) return 0;
        return _convertToAssets(balanceOf(owner), Math.Rounding.Down);
    }

    function previewWithdraw(uint256 assets) public view virtual override returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Up);
    }

    function withdraw(uint256 assets, address receiver, address owner) 
        public 
        virtual 
        override 
        nonReentrant 
        whenWithdrawalsEnabled 
        returns (uint256 shares) 
    {
        require(canWithdraw[owner], "Withdrawal not requested");
        require(block.timestamp >= withdrawalRequestTime[owner] + withdrawalDelay, "Withdrawal delay not met");

        shares = _convertToShares(assets, Math.Rounding.Up);

        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        _burn(owner, shares);
        _asset.safeTransfer(receiver, assets);

        userShares[owner] -= shares;
        canWithdraw[owner] = false;

        emit UserWithdrawalExecuted(owner, address(_asset), assets);
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
        
        return shares;
    }

    function maxRedeem(address owner) public view virtual override returns (uint256) {
        return balanceOf(owner);
    }

    function previewRedeem(uint256 shares) public view virtual override returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Down);
    }

    function redeem(uint256 shares, address receiver, address owner) 
        public 
        virtual 
        override 
        nonReentrant 
        returns (uint256 assets) 
    {
        assets = previewRedeem(shares);
        withdraw(assets, receiver, owner);
        return assets;
    }

    // ====================================================================
    // MULTI-ASSET SUPPORT
    // ====================================================================

    function depositAsset(address asset, uint256 amount, address receiver) 
        external 
        nonReentrant 
        whenNotEmergency 
        whenDepositsEnabled 
        returns (uint256 shares) 
    {
        require(address(multiAssetManager) != address(0), "Multi-asset not available");
        require(amount > 0, "Amount must be greater than 0");

        uint256 baseAmount = multiAssetManager.depositAsset(asset, amount, receiver);
        
        shares = _convertToShares(baseAmount, Math.Rounding.Down);
        _mint(receiver, shares);

        userShares[receiver] += shares;
        lastDepositTime[receiver] = block.timestamp;
        totalDeployed += baseAmount;

        // Add to lottery if available
        if (address(lotteryManager) != address(0)) {
            try lotteryManager.addParticipant(receiver, baseAmount) {} catch {}
        }

        emit UserDeposited(receiver, asset, amount, baseAmount, shares);
        emit Deposit(msg.sender, receiver, baseAmount, shares);
        
        return shares;
    }

    // ====================================================================
    // WITHDRAWAL MANAGEMENT
    // ====================================================================

    function requestWithdrawal(uint256 amount) external {
        require(amount > 0, "Invalid amount");
        require(balanceOf(msg.sender) >= _convertToShares(amount, Math.Rounding.Up), "Insufficient balance");

        canWithdraw[msg.sender] = true;
        withdrawalRequestTime[msg.sender] = block.timestamp;

        emit UserWithdrawalRequested(msg.sender, amount, block.timestamp + withdrawalDelay);
    }

    // ====================================================================
    // STRATEGY MANAGEMENT
    // ====================================================================

    function deployToStrategies(address[] calldata strategies, uint256[] calldata amounts) 
        external 
        onlyAgent 
        nonReentrant 
    {
        require(address(strategyManager) != address(0), "Strategy manager not set");
        
        // Risk check if available
        if (address(riskManager) != address(0)) {
            uint256 totalAmount = 0;
            for (uint256 i = 0; i < amounts.length; i++) {
                totalAmount += amounts[i];
            }
            require(riskManager.isWithinRiskLimits(totalAmount), "Risk limits exceeded");
        }

        strategyManager.deployToStrategies(strategies, amounts);
    }

    function harvestFromStrategies(address[] calldata strategies) 
        external 
        onlyAgent 
        nonReentrant 
        returns (uint256 harvestedYield) 
    {
        require(address(strategyManager) != address(0), "Strategy manager not set");
        
        harvestedYield = strategyManager.harvestFromStrategies(strategies);

        if (harvestedYield > 0) {
            uint256 managementFee = _calculateManagementFee();
            uint256 performanceFee = (harvestedYield * performanceFeeRate) / 10000;
            uint256 totalFees = managementFee + performanceFee;

            if (totalFees > 0) {
                _asset.safeTransfer(agentAddress, totalFees);
                harvestedYield -= totalFees;
            }

            // Update state variable with the net harvested amount
            totalHarvestedAmount += harvestedYield;
            lastFeeCollection = block.timestamp;

            emit YieldHarvested(harvestedYield, managementFee, performanceFee);
        }

        return harvestedYield;
    }

    // ====================================================================
    // INTERNAL FUNCTIONS
    // ====================================================================

    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view returns (uint256) {
        uint256 supply = totalSupply();
        return (supply == 0) ? assets : Math.mulDiv(assets, supply, totalAssets(), rounding);
    }

    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view returns (uint256) {
        uint256 supply = totalSupply();
        return (supply == 0) ? shares : Math.mulDiv(shares, totalAssets(), supply, rounding);
    }

    function _calculateManagementFee() internal view returns (uint256) {
        uint256 timeElapsed = block.timestamp - lastFeeCollection;
        uint256 annualFee = (totalAssets() * managementFeeRate) / 10000;
        return (annualFee * timeElapsed) / 365 days;
    }

    // ====================================================================
    // COMPONENT MANAGEMENT
    // ====================================================================

    function setMultiAssetManager(address _multiAssetManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        multiAssetManager = IMultiAssetManager(_multiAssetManager);
        emit ComponentUpdated("MultiAssetManager", _multiAssetManager);
    }

    function setStrategyManager(address _strategyManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        strategyManager = IStrategyManager(_strategyManager);
        emit ComponentUpdated("StrategyManager", _strategyManager);
    }

    function setLotteryManager(address _lotteryManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        lotteryManager = ILotteryManager(_lotteryManager);
        emit ComponentUpdated("LotteryManager", _lotteryManager);
    }

    function setRiskManager(address _riskManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        riskManager = IRiskManager(_riskManager);
        emit ComponentUpdated("RiskManager", _riskManager);
    }

    // ====================================================================
    // ADMIN FUNCTIONS
    // ====================================================================

    function setFeeRates(uint256 _managementFeeRate, uint256 _performanceFeeRate) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(_managementFeeRate <= 500, "Management fee too high");
        require(_performanceFeeRate <= 2000, "Performance fee too high");

        managementFeeRate = _managementFeeRate;
        performanceFeeRate = _performanceFeeRate;
    }

    function toggleDeposits(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        depositsEnabled = enabled;
    }

    function toggleWithdrawals(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        withdrawalsEnabled = enabled;
    }

    function setEmergencyMode(bool enabled) external onlyRole(EMERGENCY_ROLE) {
        emergencyMode = enabled;
        if (enabled) {
            depositsEnabled = false;
            withdrawalsEnabled = false;
        }
        emit EmergencyModeToggled(enabled);
    }

    function setAgent(address newAgent) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newAgent != address(0), "Invalid agent");
        _revokeRole(AGENT_ROLE, agentAddress);
        _grantRole(AGENT_ROLE, newAgent);
        agentAddress = newAgent;
    }

    function emergencyWithdraw(address token, uint256 amount) external onlyRole(EMERGENCY_ROLE) {
        require(emergencyMode, "Not in emergency mode");
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    // ====================================================================
    // VIEW FUNCTIONS
    // ====================================================================

    function getBalance() external view returns (uint256) {
        return totalAssets();
    }

    function getTotalHarvested() external view returns (uint256) {
        return totalHarvestedAmount;
    }

    function getUserInfo(address user) external view returns (
        uint256 shares,
        uint256 assets,
        uint256 lastDeposit,
        bool withdrawalRequested,
        uint256 withdrawalAvailableAt
    ) {
        shares = userShares[user];
        assets = _convertToAssets(shares, Math.Rounding.Down);
        lastDeposit = lastDepositTime[user];
        withdrawalRequested = canWithdraw[user];
        withdrawalAvailableAt = withdrawalRequestTime[user] + withdrawalDelay;
    }

    function getVaultMetrics() external view returns (
        uint256 totalAssets_,
        uint256 totalShares,
        uint256 totalDeployed_,
        uint256 totalHarvested_,
        uint256 managementFee,
        uint256 performanceFee
    ) {
        return (
            totalAssets(),
            totalSupply(),
            totalDeployed,
            totalHarvestedAmount,
            managementFeeRate,
            performanceFeeRate
        );
    }
}