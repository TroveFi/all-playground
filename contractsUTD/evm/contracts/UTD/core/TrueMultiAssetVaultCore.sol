// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

// WFLOW interface
interface IWFLOW {
    function withdraw(uint256 amount) external;
    function deposit() external payable;
}

// Strategy interface
interface IStrategyWithAssets {
    function executeWithAsset(address asset, uint256 amount, bytes calldata data) external payable returns (uint256);
    function harvest(bytes calldata data) external returns (uint256);
    function emergencyExit(bytes calldata data) external returns (uint256);
    function getBalance() external view returns (uint256);
    function underlyingToken() external view returns (address);
}

interface IRiskManager {
    function checkRisk() external view returns (bool healthy, uint256 riskScore);
    function isWithinRiskLimits(uint256 amount) external view returns (bool);
}

interface IPriceOracle {
    function getNormalizedPrice(address token) external view returns (uint256);
}

interface IStrategyManager {
    function executeStrategy(address strategy, address asset, uint256 amount, bytes calldata data) external payable returns (uint256);
    function harvestStrategy(address strategy, bytes calldata data) external returns (uint256);
    function getActiveStrategies() external view returns (address[] memory);
}

interface IVaultExtension {
    enum RiskLevel { CONSERVATIVE, NORMAL, AGGRESSIVE }
    
    function recordDeposit(address user, address asset, uint256 amount, RiskLevel riskLevel) external;
    function recordWithdrawal(address user, address asset, uint256 amount) external returns (bool success);
    function addYield(address asset, uint256 amount) external;
    function processEpochRewards() external;
    function getUserEpochStatus(address user) external view returns (
        bool eligibleForCurrentEpoch,
        uint256 currentEpoch,
        uint256 timeRemaining,
        bool hasUnclaimedRewards,
        RiskLevel riskLevel
    );
}

