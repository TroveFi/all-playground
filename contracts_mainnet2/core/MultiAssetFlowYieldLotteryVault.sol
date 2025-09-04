// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title ICadenceArchVRF - Interface for Flow's Cadence Arch VRF precompile
interface ICadenceArchVRF {
    function revertibleRandom() external view returns (uint256 randomValue);
}

/// @title MultiAssetFlowYieldLotteryVault - Multi-Asset Vault with Yield Lottery
/// @notice Accepts multiple assets (USDC, USDT, WFLOW, WETH) and converts to base asset for yield generation
/// @dev Integrates with Flow VRF for winner selection and various DeFi protocols on Flow EVM
contract MultiAssetFlowYieldLotteryVault is ERC20, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ====================================================================
    // ROLES & CONSTANTS
    // ====================================================================
    
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");
    bytes32 public constant STRATEGY_ROLE = keccak256("STRATEGY_ROLE");
    bytes32 public constant LOTTERY_MANAGER_ROLE = keccak256("LOTTERY_MANAGER_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    
    // Flow's Cadence Arch VRF precompile address
    address public constant CADENCE_ARCH_VRF = 0x0000000000000000000000010000000000000001;

    // Supported asset addresses on Flow EVM
    address public constant USDC = 0xF1815bd50389c46847f0Bda824eC8da914045D14;
    address public constant USDT = 0x674843C06FF83502ddb4D37c2E09C01cdA38cbc8;
    address public constant WFLOW = 0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e;
    address public constant WETH = 0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590;

    // PunchSwap Router for asset conversion
    address public constant PUNCH_SWAP_ROUTER = 0xf45AFe28fd5519d5f8C1d4787a4D5f724C0eFa4d;

    // ====================================================================
    // STRUCTS & ENUMS
    // ====================================================================
    
    struct LotteryRound {
        uint256 roundId;
        uint256 startTime;
        uint256 endTime;
        uint256 totalYieldGenerated;
        uint256 totalParticipants;
        uint256 winnersCount;
        address[] winners;
        uint256 prizePerWinner;
        bool isActive;
        bool isFinalized;
        uint256 vrfRandomness;
        bytes32 vrfSeed;
    }

    struct UserInfo {
        uint256 totalDeposited; // In base asset terms
        uint256 shares;
        uint256 lastDepositTime;
        uint256[] participatingRounds;
        uint256 totalPrizesWon;
        bool canWithdraw;
        uint256 withdrawalRequestTime;
        mapping(address => uint256) assetDeposits; // Track original asset deposits
    }

    struct AssetInfo {
        bool supported;
        uint256 minDeposit;
        uint256 maxDeposit;
        uint256 conversionSlippage; // Slippage tolerance for conversion to base asset
        bool requiresSwap; // Whether this asset needs to be swapped to base asset
    }

    struct StrategyInfo {
        address strategyAddress;
        string name;
        uint256 allocation; // Percentage in basis points (10000 = 100%)
        uint256 currentBalance;
        bool active;
    }

    // ====================================================================
    // STATE VARIABLES
    // ====================================================================
    
    IERC20 public immutable baseAsset; // Base asset for yield generation (USDC)
    ICadenceArchVRF public immutable cadenceVRF;
    
    address public agentAddress;
    
    // Supported assets
    mapping(address => AssetInfo) public supportedAssets;
    address[] public assetList;
    
    // Lottery system
    mapping(uint256 => LotteryRound) public lotteryRounds;
    mapping(address => UserInfo) public userInfo;
    mapping(uint256 => mapping(address => bool)) public roundParticipants;
    uint256 public currentRoundId;
    uint256 public totalYieldGenerated;
    
    // Strategy management
    mapping(address => StrategyInfo) public strategies;
    address[] public activeStrategies;
    
    // Yield and lottery settings
    uint256 public lotteryDuration = 30 days;
    uint256 public minWinnersCount = 1;
    uint256 public maxWinnersCount = 10;
    uint256 public withdrawalDelay = 1 days;
    
    // Vault settings
    bool public depositsEnabled = true;
    bool public withdrawalsEnabled = true;
    bool public emergencyMode = false;
    
    // Fee structure
    uint256 public managementFeeRate = 200; // 2% annual management fee
    uint256 public performanceFeeRate = 1000; // 10% performance fee
    uint256 public lastFeeCollection;

    // Asset conversion
    uint256 public defaultSlippage = 300; // 3% default slippage
    bool public autoConvertToBase = true; // Automatically convert deposits to base asset

    // ====================================================================
    // EVENTS
    // ====================================================================
    
    event LotteryRoundStarted(uint256 indexed roundId, uint256 startTime, uint256 endTime);
    event LotteryRoundFinalized(uint256 indexed roundId, address[] winners, uint256 prizePerWinner);
    event UserDeposited(address indexed user, address asset, uint256 assetAmount, uint256 baseAmount, uint256 shares);
    event UserWithdrawalRequested(address indexed user, uint256 amount, uint256 availableAt);
    event UserWithdrawalExecuted(address indexed user, address asset, uint256 amount);
    event StrategyAdded(address indexed strategy, string name, uint256 allocation);
    event AssetAdded(address indexed asset, uint256 minDeposit, uint256 maxDeposit);
    event AssetConverted(address indexed fromAsset, address indexed toAsset, uint256 fromAmount, uint256 toAmount);
    event YieldHarvested(uint256 totalYield, uint256 managementFees, uint256 performanceFees);
    event PrizeClaimed(address indexed winner, uint256 roundId, uint256 amount);

    // ====================================================================
    // CONSTRUCTOR
    // ====================================================================
    
    constructor(
        string memory name,
        string memory symbol,
        address _agentAddress
    ) ERC20(name, symbol) {
        require(_agentAddress != address(0), "Invalid agent");

        baseAsset = IERC20(USDC); // USDC as base asset
        agentAddress = _agentAddress;
        cadenceVRF = ICadenceArchVRF(CADENCE_ARCH_VRF);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(AGENT_ROLE, _agentAddress);
        _grantRole(LOTTERY_MANAGER_ROLE, msg.sender);

        lastFeeCollection = block.timestamp;

        // Initialize supported assets
        _initializeSupportedAssets();

        // Start the first lottery round
        _startNewLotteryRound();
    }

    function _initializeSupportedAssets() internal {
        // USDC (base asset - no swap needed)
        supportedAssets[USDC] = AssetInfo({
            supported: true,
            minDeposit: 1 * 10**6, // 1 USDC
            maxDeposit: 1000000 * 10**6, // 1M USDC
            conversionSlippage: 0, // No conversion needed
            requiresSwap: false
        });
        assetList.push(USDC);

        // USDT (stable - minimal slippage)
        supportedAssets[USDT] = AssetInfo({
            supported: true,
            minDeposit: 1 * 10**6, // 1 USDT
            maxDeposit: 1000000 * 10**6, // 1M USDT
            conversionSlippage: 100, // 1% slippage
            requiresSwap: true
        });
        assetList.push(USDT);

        // WFLOW (volatile - higher slippage)
        supportedAssets[WFLOW] = AssetInfo({
            supported: true,
            minDeposit: 1 * 10**18, // 1 FLOW
            maxDeposit: 100000 * 10**18, // 100K FLOW
            conversionSlippage: 500, // 5% slippage
            requiresSwap: true
        });
        assetList.push(WFLOW);

        // WETH (volatile - higher slippage)
        supportedAssets[WETH] = AssetInfo({
            supported: true,
            minDeposit: 1 * 10**15, // 0.001 ETH
            maxDeposit: 1000 * 10**18, // 1000 ETH
            conversionSlippage: 500, // 5% slippage
            requiresSwap: true
        });
        assetList.push(WETH);
    }

    // ====================================================================
    // MODIFIERS
    // ====================================================================
    
    modifier onlyAgent() {
        require(hasRole(AGENT_ROLE, msg.sender), "Only agent can call");
        _;
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

    modifier supportedAsset(address asset) {
        require(supportedAssets[asset].supported, "Asset not supported");
        _;
    }

    // ====================================================================
    // MULTI-ASSET DEPOSIT FUNCTIONS
    // ====================================================================

    /// @notice Deposit any supported asset
    /// @param asset Address of the asset to deposit
    /// @param amount Amount of the asset to deposit
    /// @param receiver Address to receive vault shares
    /// @return shares Amount of shares minted
    function depositAsset(
        address asset,
        uint256 amount,
        address receiver
    ) public nonReentrant whenNotEmergency whenDepositsEnabled supportedAsset(asset) returns (uint256 shares) {
        AssetInfo memory assetInfo = supportedAssets[asset];
        require(amount >= assetInfo.minDeposit, "Below minimum deposit");
        require(amount <= assetInfo.maxDeposit, "Above maximum deposit");

        // Transfer asset from user
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        uint256 baseAssetAmount;
        
        if (assetInfo.requiresSwap && autoConvertToBase) {
            // Convert to base asset
            baseAssetAmount = _convertToBaseAsset(asset, amount, assetInfo.conversionSlippage);
        } else {
            // Asset is base asset or conversion disabled
            baseAssetAmount = amount;
        }

        // Calculate shares based on base asset amount
        shares = _convertToShares(baseAssetAmount);
        _mint(receiver, shares);
        
        // Update user info
        UserInfo storage user = userInfo[receiver];
        user.totalDeposited += baseAssetAmount;
        user.shares += shares;
        user.lastDepositTime = block.timestamp;
        user.assetDeposits[asset] += amount;
        
        // Add to current lottery round if active
        if (lotteryRounds[currentRoundId].isActive && !roundParticipants[currentRoundId][receiver]) {
            roundParticipants[currentRoundId][receiver] = true;
            user.participatingRounds.push(currentRoundId);
            lotteryRounds[currentRoundId].totalParticipants++;
        }
        
        emit UserDeposited(receiver, asset, amount, baseAssetAmount, shares);
        return shares;
    }

    /// @notice Deposit USDC (base asset) - simplified function
    /// @param amount Amount of USDC to deposit
    /// @param receiver Address to receive vault shares
    /// @return shares Amount of shares minted
    function depositUSDC(uint256 amount, address receiver) external returns (uint256 shares) {
        return depositAsset(USDC, amount, receiver);
    }

    /// @notice Deposit WFLOW
    /// @param amount Amount of WFLOW to deposit
    /// @param receiver Address to receive vault shares
    /// @return shares Amount of shares minted
    function depositWFLOW(uint256 amount, address receiver) external returns (uint256 shares) {
        return depositAsset(WFLOW, amount, receiver);
    }

    /// @notice Deposit WETH
    /// @param amount Amount of WETH to deposit
    /// @param receiver Address to receive vault shares
    /// @return shares Amount of shares minted
    function depositWETH(uint256 amount, address receiver) external returns (uint256 shares) {
        return depositAsset(WETH, amount, receiver);
    }

    /// @notice Deposit native ETH (converts to WETH first)
    /// @param receiver Address to receive vault shares
    /// @return shares Amount of shares minted
    function depositETH(address receiver) external payable returns (uint256 shares) {
        require(msg.value > 0, "Must send ETH");
        require(msg.value >= supportedAssets[WETH].minDeposit, "Below minimum deposit");
        require(msg.value <= supportedAssets[WETH].maxDeposit, "Above maximum deposit");

        // Convert ETH to WETH (simplified - in production would use WETH contract)
        uint256 baseAssetAmount = _convertToBaseAsset(address(0), msg.value, supportedAssets[WETH].conversionSlippage);
        
        shares = _convertToShares(baseAssetAmount);
        _mint(receiver, shares);
        
        // Update user info
        UserInfo storage user = userInfo[receiver];
        user.totalDeposited += baseAssetAmount;
        user.shares += shares;
        user.lastDepositTime = block.timestamp;
        user.assetDeposits[WETH] += msg.value; // Track as WETH equivalent
        
        // Add to current lottery round if active
        if (lotteryRounds[currentRoundId].isActive && !roundParticipants[currentRoundId][receiver]) {
            roundParticipants[currentRoundId][receiver] = true;
            user.participatingRounds.push(currentRoundId);
            lotteryRounds[currentRoundId].totalParticipants++;
        }
        
        emit UserDeposited(receiver, address(0), msg.value, baseAssetAmount, shares);
        return shares;
    }

    // ====================================================================
    // ASSET CONVERSION FUNCTIONS
    // ====================================================================

    function _convertToBaseAsset(
        address fromAsset,
        uint256 amount,
        uint256 maxSlippage
    ) internal returns (uint256 baseAssetAmount) {
        if (fromAsset == address(baseAsset)) {
            return amount; // Already base asset
        }

        if (fromAsset == address(0)) {
            // Handle ETH to USDC conversion
            return _swapETHForUSDC(amount, maxSlippage);
        }

        // Use PunchSwap to convert asset to base asset
        return _swapTokenForUSDC(fromAsset, amount, maxSlippage);
    }

    function _swapTokenForUSDC(
        address fromToken,
        uint256 amountIn,
        uint256 maxSlippage
    ) internal returns (uint256 amountOut) {
        require(fromToken != address(0), "Invalid from token");

        // Approve PunchSwap router
        IERC20(fromToken).approve(PUNCH_SWAP_ROUTER, amountIn);

        // Create swap path
        address[] memory path = new address[](2);
        path[0] = fromToken;
        path[1] = address(baseAsset);

        // Calculate minimum amount out with slippage protection
        uint256[] memory amountsOut = IPunchSwapRouter(PUNCH_SWAP_ROUTER).getAmountsOut(amountIn, path);
        uint256 minAmountOut = (amountsOut[1] * (10000 - maxSlippage)) / 10000;

        try IPunchSwapRouter(PUNCH_SWAP_ROUTER).swapExactTokensForTokens(
            amountIn,
            minAmountOut,
            path,
            address(this),
            block.timestamp + 300 // 5 minutes deadline
        ) returns (uint256[] memory amounts) {
            amountOut = amounts[1];
            emit AssetConverted(fromToken, address(baseAsset), amountIn, amountOut);
        } catch {
            // Swap failed - return 0 or revert based on strategy
            revert("Asset conversion failed");
        }
    }

    function _swapETHForUSDC(uint256 ethAmount, uint256 maxSlippage) internal returns (uint256 usdcAmount) {
        // Create swap path: ETH -> WETH -> USDC
        address[] memory path = new address[](2);
        path[0] = WFLOW; // Use WFLOW as ETH equivalent on Flow
        path[1] = address(baseAsset);

        // Get quote
        uint256[] memory amountsOut = IPunchSwapRouter(PUNCH_SWAP_ROUTER).getAmountsOut(ethAmount, path);
        uint256 minAmountOut = (amountsOut[1] * (10000 - maxSlippage)) / 10000;

        try IPunchSwapRouter(PUNCH_SWAP_ROUTER).swapExactETHForTokens{value: ethAmount}(
            minAmountOut,
            path,
            address(this),
            block.timestamp + 300
        ) returns (uint256[] memory amounts) {
            usdcAmount = amounts[1];
            emit AssetConverted(address(0), address(baseAsset), ethAmount, usdcAmount);
        } catch {
            revert("ETH to USDC conversion failed");
        }
    }

    // ====================================================================
    // WITHDRAWAL FUNCTIONS
    // ====================================================================

    /// @notice Request withdrawal in a specific asset
    /// @param amount Amount in base asset terms to withdraw
    /// @param preferredAsset Asset to receive (if available)
    function requestWithdrawal(uint256 amount, address preferredAsset) 
        external 
        nonReentrant 
        whenWithdrawalsEnabled 
        supportedAsset(preferredAsset) 
    {
        require(amount > 0, "Invalid amount");
        require(balanceOf(msg.sender) >= _convertToShares(amount), "Insufficient balance");
        
        UserInfo storage user = userInfo[msg.sender];
        user.canWithdraw = true;
        user.withdrawalRequestTime = block.timestamp;
        
        emit UserWithdrawalRequested(msg.sender, amount, block.timestamp + withdrawalDelay);
    }

    /// @notice Execute withdrawal in requested asset
    /// @param amount Amount to withdraw (in base asset terms)
    /// @param asset Asset to receive
    function withdraw(uint256 amount, address asset, address receiver) 
        external 
        nonReentrant 
        whenWithdrawalsEnabled 
        supportedAsset(asset) 
        returns (uint256 assetAmount) 
    {
        require(userInfo[msg.sender].canWithdraw, "Withdrawal not requested");
        require(
            block.timestamp >= userInfo[msg.sender].withdrawalRequestTime + withdrawalDelay,
            "Withdrawal delay not met"
        );
        
        uint256 shares = _convertToShares(amount);
        _burn(msg.sender, shares);
        
        // Convert base asset to requested asset if needed
        if (asset == address(baseAsset)) {
            assetAmount = amount;
            baseAsset.safeTransfer(receiver, amount);
        } else {
            assetAmount = _convertFromBaseAsset(asset, amount);
            IERC20(asset).safeTransfer(receiver, assetAmount);
        }
        
        // Update user info
        UserInfo storage user = userInfo[msg.sender];
        user.shares -= shares;
        user.canWithdraw = false;
        
        emit UserWithdrawalExecuted(msg.sender, asset, assetAmount);
        return assetAmount;
    }

    function _convertFromBaseAsset(address toAsset, uint256 baseAmount) internal returns (uint256 assetAmount) {
        if (toAsset == address(baseAsset)) {
            return baseAmount;
        }

        // Swap base asset to target asset
        address[] memory path = new address[](2);
        path[0] = address(baseAsset);
        path[1] = toAsset;

        baseAsset.approve(PUNCH_SWAP_ROUTER, baseAmount);

        AssetInfo memory assetInfo = supportedAssets[toAsset];
        uint256[] memory amountsOut = IPunchSwapRouter(PUNCH_SWAP_ROUTER).getAmountsOut(baseAmount, path);
        uint256 minAmountOut = (amountsOut[1] * (10000 - assetInfo.conversionSlippage)) / 10000;

        try IPunchSwapRouter(PUNCH_SWAP_ROUTER).swapExactTokensForTokens(
            baseAmount,
            minAmountOut,
            path,
            address(this),
            block.timestamp + 300
        ) returns (uint256[] memory amounts) {
            assetAmount = amounts[1];
        } catch {
            // If swap fails, return base asset instead
            assetAmount = baseAmount;
            // Note: This would need additional logic to handle the asset mismatch
        }
    }

    // ====================================================================
    // LOTTERY FUNCTIONS (same as before but adapted for multi-asset)
    // ====================================================================

    function _startNewLotteryRound() internal {
        currentRoundId++;
        
        lotteryRounds[currentRoundId] = LotteryRound({
            roundId: currentRoundId,
            startTime: block.timestamp,
            endTime: block.timestamp + lotteryDuration,
            totalYieldGenerated: 0,
            totalParticipants: 0,
            winnersCount: 0,
            winners: new address[](0),
            prizePerWinner: 0,
            isActive: true,
            isFinalized: false,
            vrfRandomness: 0,
            vrfSeed: bytes32(0)
        });
        
        emit LotteryRoundStarted(currentRoundId, block.timestamp, block.timestamp + lotteryDuration);
    }

    // ====================================================================
    // VIEW FUNCTIONS
    // ====================================================================

    function totalAssets() public view returns (uint256) {
        uint256 assetsInStrategies = 0;
        for (uint i = 0; i < activeStrategies.length; i++) {
            assetsInStrategies += strategies[activeStrategies[i]].currentBalance;
        }
        return baseAsset.balanceOf(address(this)) + assetsInStrategies;
    }

    function _convertToShares(uint256 assets) internal view returns (uint256) {
        uint256 supply = totalSupply();
        return (supply == 0) ? assets : Math.mulDiv(assets, supply, totalAssets(), Math.Rounding.Down);
    }

    function getSupportedAssets() external view returns (address[] memory) {
        return assetList;
    }

    function getUserAssetDeposits(address user, address asset) external view returns (uint256) {
        return userInfo[user].assetDeposits[asset];
    }

    function estimateDepositReturn(address asset, uint256 amount) external view returns (uint256 baseAssetAmount, uint256 shares) {
        if (asset == address(baseAsset)) {
            baseAssetAmount = amount;
        } else {
            // Estimate conversion (simplified)
            baseAssetAmount = (amount * 95) / 100; // Assume 5% conversion cost
        }
        shares = _convertToShares(baseAssetAmount);
    }

    // ====================================================================
    // ADMIN FUNCTIONS
    // ====================================================================

    function addSupportedAsset(
        address asset,
        uint256 minDeposit,
        uint256 maxDeposit,
        uint256 conversionSlippage,
        bool requiresSwap
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(asset != address(0), "Invalid asset");
        require(!supportedAssets[asset].supported, "Asset already supported");

        supportedAssets[asset] = AssetInfo({
            supported: true,
            minDeposit: minDeposit,
            maxDeposit: maxDeposit,
            conversionSlippage: conversionSlippage,
            requiresSwap: requiresSwap
        });

        assetList.push(asset);
        emit AssetAdded(asset, minDeposit, maxDeposit);
    }

    function setAutoConvertToBase(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        autoConvertToBase = enabled;
    }

    function setDefaultSlippage(uint256 slippage) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(slippage <= 1000, "Slippage too high"); // Max 10%
        defaultSlippage = slippage;
    }

    function emergencyConvertAllToBase() external onlyRole(EMERGENCY_ROLE) {
        for (uint256 i = 0; i < assetList.length; i++) {
            address asset = assetList[i];
            if (asset != address(baseAsset)) {
                uint256 balance = IERC20(asset).balanceOf(address(this));
                if (balance > 0) {
                    _convertToBaseAsset(asset, balance, supportedAssets[asset].conversionSlippage);
                }
            }
        }
    }

    // Receive function to accept ETH
    receive() external payable {
        // Auto-deposit ETH for the sender (convert to shares)
        require(msg.value > 0, "Must send ETH");
        require(msg.value >= supportedAssets[WETH].minDeposit, "Below minimum deposit");
        
        this.depositETH(msg.sender);
    }
}

// ====================================================================
// INTERFACES
// ====================================================================

interface IPunchSwapRouter {
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);
}