// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

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

interface ILotteryManager {
    function addParticipant(address participant, uint256 weight) external;
    function getCurrentRound() external view returns (uint256 roundId, bool isActive, uint256 participants, uint256 prizePool);
}

contract TrueMultiAssetVault is ERC20, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Roles
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    bytes32 public constant PRICE_ORACLE_ROLE = keccak256("PRICE_ORACLE_ROLE");

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
    }

    // User position structure
    struct UserPosition {
        mapping(address => uint256) assetBalances;
        uint256 totalShares;
        uint256 lastDepositTime;
        bool canWithdraw;
        uint256 withdrawalRequestTime;
    }

    // Core contracts - DECLARED IN CORRECT ORDER
    IStrategyManager public strategyManager;
    ILotteryManager public lotteryManager;
    IPriceOracle public priceOracle;
    IRiskManager public riskManager;
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

    // Events
    event AssetDeposited(address indexed user, address indexed asset, uint256 amount, uint256 shares);
    event AssetWithdrawn(address indexed user, address indexed asset, uint256 amount, uint256 shares);
    event AssetAdded(address indexed asset, uint256 minDeposit, uint256 maxDeposit);
    event AssetDeployedToStrategy(address indexed asset, address indexed strategy, uint256 amount);
    event YieldHarvested(address indexed asset, uint256 amount);
    event WithdrawalRequested(address indexed user, uint256 availableAt);
    event EmergencyModeToggled(bool enabled);

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

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(AGENT_ROLE, _agentAddress);
        _grantRole(PRICE_ORACLE_ROLE, _priceOracle);

        lastFeeCollection = block.timestamp;

        _initializeSupportedAssets();
    }

    // Internal function to initialize supported assets
    function _initializeSupportedAssets() internal {
        _addAssetInternal(USDF, 1 * 10**6, 10000000 * 10**6, 6);
        _addAssetInternal(WFLOW, 1 * 10**18, 1000000 * 10**18, 18);
        _addAssetInternal(WETH, 1 * 10**15, 10000 * 10**18, 18);
        _addAssetInternal(STGUSD, 1 * 10**6, 10000000 * 10**6, 6);
        _addAssetInternal(USDT, 1 * 10**6, 10000000 * 10**6, 6);
        _addAssetInternal(USDC_E, 1 * 10**6, 10000000 * 10**6, 6);
        _addAssetInternal(STFLOW, 1 * 10**18, 1000000 * 10**18, 18);
        _addAssetInternal(ANKRFLOW, 1 * 10**18, 1000000 * 10**18, 18);
        _addAssetInternal(CBBTC, 1 * 10**6, 1000 * 10**8, 8);
    }

    // Internal function to add asset
    function _addAssetInternal(address asset, uint256 minDeposit, uint256 maxDeposit, uint8 decimals) internal {
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
            lastHarvestTime: block.timestamp
        });
        
        supportedAssets.push(asset);
        isAssetSupported[asset] = true;
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

    // Internal helper functions
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
        
        try priceOracle.getNormalizedPrice(asset) returns (uint256 price) {
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
        } else if (asset == WFLOW || asset == STFLOW || asset == ANKRFLOW) {
            return (amount * 1) / 10**12;
        } else if (asset == WETH) {
            return (amount * 2500) / 10**12;
        } else if (asset == CBBTC) {
            return (amount * 50000) / 10**2;
        }
        return amount;
    }

    function _calculateManagementFee(address asset) internal view returns (uint256) {
        uint256 timeElapsed = block.timestamp - lastFeeCollection;
        uint256 assetBalance = assetInfo[asset].totalBalance;
        uint256 annualFee = (assetBalance * managementFeeRate) / 10000;
        return (annualFee * timeElapsed) / 365 days;
    }

    // Core deposit function - internal implementation
    function _executeDeposit(
        address asset,
        uint256 amount,
        address receiver
    ) internal returns (uint256 shares) {
        require(amount > 0, "Amount must be greater than 0");
        require(assetInfo[asset].acceptingDeposits, "Asset not accepting deposits");
        require(amount >= assetInfo[asset].minDeposit, "Below minimum deposit");
        require(amount <= assetInfo[asset].maxDeposit, "Above maximum deposit");

        // Risk check if available - NOW RISKMANAGER IS PROPERLY DECLARED
        if (address(riskManager) != address(0)) {
            require(riskManager.isWithinRiskLimits(amount), "Risk limits exceeded");
        }

        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        shares = _calculateShares(asset, amount);

        UserPosition storage position = userPositions[receiver];
        if (position.totalShares == 0) {
            totalUsers++;
        }
        
        position.assetBalances[asset] += amount;
        position.totalShares += shares;
        position.lastDepositTime = block.timestamp;

        assetInfo[asset].totalBalance += amount;
        assetInfo[asset].vaultBalance += amount;

        _mint(receiver, shares);

        if (address(lotteryManager) != address(0)) {
            try lotteryManager.addParticipant(receiver, _getAssetValueInUSD(asset, amount)) {} catch {}
        }

        totalValueLocked += _getAssetValueInUSD(asset, amount);

        emit AssetDeposited(receiver, asset, amount, shares);

        return shares;
    }

    // Public deposit function
    function deposit(
        address asset,
        uint256 amount,
        address receiver
    ) external nonReentrant whenNotEmergency whenDepositsEnabled supportedAsset(asset) returns (uint256 shares) {
        return _executeDeposit(asset, amount, receiver);
    }

    // Multiple asset deposit function
    function depositMultiple(
        address[] calldata assets,
        uint256[] calldata amounts,
        address receiver
    ) external nonReentrant whenNotEmergency whenDepositsEnabled returns (uint256 totalShares) {
        require(assets.length == amounts.length, "Array length mismatch");
        require(assets.length > 0, "No assets provided");

        for (uint256 i = 0; i < assets.length; i++) {
            if (amounts[i] > 0 && isAssetSupported[assets[i]]) {
                totalShares += _executeDeposit(assets[i], amounts[i], receiver);
            }
        }

        return totalShares;
    }

    // Withdrawal request function
    function requestWithdrawal() external {
        require(userPositions[msg.sender].totalShares > 0, "No shares to withdraw");
        
        userPositions[msg.sender].canWithdraw = true;
        userPositions[msg.sender].withdrawalRequestTime = block.timestamp;

        emit WithdrawalRequested(msg.sender, block.timestamp + withdrawalDelay);
    }

    // Single asset withdrawal function
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

        shares = _calculateShares(asset, amount);
        require(position.totalShares >= shares, "Insufficient shares");
        require(assetInfo[asset].vaultBalance >= amount, "Insufficient vault balance");

        position.assetBalances[asset] -= amount;
        position.totalShares -= shares;
        
        if (position.totalShares == 0) {
            position.canWithdraw = false;
            totalUsers--;
        }

        assetInfo[asset].totalBalance -= amount;
        assetInfo[asset].vaultBalance -= amount;

        _burn(msg.sender, shares);
        IERC20(asset).safeTransfer(receiver, amount);

        totalValueLocked -= _getAssetValueInUSD(asset, amount);

        emit AssetWithdrawn(msg.sender, asset, amount, shares);

        return shares;
    }

    // Withdraw all assets function
    function withdrawAll(address receiver) external nonReentrant whenWithdrawalsEnabled {
        require(userPositions[msg.sender].canWithdraw, "Withdrawal not requested");
        require(block.timestamp >= userPositions[msg.sender].withdrawalRequestTime + withdrawalDelay, "Withdrawal delay not met");

        UserPosition storage position = userPositions[msg.sender];
        require(position.totalShares > 0, "No shares to withdraw");

        uint256 totalShares = position.totalShares;

        for (uint256 i = 0; i < supportedAssets.length; i++) {
            address asset = supportedAssets[i];
            uint256 assetBalance = position.assetBalances[asset];
            
            if (assetBalance > 0 && assetInfo[asset].vaultBalance >= assetBalance) {
                position.assetBalances[asset] = 0;
                assetInfo[asset].totalBalance -= assetBalance;
                assetInfo[asset].vaultBalance -= assetBalance;
                
                IERC20(asset).safeTransfer(receiver, assetBalance);
                totalValueLocked -= _getAssetValueInUSD(asset, assetBalance);
                
                emit AssetWithdrawn(msg.sender, asset, assetBalance, 0);
            }
        }

        position.totalShares = 0;
        position.canWithdraw = false;
        totalUsers--;

        _burn(msg.sender, totalShares);
    }

    // Strategy management functions
    function deployToStrategies(
        address[] calldata strategies,
        uint256[] calldata amounts,
        address asset
    ) external onlyAgent nonReentrant supportedAsset(asset) {
        require(address(strategyManager) != address(0), "Strategy manager not set");
        require(strategies.length == amounts.length, "Array length mismatch");

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }

        require(assetInfo[asset].vaultBalance >= totalAmount, "Insufficient vault balance");

        IERC20(asset).safeTransfer(address(strategyManager), totalAmount);

        strategyManager.deployToStrategies(strategies, amounts, asset);

        assetInfo[asset].vaultBalance -= totalAmount;
        assetInfo[asset].strategyBalance += totalAmount;

        emit AssetDeployedToStrategy(asset, address(0), totalAmount);
    }

    function harvestFromStrategies(
        address[] calldata strategies,
        address asset
    ) external onlyAgent nonReentrant supportedAsset(asset) returns (uint256 harvestedAmount) {
        require(address(strategyManager) != address(0), "Strategy manager not set");

        harvestedAmount = strategyManager.harvestFromStrategies(strategies, asset);

        if (harvestedAmount > 0) {
            uint256 managementFee = _calculateManagementFee(asset);
            uint256 performanceFee = (harvestedAmount * performanceFeeRate) / 10000;
            uint256 totalFees = managementFee + performanceFee;

            if (totalFees > 0 && totalFees < harvestedAmount) {
                IERC20(asset).safeTransfer(agentAddress, totalFees);
                harvestedAmount -= totalFees;
            }

            assetInfo[asset].vaultBalance += harvestedAmount;
            assetInfo[asset].totalHarvested += harvestedAmount;
            assetInfo[asset].lastHarvestTime = block.timestamp;

            emit YieldHarvested(asset, harvestedAmount);
        }

        lastFeeCollection = block.timestamp;
        return harvestedAmount;
    }

    // Admin functions
    function addSupportedAsset(
        address asset,
        uint256 minDeposit,
        uint256 maxDeposit,
        uint8 decimals
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(asset != address(0), "Invalid asset");
        require(!isAssetSupported[asset], "Asset already supported");

        _addAssetInternal(asset, minDeposit, maxDeposit, decimals);
        emit AssetAdded(asset, minDeposit, maxDeposit);
    }

    function updateAssetConfig(
        address asset,
        uint256 minDeposit,
        uint256 maxDeposit,
        bool acceptingDeposits
    ) external onlyRole(DEFAULT_ADMIN_ROLE) supportedAsset(asset) {
        assetInfo[asset].minDeposit = minDeposit;
        assetInfo[asset].maxDeposit = maxDeposit;
        assetInfo[asset].acceptingDeposits = acceptingDeposits;
    }

    function setStrategyManager(address _strategyManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        strategyManager = IStrategyManager(_strategyManager);
    }

    function setLotteryManager(address _lotteryManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        lotteryManager = ILotteryManager(_lotteryManager);
    }

    function setPriceOracle(address _priceOracle) external onlyRole(DEFAULT_ADMIN_ROLE) {
        priceOracle = IPriceOracle(_priceOracle);
    }

    function setRiskManager(address _riskManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        riskManager = IRiskManager(_riskManager);
    }

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

    function emergencyWithdrawAsset(address asset, uint256 amount) external onlyRole(EMERGENCY_ROLE) {
        require(emergencyMode, "Not in emergency mode");
        IERC20(asset).safeTransfer(msg.sender, amount);
    }

    // View functions
    function getAssetBalance(address asset) external view returns (uint256 vaultBalance, uint256 strategyBalance, uint256 totalBalance) {
        AssetInfo memory info = assetInfo[asset];
        return (info.vaultBalance, info.strategyBalance, info.totalBalance);
    }

    function getUserAssetBalance(address user, address asset) external view returns (uint256) {
        return userPositions[user].assetBalances[asset];
    }

    function getUserTotalShares(address user) external view returns (uint256) {
        return userPositions[user].totalShares;
    }

    function getUserPosition(address user) external view returns (
        uint256 totalShares,
        uint256 lastDeposit,
        bool withdrawalRequested,
        uint256 withdrawalAvailableAt
    ) {
        UserPosition storage position = userPositions[user];
        return (
            position.totalShares,
            position.lastDepositTime,
            position.canWithdraw,
            position.withdrawalRequestTime + withdrawalDelay
        );
    }

    function getUserAssetBalances(address user) external view returns (
        address[] memory assets,
        uint256[] memory balances,
        uint256[] memory values
    ) {
        assets = new address[](supportedAssets.length);
        balances = new uint256[](supportedAssets.length);
        values = new uint256[](supportedAssets.length);

        for (uint256 i = 0; i < supportedAssets.length; i++) {
            address asset = supportedAssets[i];
            assets[i] = asset;
            balances[i] = userPositions[user].assetBalances[asset];
            values[i] = _getAssetValueInUSD(asset, balances[i]);
        }
    }

    function getVaultMetrics() external view returns (
        uint256 totalValueLocked_,
        uint256 totalUsers_,
        uint256 totalSupply_,
        uint256 managementFee,
        uint256 performanceFee,
        uint256 assetsCount
    ) {
        return (
            totalValueLocked,
            totalUsers,
            totalSupply(),
            managementFeeRate,
            performanceFeeRate,
            supportedAssets.length
        );
    }

    function getAllAssetInfo() external view returns (
        address[] memory assets,
        uint256[] memory vaultBalances,
        uint256[] memory strategyBalances,
        uint256[] memory totalBalances,
        bool[] memory acceptingDeposits
    ) {
        uint256 length = supportedAssets.length;
        assets = new address[](length);
        vaultBalances = new uint256[](length);
        strategyBalances = new uint256[](length);
        totalBalances = new uint256[](length);
        acceptingDeposits = new bool[](length);

        for (uint256 i = 0; i < length; i++) {
            address asset = supportedAssets[i];
            AssetInfo memory info = assetInfo[asset];
            
            assets[i] = asset;
            vaultBalances[i] = info.vaultBalance;
            strategyBalances[i] = info.strategyBalance;
            totalBalances[i] = info.totalBalance;
            acceptingDeposits[i] = info.acceptingDeposits;
        }
    }

    function getSupportedAssets() external view returns (address[] memory) {
        return supportedAssets;
    }

    function getTotalValueInUSD() external view returns (uint256 totalValue) {
        for (uint256 i = 0; i < supportedAssets.length; i++) {
            address asset = supportedAssets[i];
            totalValue += _getAssetValueInUSD(asset, assetInfo[asset].totalBalance);
        }
        return totalValue;
    }

    // Compatibility functions
    function getBalance() external view returns (uint256) {
        return this.getTotalValueInUSD();
    }

    function asset() external pure returns (address) {
        return USDF;
    }

    function totalAssets() external view returns (uint256) {
        return this.getTotalValueInUSD();
    }
}