contract TrueMultiAssetVaultCore is ERC20, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ====================================================================
    // ROLES
    // ====================================================================
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    bytes32 public constant STRATEGY_MANAGER_ROLE = keccak256("STRATEGY_MANAGER_ROLE");

    // ====================================================================
    // CONSTANTS
    // ====================================================================
    address public constant NATIVE_FLOW = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    
    // Flow EVM Token Addresses
    address public constant USDF = 0x2aaBea2058b5aC2D339b163C6Ab6f2b6d53aabED;
    address public constant WFLOW = 0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e;
    address public constant WETH = 0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590;
    address public constant STGUSD = 0xF1815bd50389c46847f0Bda824eC8da914045D14;
    address public constant USDT = 0x674843C06FF83502ddb4D37c2E09C01cdA38cbc8;
    address public constant USDC_E = 0x7f27352D5F83Db87a5A3E00f4B07Cc2138D8ee52;
    address public constant STFLOW = 0x5598c0652B899EB40f169Dd5949BdBE0BF36ffDe;
    address public constant ANKRFLOW = 0x1b97100eA1D7126C4d60027e231EA4CB25314bdb;
    address public constant CBBTC = 0xA0197b2044D28b08Be34d98b23c9312158Ea9A18;

    // ====================================================================
    // STRUCTS
    // ====================================================================
    struct AssetInfo {
        bool supported;
        uint256 totalBalance;
        uint256 vaultBalance;
        uint256 strategyBalance;
        uint256 cadenceBalance;  // Balance on Cadence side
        uint256 minDeposit;
        uint256 maxDeposit;
        uint8 decimals;
        bool acceptingDeposits;
        uint256 totalHarvested;
        uint256 lastHarvestTime;
        bool isNative;
    }

    struct UserPosition {
        mapping(address => uint256) assetBalances;
        uint256 totalShares;
        uint256 totalDeposited;
        uint256 lastDepositTime;
        uint256 withdrawalRequestTime;
        uint256 requestedWithdrawalAmount;
        bool hasWithdrawalRequest;
        bool yieldEligible;  // For subsidized accounts
        IVaultExtension.RiskLevel riskLevel;
    }

    struct WithdrawalRequest {
        address user;
        address asset;
        uint256 amount;
        uint256 requestTime;
        bool processed;
    }

    // ====================================================================
    // STATE VARIABLES
    // ====================================================================
    IStrategyManager public strategyManager;
    IPriceOracle public priceOracle;
    IRiskManager public riskManager;
    IVaultExtension public vaultExtension;
    address public agentAddress;
    IWFLOW public wflowContract;

    // Asset management
    mapping(address => AssetInfo) public assetInfo;
    address[] public supportedAssets;
    mapping(address => bool) public isAssetSupported;

    // User management
    mapping(address => UserPosition) private userPositions;
    
    // Withdrawal queue
    WithdrawalRequest[] public withdrawalQueue;
    mapping(address => uint256[]) public userWithdrawalRequests;
    uint256 public nextWithdrawalToProcess;
    
    // Strategy whitelist
    mapping(address => bool) public whitelistedStrategies;
    address[] public strategies;
    
    // Vault settings
    uint256 public withdrawalDelay = 0; // Immediate for principal
    uint256 public managementFeeRate = 200; // 2%
    uint256 public performanceFeeRate = 1000; // 10%
    uint256 public lastFeeCollection;

    // Control flags
    bool public depositsEnabled = true;
    bool public withdrawalsEnabled = true;
    bool public emergencyMode = false;

    // Tracking
    uint256 public totalValueLocked;
    uint256 public totalUsers;
    uint256 public totalPrincipal;
    uint256 public totalYieldGenerated;
    uint256 public totalYieldDistributed;

    // Bridge tracking
    uint256 public totalBridgedToCadence;
    uint256 public totalBridgedFromCadence;

    // ====================================================================
    // EVENTS
    // ====================================================================
    event AssetDeposited(address indexed user, address indexed asset, uint256 amount, uint256 shares, IVaultExtension.RiskLevel riskLevel);
    event AssetWithdrawn(address indexed user, address indexed asset, uint256 amount, uint256 shares);
    event WithdrawalRequested(address indexed user, address indexed asset, uint256 amount, uint256 requestId);
    event WithdrawalProcessed(address indexed user, uint256 requestId, uint256 amount);
    event AssetDeployedToStrategy(address indexed strategy, address indexed asset, uint256 amount);
    event YieldHarvested(address indexed asset, uint256 amount, uint256 fees);
    event StrategyWhitelisted(address indexed strategy, bool status);
    event EmergencyModeToggled(bool enabled);
    event BridgedToCadence(address indexed asset, uint256 amount);
    event BridgedFromCadence(address indexed asset, uint256 amount);
    event YieldEligibilityChanged(address indexed user, bool eligible);

    // ====================================================================
    // CONSTRUCTOR
    // ====================================================================
    constructor(
        string memory name,
        string memory symbol,
        address _agentAddress,
        address _priceOracle
    ) ERC20(name, symbol) {
        require(_agentAddress != address(0), "Invalid agent");
        require(_priceOracle != address(0), "Invalid price oracle");

        agentAddress = _agentAddress;
        priceOracle = IPriceOracle(_priceOracle);
        wflowContract = IWFLOW(WFLOW);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(AGENT_ROLE, _agentAddress);
        _grantRole(EMERGENCY_ROLE, msg.sender);

        lastFeeCollection = block.timestamp;
        _initializeSupportedAssets();
    }

    // ====================================================================
    // MODIFIERS
    // ====================================================================
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
        require(hasRole(AGENT_ROLE, msg.sender), "Only agent");
        _;
    }

    modifier supportedAsset(address asset) {
        require(isAssetSupported[asset], "Asset not supported");
        _;
    }

    // ====================================================================
    // INITIALIZATION
    // ====================================================================
    function _initializeSupportedAssets() internal {
        _addAssetInternal(NATIVE_FLOW, 0.1 * 10**18, 1000000 * 10**18, 18, true);
        _addAssetInternal(WFLOW, 0.1 * 10**18, 1000000 * 10**18, 18, false);
        _addAssetInternal(USDF, 1 * 10**6, 10000000 * 10**6, 6, false);
        _addAssetInternal(WETH, 0.001 * 10**18, 10000 * 10**18, 18, false);
        _addAssetInternal(STGUSD, 1 * 10**6, 10000000 * 10**6, 6, false);
        _addAssetInternal(USDT, 1 * 10**6, 10000000 * 10**6, 6, false);
        _addAssetInternal(USDC_E, 1 * 10**6, 10000000 * 10**6, 6, false);
        _addAssetInternal(STFLOW, 0.1 * 10**18, 1000000 * 10**18, 18, false);
        _addAssetInternal(ANKRFLOW, 0.1 * 10**18, 1000000 * 10**18, 18, false);
        _addAssetInternal(CBBTC, 0.0001 * 10**8, 1000 * 10**8, 8, false);
    }

    function _addAssetInternal(
        address asset,
        uint256 minDeposit,
        uint256 maxDeposit,
        uint8 decimals,
        bool isNative
    ) internal {
        assetInfo[asset] = AssetInfo({
            supported: true,
            totalBalance: 0,
            vaultBalance: 0,
            strategyBalance: 0,
            cadenceBalance: 0,
            minDeposit: minDeposit,
            maxDeposit: maxDeposit,
            decimals: decimals,
            acceptingDeposits: true,
            totalHarvested: 0,
            lastHarvestTime: block.timestamp,
            isNative: isNative
        });
        
        supportedAssets.push(asset);
        isAssetSupported[asset] = true;
    }

    // ====================================================================
    // DEPOSIT FUNCTIONS
    // ====================================================================
    function deposit(
        address asset,
        uint256 amount,
        address receiver,
        IVaultExtension.RiskLevel riskLevel
    ) external nonReentrant whenNotEmergency whenDepositsEnabled supportedAsset(asset) returns (uint256 shares) {
        require(asset != NATIVE_FLOW, "Use depositNativeFlow");
        return _executeDeposit(asset, amount, receiver, riskLevel);
    }

    function deposit(
        address asset,
        uint256 amount,
        address receiver
    ) external nonReentrant whenNotEmergency whenDepositsEnabled supportedAsset(asset) returns (uint256 shares) {
        require(asset != NATIVE_FLOW, "Use depositNativeFlow");
        return _executeDeposit(asset, amount, receiver, IVaultExtension.RiskLevel.NORMAL);
    }

    function depositNativeFlow(
        address receiver,
        IVaultExtension.RiskLevel riskLevel
    ) external payable nonReentrant whenNotEmergency whenDepositsEnabled returns (uint256 shares) {
        require(isAssetSupported[NATIVE_FLOW], "Native FLOW not supported");
        require(msg.value > 0, "Amount must be > 0");
        
        shares = _executeDeposit(NATIVE_FLOW, msg.value, receiver, riskLevel);
        emit AssetDeposited(receiver, NATIVE_FLOW, msg.value, shares, riskLevel);
        return shares;
    }

    function depositNativeFlow(address receiver) 
        external 
        payable 
        nonReentrant 
        whenNotEmergency 
        whenDepositsEnabled 
        returns (uint256 shares) 
    {
        require(isAssetSupported[NATIVE_FLOW], "Native FLOW not supported");
        require(msg.value > 0, "Amount must be > 0");
        
        shares = _executeDeposit(NATIVE_FLOW, msg.value, receiver, IVaultExtension.RiskLevel.NORMAL);
        emit AssetDeposited(receiver, NATIVE_FLOW, msg.value, shares, IVaultExtension.RiskLevel.NORMAL);
        return shares;
    }

    function _executeDeposit(
        address asset,
        uint256 amount,
        address receiver,
        IVaultExtension.RiskLevel riskLevel
    ) internal returns (uint256 shares) {
        require(amount > 0, "Amount must be > 0");
        require(assetInfo[asset].acceptingDeposits, "Asset not accepting deposits");
        require(amount >= assetInfo[asset].minDeposit, "Below minimum");
        require(amount <= assetInfo[asset].maxDeposit, "Above maximum");

        if (address(riskManager) != address(0)) {
            require(riskManager.isWithinRiskLimits(amount), "Risk limits exceeded");
        }

        // Transfer tokens (already received native FLOW in calling function)
        if (asset != NATIVE_FLOW) {
            require(msg.value == 0, "Unexpected native FLOW");
            IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        }

        shares = _calculateShares(asset, amount);

        UserPosition storage position = userPositions[receiver];
        
        if (position.totalShares == 0) {
            totalUsers++;
            position.riskLevel = riskLevel;
            position.yieldEligible = true; // Default to eligible
        }
        
        position.assetBalances[asset] += amount;
        position.totalShares += shares;
        position.lastDepositTime = block.timestamp;
        position.totalDeposited += amount;

        assetInfo[asset].totalBalance += amount;
        assetInfo[asset].vaultBalance += amount;
        totalPrincipal += amount;

        _mint(receiver, shares);

        // Record in extension
        if (address(vaultExtension) != address(0)) {
            try vaultExtension.recordDeposit(receiver, asset, amount, position.riskLevel) {} catch {}
        }

        totalValueLocked += _getAssetValueInUSD(asset, amount);
        emit AssetDeposited(receiver, asset, amount, shares, riskLevel);

        return shares;
    }

    // ====================================================================
    // WITHDRAWAL FUNCTIONS
    // ====================================================================
    function requestWithdrawal(address asset, uint256 amount) external nonReentrant supportedAsset(asset) {
        UserPosition storage position = userPositions[msg.sender];
        require(position.assetBalances[asset] >= amount, "Insufficient balance");
        require(amount > 0, "Amount must be > 0");

        // Create withdrawal request
        uint256 requestId = withdrawalQueue.length;
        withdrawalQueue.push(WithdrawalRequest({
            user: msg.sender,
            asset: asset,
            amount: amount,
            requestTime: block.timestamp,
            processed: false
        }));

        userWithdrawalRequests[msg.sender].push(requestId);
        
        position.hasWithdrawalRequest = true;
        position.requestedWithdrawalAmount += amount;

        emit WithdrawalRequested(msg.sender, asset, amount, requestId);
    }

    function processWithdrawalRequest(uint256 requestId) 
        external 
        nonReentrant 
        whenWithdrawalsEnabled 
        returns (bool) 
    {
        require(requestId < withdrawalQueue.length, "Invalid request");
        WithdrawalRequest storage request = withdrawalQueue[requestId];
        require(!request.processed, "Already processed");
        require(request.user == msg.sender, "Not your request");

        return _processWithdrawal(requestId);
    }

    function _processWithdrawal(uint256 requestId) internal returns (bool) {
        WithdrawalRequest storage request = withdrawalQueue[requestId];
        UserPosition storage position = userPositions[request.user];

        require(position.assetBalances[request.asset] >= request.amount, "Insufficient balance");
        require(assetInfo[request.asset].vaultBalance >= request.amount, "Insufficient vault balance");

        // Record withdrawal in extension
        if (address(vaultExtension) != address(0)) {
            bool success = vaultExtension.recordWithdrawal(request.user, request.asset, request.amount);
            require(success, "Extension rejected");
        }

        uint256 shares = _calculateShares(request.asset, request.amount);
        require(position.totalShares >= shares, "Insufficient shares");

        // Update state
        position.assetBalances[request.asset] -= request.amount;
        position.totalShares -= shares;
        position.totalDeposited -= request.amount;
        position.requestedWithdrawalAmount -= request.amount;
        
        if (position.totalShares == 0) {
            totalUsers--;
            position.hasWithdrawalRequest = false;
        }

        assetInfo[request.asset].totalBalance -= request.amount;
        assetInfo[request.asset].vaultBalance -= request.amount;
        totalPrincipal -= request.amount;

        _burn(request.user, shares);

        // Transfer assets
        if (request.asset == NATIVE_FLOW) {
            payable(request.user).transfer(request.amount);
        } else {
            IERC20(request.asset).safeTransfer(request.user, request.amount);
        }

        request.processed = true;
        totalValueLocked -= _getAssetValueInUSD(request.asset, request.amount);

        emit WithdrawalProcessed(request.user, requestId, request.amount);
        emit AssetWithdrawn(request.user, request.asset, request.amount, shares);

        return true;
    }

    // ====================================================================
    // STRATEGY EXECUTION (AGENT ONLY)
    // ====================================================================
    function executeStrategy(
        address strategy,
        address asset,
        uint256 amount,
        bytes calldata data
    ) external onlyAgent nonReentrant whenNotEmergency supportedAsset(asset) returns (uint256) {
        require(whitelistedStrategies[strategy], "Strategy not whitelisted");
        require(assetInfo[asset].vaultBalance >= amount, "Insufficient vault balance");

        uint256 result;
        
        if (asset == NATIVE_FLOW) {
            require(address(this).balance >= amount, "Insufficient native balance");
            result = IStrategyWithAssets(strategy).executeWithAsset{value: amount}(asset, amount, data);
        } else {
            IERC20(asset).safeTransfer(strategy, amount);
            result = IStrategyWithAssets(strategy).executeWithAsset(asset, amount, data);
        }

        assetInfo[asset].vaultBalance -= amount;
        assetInfo[asset].strategyBalance += amount;

        emit AssetDeployedToStrategy(strategy, asset, amount);
        return result;
    }

    function harvestStrategy(address strategy, bytes calldata data) 
        external 
        onlyAgent 
        nonReentrant 
        returns (uint256) 
    {
        require(whitelistedStrategies[strategy], "Strategy not whitelisted");
        
        address underlyingAsset = IStrategyWithAssets(strategy).underlyingToken();
        uint256 balanceBefore;
        
        if (underlyingAsset == NATIVE_FLOW) {
            balanceBefore = address(this).balance;
        } else {
            balanceBefore = IERC20(underlyingAsset).balanceOf(address(this));
        }

        uint256 harvested = IStrategyWithAssets(strategy).harvest(data);
        
        uint256 balanceAfter;
        if (underlyingAsset == NATIVE_FLOW) {
            balanceAfter = address(this).balance;
        } else {
            balanceAfter = IERC20(underlyingAsset).balanceOf(address(this));
        }

        uint256 actualHarvested = balanceAfter - balanceBefore;
        
        // Calculate fees
        uint256 managementFee = (assetInfo[underlyingAsset].totalBalance * managementFeeRate * 
            (block.timestamp - lastFeeCollection)) / (10000 * 365 days);
        uint256 performanceFee = (actualHarvested * performanceFeeRate) / 10000;
        uint256 totalFees = managementFee + performanceFee;

        if (totalFees > 0 && totalFees < actualHarvested) {
            if (underlyingAsset == NATIVE_FLOW) {
                payable(agentAddress).transfer(totalFees);
            } else {
                IERC20(underlyingAsset).safeTransfer(agentAddress, totalFees);
            }
            actualHarvested -= totalFees;
        }

        assetInfo[underlyingAsset].vaultBalance += actualHarvested;
        assetInfo[underlyingAsset].totalHarvested += actualHarvested;
        assetInfo[underlyingAsset].lastHarvestTime = block.timestamp;
        totalYieldGenerated += actualHarvested;

        // Add to extension yield pool
        if (address(vaultExtension) != address(0) && actualHarvested > 0) {
            try vaultExtension.addYield(underlyingAsset, actualHarvested) {} catch {}
        }

        lastFeeCollection = block.timestamp;
        emit YieldHarvested(underlyingAsset, actualHarvested, totalFees);

        return actualHarvested;
    }

    // ====================================================================
    // BRIDGE FUNCTIONS
    // ====================================================================
    function bridgeToCadence(address asset, uint256 amount) 
        external 
        onlyAgent 
        nonReentrant 
        supportedAsset(asset) 
    {
        require(asset == NATIVE_FLOW || asset == WFLOW, "Only FLOW/WFLOW bridgeable");
        require(assetInfo[asset].vaultBalance >= amount, "Insufficient balance");

        if (asset == WFLOW) {
            // Convert WFLOW to native FLOW for bridging
            IERC20(WFLOW).safeApprove(WFLOW, amount);
            wflowContract.withdraw(amount);
        }

        // Native FLOW is now ready for Cadence COA to withdraw
        assetInfo[NATIVE_FLOW].vaultBalance -= amount;
        assetInfo[NATIVE_FLOW].cadenceBalance += amount;
        totalBridgedToCadence += amount;

        emit BridgedToCadence(asset, amount);
    }

    function recordBridgeFromCadence(address asset, uint256 amount) 
        external 
        onlyAgent 
        supportedAsset(asset) 
    {
        require(asset == NATIVE_FLOW || asset == WFLOW, "Only FLOW/WFLOW bridgeable");

        assetInfo[NATIVE_FLOW].cadenceBalance -= amount;
        assetInfo[NATIVE_FLOW].vaultBalance += amount;
        totalBridgedFromCadence += amount;

        emit BridgedFromCadence(asset, amount);
    }

    // ====================================================================
    // PRICING & SHARES
    // ====================================================================
    function _calculateShares(address asset, uint256 amount) internal view returns (uint256) {
        uint256 assetValueUSD = _getAssetValueInUSD(asset, amount);
        uint256 supply = totalSupply();
        
        if (supply == 0) {
            return assetValueUSD;
        }
        
        return Math.mulDiv(assetValueUSD, supply, totalValueLocked);
    }

    function _getAssetValueInUSD(address asset, uint256 amount) internal view returns (uint256) {
        if (address(priceOracle) == address(0)) {
            return _fallbackPricing(asset, amount);
        }
        
        try priceOracle.getNormalizedPrice(asset == NATIVE_FLOW ? WFLOW : asset) returns (uint256 price) {
            uint8 assetDecimals = assetInfo[asset].decimals;
            return (amount * price) / (10 ** assetDecimals);
        } catch {
            return _fallbackPricing(asset, amount);
        }
    }

    function _fallbackPricing(address asset, uint256 amount) internal pure returns (uint256) {
        if (asset == USDF || asset == STGUSD || asset == USDT || asset == USDC_E) {
            return amount;
        } else if (asset == WFLOW || asset == STFLOW || asset == ANKRFLOW || asset == NATIVE_FLOW) {
            return (amount * 1) / 10**12;
        } else if (asset == WETH) {
            return (amount * 2500) / 10**12;
        } else if (asset == CBBTC) {
            return (amount * 50000) / 10**2;
        }
        return amount;
    }

    // ====================================================================
    // ADMIN FUNCTIONS
    // ====================================================================
    function whitelistStrategy(address strategy, bool status) external onlyRole(DEFAULT_ADMIN_ROLE) {
        whitelistedStrategies[strategy] = status;
        
        if (status) {
            bool exists = false;
            for (uint256 i = 0; i < strategies.length; i++) {
                if (strategies[i] == strategy) {
                    exists = true;
                    break;
                }
            }
            if (!exists) {
                strategies.push(strategy);
            }
        }
        
        emit StrategyWhitelisted(strategy, status);
    }

    function setYieldEligibility(address user, bool eligible) external onlyRole(DEFAULT_ADMIN_ROLE) {
        userPositions[user].yieldEligible = eligible;
        emit YieldEligibilityChanged(user, eligible);
    }

    function setVaultExtension(address _extension) external onlyRole(DEFAULT_ADMIN_ROLE) {
        vaultExtension = IVaultExtension(_extension);
    }

    function setStrategyManager(address _manager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        strategyManager = IStrategyManager(_manager);
    }

    function setPriceOracle(address _oracle) external onlyRole(DEFAULT_ADMIN_ROLE) {
        priceOracle = IPriceOracle(_oracle);
    }

    function setRiskManager(address _manager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        riskManager = IRiskManager(_manager);
    }

    function setEmergencyMode(bool enabled) external onlyRole(EMERGENCY_ROLE) {
        emergencyMode = enabled;
        if (enabled) {
            depositsEnabled = false;
        }
        emit EmergencyModeToggled(enabled);
    }

    function toggleDeposits(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        depositsEnabled = enabled;
    }

    function toggleWithdrawals(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        withdrawalsEnabled = enabled;
    }

    // ====================================================================
    // VIEW FUNCTIONS
    // ====================================================================
    function getUserPosition(address user) external view returns (
        uint256 totalShares,
        uint256 totalDeposited,
        uint256 lastDeposit,
        bool hasWithdrawalRequest,
        uint256 requestedAmount,
        bool yieldEligible,
        IVaultExtension.RiskLevel riskLevel
    ) {
        UserPosition storage position = userPositions[user];
        return (
            position.totalShares,
            position.totalDeposited,
            position.lastDepositTime,
            position.hasWithdrawalRequest,
            position.requestedWithdrawalAmount,
            position.yieldEligible,
            position.riskLevel
        );
    }

    function getUserAssetBalance(address user, address asset) external view returns (uint256) {
        return userPositions[user].assetBalances[asset];
    }

    function getAssetBalance(address asset) external view returns (
        uint256 vaultBalance,
        uint256 strategyBalance,
        uint256 cadenceBalance,
        uint256 totalBalance
    ) {
        AssetInfo memory info = assetInfo[asset];
        return (info.vaultBalance, info.strategyBalance, info.cadenceBalance, info.totalBalance);
    }

    function getVaultMetrics() external view returns (
        uint256 totalValueLocked_,
        uint256 totalUsers_,
        uint256 totalSupply_,
        uint256 totalPrincipal_,
        uint256 totalYieldGenerated_,
        uint256 totalYieldDistributed_,
        uint256 totalBridgedToCadence_,
        uint256 totalBridgedFromCadence_
    ) {
        return (
            totalValueLocked,
            totalUsers,
            totalSupply(),
            totalPrincipal,
            totalYieldGenerated,
            totalYieldDistributed,
            totalBridgedToCadence,
            totalBridgedFromCadence
        );
    }

    function getSupportedAssets() external view returns (address[] memory) {
        return supportedAssets;
    }

    function getWhitelistedStrategies() external view returns (address[] memory) {
        return strategies;
    }

    function getUserWithdrawalRequests(address user) external view returns (uint256[] memory) {
        return userWithdrawalRequests[user];
    }

    function getWithdrawalRequest(uint256 requestId) external view returns (
        address user,
        address asset,
        uint256 amount,
        uint256 requestTime,
        bool processed
    ) {
        require(requestId < withdrawalQueue.length, "Invalid request");
        WithdrawalRequest memory request = withdrawalQueue[requestId];
        return (request.user, request.asset, request.amount, request.requestTime, request.processed);
    }

    // ====================================================================
    // EMERGENCY FUNCTIONS
    // ====================================================================
    function emergencyWithdraw(address asset, uint256 amount) 
        external 
        onlyRole(EMERGENCY_ROLE) 
        nonReentrant 
    {
        require(emergencyMode, "Not in emergency mode");
        
        if (asset == NATIVE_FLOW) {
            payable(msg.sender).transfer(amount);
        } else {
            IERC20(asset).safeTransfer(msg.sender, amount);
        }
    }

    // ====================================================================
    // RECEIVE FUNCTIONS
    // ====================================================================
    receive() external payable {
        assetInfo[NATIVE_FLOW].vaultBalance += msg.value;
        assetInfo[NATIVE_FLOW].totalBalance += msg.value;
    }

    fallback() external payable {}
}