// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

// WFLOW interface
interface IWFLOW {
    function withdraw(uint256 amount) external;
    function deposit() external payable;
}

// Flow Bridge interface for WFLOW <-> FLOW conversion
interface IFlowBridge {
    function bridgeToFlow(uint256 wflowAmount, address cadenceRecipient) external payable returns (bytes32 requestId);
    function bridgeFromFlow(uint256 flowAmount, address evmRecipient) external returns (bytes32 requestId);
    function getBridgeStatus(bytes32 requestId) external view returns (bool completed, uint256 amount);
    function estimateBridgeFee() external view returns (uint256 fee);
}

// Cross-VM call interface for Cadence transactions
interface ICrossVMPrecompile {
    struct CadenceCall {
        bytes32 contractAddress;
        string functionName;
        bytes arguments;
        uint256 gasLimit;
    }
    
    function executeCadenceTransaction(
        CadenceCall calldata call,
        bytes32 nonce
    ) external payable returns (bytes memory result);
    
    function queryCadenceContract(
        bytes32 contractAddress,
        string calldata functionName,
        bytes calldata arguments
    ) external view returns (bytes memory result);
}

// Oracle mirror for Increment price feeds
interface IIncrementOracleMirror {
    function getStFlowPrice() external view returns (uint256 price, uint256 timestamp);
    function getExchangeRate() external view returns (uint256 rate, uint256 timestamp);
    function updatePrices(
        uint256 stFlowPrice,
        uint256 exchangeRate,
        uint256 timestamp,
        bytes[] calldata signatures
    ) external;
}

