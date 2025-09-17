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
    function executeWithAsset(address asset, uint256 amount, bytes calldata data) external payable;
    function execute(uint256 amount, bytes calldata data) external;
    function harvest(bytes calldata data) external;
    function emergencyExit(bytes calldata data) external;
    function getBalance() external view returns (uint256);
    function underlyingToken() external view returns (address);
    function protocol() external view returns (address);
    function paused() external view returns (bool);
    function setPaused(bool pauseState) external;
}

interface IRiskManager {
    function checkRisk() external view returns (bool healthy, uint256 riskScore);
    function performRiskCheck() external;
    function isWithinRiskLimits(uint256 amount) external view returns (bool);
    function getRiskMetrics() external view returns (uint256 totalLeverage, uint256 avgHealthFactor, bool emergency);
}

interface IPriceOracle {
    function getPrice(address token) external view returns (uint256 price, uint8 decimals);
    function getNormalizedPrice(address token) external view returns (uint256);
}

interface IStrategyManager {
    function deployToStrategies(address[] calldata strategies, uint256[] calldata amounts, address asset) external;
    function harvestFromStrategies(address[] calldata strategies, address asset) external returns (uint256 totalHarvested);
    function getActiveStrategies() external view returns (address[] memory);
}

// Vault Extension Interface
interface IVaultExtension {
    enum RiskLevel { LOW, MEDIUM, HIGH }
    
    function recordDeposit(address user, address asset, uint256 amount, RiskLevel riskLevel) external;
    function recordWithdrawal(address user, address asset, uint256 amount) external returns (bool success);
    function addYield(address asset, uint256 amount) external;
    function claimEpochReward(address user, uint256 epochNumber) external returns (bool won, uint256 rewardAmount);
    function getUserEpochStatus(address user) external view returns (bool eligibleForCurrentEpoch, uint256 currentEpoch, uint256 timeRemaining, bool hasUnclaimedRewards, RiskLevel riskLevel);
    function updateUserRiskLevel(address user, RiskLevel newRiskLevel) external;
}

