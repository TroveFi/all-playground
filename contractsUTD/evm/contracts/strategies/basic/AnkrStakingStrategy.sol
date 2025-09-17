// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import "../../core/interfaces/IStrategy.sol";

// WFLOW interface for unwrapping
interface IWFLOW {
    function withdraw(uint256 amount) external;
    function deposit() external payable;
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

// CORRECTED Ankr Flow Staking Pool interface
interface IAnkrFlowStakingPool {
    function getMinStake() external view returns (uint256);
    function getMinUnstake() external view returns (uint256);
    function getTotalPendingUnstakes() external view returns (uint256);
    function getPendingUnstakesOf(address account) external view returns (uint256);
    function getFreeBalance() external view returns (uint256);
    function distributePendingRewards() external payable;
    function getFlowBridgeAddress() external view returns (address);
    function unstake(uint256 amount) external;
    // ADDED: The correct staking function
    function stakeCerts() external payable;
}

// ankrFLOW token interface
interface IAnkrFlowToken {
    function exchangeRate() external view returns (uint256);
    function ratio() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

contract AnkrStakingStrategy is IStrategy, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Roles
    bytes32 public constant STRATEGY_ROLE = keccak256("STRATEGY_ROLE");
    bytes32 public constant HARVESTER_ROLE = keccak256("HARVESTER_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    // Contract addresses on Flow EVM
    address public constant WFLOW_ADDRESS = 0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e;
    address public constant ANKR_FLOW_TOKEN_ADDRESS = 0x1b97100eA1D7126C4d60027e231EA4CB25314bdb;
    address public constant FLOW_STAKING_POOL_ADDRESS = 0xFE8189A3016cb6A3668b8ccdAC520CE572D4287a;
    address public constant NATIVE_FLOW = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // Contract references
    IWFLOW public wflowContract;
    IAnkrFlowToken public ankrFlowToken;
    IAnkrFlowStakingPool public stakingPool;
    IERC20 public wflowAsERC20;
    IERC20 public ankrFlowAsERC20;

    // Strategy configuration
    address public vault;
    bool public strategyPaused;
    string public strategyName;

    // Position tracking
    uint256 public totalFlowStaked;
    uint256 public ankrFlowBalance;
    uint256 public lastExchangeRate;

    // Strategy metrics
    uint256 public totalDeployed;
    uint256 public totalHarvested;
    uint256 public lastHarvestTime;
    uint256 public harvestCount;

    // Performance tracking
    uint256 public rewardsEarned;
    uint256 public exchangeRateGains;

    // Configuration parameters
    uint256 public maxSingleDeployment = 100000 * 10**18;
    uint256 public minHarvestAmount = 1 * 10**18;
    uint256 public harvestThreshold = 5 * 10**18;

    // Unstaking management
    uint256 public unstakeCooldown = 14 days;
    mapping(uint256 => uint256) public unstakeRequests;
    mapping(uint256 => uint256) public unstakeTimestamps;
    uint256[] public pendingUnstakeRequests;
    uint256 public totalPendingUnstakes;

    // Events
    event StrategyExecuted(uint256 amount, bytes data);
    event StrategyHarvested(uint256 harvested, uint256 totalHarvested);
    event EmergencyExitExecuted(uint256 recoveredAmount);
    event FlowStaked(uint256 flowAmount, uint256 ankrFlowReceived, uint256 exchangeRate);
    event FlowUnstaked(uint256 ankrFlowAmount, uint256 flowReceived);
    event WFlowUnwrapped(uint256 wflowAmount, uint256 flowReceived);
    event NativeFlowStaked(uint256 flowAmount, uint256 ankrFlowReceived);
    event ExchangeRateUpdated(uint256 oldRate, uint256 newRate, uint256 gainAmount);
    event UnstakeRequested(uint256 requestId, uint256 ankrFlowAmount, uint256 availableAt);
    event FundsWithdrawn(address indexed to, uint256 wflowAmount, uint256 ankrFlowAmount);

    constructor(
        address _vault,
        address _stakingPool,
        string memory _name
    ) {
        require(_vault != address(0), "Invalid vault address");
        require(_stakingPool != address(0), "Invalid staking pool address");

        vault = _vault;
        strategyName = _name;

        // Initialize contract references
        wflowContract = IWFLOW(WFLOW_ADDRESS);
        ankrFlowToken = IAnkrFlowToken(ANKR_FLOW_TOKEN_ADDRESS);
        stakingPool = IAnkrFlowStakingPool(_stakingPool);
        
        // Initialize IERC20 interfaces for SafeERC20 usage
        wflowAsERC20 = IERC20(WFLOW_ADDRESS);
        ankrFlowAsERC20 = IERC20(ANKR_FLOW_TOKEN_ADDRESS);

        // Initialize exchange rate
        lastExchangeRate = _initializeExchangeRate();

        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(STRATEGY_ROLE, _vault);
        _grantRole(HARVESTER_ROLE, msg.sender);
    }

    function _initializeExchangeRate() internal view returns (uint256) {
        try ankrFlowToken.exchangeRate() returns (uint256 rate) {
            return rate;
        } catch {
            try ankrFlowToken.ratio() returns (uint256 rate) {
                return rate;
            } catch {
                return 1e18; // Default 1:1 ratio
            }
        }
    }

    // Modifiers
    modifier onlyVault() {
        require(hasRole(STRATEGY_ROLE, msg.sender), "Only vault can call");
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

    // IStrategy interface implementation
    function execute(uint256 amount, bytes calldata data) 
        external 
        override 
        onlyVault 
        nonReentrant 
        whenNotPaused 
    {
        _executeWFlowStaking(amount, data);
    }

    // Enhanced function to handle both WFLOW and native FLOW
    function executeWithAsset(address asset, uint256 amount, bytes calldata data) 
        external 
        payable 
        onlyVault 
        nonReentrant 
        whenNotPaused 
    {
        require(amount > 0, "Amount must be greater than 0");
        require(amount <= maxSingleDeployment, "Amount exceeds max deployment");
        require(asset == WFLOW_ADDRESS || asset == NATIVE_FLOW, "Unsupported asset");

        if (asset == WFLOW_ADDRESS) {
            _executeWFlowStaking(amount, data);
        } else {
            require(msg.value == amount, "Native FLOW amount mismatch");
            _executeNativeFlowStaking(amount, data);
        }
    }

    function _executeWFlowStaking(uint256 amount, bytes calldata data) internal {
        require(amount > 0, "Amount must be greater than 0");
        require(amount <= maxSingleDeployment, "Amount exceeds max deployment");
        
        uint256 minStake = _getMinStakeAmount();
        require(amount >= minStake, "Below minimum stake amount");

        wflowAsERC20.safeTransferFrom(msg.sender, address(this), amount);
        uint256 ankrFlowReceived = _stakeFromWFLOW(amount);

        totalFlowStaked += amount;
        ankrFlowBalance += ankrFlowReceived;
        totalDeployed += amount;

        uint256 currentRate = _getCurrentExchangeRate();
        lastExchangeRate = currentRate;

        emit StrategyExecuted(amount, data);
        emit FlowStaked(amount, ankrFlowReceived, currentRate);
    }

    function _executeNativeFlowStaking(uint256 amount, bytes calldata data) internal {
        require(amount > 0, "Amount must be greater than 0");
        require(amount <= maxSingleDeployment, "Amount exceeds max deployment");
        
        uint256 minStake = _getMinStakeAmount();
        require(amount >= minStake, "Below minimum stake amount");

        uint256 ankrFlowReceived = _stakeFromNativeFLOW(amount);

        totalFlowStaked += amount;
        ankrFlowBalance += ankrFlowReceived;
        totalDeployed += amount;

        uint256 currentRate = _getCurrentExchangeRate();
        lastExchangeRate = currentRate;

        emit StrategyExecuted(amount, data);
        emit FlowStaked(amount, ankrFlowReceived, currentRate);
    }

    function withdrawToVault(uint256 wflowAmount, uint256 ankrFlowAmount) 
        external 
        onlyVault 
        nonReentrant 
        whenNotPaused 
    {
        require(wflowAmount > 0 || ankrFlowAmount > 0, "Must withdraw something");

        if (wflowAmount > 0) {
            uint256 availableWFlow = wflowAsERC20.balanceOf(address(this));
            require(availableWFlow >= wflowAmount, "Insufficient WFLOW balance");
            wflowAsERC20.safeTransfer(vault, wflowAmount);
        }

        if (ankrFlowAmount > 0) {
            require(ankrFlowBalance >= ankrFlowAmount, "Insufficient ankrFLOW balance");
            ankrFlowAsERC20.safeTransfer(vault, ankrFlowAmount);
            ankrFlowBalance -= ankrFlowAmount;
        }

        emit FundsWithdrawn(vault, wflowAmount, ankrFlowAmount);
    }

    function withdrawAllToVault() external onlyVault nonReentrant {
        uint256 wflowBal = wflowAsERC20.balanceOf(address(this));
        uint256 ankrFlowBal = ankrFlowToken.balanceOf(address(this));
        uint256 nativeBal = address(this).balance;

        if (nativeBal > 0) {
            wflowContract.deposit{value: nativeBal}();
            wflowBal += nativeBal;
        }

        if (wflowBal > 0) {
            wflowAsERC20.safeTransfer(vault, wflowBal);
        }

        if (ankrFlowBal > 0) {
            ankrFlowAsERC20.safeTransfer(vault, ankrFlowBal);
            ankrFlowBalance = 0;
        }

        emit FundsWithdrawn(vault, wflowBal, ankrFlowBal);
    }

    function unstakeToVault(uint256 ankrFlowAmount) 
        external 
        onlyVault 
        nonReentrant 
        whenNotPaused 
    {
        require(ankrFlowAmount > 0, "Amount must be greater than 0");
        require(ankrFlowBalance >= ankrFlowAmount, "Insufficient ankrFLOW balance");

        uint256 minUnstake = _getMinUnstakeAmount();
        require(ankrFlowAmount >= minUnstake, "Below minimum unstake amount");

        uint256 flowBefore = address(this).balance;
        ankrFlowAsERC20.safeApprove(FLOW_STAKING_POOL_ADDRESS, ankrFlowAmount);
        
        try stakingPool.unstake(ankrFlowAmount) {
            uint256 flowReceived = address(this).balance - flowBefore;
            
            if (flowReceived > 0) {
                wflowContract.deposit{value: flowReceived}();
                wflowAsERC20.safeTransfer(vault, flowReceived);
            }

            ankrFlowBalance -= ankrFlowAmount;
            emit FlowUnstaked(ankrFlowAmount, flowReceived);
        } catch {
            _requestUnstake(ankrFlowAmount);
        }
    }

    function harvest(bytes calldata data) external override onlyHarvester nonReentrant whenNotPaused {
        uint256 wflowBalanceBefore = wflowAsERC20.balanceOf(address(this));
        uint256 nativeFlowBefore = address(this).balance;
        uint256 totalHarvestedAmount = 0;

        _processCompletedUnstakes();
        _distributePendingRewards();

        uint256 currentRate = _getCurrentExchangeRate();
        if (currentRate > lastExchangeRate && ankrFlowBalance > 0) {
            uint256 rateGain = currentRate - lastExchangeRate;
            uint256 gainAmount = (ankrFlowBalance * rateGain) / 1e18;
            
            if (gainAmount >= harvestThreshold) {
                uint256 ankrFlowToUnstake = (gainAmount * 1e18) / currentRate;
                if (ankrFlowToUnstake <= ankrFlowBalance) {
                    _requestUnstake(ankrFlowToUnstake);
                }
            }
            
            emit ExchangeRateUpdated(lastExchangeRate, currentRate, gainAmount);
            lastExchangeRate = currentRate;
        }

        uint256 nativeFlowReceived = address(this).balance - nativeFlowBefore;
        if (nativeFlowReceived > 0) {
            wflowContract.deposit{value: nativeFlowReceived}();
            totalHarvestedAmount += nativeFlowReceived;
        }

        uint256 wflowHarvested = wflowAsERC20.balanceOf(address(this)) - wflowBalanceBefore;
        totalHarvestedAmount += wflowHarvested;

        if (totalHarvestedAmount >= minHarvestAmount) {
            wflowAsERC20.safeTransfer(vault, totalHarvestedAmount);
            
            totalHarvested += totalHarvestedAmount;
            lastHarvestTime = block.timestamp;
            harvestCount++;
            
            emit StrategyHarvested(totalHarvestedAmount, totalHarvested);
        }
    }

    function emergencyExit(bytes calldata data) external override onlyRole(EMERGENCY_ROLE) nonReentrant {
        strategyPaused = true;
        uint256 recovered = 0;

        uint256 ankrFlowBal = ankrFlowToken.balanceOf(address(this));
        if (ankrFlowBal > 0) {
            ankrFlowAsERC20.safeTransfer(vault, ankrFlowBal);
            recovered += ankrFlowBal;
            ankrFlowBalance = 0;
        }

        uint256 wflowBal = wflowAsERC20.balanceOf(address(this));
        if (wflowBal > 0) {
            wflowAsERC20.safeTransfer(vault, wflowBal);
            recovered += wflowBal;
        }

        if (address(this).balance > 0) {
            uint256 nativeBalance = address(this).balance;
            wflowContract.deposit{value: nativeBalance}();
            wflowAsERC20.safeTransfer(vault, nativeBalance);
            recovered += nativeBalance;
        }

        emit EmergencyExitExecuted(recovered);
    }

    function getBalance() external view override returns (uint256) {
        uint256 wflowBalance = wflowAsERC20.balanceOf(address(this));
        uint256 nativeBalance = address(this).balance;
        uint256 stakedValue = _getStakedValue();
        return wflowBalance + nativeBalance + stakedValue;
    }

    function underlyingToken() external view override returns (address) {
        return WFLOW_ADDRESS;
    }

    function protocol() external view override returns (address) {
        return FLOW_STAKING_POOL_ADDRESS;
    }

    function paused() external view override returns (bool) {
        return strategyPaused;
    }

    function setPaused(bool pauseState) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        strategyPaused = pauseState;
    }

    function _stakeFromWFLOW(uint256 wflowAmount) internal returns (uint256 ankrFlowReceived) {
        wflowContract.withdraw(wflowAmount);
        emit WFlowUnwrapped(wflowAmount, wflowAmount);
        return _stakeNativeFlow(wflowAmount);
    }

    function _stakeFromNativeFLOW(uint256 flowAmount) internal returns (uint256 ankrFlowReceived) {
        emit NativeFlowStaked(flowAmount, 0);
        return _stakeNativeFlow(flowAmount);
    }

    // CORRECTED: Use stakeCerts() function instead of low-level call
    function _stakeNativeFlow(uint256 flowAmount) internal returns (uint256 ankrFlowReceived) {
        uint256 ankrFlowBefore = ankrFlowToken.balanceOf(address(this));

        // FIXED: Use stakeCerts function instead of low-level call
        stakingPool.stakeCerts{value: flowAmount}();

        uint256 ankrFlowAfter = ankrFlowToken.balanceOf(address(this));
        ankrFlowReceived = ankrFlowAfter - ankrFlowBefore;
        
        require(ankrFlowReceived > 0, "No ankrFLOW tokens received");
        return ankrFlowReceived;
    }

    function _getStakedValue() internal view returns (uint256) {
        if (ankrFlowBalance == 0) {
            return 0;
        }
        uint256 currentRate = _getCurrentExchangeRate();
        return (ankrFlowBalance * currentRate) / 1e18;
    }

    function _getCurrentExchangeRate() internal view returns (uint256) {
        try ankrFlowToken.ratio() returns (uint256 rate) {
            return rate;
        } catch {
            try ankrFlowToken.exchangeRate() returns (uint256 rate) {
                return rate;
            } catch {
                return lastExchangeRate;
            }
        }
    }

    function _getMinStakeAmount() internal view returns (uint256) {
        try stakingPool.getMinStake() returns (uint256 minStake) {
            return minStake;
        } catch {
            return 1e18;
        }
    }

    function _getMinUnstakeAmount() internal view returns (uint256) {
        try stakingPool.getMinUnstake() returns (uint256 minUnstake) {
            return minUnstake;
        } catch {
            return 1e18;
        }
    }

    function _distributePendingRewards() internal {
        try stakingPool.distributePendingRewards{value: 0}() {
        } catch {
        }
    }

    function _requestUnstake(uint256 ankrFlowAmount) internal {
        require(ankrFlowAmount <= ankrFlowBalance, "Insufficient ankrFLOW balance");
        
        ankrFlowBalance -= ankrFlowAmount;
        totalPendingUnstakes += ankrFlowAmount;
        
        uint256 requestId = block.timestamp;
        unstakeRequests[requestId] = ankrFlowAmount;
        unstakeTimestamps[requestId] = block.timestamp;
        pendingUnstakeRequests.push(requestId);
        
        uint256 availableAt = block.timestamp + unstakeCooldown;
        emit UnstakeRequested(requestId, ankrFlowAmount, availableAt);
    }

    function _processCompletedUnstakes() internal {
        uint256 currentTime = block.timestamp;
        
        for (uint256 i = 0; i < pendingUnstakeRequests.length; i++) {
            uint256 requestId = pendingUnstakeRequests[i];
            uint256 amount = unstakeRequests[requestId];
            uint256 requestTime = unstakeTimestamps[requestId];
            
            if (amount > 0 && currentTime >= requestTime + unstakeCooldown) {
                totalPendingUnstakes -= amount;
                exchangeRateGains += amount;
                
                delete unstakeRequests[requestId];
                delete unstakeTimestamps[requestId];
            }
        }
        
        _cleanUpProcessedRequests();
    }

    function _cleanUpProcessedRequests() internal {
        uint256 writeIndex = 0;
        
        for (uint256 i = 0; i < pendingUnstakeRequests.length; i++) {
            uint256 requestId = pendingUnstakeRequests[i];
            if (unstakeRequests[requestId] > 0) {
                pendingUnstakeRequests[writeIndex] = requestId;
                writeIndex++;
            }
        }
        
        while (pendingUnstakeRequests.length > writeIndex) {
            pendingUnstakeRequests.pop();
        }
    }

    // View functions
    function getSupportedAssets() external pure returns (address[] memory) {
        address[] memory assets = new address[](2);
        assets[0] = WFLOW_ADDRESS;
        assets[1] = NATIVE_FLOW;
        return assets;
    }

    function getCurrentAPY() external view returns (uint256) {
        uint256 currentRate = _getCurrentExchangeRate();
        
        if (lastExchangeRate == 0 || lastHarvestTime == 0) {
            return 683;
        }
        
        uint256 timeElapsed = block.timestamp - lastHarvestTime;
        if (timeElapsed == 0) {
            return 683;
        }
        
        uint256 rateIncrease = currentRate > lastExchangeRate ? currentRate - lastExchangeRate : 0;
        uint256 annualizedRate = (rateIncrease * 365 days * 10000) / (lastExchangeRate * timeElapsed);
        
        return annualizedRate;
    }

    function getStakingInfo() external view returns (
        uint256 totalStaked,
        uint256 ankrFlowBal,
        uint256 currentExchangeRate,
        uint256 stakedValue,
        uint256 pendingUnstakes,
        uint256 minStake,
        uint256 totalPendingUnstakes_,
        bool canStake
    ) {
        totalStaked = totalFlowStaked;
        ankrFlowBal = ankrFlowBalance;
        currentExchangeRate = _getCurrentExchangeRate();
        stakedValue = _getStakedValue();
        totalPendingUnstakes_ = totalPendingUnstakes;
        minStake = _getMinStakeAmount();
        
        try stakingPool.getPendingUnstakesOf(address(this)) returns (uint256 pending) {
            pendingUnstakes = pending;
        } catch {
            pendingUnstakes = 0;
        }
        
        canStake = !strategyPaused;
    }

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
            WFLOW_ADDRESS,
            FLOW_STAKING_POOL_ADDRESS,
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
        uint256 totalRewards,
        uint256 currentAPY
    ) {
        uint256 avgHarvest = harvestCount > 0 ? totalHarvested / harvestCount : 0;
        uint256 apy = this.getCurrentAPY();

        return (
            totalDeployed,
            totalHarvested,
            harvestCount,
            avgHarvest,
            rewardsEarned,
            apy
        );
    }

