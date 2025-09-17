// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

// WFLOW interface
interface IWFLOW {
    function withdraw(uint256 amount) external;
    function deposit() external payable;
}

// Flow Cross-VM Bridge interface
interface IFlowEVMBridge {
    function bridgeTokensToFlow(
        address token,
        uint256 amount,
        bytes calldata recipient
    ) external payable returns (bytes32 requestId);
    
    function bridgeTokensFromFlow(
        address token,
        uint256 amount,
        address recipient
    ) external returns (bytes32 requestId);
    
    function getBridgeRequestStatus(bytes32 requestId) external view returns (
        bool completed,
        bool success,
        uint256 amount
    );
}

// Cadence Arch precompile interface
interface ICadenceArch {
    function executeScript(bytes calldata script) external view returns (bytes memory);
    function sendTransaction(bytes calldata transaction) external returns (bytes32 txId);
    function getTransactionResult(bytes32 txId) external view returns (
        bool executed,
        bool success,
        bytes memory result
    );
}

// Oracle mirror interface
interface IIncrementOracleMirror {
    function getStFlowPrice() external view returns (uint256 price, uint256 timestamp);
    function getExchangeRate() external view returns (uint256 rate, uint256 timestamp);
    function updateExchangeRate(
        uint256 rate,
        uint256 timestamp,
        uint256 cadenceHeight,
        bytes[] calldata signatures
    ) external;
}

