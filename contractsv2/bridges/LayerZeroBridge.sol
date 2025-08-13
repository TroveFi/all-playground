// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import "../interfaces/IBridge.sol";

/// @title LayerZeroBridge - Enhanced Cross-Chain Bridge
/// @notice Advanced bridge with automatic optimal strategy deployment on destination chains
contract LayerZeroBridge is IBridge, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant BRIDGE_ADMIN_ROLE = keccak256("BRIDGE_ADMIN_ROLE");
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");
    bytes32 public constant STRATEGY_DEPLOYER_ROLE = keccak256("STRATEGY_DEPLOYER_ROLE");

    // Chain IDs for different networks
    uint16 public constant ETHEREUM_CHAIN_ID = 101;
    uint16 public constant ARBITRUM_CHAIN_ID = 110;
    uint16 public constant POLYGON_CHAIN_ID = 109;
    uint16 public constant OPTIMISM_CHAIN_ID = 111;
    uint16 public constant ETHERLINK_CHAIN_ID = 30302;

    struct ChainConfig {
        uint16 chainId;
        address remoteContract;
        bool active;
        uint256 minAmount;
        uint256 maxAmount;
        uint256 fee;
    }

    struct BridgeRequest {
        bytes32 id;
        uint16 srcChainId;
        uint16 dstChainId;
        address token;
        uint256 amount;
        address sender;
        address recipient;
        bytes data;
        uint256 timestamp;
        bool completed;
    }

    struct AutoDeployConfig {
        bool enabled;
        uint256 minAmount;
        uint256 maxRiskTolerance;
        uint256 defaultRiskTolerance;
        bool allowCrossChainRebalancing;
    }

    // Mock LayerZero interface for demonstration
    interface ILayerZeroEndpoint {
        function send(
            uint16 _dstChainId,
            bytes calldata _destination,
            bytes calldata _payload,
            address payable _refundAddress,
            address _zroPaymentAddress,
            bytes calldata _adapterParams
        ) external payable;

        function estimateFees(
            uint16 _dstChainId,
            address _userApplication,
            bytes calldata _payload,
            bool _payInZRO,
            bytes calldata _adapterParam
        ) external view returns (uint256 nativeFee, uint256 zroFee);
    }

    // State variables
    address public vault;
    ILayerZeroEndpoint public layerZeroEndpoint;
    
    mapping(bytes32 => BridgeRequest) public bridgeRequests;
    mapping(uint16 => ChainConfig) public chainConfigs;
    mapping(address => bool) public supportedTokens;
    mapping(uint16 => bytes) public trustedRemotes;
    
    AutoDeployConfig public autoDeployConfig;
    mapping(bytes32 => uint256) public deployedAmounts;
    mapping(uint16 => uint256) public chainDeployments;
    
    uint256 public bridgeNonce;
    bool public paused;

    // Events
    event BridgeInitiated(
        bytes32 indexed requestId,
        uint16 indexed dstChainId,
        address indexed token,
        uint256 amount,
        address sender,
        address recipient
    );
    
    event BridgeCompleted(bytes32 indexed requestId, bool success, uint256 amount);
    event AutoStrategyDeployment(bytes32 indexed requestId, uint16 chainId, address strategy, uint256 amount);
    event OptimalStrategySelected(bytes32 indexed requestId, bytes32 strategyHash, uint256 expectedAPY);

    // Errors
    error BridgePaused();
    error ChainNotSupported();
    error TokenNotSupported();
    error InsufficientAmount();
    error ExcessiveAmount();
    error InsufficientFee();
    error InvalidRecipient();

    constructor(
        address _layerZeroEndpoint,
        address _vault,
        address _admin
    ) {
        require(_layerZeroEndpoint != address(0), "Invalid LayerZero endpoint");
        require(_vault != address(0), "Invalid vault");
        require(_admin != address(0), "Invalid admin");

        layerZeroEndpoint = ILayerZeroEndpoint(_layerZeroEndpoint);
        vault = _vault;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(BRIDGE_ADMIN_ROLE, _admin);
        _grantRole(VAULT_ROLE, _vault);
        _grantRole(STRATEGY_DEPLOYER_ROLE, _admin);

        // Initialize auto-deployment configuration
        autoDeployConfig = AutoDeployConfig({
            enabled: true,
            minAmount: 100 * 10**6, // 100 USDC minimum
            maxRiskTolerance: 6000, // 60% max risk
            defaultRiskTolerance: 5000, // 50% default risk
            allowCrossChainRebalancing: true
        });

        _initializeChainConfigs();
    }

    function _initializeChainConfigs() internal {
        // Ethereum - Premier DeFi ecosystem
        chainConfigs[ETHEREUM_CHAIN_ID] = ChainConfig({
            chainId: ETHEREUM_CHAIN_ID,
            remoteContract: address(0),
            active: false,
            minAmount: 1000 * 10**6, // 1000 USDC
            maxAmount: 10000000 * 10**6, // 10M USDC
            fee: 0.02 ether
        });

        // Arbitrum - L2 with lower fees
        chainConfigs[ARBITRUM_CHAIN_ID] = ChainConfig({
            chainId: ARBITRUM_CHAIN_ID,
            remoteContract: address(0),
            active: false,
            minAmount: 100 * 10**6, // 100 USDC
            maxAmount: 5000000 * 10**6, // 5M USDC
            fee: 0.005 ether
        });
    }

    function bridgeToOptimalStrategy(
        uint256 amount,
        uint256 maxRiskTolerance,
        bytes calldata data
    ) external payable onlyRole(VAULT_ROLE) nonReentrant returns (bytes32 requestId) {
        require(!paused, "Bridge paused");
        require(amount >= autoDeployConfig.minAmount, "Amount below minimum");
        require(maxRiskTolerance <= 10000, "Invalid risk tolerance");

        // Generate unique request ID
        requestId = keccak256(abi.encodePacked(
            block.timestamp,
            bridgeNonce++,
            msg.sender,
            amount
        ));

        // For demonstration, assume we're bridging to Ethereum
        uint16 dstChainId = ETHEREUM_CHAIN_ID;
        ChainConfig memory config = chainConfigs[dstChainId];
        require(config.active, "Chain not supported");
        require(msg.value >= config.fee, "Insufficient bridge fee");

        // Mock strategy selection - in real implementation would use strategy registry
        bytes32 mockStrategyHash = keccak256("ethereum_aave_strategy");
        uint256 expectedReturn = 500; // 5% APY

        // Store bridge request
        bridgeRequests[requestId] = BridgeRequest({
            id: requestId,
            srcChainId: ETHERLINK_CHAIN_ID,
            dstChainId: dstChainId,
            token: address(0), // Would be the actual token
            amount: amount,
            sender: msg.sender,
            recipient: vault,
            data: abi.encode(mockStrategyHash, expectedReturn, maxRiskTolerance, data),
            timestamp: block.timestamp,
            completed: false
        });

        // Mock LayerZero bridge execution
        bytes memory payload = abi.encode(
            requestId,
            amount,
            mockStrategyHash,
            expectedReturn,
            maxRiskTolerance
        );

        // In real implementation, would call LayerZero
        // layerZeroEndpoint.send{value: msg.value}(...);

        chainDeployments[dstChainId] += amount;
        
        emit BridgeInitiated(requestId, dstChainId, address(0), amount, msg.sender, vault);
        emit OptimalStrategySelected(requestId, mockStrategyHash, expectedReturn);
        
        return requestId;
    }

    function bridgeToken(
        uint16 dstChainId,
        address token,
        uint256 amount,
        address recipient,
        bytes calldata data
    ) external payable override onlyRole(VAULT_ROLE) nonReentrant returns (bytes32 requestId) {
        ChainConfig memory config = chainConfigs[dstChainId];
        
        if (!config.active) revert ChainNotSupported();
        if (!supportedTokens[token]) revert TokenNotSupported();
        if (amount < config.minAmount) revert InsufficientAmount();
        if (amount > config.maxAmount) revert ExcessiveAmount();
        if (recipient == address(0)) revert InvalidRecipient();
        if (msg.value < config.fee) revert InsufficientFee();

        requestId = keccak256(abi.encodePacked(
            block.timestamp,
            bridgeNonce++,
            msg.sender,
            dstChainId,
            token,
            amount
        ));

        bridgeRequests[requestId] = BridgeRequest({
            id: requestId,
            srcChainId: ETHERLINK_CHAIN_ID,
            dstChainId: dstChainId,
            token: token,
            amount: amount,
            sender: msg.sender,
            recipient: recipient,
            data: data,
            timestamp: block.timestamp,
            completed: false
        });

        // Mock bridge execution - in real implementation would use LayerZero
        emit BridgeInitiated(requestId, dstChainId, token, amount, msg.sender, recipient);
        
        return requestId;
    }

    function getBridgeFee(uint16 dstChainId, uint256 amount) external view override returns (uint256 fee) {
        ChainConfig memory config = chainConfigs[dstChainId];
        if (!config.active) return 0;
        return config.fee;
    }

    function isChainSupported(uint16 chainId) external view override returns (bool supported) {
        return chainConfigs[chainId].active;
    }

    function isTokenSupported(address token) external view returns (bool supported) {
        return supportedTokens[token];
    }

    function getBridgeRequest(bytes32 requestId) external view returns (BridgeRequest memory request) {
        return bridgeRequests[requestId];
    }

    // Admin functions
    function configureChain(
        uint16 chainId,
        address remoteContract,
        bool active,
        uint256 minAmount,
        uint256 maxAmount,
        uint256 fee
    ) external onlyRole(BRIDGE_ADMIN_ROLE) {
        chainConfigs[chainId] = ChainConfig({
            chainId: chainId,
            remoteContract: remoteContract,
            active: active,
            minAmount: minAmount,
            maxAmount: maxAmount,
            fee: fee
        });
    }

    function configureSupportedToken(address token, bool active) external onlyRole(BRIDGE_ADMIN_ROLE) {
        supportedTokens[token] = active;
    }

    function setTrustedRemote(uint16 _chainId, bytes calldata _remoteAddress) external onlyRole(BRIDGE_ADMIN_ROLE) {
        trustedRemotes[_chainId] = _remoteAddress;
    }

    function setPaused(bool _paused) external onlyRole(BRIDGE_ADMIN_ROLE) {
        paused = _paused;
    }

    function setVault(address _newVault) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_newVault != address(0), "Invalid vault");
        
        if (vault != address(0)) {
            _revokeRole(VAULT_ROLE, vault);
        }
        
        vault = _newVault;
        _grantRole(VAULT_ROLE, _newVault);
    }

    function emergencyWithdraw(
        address token,
        uint256 amount,
        address to
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to != address(0), "Invalid recipient");
        IERC20(token).safeTransfer(to, amount);
    }

    function withdrawNative(uint256 amount, address to) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to != address(0), "Invalid recipient");
        (bool success, ) = to.call{value: amount}("");
        require(success, "Transfer failed");
    }

    receive() external payable {}
}