// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @title ICadenceArchVRF - Interface for Flow's Cadence Arch VRF precompile
interface ICadenceArchVRF {
    function revertibleRandom() external view returns (uint256 randomValue);
}

/// @title FlowYieldLotteryVault - ERC4626 Vault with Yield Lottery System
/// @notice Vault that generates yield through DeFi strategies and distributes it via VRF-based lottery
/// @dev Integrates with Flow VRF for winner selection and various DeFi protocols on Flow EVM
contract FlowYieldLotteryVault is ERC20, AccessControl, ReentrancyGuard, IERC4626 {
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
        uint256 totalDeposited;
        uint256 shares;
        uint256 lastDepositTime;
        uint256[] participatingRounds;
        uint256 totalPrizesWon;
        bool canWithdraw;
        uint256 withdrawalRequestTime;
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
    
    IERC20 private immutable _asset;
    ICadenceArchVRF public immutable cadenceVRF;
    
    address public agentAddress;
    
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
    uint256 public lotteryDuration = 30 days; // Default 30 days
    uint256 public minWinnersCount = 1;
    uint256 public maxWinnersCount = 10;
    uint256 public minDepositAmount = 1 * 10**6; // 1 USDC minimum
    uint256 public withdrawalDelay = 1 days; // 24 hours withdrawal delay
    
    // Vault settings
    bool public depositsEnabled = true;
    bool public withdrawalsEnabled = true;
    bool public emergencyMode = false;
    
    // Fee structure
    uint256 public managementFeeRate = 200; // 2% annual management fee
    uint256 public performanceFeeRate = 1000; // 10% performance fee
    uint256 public lastFeeCollection;

    // ====================================================================
    // EVENTS
    // ====================================================================
    
    event LotteryRoundStarted(uint256 indexed roundId, uint256 startTime, uint256 endTime);
    event LotteryRoundFinalized(uint256 indexed roundId, address[] winners, uint256 prizePerWinner);
    event UserDeposited(address indexed user, uint256 assets, uint256 shares);
    event UserWithdrawalRequested(address indexed user, uint256 amount, uint256 availableAt);
    event UserWithdrawalExecuted(address indexed user, uint256 amount);
    event StrategyAdded(address indexed strategy, string name, uint256 allocation);
    event StrategyUpdated(address indexed strategy, uint256 newAllocation);
    event YieldHarvested(uint256 totalYield, uint256 managementFees, uint256 performanceFees);
    event PrizeClaimed(address indexed winner, uint256 roundId, uint256 amount);
    event EmergencyModeToggled(bool enabled);

    // ====================================================================
    // CONSTRUCTOR
    // ====================================================================
    
    constructor(
        IERC20 assetToken,
        string memory name,
        string memory symbol,
        address _agentAddress
    ) ERC20(name, symbol) {
        require(address(assetToken) != address(0), "Invalid asset");
        require(_agentAddress != address(0), "Invalid agent");

        _asset = assetToken;
        agentAddress = _agentAddress;
        cadenceVRF = ICadenceArchVRF(CADENCE_ARCH_VRF);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(AGENT_ROLE, _agentAddress);
        _grantRole(LOTTERY_MANAGER_ROLE, msg.sender);

        lastFeeCollection = block.timestamp;

        // Start the first lottery round
        _startNewLotteryRound();
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

    // ====================================================================
    // ERC4626 IMPLEMENTATION
    // ====================================================================

    function asset() public view virtual override returns (address) {
        return address(_asset);
    }

    function totalAssets() public view virtual override returns (uint256) {
        uint256 assetsInStrategies = 0;
        for (uint i = 0; i < activeStrategies.length; i++) {
            assetsInStrategies += strategies[activeStrategies[i]].currentBalance;
        }
        return _asset.balanceOf(address(this)) + assetsInStrategies;
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
        require(assets >= minDepositAmount, "Below minimum deposit");
        
        shares = previewDeposit(assets);
        _deposit(assets, shares, receiver);
        
        // Update user info and add to current lottery round
        UserInfo storage user = userInfo[receiver];
        user.totalDeposited += assets;
        user.shares += shares;
        user.lastDepositTime = block.timestamp;
        
        // Add to current lottery round if active
        if (lotteryRounds[currentRoundId].isActive && !roundParticipants[currentRoundId][receiver]) {
            roundParticipants[currentRoundId][receiver] = true;
            user.participatingRounds.push(currentRoundId);
            lotteryRounds[currentRoundId].totalParticipants++;
        }
        
        emit UserDeposited(receiver, assets, shares);
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
        require(assets >= minDepositAmount, "Below minimum deposit");
        
        _deposit(assets, shares, receiver);
        
        // Update user info
        UserInfo storage user = userInfo[receiver];
        user.totalDeposited += assets;
        user.shares += shares;
        user.lastDepositTime = block.timestamp;
        
        return assets;
    }

    function maxWithdraw(address owner) public view virtual override returns (uint256) {
        if (!withdrawalsEnabled || emergencyMode || !userInfo[owner].canWithdraw) return 0;
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
        require(userInfo[owner].canWithdraw, "Withdrawal not allowed");
        require(
            block.timestamp >= userInfo[owner].withdrawalRequestTime + withdrawalDelay,
            "Withdrawal delay not met"
        );
        
        shares = previewWithdraw(assets);
        _withdraw(assets, shares, receiver, owner);
        
        // Update user info
        UserInfo storage user = userInfo[owner];
        user.shares -= shares;
        user.canWithdraw = false;
        
        emit UserWithdrawalExecuted(owner, assets);
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
        _withdraw(assets, shares, receiver, owner);
        return assets;
    }

    // ====================================================================
    // WITHDRAWAL REQUEST SYSTEM
    // ====================================================================
    
    /// @notice Request withdrawal - users must request before withdrawing
    /// @param amount Amount to withdraw
    function requestWithdrawal(uint256 amount) external nonReentrant whenWithdrawalsEnabled {
        require(amount > 0, "Invalid amount");
        require(balanceOf(msg.sender) >= _convertToShares(amount, Math.Rounding.Up), "Insufficient balance");
        
        UserInfo storage user = userInfo[msg.sender];
        user.canWithdraw = true;
        user.withdrawalRequestTime = block.timestamp;
        
        emit UserWithdrawalRequested(msg.sender, amount, block.timestamp + withdrawalDelay);
    }

    // ====================================================================
    // LOTTERY SYSTEM
    // ====================================================================
    
    /// @notice Start a new lottery round
    function startNewLotteryRound() external onlyRole(LOTTERY_MANAGER_ROLE) {
        require(!lotteryRounds[currentRoundId].isActive || block.timestamp >= lotteryRounds[currentRoundId].endTime, 
                "Current round still active");
        
        if (currentRoundId > 0) {
            _finalizeLotteryRound(currentRoundId, 1); // Default to 1 winner if not specified
        }
        
        _startNewLotteryRound();
    }

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

    /// @notice Finalize lottery round and select winners
    /// @param roundId Round ID to finalize
    /// @param winnersCount Number of winners to select
    function finalizeLotteryRound(uint256 roundId, uint256 winnersCount) 
        external 
        onlyRole(LOTTERY_MANAGER_ROLE) 
        nonReentrant 
    {
        require(winnersCount >= minWinnersCount && winnersCount <= maxWinnersCount, "Invalid winners count");
        require(lotteryRounds[roundId].isActive, "Round not active");
        require(block.timestamp >= lotteryRounds[roundId].endTime, "Round not ended");
        
        _finalizeLotteryRound(roundId, winnersCount);
    }

    function _finalizeLotteryRound(uint256 roundId, uint256 winnersCount) internal {
        LotteryRound storage round = lotteryRounds[roundId];
        
        if (round.totalParticipants == 0) {
            round.isActive = false;
            round.isFinalized = true;
            return;
        }
        
        // Use Flow VRF for randomness
        uint256 vrfRandomness = cadenceVRF.revertibleRandom();
        bytes32 vrfSeed = keccak256(abi.encodePacked(
            vrfRandomness,
            roundId,
            block.timestamp,
            block.prevrandao,
            blockhash(block.number - 1)
        ));
        
        round.vrfRandomness = vrfRandomness;
        round.vrfSeed = vrfSeed;
        round.winnersCount = winnersCount;
        
        // Select winners using VRF
        address[] memory allParticipants = _getParticipants(roundId);
        address[] memory winners = _selectWinners(allParticipants, winnersCount, vrfSeed);
        
        round.winners = winners;
        round.prizePerWinner = round.totalYieldGenerated / winnersCount;
        round.isActive = false;
        round.isFinalized = true;
        
        // Update user prize info
        for (uint256 i = 0; i < winners.length; i++) {
            userInfo[winners[i]].totalPrizesWon += round.prizePerWinner;
        }
        
        emit LotteryRoundFinalized(roundId, winners, round.prizePerWinner);
    }

    function _selectWinners(address[] memory participants, uint256 count, bytes32 seed) 
        internal 
        pure 
        returns (address[] memory winners) 
    {
        if (participants.length <= count) {
            return participants;
        }
        
        winners = new address[](count);
        bool[] memory selected = new bool[](participants.length);
        
        for (uint256 i = 0; i < count; i++) {
            uint256 randomIndex = uint256(keccak256(abi.encodePacked(seed, i))) % participants.length;
            
            // Find next unselected participant
            while (selected[randomIndex]) {
                randomIndex = (randomIndex + 1) % participants.length;
            }
            
            winners[i] = participants[randomIndex];
            selected[randomIndex] = true;
        }
    }

    function _getParticipants(uint256 roundId) internal view returns (address[] memory) {
        // This is a simplified approach - in production, you'd want to track participants more efficiently
        uint256 participantCount = lotteryRounds[roundId].totalParticipants;
        address[] memory participants = new address[](participantCount);
        
        // This would need to be implemented with proper participant tracking
        // For now, return empty array as placeholder
        return participants;
    }

    /// @notice Claim prize from a lottery round
    /// @param roundId Round ID to claim from
    function claimPrize(uint256 roundId) external nonReentrant {
        require(lotteryRounds[roundId].isFinalized, "Round not finalized");
        
        LotteryRound storage round = lotteryRounds[roundId];
        bool isWinner = false;
        
        for (uint256 i = 0; i < round.winners.length; i++) {
            if (round.winners[i] == msg.sender) {
                isWinner = true;
                break;
            }
        }
        
        require(isWinner, "Not a winner");
        require(round.prizePerWinner > 0, "No prize to claim");
        
        // Transfer prize
        _asset.safeTransfer(msg.sender, round.prizePerWinner);
        
        emit PrizeClaimed(msg.sender, roundId, round.prizePerWinner);
    }

    // ====================================================================
    // STRATEGY MANAGEMENT
    // ====================================================================
    
    /// @notice Add a new strategy
    /// @param strategy Strategy contract address
    /// @param name Strategy name
    /// @param allocation Allocation percentage in basis points
    function addStrategy(address strategy, string calldata name, uint256 allocation) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(strategy != address(0), "Invalid strategy");
        require(allocation <= 10000, "Invalid allocation");
        require(!strategies[strategy].active, "Strategy already exists");
        
        strategies[strategy] = StrategyInfo({
            strategyAddress: strategy,
            name: name,
            allocation: allocation,
            currentBalance: 0,
            active: true
        });
        
        activeStrategies.push(strategy);
        _grantRole(STRATEGY_ROLE, strategy);
        
        emit StrategyAdded(strategy, name, allocation);
    }

    /// @notice Update strategy allocation
    /// @param strategy Strategy address
    /// @param newAllocation New allocation in basis points
    function updateStrategyAllocation(address strategy, uint256 newAllocation) 
        external 
        onlyAgent 
    {
        require(strategies[strategy].active, "Strategy not active");
        require(newAllocation <= 10000, "Invalid allocation");
        
        strategies[strategy].allocation = newAllocation;
        
        emit StrategyUpdated(strategy, newAllocation);
    }

    /// @notice Deploy funds to strategies
    /// @param strategyAddresses Array of strategy addresses
    /// @param amounts Array of amounts to deploy to each strategy
    function deployToStrategies(address[] calldata strategyAddresses, uint256[] calldata amounts) 
        external 
        onlyAgent 
        nonReentrant 
    {
        require(strategyAddresses.length == amounts.length, "Array length mismatch");
        
        for (uint256 i = 0; i < strategyAddresses.length; i++) {
            address strategy = strategyAddresses[i];
            uint256 amount = amounts[i];
            
            require(strategies[strategy].active, "Strategy not active");
            require(_asset.balanceOf(address(this)) >= amount, "Insufficient funds");
            
            // Transfer to strategy and execute
            _asset.safeTransfer(strategy, amount);
            IStrategy(strategy).execute(amount, "");
            
            strategies[strategy].currentBalance += amount;
        }
    }

    /// @notice Harvest yield from strategies
    /// @param strategyAddresses Array of strategies to harvest from
    function harvestFromStrategies(address[] calldata strategyAddresses) 
        external 
        onlyAgent 
        nonReentrant 
        returns (uint256 totalHarvested) 
    {
        uint256 balanceBefore = _asset.balanceOf(address(this));
        
        for (uint256 i = 0; i < strategyAddresses.length; i++) {
            address strategy = strategyAddresses[i];
            require(strategies[strategy].active, "Strategy not active");
            
            try IStrategy(strategy).harvest("") {
                // Harvest successful
            } catch {
                // Continue with other strategies if one fails
            }
        }
        
        totalHarvested = _asset.balanceOf(address(this)) - balanceBefore;
        
        if (totalHarvested > 0) {
            // Collect fees
            uint256 managementFee = _calculateManagementFee();
            uint256 performanceFee = (totalHarvested * performanceFeeRate) / 10000;
            uint256 totalFees = managementFee + performanceFee;
            
            if (totalFees > 0) {
                _asset.safeTransfer(agentAddress, totalFees);
                totalHarvested -= totalFees;
            }
            
            // Add to current lottery round
            lotteryRounds[currentRoundId].totalYieldGenerated += totalHarvested;
            totalYieldGenerated += totalHarvested;
            
            lastFeeCollection = block.timestamp;
            
            emit YieldHarvested(totalHarvested, managementFee, performanceFee);
        }
        
        return totalHarvested;
    }

    function _calculateManagementFee() internal view returns (uint256) {
        uint256 timeElapsed = block.timestamp - lastFeeCollection;
        uint256 annualFee = (totalAssets() * managementFeeRate) / 10000;
        return (annualFee * timeElapsed) / 365 days;
    }

    // ====================================================================
    // INTERNAL ERC4626 LOGIC
    // ====================================================================

    function _deposit(uint256 assets, uint256 shares, address receiver) internal {
        _asset.safeTransferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
        
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function _withdraw(uint256 assets, uint256 shares, address receiver, address owner) internal {
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        _burn(owner, shares);
        _asset.safeTransfer(receiver, assets);
        
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view returns (uint256) {
        uint256 supply = totalSupply();
        return (supply == 0) ? assets : Math.mulDiv(assets, supply, totalAssets(), rounding);
    }

    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view returns (uint256) {
        uint256 supply = totalSupply();
        return (supply == 0) ? shares : Math.mulDiv(shares, totalAssets(), supply, rounding);
    }

    // ====================================================================
    // VIEW FUNCTIONS
    // ====================================================================
    
    function getCurrentRound() external view returns (LotteryRound memory) {
        return lotteryRounds[currentRoundId];
    }

    function getUserParticipatingRounds(address user) external view returns (uint256[] memory) {
        return userInfo[user].participatingRounds;
    }

    function isUserWinner(address user, uint256 roundId) external view returns (bool) {
        address[] memory winners = lotteryRounds[roundId].winners;
        for (uint256 i = 0; i < winners.length; i++) {
            if (winners[i] == user) return true;
        }
        return false;
    }

    function getActiveStrategies() external view returns (address[] memory) {
        return activeStrategies;
    }

    // ====================================================================
    // ADMIN FUNCTIONS
    // ====================================================================
    
    function setLotterySettings(
        uint256 _lotteryDuration,
        uint256 _minWinnersCount,
        uint256 _maxWinnersCount,
        uint256 _minDepositAmount,
        uint256 _withdrawalDelay
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        lotteryDuration = _lotteryDuration;
        minWinnersCount = _minWinnersCount;
        maxWinnersCount = _maxWinnersCount;
        minDepositAmount = _minDepositAmount;
        withdrawalDelay = _withdrawalDelay;
    }

    function setFeeRates(uint256 _managementFeeRate, uint256 _performanceFeeRate) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(_managementFeeRate <= 500, "Management fee too high"); // Max 5%
        require(_performanceFeeRate <= 2000, "Performance fee too high"); // Max 20%
        
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
        emit EmergencyModeToggled(enabled);
    }

    function emergencyWithdraw(address token, uint256 amount) external onlyRole(EMERGENCY_ROLE) {
        require(emergencyMode, "Not in emergency mode");
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    /// @notice Update agent address
    function setAgent(address newAgent) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newAgent != address(0), "Invalid agent");
        _revokeRole(AGENT_ROLE, agentAddress);
        _grantRole(AGENT_ROLE, newAgent);
        agentAddress = newAgent;
    }
}

// ====================================================================
// INTERFACES
// ====================================================================

interface IStrategy {
    function execute(uint256 amount, bytes calldata data) external;
    function harvest(bytes calldata data) external;
    function getBalance() external view returns (uint256);
}