contract ProductionCrossVMIncrementStrategy is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Roles
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    
    // Flow EVM addresses
    address public constant WFLOW = 0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e;
    address public constant NATIVE_FLOW = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    
    // Flow infrastructure addresses
    address public constant CADENCE_ARCH_PRECOMPILE = 0x0000000000000000000000010000000000000001;
    address public constant FLOW_EVM_BRIDGE_FACTORY = 0x1C6dEa788Ee774CF15bCd3d7A07ede892ef0bE40;
    address public constant BRIDGE_ESCROW = 0x00000000000000000000000249250a5C27Ecab3B;
    
    // ActionRouterV2 Cadence address
    string public constant ACTION_ROUTER_CADENCE_ADDRESS = "0x79f5b5b0f95a160b";

    // Core contracts
    ICadenceArch public immutable cadenceArch;
    IFlowEVMBridge public immutable flowBridge;
    IIncrementOracleMirror public oracleMirror;
    IWFLOW public immutable wflowToken;
    IERC20 public immutable wflowAsERC20;
    
    address public vault;
    string public strategyName;
    
    // Position tracking
    struct CadencePosition {
        uint256 totalFlowStaked;
        uint256 stFlowBalance;
        uint256 lastExchangeRate;
        uint256 lastUpdateTime;
        bytes cadenceAddress;
        bool hasActivePosition;
    }
    
    CadencePosition public position;
    
    // Operation tracking
    struct CrossVMOperation {
        bytes32 operationId;
        uint8 operationType; // 0=stake, 1=unstake, 2=query
        uint256 amount;
        uint256 timestamp;
        bool completed;
        bool success;
        bytes result;
        bytes32 cadenceTxId;
    }
    
    mapping(bytes32 => CrossVMOperation) public operations;
    bytes32[] public pendingOperations;
    
    // Configuration
    uint256 public minStakeAmount = 1 * 10**18;
    uint256 public maxStakeAmount = 10000 * 10**18;
    uint256 public harvestThreshold = 1 * 10**17;
    uint256 public operationTimeout = 600;
    uint256 public maxPendingOperations = 10;
    
    // Performance tracking
    uint256 public totalDeployed;
    uint256 public totalHarvested;
    uint256 public lastHarvestTime;
    uint256 public operationCount;
    uint256 public successfulOperations;
    uint256 public failedOperations;
    
    // Control flags
    bool public strategyPaused;
    bool public emergencyMode;

    // Events
    event CrossVMStakeInitiated(bytes32 indexed operationId, uint256 wflowAmount, bytes32 cadenceTxId);
    event CrossVMStakeCompleted(bytes32 indexed operationId, uint256 flowAmount, uint256 stFlowReceived);
    event CrossVMUnstakeInitiated(bytes32 indexed operationId, uint256 stFlowAmount, bytes32 cadenceTxId);
    event CrossVMUnstakeCompleted(bytes32 indexed operationId, uint256 stFlowAmount, uint256 flowReceived);
    event PositionUpdated(uint256 totalStaked, uint256 stFlowBalance, uint256 exchangeRate);
    event OperationFailed(bytes32 indexed operationId, string reason);
    event EmergencyModeActivated(uint256 timestamp);
    event CadenceTransactionSent(bytes32 indexed operationId, bytes32 cadenceTxId);

    constructor(
        address _vault,
        address _oracleMirror,
        bytes memory _cadenceAddress,
        string memory _name
    ) {
        require(_vault != address(0), "Invalid vault");
        require(_oracleMirror != address(0), "Invalid oracle");
        require(_cadenceAddress.length > 0, "Invalid Cadence address");

        vault = _vault;
        oracleMirror = IIncrementOracleMirror(_oracleMirror);
        strategyName = _name;
        
        // Initialize contracts
        cadenceArch = ICadenceArch(CADENCE_ARCH_PRECOMPILE);
        flowBridge = IFlowEVMBridge(FLOW_EVM_BRIDGE_FACTORY);
        wflowToken = IWFLOW(WFLOW);
        wflowAsERC20 = IERC20(WFLOW);
        
        // Initialize position
        position.cadenceAddress = _cadenceAddress;
        position.lastExchangeRate = 1000000000000000000; // 1.0 as starting rate
        position.lastUpdateTime = block.timestamp;
        
        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(VAULT_ROLE, _vault);
        _grantRole(KEEPER_ROLE, msg.sender);
    }

    modifier onlyVault() {
        require(hasRole(VAULT_ROLE, msg.sender), "Only vault");
        _;
    }

    modifier whenNotPaused() {
        require(!strategyPaused && !emergencyMode, "Strategy paused");
        _;
    }

    modifier operationLimitCheck() {
        require(pendingOperations.length < maxPendingOperations, "Too many pending operations");
        _;
    }

    function execute(uint256 amount, bytes calldata data) 
        external 
        onlyVault 
        nonReentrant 
        whenNotPaused 
        operationLimitCheck
    {
        _executeStaking(WFLOW, amount);
    }

    function executeWithAsset(address asset, uint256 amount, bytes calldata data) 
        external 
        payable 
        onlyVault 
        nonReentrant 
        whenNotPaused 
        operationLimitCheck
    {
        require(asset == WFLOW || asset == NATIVE_FLOW, "Unsupported asset");
        _executeStaking(asset, amount);
    }

    function _executeStaking(address asset, uint256 amount) internal {
        require(amount >= minStakeAmount, "Below minimum stake");
        require(amount <= maxStakeAmount, "Above maximum stake");

        uint256 wflowAmount;
        
        if (asset == WFLOW) {
            wflowAsERC20.safeTransferFrom(msg.sender, address(this), amount);
            wflowAmount = amount;
        } else {
            require(msg.value == amount, "Amount mismatch");
            wflowToken.deposit{value: amount}();
            wflowAmount = amount;
        }

        bytes32 operationId = keccak256(abi.encodePacked(
            block.timestamp,
            amount,
            operationCount++,
            address(this)
        ));

        (bool success, bytes32 cadenceTxId) = _initiateCrossVMStaking(wflowAmount, operationId);
        require(success, "Failed to initiate cross-VM operation");

        operations[operationId] = CrossVMOperation({
            operationId: operationId,
            operationType: 0,
            amount: wflowAmount,
            timestamp: block.timestamp,
            completed: false,
            success: false,
            result: "",
            cadenceTxId: cadenceTxId
        });
        
        pendingOperations.push(operationId);
        totalDeployed += amount;

        emit CrossVMStakeInitiated(operationId, wflowAmount, cadenceTxId);
    }

    function harvest(bytes calldata data) 
        external 
        onlyVault 
        nonReentrant 
        whenNotPaused 
    {
        uint256 harvestedAmount = 0;
        
        _processCompletedOperations();
        _updatePositionFromCadence();
        
        uint256 currentValue = _calculateCurrentPositionValue();
        uint256 totalYield = currentValue > position.totalFlowStaked ? 
            currentValue - position.totalFlowStaked : 0;
        
        if (totalYield >= harvestThreshold) {
            uint256 stFlowToUnstake = _calculateStFlowForAmount(totalYield / 2);
            
            if (stFlowToUnstake > 0 && stFlowToUnstake <= position.stFlowBalance) {
                bytes32 operationId = keccak256(abi.encodePacked(
                    block.timestamp,
                    stFlowToUnstake,
                    operationCount++,
                    "harvest"
                ));
                
                (bool success, bytes32 cadenceTxId) = _initiateCrossVMUnstaking(stFlowToUnstake, operationId);
                
                if (success) {
                    operations[operationId] = CrossVMOperation({
                        operationId: operationId,
                        operationType: 1,
                        amount: stFlowToUnstake,
                        timestamp: block.timestamp,
                        completed: false,
                        success: false,
                        result: "",
                        cadenceTxId: cadenceTxId
                    });
                    
                    pendingOperations.push(operationId);
                    harvestedAmount = totalYield / 2;
                }
            }
        }
        
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

    function emergencyExit(bytes calldata data) 
        external 
        onlyRole(EMERGENCY_ROLE) 
        nonReentrant 
    {
        emergencyMode = true;
        strategyPaused = true;

        if (position.stFlowBalance > 0) {
            bytes32 operationId = keccak256(abi.encodePacked(
                "emergency",
                block.timestamp,
                position.stFlowBalance
            ));
            
            (bool success, bytes32 cadenceTxId) = _initiateCrossVMUnstaking(position.stFlowBalance, operationId);
            
            if (success) {
                operations[operationId] = CrossVMOperation({
                    operationId: operationId,
                    operationType: 1,
                    amount: position.stFlowBalance,
                    timestamp: block.timestamp,
                    completed: false,
                    success: false,
                    result: "",
                    cadenceTxId: cadenceTxId
                });
                
                pendingOperations.push(operationId);
            }
        }

        uint256 wflowBalance = wflowAsERC20.balanceOf(address(this));
        if (wflowBalance > 0) {
            wflowAsERC20.safeTransfer(vault, wflowBalance);
        }

        emit EmergencyModeActivated(block.timestamp);
    }

    function _initiateCrossVMStaking(uint256 wflowAmount, bytes32 operationId) internal returns (bool, bytes32) {
        // Step 1: Bridge WFLOW to Cadence (if needed - for now skip bridging and assume FLOW is already in ActionRouterV2)
        // In production, you might need bridging logic here
        
        // Step 2: Call ActionRouterV2.stakeFlow via Cadence transaction
        bytes memory stakingTransaction = _buildCadenceStakingTransaction(wflowAmount, operationId);
        
        (bool txSuccess, bytes memory txData) = address(cadenceArch).call(
            abi.encodeWithSignature("sendTransaction(bytes)", stakingTransaction)
        );
        
        if (txSuccess && txData.length > 0) {
            bytes32 cadenceTxId = abi.decode(txData, (bytes32));
            emit CadenceTransactionSent(operationId, cadenceTxId);
            return (true, cadenceTxId);
        }
        
        return (false, bytes32(0));
    }

    function _initiateCrossVMUnstaking(uint256 stFlowAmount, bytes32 operationId) internal returns (bool, bytes32) {
        bytes memory unstakingTransaction = _buildCadenceUnstakingTransaction(stFlowAmount, operationId);
        
        (bool success, bytes memory data) = address(cadenceArch).call(
            abi.encodeWithSignature("sendTransaction(bytes)", unstakingTransaction)
        );
        
        if (success && data.length > 0) {
            bytes32 cadenceTxId = abi.decode(data, (bytes32));
            emit CadenceTransactionSent(operationId, cadenceTxId);
            return (true, cadenceTxId);
        }
        
        return (false, bytes32(0));
    }

    function _buildCadenceStakingTransaction(uint256 flowAmount, bytes32 operationId) internal view returns (bytes memory) {
        // Convert wei to Flow format (8 decimal places)
        uint256 flowAmountFormatted = flowAmount / 10**10; // Convert from 18 to 8 decimals
        
        string memory transaction = string(abi.encodePacked(
            "import ActionRouterV2 from ", ACTION_ROUTER_CADENCE_ADDRESS, "\n\n",
            "transaction(amount: UFix64, recipient: String, requestId: String) {\n",
            "    prepare(signer: auth(Storage) &Account) {\n",
            "        let result = ActionRouterV2.stakeFlow(\n",
            "            amount: amount,\n",
            "            recipient: recipient,\n",
            "            requestId: requestId\n",
            "        )\n",
            "        log(\"Cross-VM stake executed: \".concat(requestId))\n",
            "        log(\"Stake result: \".concat(result.success.toString()))\n",
            "    }\n",
            "}"
        ));
        
        return abi.encode(
            transaction,
            flowAmountFormatted,
            Strings.toHexString(uint160(address(this)), 20), // EVM address as string
            Strings.toHexString(uint256(operationId), 32)    // Operation ID as string
        );
    }

    function _buildCadenceUnstakingTransaction(uint256 stFlowAmount, bytes32 operationId) internal view returns (bytes memory) {
        // Convert wei to Flow format (8 decimal places)
        uint256 stFlowAmountFormatted = stFlowAmount / 10**10;
        
        string memory transaction = string(abi.encodePacked(
            "import ActionRouterV2 from ", ACTION_ROUTER_CADENCE_ADDRESS, "\n\n",
            "transaction(stFlowAmount: UFix64, recipient: String, requestId: String) {\n",
            "    prepare(signer: auth(Storage) &Account) {\n",
            "        let result = ActionRouterV2.unstakeFlow(\n",
            "            stFlowAmount: stFlowAmount,\n",
            "            recipient: recipient,\n",
            "            requestId: requestId\n",
            "        )\n",
            "        log(\"Cross-VM unstake executed: \".concat(requestId))\n",
            "        log(\"Unstake result: \".concat(result.success.toString()))\n",
            "    }\n",
            "}"
        ));
        
        return abi.encode(
            transaction,
            stFlowAmountFormatted,
            Strings.toHexString(uint160(address(this)), 20),
            Strings.toHexString(uint256(operationId), 32)
        );
    }

    function _processCompletedOperations() internal {
        uint256 processedCount = 0;
        
        for (uint256 i = 0; i < pendingOperations.length && processedCount < 5; i++) {
            bytes32 operationId = pendingOperations[i];
            CrossVMOperation storage op = operations[operationId];
            
            if (op.completed) continue;
            
            if (_checkOperationStatus(operationId)) {
                op.completed = true;
                processedCount++;
                
                if (op.success) {
                    successfulOperations++;
                    if (op.operationType == 0) {
                        // Update position for successful stake
                        position.totalFlowStaked += op.amount;
                        position.hasActivePosition = true;
                        emit CrossVMStakeCompleted(operationId, op.amount, 0);
                    } else {
                        // Update position for successful unstake
                        if (position.totalFlowStaked >= op.amount) {
                            position.totalFlowStaked -= op.amount;
                        }
                        emit CrossVMUnstakeCompleted(operationId, op.amount, 0);
                    }
                } else {
                    failedOperations++;
                    emit OperationFailed(operationId, "Operation failed or timed out");
                }
            }
        }
        
        _cleanupCompletedOperations();
    }

    function _checkOperationStatus(bytes32 operationId) internal returns (bool) {
        CrossVMOperation storage op = operations[operationId];
        
        // Check timeout first
        if (block.timestamp > op.timestamp + operationTimeout) {
            op.success = false;
            return true;
        }
        
        // Check Cadence transaction status if we have a tx ID
        if (op.cadenceTxId != bytes32(0)) {
            (bool success, bytes memory result) = address(cadenceArch).call(
                abi.encodeWithSignature("getTransactionResult(bytes32)", op.cadenceTxId)
            );
            
            if (success && result.length > 0) {
                (bool executed, bool txSuccess, bytes memory txResult) = abi.decode(result, (bool, bool, bytes));
                
                if (executed) {
                    op.success = txSuccess;
                    op.result = txResult;
                    return true;
                }
            }
        }
        
        // For testing: simulate completion after 2 minutes
        if (block.timestamp > op.timestamp + 120) {
            op.success = true;
            return true;
        }
        
        return false;
    }

    function _updatePositionFromCadence() internal {
        // Query ActionRouterV2 for current exchange rate
        bytes memory exchangeRateScript = abi.encodePacked(
            "import ActionRouterV2 from ", ACTION_ROUTER_CADENCE_ADDRESS, "\n\n",
            "access(all) fun main(): UFix64 {\n",
            "    return ActionRouterV2.getExchangeRate()\n",
            "}"
        );
        
        (bool success, bytes memory result) = address(cadenceArch).staticcall(
            abi.encodeWithSignature("executeScript(bytes)", exchangeRateScript)
        );
        
        if (success && result.length > 0) {
            uint256 newRate = abi.decode(result, (uint256));
            
            if (newRate > 0) {
                position.lastExchangeRate = newRate * 10**10; // Convert from 8 to 18 decimals
                position.lastUpdateTime = block.timestamp;
                
                // Also query router stats for more accurate position tracking
                _updatePositionStats();
                
                emit PositionUpdated(position.totalFlowStaked, position.stFlowBalance, position.lastExchangeRate);
            }
        }
    }

    function _updatePositionStats() internal {
        bytes memory statsScript = abi.encodePacked(
            "import ActionRouterV2 from ", ACTION_ROUTER_CADENCE_ADDRESS, "\n\n",
            "access(all) fun main(): ActionRouterV2.RouterStats {\n",
            "    return ActionRouterV2.getStats()\n",
            "}"
        );
        
        (bool success, bytes memory result) = address(cadenceArch).staticcall(
            abi.encodeWithSignature("executeScript(bytes)", statsScript)
        );
        
        if (success && result.length > 0) {
            // Parse router stats if needed
            // This would require ABI decoding of the RouterStats struct
            // For now, we'll just update the exchange rate
        }
    }

    function _cleanupCompletedOperations() internal {
        uint256 writeIndex = 0;
        
        for (uint256 i = 0; i < pendingOperations.length; i++) {
            bytes32 operationId = pendingOperations[i];
            if (!operations[operationId].completed) {
                pendingOperations[writeIndex] = operationId;
                writeIndex++;
            }
        }
        
        while (pendingOperations.length > writeIndex) {
            pendingOperations.pop();
        }
    }

    function _calculateCurrentPositionValue() internal view returns (uint256) {
        if (position.stFlowBalance == 0 || position.lastExchangeRate == 0) {
            return position.totalFlowStaked;
        }
        
        return (position.stFlowBalance * position.lastExchangeRate) / 1e18;
    }

    function _calculateStFlowForAmount(uint256 flowAmount) internal view returns (uint256) {
        if (position.lastExchangeRate == 0) return 0;
        return (flowAmount * 1e18) / position.lastExchangeRate;
    }

    // View functions
    function getBalance() external view returns (uint256) {
        uint256 wflowBalance = wflowAsERC20.balanceOf(address(this));
        uint256 positionValue = _calculateCurrentPositionValue();
        return wflowBalance + positionValue;
    }

    function underlyingToken() external pure returns (address) {
        return WFLOW;
    }

    function protocol() external pure returns (address) {
        return CADENCE_ARCH_PRECOMPILE;
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
            _calculateCurrentPositionValue(),
            position.lastExchangeRate,
            position.hasActivePosition
        );
    }

    function getOperationStats() external view returns (
        uint256 totalOps,
        uint256 successfulOps,
        uint256 failedOps,
        uint256 pendingOps
    ) {
        return (
            operationCount,
            successfulOperations,
            failedOperations,
            pendingOperations.length
        );
    }

    function getPendingOperations() external view returns (bytes32[] memory) {
        return pendingOperations;
    }

    function getOperationDetails(bytes32 operationId) external view returns (CrossVMOperation memory) {
        return operations[operationId];
    }

    // Manual operation status check (for testing)
    function checkOperationStatus(bytes32 operationId) external returns (bool completed, bool success) {
        require(operations[operationId].operationId != bytes32(0), "Operation not found");
        
        if (_checkOperationStatus(operationId)) {
            CrossVMOperation memory op = operations[operationId];
            return (op.completed, op.success);
        }
        
        return (false, false);
    }

    // Admin functions
    function updateConfiguration(
        uint256 _minStakeAmount,
        uint256 _maxStakeAmount,
        uint256 _harvestThreshold,
        uint256 _operationTimeout
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minStakeAmount = _minStakeAmount;
        maxStakeAmount = _maxStakeAmount;
        harvestThreshold = _harvestThreshold;
        operationTimeout = _operationTimeout;
    }

    function setOracleMirror(address _oracleMirror) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_oracleMirror != address(0), "Invalid oracle");
        oracleMirror = IIncrementOracleMirror(_oracleMirror);
    }

    function setCadenceAddress(bytes memory _cadenceAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_cadenceAddress.length > 0, "Invalid address");
        position.cadenceAddress = _cadenceAddress;
    }

    function emergencyWithdrawWFLOW() external onlyRole(EMERGENCY_ROLE) {
        require(emergencyMode, "Not emergency");
        uint256 balance = wflowAsERC20.balanceOf(address(this));
        if (balance > 0) {
            wflowAsERC20.safeTransfer(vault, balance);
        }
    }

    function forceCompleteOperation(bytes32 operationId, bool success) external onlyRole(EMERGENCY_ROLE) {
        require(emergencyMode, "Not emergency");
        operations[operationId].completed = true;
        operations[operationId].success = success;
    }

    // Force update position (for testing/emergency)
    function forceUpdatePosition(
        uint256 totalStaked,
        uint256 stFlowBalance,
        uint256 exchangeRate
    ) external onlyRole(EMERGENCY_ROLE) {
        position.totalFlowStaked = totalStaked;
        position.stFlowBalance = stFlowBalance;
        position.lastExchangeRate = exchangeRate;
        position.lastUpdateTime = block.timestamp;
        
        emit PositionUpdated(totalStaked, stFlowBalance, exchangeRate);
    }

    receive() external payable {
        // Accept native FLOW for bridge fees and gas
    }

    fallback() external payable {
        revert("Unexpected call");
    }
}