contract TrueMultiAssetVaultCore is ERC20, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Roles
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    bytes32 public constant PRICE_ORACLE_ROLE = keccak256("PRICE_ORACLE_ROLE");

    // Special address for native FLOW
    address public constant NATIVE_FLOW = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // Asset information structure
    struct AssetInfo {
        bool supported;
        uint256 totalBalance;
        uint256 vaultBalance;
        uint256 strategyBalance;
        uint256 minDeposit;
        uint256 maxDeposit;
        uint8 decimals;
        bool acceptingDeposits;
        uint256 totalHarvested;
        uint256 lastHarvestTime;
        bool isNative;
    }

    // User position structure
    struct UserPosition {
        mapping(address => uint256) assetBalances;
        uint256 totalShares;
        uint256 lastDepositTime;
        bool canWithdraw;
        uint256 withdrawalRequestTime;
        IVaultExtension.RiskLevel riskLevel;
        uint256 totalDeposited;
    }

    // Core contracts
    IStrategyManager public strategyManager;
    IPriceOracle public priceOracle;
    IRiskManager public riskManager;
    IVaultExtension public vaultExtension;
    address public agentAddress;

    // Asset management
    mapping(address => AssetInfo) public assetInfo;
    address[] public supportedAssets;
    mapping(address => bool) public isAssetSupported;

    // User management
    mapping(address => UserPosition) public userPositions;
    
    // Vault settings
    uint256 public withdrawalDelay = 1 days;
    uint256 public managementFeeRate = 200;
    uint256 public performanceFeeRate = 1000;
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

    IWFLOW public wflowContract;

    // Events
    event AssetDeposited(address indexed user, address indexed asset, uint256 amount, uint256 shares, IVaultExtension.RiskLevel riskLevel);
    event AssetWithdrawn(address indexed user, address indexed asset, uint256 amount, uint256 shares);
    event AssetAdded(address indexed asset, uint256 minDeposit, uint256 maxDeposit);
    event AssetDeployedToStrategy(address indexed asset, address indexed strategy, uint256 amount);
    event YieldHarvested(address indexed asset, uint256 amount);
    event WithdrawalRequested(address indexed user, uint256 availableAt);
    event EmergencyModeToggled(bool enabled);
    event NativeFlowDeposited(address indexed user, uint256 amount, uint256 shares, IVaultExtension.RiskLevel riskLevel);
    event NativeFlowWithdrawn(address indexed user, uint256 amount, uint256 shares);
    event NativeFlowDeployedToStrategy(address indexed strategy, uint256 amount);
    event RiskLevelUpdated(address indexed user, IVaultExtension.RiskLevel oldLevel, IVaultExtension.RiskLevel newLevel);

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
        _grantRole(PRICE_ORACLE_ROLE, _priceOracle);

        lastFeeCollection = block.timestamp;
        _initializeSupportedAssets();
    }

    // Modifiers
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

    modifier supportedAsset(address asset) {
        require(isAssetSupported[asset], "Asset not supported");
        _;
    }

    function _initializeSupportedAssets() internal {
        _addAssetInternal(NATIVE_FLOW, 1 * 10**18, 1000000 * 10**18, 18, true);
        _addAssetInternal(USDF, 1 * 10**6, 10000000 * 10**6, 6, false);
        _addAssetInternal(WFLOW, 1 * 10**18, 1000000 * 10**18, 18, false);
        _addAssetInternal(WETH, 1 * 10**15, 10000 * 10**18, 18, false);
        _addAssetInternal(STGUSD, 1 * 10**6, 10000000 * 10**6, 6, false);
        _addAssetInternal(USDT, 1 * 10**6, 10000000 * 10**6, 6, false);
        _addAssetInternal(USDC_E, 1 * 10**6, 10000000 * 10**6, 6, false);
        _addAssetInternal(STFLOW, 1 * 10**18, 1000000 * 10**18, 18, false);
        _addAssetInternal(ANKRFLOW, 1 * 10**18, 1000000 * 10**18, 18, false);
        _addAssetInternal(CBBTC, 1 * 10**6, 1000 * 10**8, 8, false);
    }

    function _addAssetInternal(address asset, uint256 minDeposit, uint256 maxDeposit, uint8 decimals, bool isNative) internal {
        assetInfo[asset] = AssetInfo({
            supported: true,
            totalBalance: 0,
            vaultBalance: 0,
            strategyBalance: 0,
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
            if (assetDecimals <= 18) {
                return (amount * price) / (10 ** (18 + assetDecimals - 18));
            } else {
                return (amount * price * (10 ** (assetDecimals - 18))) / (10 ** 18);
            }
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

    function _executeDeposit(
        address asset,
        uint256 amount,
        address receiver,
        IVaultExtension.RiskLevel riskLevel
    ) internal returns (uint256 shares) {
        require(amount > 0, "Amount must be greater than 0");
        require(assetInfo[asset].acceptingDeposits, "Asset not accepting deposits");
        require(amount >= assetInfo[asset].minDeposit, "Below minimum deposit");
        require(amount <= assetInfo[asset].maxDeposit, "Above maximum deposit");

        if (address(riskManager) != address(0)) {
            require(riskManager.isWithinRiskLimits(amount), "Risk limits exceeded");
        }

        if (asset == NATIVE_FLOW) {
            require(msg.value == amount, "Native FLOW amount mismatch");
        } else {
            require(msg.value == 0, "Unexpected native FLOW");
            IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        }

        shares = _calculateShares(asset, amount);

        UserPosition storage position = userPositions[receiver];
        
        if (position.totalShares == 0) {
            totalUsers++;
            position.riskLevel = riskLevel;
        }
        
        position.assetBalances[asset] += amount;
        position.totalShares += shares;
        position.lastDepositTime = block.timestamp;
        position.totalDeposited += amount;

        assetInfo[asset].totalBalance += amount;
        assetInfo[asset].vaultBalance += amount;
        totalPrincipal += amount;

        _mint(receiver, shares);

        // Record in extension if available
        if (address(vaultExtension) != address(0)) {
            try vaultExtension.recordDeposit(receiver, asset, amount, position.riskLevel) {} catch {}
        }

        totalValueLocked += _getAssetValueInUSD(asset, amount);
        emit AssetDeposited(receiver, asset, amount, shares, riskLevel);

        return shares;
    }

    // Public deposit functions
    function deposit(
        address asset,
        uint256 amount,
        address receiver,
        IVaultExtension.RiskLevel riskLevel
    ) external nonReentrant whenNotEmergency whenDepositsEnabled supportedAsset(asset) returns (uint256 shares) {
        require(asset != NATIVE_FLOW, "Use depositNativeFlow for native FLOW");
        return _executeDeposit(asset, amount, receiver, riskLevel);
    }

    function deposit(
        address asset,
        uint256 amount,
        address receiver
    ) external nonReentrant whenNotEmergency whenDepositsEnabled supportedAsset(asset) returns (uint256 shares) {
        require(asset != NATIVE_FLOW, "Use depositNativeFlow for native FLOW");
        return _executeDeposit(asset, amount, receiver, IVaultExtension.RiskLevel.MEDIUM);
    }

    function depositNativeFlow(
        address receiver,
        IVaultExtension.RiskLevel riskLevel
    ) external payable nonReentrant whenNotEmergency whenDepositsEnabled returns (uint256 shares) {
        require(isAssetSupported[NATIVE_FLOW], "Native FLOW not supported");
        require(msg.value > 0, "Amount must be greater than 0");
        
        shares = _executeDeposit(NATIVE_FLOW, msg.value, receiver, riskLevel);
        emit NativeFlowDeposited(receiver, msg.value, shares, riskLevel);
        return shares;
    }

    function depositNativeFlow(address receiver) external payable nonReentrant whenNotEmergency whenDepositsEnabled returns (uint256 shares) {
        require(isAssetSupported[NATIVE_FLOW], "Native FLOW not supported");
        require(msg.value > 0, "Amount must be greater than 0");
        
        shares = _executeDeposit(NATIVE_FLOW, msg.value, receiver, IVaultExtension.RiskLevel.MEDIUM);
        emit NativeFlowDeposited(receiver, msg.value, shares, IVaultExtension.RiskLevel.MEDIUM);
        return shares;
    }

    function updateRiskLevel(IVaultExtension.RiskLevel newRiskLevel) external {
        require(userPositions[msg.sender].totalShares > 0, "No position found");
        
        IVaultExtension.RiskLevel oldLevel = userPositions[msg.sender].riskLevel;
        userPositions[msg.sender].riskLevel = newRiskLevel;
        
        if (address(vaultExtension) != address(0)) {
            try vaultExtension.updateUserRiskLevel(msg.sender, newRiskLevel) {} catch {}
        }
        
        emit RiskLevelUpdated(msg.sender, oldLevel, newRiskLevel);
    }

    function requestWithdrawal() external {
        require(userPositions[msg.sender].totalShares > 0, "No shares to withdraw");
        
        userPositions[msg.sender].canWithdraw = true;
        userPositions[msg.sender].withdrawalRequestTime = block.timestamp;

        emit WithdrawalRequested(msg.sender, block.timestamp + withdrawalDelay);
    }

    function withdraw(
        address asset,
        uint256 amount,
        address receiver
    ) external nonReentrant whenWithdrawalsEnabled supportedAsset(asset) returns (uint256 shares) {
        require(userPositions[msg.sender].canWithdraw, "Withdrawal not requested");
        require(block.timestamp >= userPositions[msg.sender].withdrawalRequestTime + withdrawalDelay, "Withdrawal delay not met");
        require(amount > 0, "Amount must be greater than 0");

        UserPosition storage position = userPositions[msg.sender];
        require(position.assetBalances[asset] >= amount, "Insufficient asset balance");
        require(amount <= position.totalDeposited, "Cannot withdraw more than deposited");

        if (address(vaultExtension) != address(0)) {
            bool success = vaultExtension.recordWithdrawal(msg.sender, asset, amount);
            require(success, "Withdrawal rejected by extension");
        }

        shares = _calculateShares(asset, amount);
        require(position.totalShares >= shares, "Insufficient shares");
        require(assetInfo[asset].vaultBalance >= amount, "Insufficient vault balance");

        position.assetBalances[asset] -= amount;
        position.totalShares -= shares;
        position.totalDeposited -= amount;
        
        if (position.totalShares == 0) {
            position.canWithdraw = false;
            totalUsers--;
        }

        assetInfo[asset].totalBalance -= amount;
        assetInfo[asset].vaultBalance -= amount;
        totalPrincipal -= amount;

        _burn(msg.sender, shares);

        if (asset == NATIVE_FLOW) {
            payable(receiver).transfer(amount);
            emit NativeFlowWithdrawn(msg.sender, amount, shares);
        } else {
            IERC20(asset).safeTransfer(receiver, amount);
        }

        totalValueLocked -= _getAssetValueInUSD(asset, amount);
        emit AssetWithdrawn(msg.sender, asset, amount, shares);

        return shares;
    }

    function claimEpochReward(uint256 epochNumber) external nonReentrant returns (bool won, uint256 rewardAmount) {
        require(address(vaultExtension) != address(0), "Extension not set");
        
        (won, rewardAmount) = vaultExtension.claimEpochReward(msg.sender, epochNumber);
        
        if (won && rewardAmount > 0) {
            IERC20(USDF).safeTransfer(msg.sender, rewardAmount);
            totalYieldDistributed += rewardAmount;
        }
        
        return (won, rewardAmount);
    }

    // Strategy functions
    function deployToStrategies(
        address[] calldata strategies,
        uint256[] calldata amounts,
        address asset
    ) external onlyAgent nonReentrant supportedAsset(asset) {
        require(strategies.length == amounts.length, "Array length mismatch");
        require(strategies.length > 0, "No strategies provided");

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }

        require(assetInfo[asset].vaultBalance >= totalAmount, "Insufficient vault balance");

        if (asset == NATIVE_FLOW) {
            require(address(this).balance >= totalAmount, "Insufficient native FLOW balance");
            
            for (uint256 i = 0; i < strategies.length; i++) {
                if (amounts[i] > 0) {
                    IStrategyWithAssets(strategies[i]).executeWithAsset{value: amounts[i]}(
                        NATIVE_FLOW,
                        amounts[i],
                        ""
                    );
                    
                    emit AssetDeployedToStrategy(asset, strategies[i], amounts[i]);
                    emit NativeFlowDeployedToStrategy(strategies[i], amounts[i]);
                }
            }
        } else {
            if (address(strategyManager) != address(0)) {
                IERC20(asset).safeTransfer(address(strategyManager), totalAmount);
                strategyManager.deployToStrategies(strategies, amounts, asset);
            } else {
                for (uint256 i = 0; i < strategies.length; i++) {
                    if (amounts[i] > 0) {
                        IERC20(asset).safeTransfer(strategies[i], amounts[i]);
                        IStrategyWithAssets(strategies[i]).execute(amounts[i], "");
                        emit AssetDeployedToStrategy(asset, strategies[i], amounts[i]);
                    }
                }
            }
        }

        assetInfo[asset].vaultBalance -= totalAmount;
        assetInfo[asset].strategyBalance += totalAmount;
    }

    function harvestFromStrategies(
        address[] calldata strategies,
        address asset
    ) external onlyAgent nonReentrant supportedAsset(asset) returns (uint256 harvestedAmount) {
        
        uint256 balanceBefore;
        
        if (asset == NATIVE_FLOW) {
            balanceBefore = address(this).balance;
            
            for (uint256 i = 0; i < strategies.length; i++) {
                try IStrategyWithAssets(strategies[i]).harvest("") {} catch {}
            }
            
            harvestedAmount = address(this).balance - balanceBefore;
            
            if (harvestedAmount > 0) {
                assetInfo[asset].vaultBalance += harvestedAmount;
                assetInfo[asset].totalHarvested += harvestedAmount;
                assetInfo[asset].lastHarvestTime = block.timestamp;
            }
        } else {
            if (address(strategyManager) != address(0)) {
                harvestedAmount = strategyManager.harvestFromStrategies(strategies, asset);
            } else {
                balanceBefore = IERC20(asset).balanceOf(address(this));
                
                for (uint256 i = 0; i < strategies.length; i++) {
                    try IStrategyWithAssets(strategies[i]).harvest("") {} catch {}
                }
                
                harvestedAmount = IERC20(asset).balanceOf(address(this)) - balanceBefore;
            }

            if (harvestedAmount > 0) {
                uint256 managementFee = (assetInfo[asset].totalBalance * managementFeeRate * (block.timestamp - lastFeeCollection)) / (10000 * 365 days);
                uint256 performanceFee = (harvestedAmount * performanceFeeRate) / 10000;
                uint256 totalFees = managementFee + performanceFee;

                if (totalFees > 0 && totalFees < harvestedAmount) {
                    IERC20(asset).safeTransfer(agentAddress, totalFees);
                    harvestedAmount -= totalFees;
                }

                assetInfo[asset].vaultBalance += harvestedAmount;
                assetInfo[asset].totalHarvested += harvestedAmount;
                assetInfo[asset].lastHarvestTime = block.timestamp;
            }
        }

        if (harvestedAmount > 0) {
            totalYieldGenerated += harvestedAmount;
            
            if (address(vaultExtension) != address(0)) {
                try vaultExtension.addYield(asset, harvestedAmount) {} catch {}
            }
            
            emit YieldHarvested(asset, harvestedAmount);
        }

        lastFeeCollection = block.timestamp;
        return harvestedAmount;
    }

    // View functions
    function getUserPosition(address user) external view returns (
        uint256 totalShares,
        uint256 lastDeposit,
        bool withdrawalRequested,
        uint256 withdrawalAvailableAt,
        IVaultExtension.RiskLevel riskLevel,
        uint256 totalDeposited
    ) {
        UserPosition storage position = userPositions[user];
        return (
            position.totalShares,
            position.lastDepositTime,
            position.canWithdraw,
            position.withdrawalRequestTime + withdrawalDelay,
            position.riskLevel,
            position.totalDeposited
        );
    }

    function getAssetBalance(address asset) external view returns (uint256 vaultBalance, uint256 strategyBalance, uint256 totalBalance) {
        AssetInfo memory info = assetInfo[asset];
        return (info.vaultBalance, info.strategyBalance, info.totalBalance);
    }

    function getVaultMetrics() external view returns (
        uint256 totalValueLocked_,
        uint256 totalUsers_,
        uint256 totalSupply_,
        uint256 managementFee,
        uint256 performanceFee,
        uint256 assetsCount,
        uint256 totalPrincipal_,
        uint256 totalYieldGenerated_,
        uint256 totalYieldDistributed_
    ) {
        return (
            totalValueLocked,
            totalUsers,
            totalSupply(),
            managementFeeRate,
            performanceFeeRate,
            supportedAssets.length,
            totalPrincipal,
            totalYieldGenerated,
            totalYieldDistributed
        );
    }

    function getSupportedAssets() external view returns (address[] memory) {
        return supportedAssets;
    }

    // Admin functions
    function setVaultExtension(address _vaultExtension) external onlyRole(DEFAULT_ADMIN_ROLE) {
        vaultExtension = IVaultExtension(_vaultExtension);
    }

    function setStrategyManager(address _strategyManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        strategyManager = IStrategyManager(_strategyManager);
    }

    function setPriceOracle(address _priceOracle) external onlyRole(DEFAULT_ADMIN_ROLE) {
        priceOracle = IPriceOracle(_priceOracle);
    }

    function setRiskManager(address _riskManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        riskManager = IRiskManager(_riskManager);
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

    // Compatibility functions
    function getBalance() external view returns (uint256) {
        return totalValueLocked;
    }

    function asset() external pure returns (address) {
        return USDF;
    }

    function totalAssets() external view returns (uint256) {
        return totalValueLocked;
    }

    receive() external payable {
        assetInfo[NATIVE_FLOW].vaultBalance += msg.value;
        assetInfo[NATIVE_FLOW].totalBalance += msg.value;
    }

    fallback() external payable {}
}