    function getWithdrawableAmounts() external view returns (
        uint256 availableWFlow,
        uint256 availableAnkrFlow,
        uint256 stakedValue,
        uint256 totalValue
    ) {
        availableWFlow = wflowAsERC20.balanceOf(address(this));
        availableAnkrFlow = ankrFlowBalance;
        stakedValue = _getStakedValue();
        totalValue = availableWFlow + address(this).balance + stakedValue;
    }

    // Admin functions
    function manualUnstake(uint256 ankrFlowAmount) external onlyRole(HARVESTER_ROLE) nonReentrant {
        require(ankrFlowAmount <= ankrFlowBalance, "Insufficient ankrFLOW balance");
        _requestUnstake(ankrFlowAmount);
    }

    function processUnstakeRequests() external onlyRole(HARVESTER_ROLE) nonReentrant {
        _processCompletedUnstakes();
    }

    function setMaxSingleDeployment(uint256 newMax) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxSingleDeployment = newMax;
    }

    function setMinHarvestAmount(uint256 newMin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minHarvestAmount = newMin;
    }

    function setHarvestThreshold(uint256 _threshold) external onlyRole(DEFAULT_ADMIN_ROLE) {
        harvestThreshold = _threshold;
    }

    function setUnstakeCooldown(uint256 _cooldown) external onlyRole(DEFAULT_ADMIN_ROLE) {
        unstakeCooldown = _cooldown;
    }

    function emergencyWithdrawAnkrFlow() external onlyRole(EMERGENCY_ROLE) {
        uint256 ankrFlowBal = ankrFlowToken.balanceOf(address(this));
        if (ankrFlowBal > 0) {
            ankrFlowAsERC20.safeTransfer(vault, ankrFlowBal);
        }
    }

    function emergencyWithdrawNativeFlow() external onlyRole(EMERGENCY_ROLE) {
        if (address(this).balance > 0) {
            uint256 balance = address(this).balance;
            wflowContract.deposit{value: balance}();
            wflowAsERC20.safeTransfer(vault, balance);
        }
    }

    receive() external payable {
        // Accept native FLOW from Ankr protocol or vault
    }

    fallback() external payable {
        // Handle any other calls with value
    }
}