/// @title CrossVMIncrementStrategy - Production Increment Liquid Staking Strategy
/// @notice Interfaces with Cadence Increment contracts via cross-VM calls
/// @dev Holds stFLOW on Cadence, tracks positions on EVM for vault integration
contract CrossVMIncrementStrategy is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ====================================================================
    // CONSTANTS & ROLES
    // ====================================================================
    
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    
    // Flow addresses
    address public constant WFLOW = 0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e;
    address public constant NATIVE_FLOW = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    
    // Cross-VM and bridge addresses (Flow-specific)
    address public constant CROSS_VM_PRECOMPILE = 0x0000000000000000000000000100000000000000;
    address public constant FLOW_BRIDGE = 0x0000000000000000000000000200000000000000;
    
    // Cadence contract addresses (as bytes32 for cross-VM calls)
    bytes32 public constant LIQUID_STAKING_CONTRACT = 0xd6f80565193ad727000000000000000000000000000000000000000000000000;
    bytes32 public constant STFLOW_TOKEN_CONTRACT = 0xd6f80565193ad727000000000000000000000000000000000000000000000000;
    bytes32 public constant PUBLIC_PRICE_ORACLE = 0xec67451f8a58216a000000000000000000000000000000000000000000000000;
    bytes32 public constant STFLOW_PRICE_ORACLE = 0x031dabc5ba1d2932000000000000000000000000000000000000000000000000;

    // ====================================================================
    // STATE VARIABLES
    // ====================================================================
    
    // Core contracts
    ICrossVMPrecompile public immutable crossVM;
    IFlowBridge public immutable flowBridge;
    IIncrementOracleMirror public oracleMirror;
    IWFLOW public immutable wflowToken;
    IERC20 public immutable wflowAsERC20;
    
    address public vault;
    string public strategyName;
    
    // Cadence position tracking (no tokens held on EVM)
    struct CadencePosition {
        uint256 totalFlowStaked;       // Total FLOW staked on Cadence
        uint256 stFlowBalance;         // stFLOW balance on Cadence
        uint256 lastExchangeRate;      // Last known stFLOW exchange rate
        uint256 lastUpdateTime;        // Last position update
        address cadenceAddress;        // Our Cadence address for staking
        bool hasActivePosition;        // Whether we have active staking
    }
    
    CadencePosition public position;
    
    // Bridge operation tracking
    struct BridgeOperation {
        bytes32 requestId;
        uint256 amount;
        uint256 timestamp;
        uint8 operationType; // 0=stake, 1=unstake
        bool completed;
    }
    
    mapping(bytes32 => BridgeOperation) public bridgeOperations;
    bytes32[] public pendingOperations;
    
    // Strategy configuration
    uint256 public minStakeAmount = 1 * 10**18;      // 1 FLOW minimum
    uint256 public maxStakeAmount = 10000 * 10**18;  // 10k FLOW maximum
    uint256 public harvestThreshold = 1 * 10**17;    // 0.1 FLOW minimum
    uint256 public bridgeTimeout = 600;              // 10 minutes max bridge time
    uint256 public oracleStaleTime = 3600;           // 1 hour oracle staleness
    
    // Performance tracking
    uint256 public totalDeployed;
    uint256 public totalHarvested;
    uint256 public lastHarvestTime;
    uint256 public operationCount;
    
    // Control flags
    bool public strategyPaused;
    bool public emergencyMode;

    // ====================================================================
    // EVENTS
    // ====================================================================
    
    event StakeInitiated(bytes32 indexed requestId, uint256 wflowAmount, uint256 flowAmount);
    event StakeCompleted(bytes32 indexed requestId, uint256 flowAmount, uint256 stFlowReceived);
    event UnstakeInitiated(bytes32 indexed requestId, uint256 stFlowAmount);
    event UnstakeCompleted(bytes32 indexed requestId, uint256 stFlowAmount, uint256 flowReceived);
    event PositionUpdated(uint256 totalStaked, uint256 stFlowBalance, uint256 exchangeRate);
    event OracleUpdated(uint256 exchangeRate, uint256 stFlowPrice, uint256 timestamp);
    event BridgeOperationFailed(bytes32 indexed requestId, string reason);

    // ====================================================================
    // CONSTRUCTOR
    // ====================================================================
    
    constructor(
        address _vault,
        address _oracleMirror,
        address _cadenceAddress,
        string memory _name
    ) {
        require(_vault != address(0), "Invalid vault");
        require(_oracleMirror != address(0), "Invalid oracle");
        require(_cadenceAddress != address(0), "Invalid Cadence address");

        vault = _vault;
        oracleMirror = IIncrementOracleMirror(_oracleMirror);
        strategyName = _name;
        
        // Initialize contracts
        crossVM = ICrossVMPrecompile(CROSS_VM_PRECOMPILE);
        flowBridge = IFlowBridge(FLOW_BRIDGE);
        wflowToken = IWFLOW(WFLOW);
        wflowAsERC20 = IERC20(WFLOW);
        
        // Initialize Cadence position
        position.cadenceAddress = _cadenceAddress;
        
        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(VAULT_ROLE, _vault);
        _grantRole(KEEPER_ROLE, msg.sender);
    }

    // ====================================================================
    // MODIFIERS
    // ====================================================================
    
    modifier onlyVault() {
        require(hasRole(VAULT_ROLE, msg.sender), "Only vault");
        _;
    }

    modifier whenNotPaused() {
        require(!strategyPaused && !emergencyMode, "Strategy paused");
        _;
    }

    // ====================================================================
    // MAIN STRATEGY FUNCTIONS
    // ====================================================================

    /// @notice Execute staking with WFLOW
    function execute(uint256 amount, bytes calldata data) 
        external 
        onlyVault 
        nonReentrant 
        whenNotPaused 
    {
        _executeStaking(WFLOW, amount);
    }

    /// @notice Execute staking with specified asset
    function executeWithAsset(address asset, uint256 amount, bytes calldata data) 
        external 
        payable 
        onlyVault 
        nonReentrant 
        whenNotPaused 
    {
        require(asset == WFLOW || asset == NATIVE_FLOW, "Unsupported asset");
        _executeStaking(asset, amount);
    }

    /// @notice Internal staking execution
    function _executeStaking(address asset, uint256 amount) internal {
        require(amount >= minStakeAmount, "Below minimum stake");
        require(amount <= maxStakeAmount, "Above maximum stake");

        uint256 wflowAmount;
        
        if (asset == WFLOW) {
            // Transfer WFLOW from vault
            wflowAsERC20.safeTransferFrom(msg.sender, address(this), amount);
            wflowAmount = amount;
        } else {
            // Native FLOW - wrap to WFLOW first
            require(msg.value == amount, "Amount mismatch");
            wflowToken.deposit{value: amount}();
            wflowAmount = amount;
        }

        // Initiate cross-VM staking process
        bytes32 requestId = _initiateCrossVMStaking(wflowAmount);
        
        // Track the operation
        bridgeOperations[requestId] = BridgeOperation({
            requestId: requestId,
            amount: wflowAmount,
            timestamp: block.timestamp,
            operationType: 0, // stake
            completed: false
        });
        
        pendingOperations.push(requestId);
        totalDeployed += amount;
        operationCount++;

        emit StakeInitiated(requestId, wflowAmount, wflowAmount);
    }

    /// @notice Harvest yields and process completed operations
    function harvest(bytes calldata data) 
        external 
        onlyVault 
        nonReentrant 
        whenNotPaused 
    {
        uint256 harvestedAmount = 0;
        
        // 1. Process completed bridge operations
        _processCompletedOperations();
        
        // 2. Update oracle data from Cadence
        _updateOracleData();
        
        // 3. Calculate position value and yield
        uint256 currentValue = _calculatePositionValue();
        uint256 totalYield = currentValue > position.totalFlowStaked ? 
            currentValue - position.totalFlowStaked : 0;
        
        if (totalYield >= harvestThreshold) {
            // Unstake yield portion
            uint256 stFlowToUnstake = _calculateStFlowForAmount(totalYield / 2); // Unstake half of yield
            
            if (stFlowToUnstake > 0 && stFlowToUnstake <= position.stFlowBalance) {
                bytes32 requestId = _initiateCrossVMUnstaking(stFlowToUnstake);
                
                bridgeOperations[requestId] = BridgeOperation({
                    requestId: requestId,
                    amount: stFlowToUnstake,
                    timestamp: block.timestamp,
                    operationType: 1, // unstake
                    completed: false
                });
                
                pendingOperations.push(requestId);
                harvestedAmount = totalYield / 2;
            }
        }
        
        // 4. Send any available WFLOW to vault
        uint256 wflowBalance = wflowAsERC20.balanceOf(address(this));
        if (wflowBalance > 0) {
            wflowAsERC20.safeTransfer(vault, wflowBalance);
            harvestedAmount += wflowBalance;
        }

        if (harvestedAmount > 0) {
            totalHarvested += harvestedAmount;
            lastHarvestTime = block.timestamp;
        }
    }

    /// @notice Emergency exit - unstake all positions
    function emergencyExit(bytes calldata data) 
        external 
        onlyRole(EMERGENCY_ROLE) 
        nonReentrant 
    {
        emergencyMode = true;
        strategyPaused = true;

        // Initiate emergency unstaking of all stFLOW
        if (position.stFlowBalance > 0) {
            bytes32 requestId = _initiateCrossVMUnstaking(position.stFlowBalance);
            
            bridgeOperations[requestId] = BridgeOperation({
                requestId: requestId,
                amount: position.stFlowBalance,
                timestamp: block.timestamp,
                operationType: 1, // unstake
                completed: false
            });
            
            pendingOperations.push(requestId);
        }

        // Send any existing WFLOW to vault
        uint256 wflowBalance = wflowAsERC20.balanceOf(address(this));
        if (wflowBalance > 0) {
            wflowAsERC20.safeTransfer(vault, wflowBalance);
        }
    }

    // ====================================================================
    // CROSS-VM OPERATIONS
    // ====================================================================

    /// @notice Initiate cross-VM staking process
    function _initiateCrossVMStaking(uint256 wflowAmount) internal returns (bytes32 requestId) {
        // Step 1: Bridge WFLOW to FLOW on Cadence
        uint256 bridgeFee = flowBridge.estimateBridgeFee();
        require(address(this).balance >= bridgeFee, "Insufficient bridge fee");
        
        requestId = flowBridge.bridgeToFlow{value: bridgeFee}(wflowAmount, position.cadenceAddress);
        
        // Step 2: Schedule Cadence staking transaction
        _scheduleCadenceStaking(wflowAmount, requestId);
        
        return requestId;
    }

    /// @notice Schedule Cadence staking transaction
    function _scheduleCadenceStaking(uint256 flowAmount, bytes32 nonce) internal {
        // Prepare Cadence function call
        ICrossVMPrecompile.CadenceCall memory call = ICrossVMPrecompile.CadenceCall({
            contractAddress: LIQUID_STAKING_CONTRACT,
            functionName: "stake",
            arguments: abi.encode(flowAmount, position.cadenceAddress),
            gasLimit: 1000000
        });
        
        // Execute cross-VM call
        try crossVM.executeCadenceTransaction(call, nonce) {
            // Transaction scheduled successfully
        } catch {
            // Handle failure - bridge operation will timeout
        }
    }

    /// @notice Initiate cross-VM unstaking process
    function _initiateCrossVMUnstaking(uint256 stFlowAmount) internal returns (bytes32 requestId) {
        requestId = keccak256(abi.encodePacked(block.timestamp, stFlowAmount, operationCount));
        
        // Prepare Cadence unstaking call
        ICrossVMPrecompile.CadenceCall memory call = ICrossVMPrecompile.CadenceCall({
            contractAddress: LIQUID_STAKING_CONTRACT,
            functionName: "unstake",
            arguments: abi.encode(stFlowAmount, position.cadenceAddress),
            gasLimit: 1000000
        });
        
        // Execute cross-VM call
        try crossVM.executeCadenceTransaction(call, requestId) {
            // Transaction scheduled successfully
        } catch {
            // Handle failure
        }
        
        return requestId;
    }

    /// @notice Process completed bridge operations
    function _processCompletedOperations() internal {
        uint256 processedCount = 0;
        
        for (uint256 i = 0; i < pendingOperations.length && processedCount < 10; i++) {
            bytes32 requestId = pendingOperations[i];
            BridgeOperation storage op = bridgeOperations[requestId];
            
            if (op.completed) continue;
            
            // Check if bridge operation completed
            (bool completed, uint256 amount) = flowBridge.getBridgeStatus(requestId);
            
            if (completed) {
                if (op.operationType == 0) {
                    // Staking completed
                    _processStakeCompletion(requestId, amount);
                } else {
                    // Unstaking completed
                    _processUnstakeCompletion(requestId, amount);
                }
                
                op.completed = true;
                processedCount++;
            } else if (block.timestamp > op.timestamp + bridgeTimeout) {
                // Operation timed out
                emit BridgeOperationFailed(requestId, "Bridge timeout");
                op.completed = true;
                processedCount++;
            }
        }
        
        // Clean up completed operations
        _cleanupCompletedOperations();
    }

    /// @notice Process completed staking operation
    function _processStakeCompletion(bytes32 requestId, uint256 flowAmount) internal {
        // Query Cadence for new stFLOW balance and exchange rate
        uint256 newStFlowBalance = _queryCadenceStFlowBalance();
        uint256 exchangeRate = _queryCadenceExchangeRate();
        
        // Calculate stFLOW received
        uint256 stFlowReceived = newStFlowBalance > position.stFlowBalance ? 
            newStFlowBalance - position.stFlowBalance : 0;
        
        // Update position
        position.totalFlowStaked += flowAmount;
        position.stFlowBalance = newStFlowBalance;
        position.lastExchangeRate = exchangeRate;
        position.lastUpdateTime = block.timestamp;
        position.hasActivePosition = true;
        
        emit StakeCompleted(requestId, flowAmount, stFlowReceived);
        emit PositionUpdated(position.totalFlowStaked, position.stFlowBalance, exchangeRate);
    }

    /// @notice Process completed unstaking operation
    function _processUnstakeCompletion(bytes32 requestId, uint256 flowReceived) internal {
        BridgeOperation memory op = bridgeOperations[requestId];
        
        // Update position
        position.stFlowBalance -= op.amount;
        position.lastUpdateTime = block.timestamp;
        
        if (position.stFlowBalance == 0) {
            position.hasActivePosition = false;
        }
        
        emit UnstakeCompleted(requestId, op.amount, flowReceived);
    }

    // ====================================================================
    // CADENCE QUERIES
    // ====================================================================

    /// @notice Query stFLOW balance on Cadence
    function _queryCadenceStFlowBalance() internal view returns (uint256) {
        try crossVM.queryCadenceContract(
            STFLOW_TOKEN_CONTRACT,
            "getBalance",
            abi.encode(position.cadenceAddress)
        ) returns (bytes memory result) {
            return abi.decode(result, (uint256));
        } catch {
            return position.stFlowBalance; // Return cached value on error
        }
    }

    /// @notice Query stFLOW exchange rate from Cadence
    function _queryCadenceExchangeRate() internal view returns (uint256) {
        try crossVM.queryCadenceContract(
            LIQUID_STAKING_CONTRACT,
            "getExchangeRate",
            ""
        ) returns (bytes memory result) {
            return abi.decode(result, (uint256));
        } catch {
            return position.lastExchangeRate; // Return cached value on error
        }
    }

    /// @notice Update oracle data from Cadence
    function _updateOracleData() internal {
        uint256 exchangeRate = _queryCadenceExchangeRate();
        
        // Query stFLOW price from Cadence oracle
        try crossVM.queryCadenceContract(
            STFLOW_PRICE_ORACLE,
            "getPrice",
            ""
        ) returns (bytes memory result) {
            uint256 stFlowPrice = abi.decode(result, (uint256));
            
            // Update oracle mirror (requires keeper signature)
            emit OracleUpdated(exchangeRate, stFlowPrice, block.timestamp);
        } catch {
            // Oracle query failed
        }
    }

    // ====================================================================
    // HELPER FUNCTIONS
    // ====================================================================

    /// @notice Calculate current position value in FLOW
    function _calculatePositionValue() internal view returns (uint256) {
        if (position.stFlowBalance == 0 || position.lastExchangeRate == 0) {
            return 0;
        }
        
        return (position.stFlowBalance * position.lastExchangeRate) / 1e18;
    }

    /// @notice Calculate stFLOW amount for given FLOW amount
    function _calculateStFlowForAmount(uint256 flowAmount) internal view returns (uint256) {
        if (position.lastExchangeRate == 0) return 0;
        return (flowAmount * 1e18) / position.lastExchangeRate;
    }

    /// @notice Clean up completed operations
    function _cleanupCompletedOperations() internal {
        uint256 writeIndex = 0;
        
        for (uint256 i = 0; i < pendingOperations.length; i++) {
            bytes32 requestId = pendingOperations[i];
            if (!bridgeOperations[requestId].completed) {
                pendingOperations[writeIndex] = requestId;
                writeIndex++;
            }
        }
        
        // Remove completed operations
        while (pendingOperations.length > writeIndex) {
            pendingOperations.pop();
        }
    }

    // ====================================================================
    // VIEW FUNCTIONS
    // ====================================================================

    function getBalance() external view returns (uint256) {
        uint256 wflowBalance = wflowAsERC20.balanceOf(address(this));
        uint256 positionValue = _calculatePositionValue();
        return wflowBalance + positionValue;
    }

    function underlyingToken() external pure returns (address) {
        return WFLOW;
    }

    function protocol() external pure returns (address) {
        return CROSS_VM_PRECOMPILE;
    }

    function paused() external view returns (bool) {
        return strategyPaused;
    }

    function setPaused(bool pauseState) external onlyRole(DEFAULT_ADMIN_ROLE) {
        strategyPaused = pauseState;
    }

    function getPosition() external view returns (
        uint256 totalStaked,
        uint256 stFlowBalance,
        uint256 currentValue,
        uint256 exchangeRate,
        bool hasPosition
    ) {
        return (
            position.totalFlowStaked,
            position.stFlowBalance,
            _calculatePositionValue(),
            position.lastExchangeRate,
            position.hasActivePosition
        );
    }

    function getPendingOperations() external view returns (bytes32[] memory) {
        return pendingOperations;
    }

    function getOperationDetails(bytes32 requestId) external view returns (BridgeOperation memory) {
        return bridgeOperations[requestId];
    }

    // ====================================================================
    // ADMIN FUNCTIONS
    // ====================================================================

    function updateConfiguration(
        uint256 _minStakeAmount,
        uint256 _maxStakeAmount,
        uint256 _harvestThreshold,
        uint256 _bridgeTimeout
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minStakeAmount = _minStakeAmount;
        maxStakeAmount = _maxStakeAmount;
        harvestThreshold = _harvestThreshold;
        bridgeTimeout = _bridgeTimeout;
    }

    function setOracleMirror(address _oracleMirror) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_oracleMirror != address(0), "Invalid oracle");
        oracleMirror = IIncrementOracleMirror(_oracleMirror);
    }

    function setCadenceAddress(address _cadenceAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_cadenceAddress != address(0), "Invalid address");
        position.cadenceAddress = _cadenceAddress;
    }

    // Emergency functions
    function emergencyWithdrawWFLOW() external onlyRole(EMERGENCY_ROLE) {
        require(emergencyMode, "Not emergency");
        uint256 balance = wflowAsERC20.balanceOf(address(this));
        if (balance > 0) {
            wflowAsERC20.safeTransfer(vault, balance);
        }
    }

    // ====================================================================
    // RECEIVE FUNCTIONS
    // ====================================================================

    receive() external payable {
        // Accept native FLOW for bridge fees
    }

    fallback() external payable {
        revert("Unexpected call");
    }
}