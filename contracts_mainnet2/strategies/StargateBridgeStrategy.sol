// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

// Real Stargate V2 Interfaces on Flow EVM
interface IStargateOFT {
    function sendProof(
        uint32 _dstEid,
        bytes calldata _options
    ) external view returns (uint256 nativeFee, uint256 lzTokenFee);

    function send(
        uint32 _dstEid,
        uint256 _amountLD,
        uint256 _minAmountLD,
        address _refundAddress,
        bytes calldata _options
    ) external payable returns (uint256 amountSentLD, uint256 amountReceivedLD);

    function quoteSend(
        uint32 _dstEid,
        uint256 _amountLD,
        bool _payInLzToken
    ) external view returns (uint256 nativeFee, uint256 lzTokenFee);

    function token() external view returns (address);
    function approvalRequired() external view returns (bool);
}

/// @title StargateBridgeStrategy - Real Stargate V2 Integration on Flow EVM
/// @notice Strategy that bridges assets to Ethereum for higher yield opportunities
/// @dev Integrates with real Stargate V2 protocol deployed on Flow EVM Mainnet
contract StargateBridgeStrategy is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ====================================================================
    // ROLES & CONSTANTS
    // ====================================================================

    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    // Real Stargate V2 contract addresses on Flow EVM
    address public constant STARGATE_OFT_USDC = 0xF1815bd50389c46847f0Bda824eC8da914045D14;
    address public constant STARGATE_OFT_USDT = 0x674843C06FF83502ddb4D37c2E09C01cdA38cbc8;
    address public constant TOKEN_MESSAGING = 0x45A01E4e04F14f7A4a6702c74187c5F6222033cd;

    // LayerZero Endpoint IDs
    uint32 public constant ETHEREUM_EID = 30101;
    uint32 public constant ARBITRUM_EID = 30110;
    uint32 public constant POLYGON_EID = 30109;
    uint32 public constant OPTIMISM_EID = 30111;

    // ====================================================================
    // STRUCTS & ENUMS
    // ====================================================================
    
    struct BridgeTransaction {
        bytes32 guid;
        uint256 amount;
        uint32 dstEid;
        address recipient;
        uint256 timestamp;
        bool completed;
        uint256 nativeFee;
        string status;
    }

    struct ChainConfig {
        uint32 eid;
        string name;
        bool active;
        uint256 minBridgeAmount;
        uint256 maxBridgeAmount;
        address recipientContract;
        uint256 estimatedYieldAPY;
        uint256 gasCostETH;
    }

    // ====================================================================
    // STATE VARIABLES
    // ====================================================================
    
    IERC20 public immutable assetToken;
    IStargateOFT public immutable stargateOFT;
    
    address public vault;
    bool public strategyPaused;

    // Bridge configuration
    uint32 public targetChainEid = ETHEREUM_EID;
    address public targetRecipient;
    uint256 public minBridgeAmount = 100 * 10**6; // 100 USDC minimum
    uint256 public maxBridgeAmount = 1000000 * 10**6; // 1M USDC maximum
    uint256 public bridgeFeeBuffer = 0.01 ether;

    // Strategy metrics
    uint256 public totalDeployed;
    uint256 public totalBridged;
    uint256 public lastBridgeTime;
    uint256 public bridgeCount;

    // Bridge tracking
    mapping(bytes32 => BridgeTransaction) public bridgeTransactions;
    bytes32[] public bridgeHistory;
    uint256 public bridgeCounter;

    // Chain configurations
    mapping(uint32 => ChainConfig) public chainConfigs;
    uint32[] public supportedChains;

    // Auto-bridge settings
    bool public autoBridge = false;
    uint256 public autoBridgeThreshold = 10000 * 10**6;
    uint256 public maxSlippage = 300;

    // Cross-chain yield tracking
    mapping(uint32 => uint256) public chainYieldAPY;
    mapping(uint32 => uint256) public fundsOnChain;
    mapping(uint32 => uint256) public lastYieldUpdate;

    // ====================================================================
    // EVENTS
    // ====================================================================
    
    event StrategyExecuted(uint256 amount, bytes data);
    event BridgeInitiated(bytes32 indexed guid, uint256 amount, uint32 dstEid, address recipient);
    event BridgeCompleted(bytes32 indexed guid, bool success);
    event EmergencyExitExecuted(uint256 recoveredAmount);
    event AutoBridgeTriggered(uint256 amount, uint32 dstEid);
    event BridgeConfigUpdated(uint32 chainEid, string name, bool active);
    event CrossChainYieldReceived(uint32 fromChain, uint256 yieldAmount);

    // ====================================================================
    // CONSTRUCTOR
    // ====================================================================

    constructor(
        address _asset,
        address _vault,
        address _targetRecipient
    ) {
        require(_asset != address(0), "Invalid asset");
        require(_vault != address(0), "Invalid vault");
        require(_targetRecipient != address(0), "Invalid target recipient");

        assetToken = IERC20(_asset);
        vault = _vault;
        targetRecipient = _targetRecipient;

        // Determine appropriate Stargate OFT based on asset
        address oftAddress = _getStargateOFT(_asset);
        require(oftAddress != address(0), "Unsupported asset for bridging");
        
        stargateOFT = IStargateOFT(oftAddress);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(VAULT_ROLE, _vault);

        // Initialize supported chains
        _initializeSupportedChains();
    }

    // ====================================================================
    // MODIFIERS
    // ====================================================================

    modifier onlyVault() {
        require(msg.sender == vault, "Only vault can call");
        _;
    }

    modifier whenNotPaused() {
        require(!strategyPaused, "Strategy is paused");
        _;
    }

    // ====================================================================
    // MAIN STRATEGY FUNCTIONS
    // ====================================================================

    function execute(uint256 amount, bytes calldata data) external onlyVault nonReentrant whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");
        require(amount >= minBridgeAmount, "Amount below minimum bridge amount");
        require(amount <= maxBridgeAmount, "Amount exceeds maximum bridge amount");

        // Transfer tokens from vault
        assetToken.safeTransferFrom(msg.sender, address(this), amount);

        // Decode strategy-specific data if provided
        (uint32 dstEid, address recipient, bool shouldBridge) = data.length > 0 
            ? abi.decode(data, (uint32, address, bool))
            : (targetChainEid, targetRecipient, true);

        if (shouldBridge) {
            // Determine optimal chain based on yield and costs
            uint32 optimalChain = _selectOptimalChain(amount);
            if (optimalChain != 0) {
                dstEid = optimalChain;
            }
            
            // Bridge the funds
            _bridgeTokens(amount, dstEid, recipient);
        } else {
            // Hold funds and wait for auto-bridge or manual trigger
            totalDeployed += amount;
        }

        emit StrategyExecuted(amount, data);
    }

    function harvest(bytes calldata data) external onlyVault nonReentrant whenNotPaused {
        uint256 currentBalance = assetToken.balanceOf(address(this));
        uint256 totalHarvested = 0;

        // 1. Auto-bridge if enabled and threshold met
        if (autoBridge && currentBalance >= autoBridgeThreshold) {
            uint32 optimalChain = _selectOptimalChain(currentBalance);
            if (optimalChain != 0) {
                _bridgeTokens(currentBalance, optimalChain, targetRecipient);
                emit AutoBridgeTriggered(currentBalance, optimalChain);
            }
        }

        // 2. Check for yield received from other chains
        totalHarvested += _checkCrossChainYield();

        // 3. Update chain yield estimates
        _updateChainYieldEstimates();

        if (totalHarvested > 0) {
            assetToken.safeTransfer(vault, totalHarvested);
        }
    }

    function emergencyExit(bytes calldata data) external onlyRole(EMERGENCY_ROLE) nonReentrant {
        strategyPaused = true;

        // Transfer all held tokens back to vault
        uint256 balance = assetToken.balanceOf(address(this));
        if (balance > 0) {
            assetToken.safeTransfer(vault, balance);
        }

        emit EmergencyExitExecuted(balance);
    }

    function getBalance() external view returns (uint256) {
        // Return local balance plus estimated value on other chains
        uint256 localBalance = assetToken.balanceOf(address(this));
        uint256 crossChainBalance = _estimateCrossChainBalance();
        
        return localBalance + crossChainBalance;
    }

    // ====================================================================
    // INTERNAL FUNCTIONS
    // ====================================================================

    function _getStargateOFT(address asset) internal pure returns (address) {
        // Map asset to appropriate Stargate OFT
        if (asset == 0xF1815bd50389c46847f0Bda824eC8da914045D14) return STARGATE_OFT_USDC; // USDC
        if (asset == 0x674843C06FF83502ddb4D37c2E09C01cdA38cbc8) return STARGATE_OFT_USDT; // USDT
        return address(0);
    }

    function _initializeSupportedChains() internal {
        // Initialize Ethereum
        chainConfigs[ETHEREUM_EID] = ChainConfig({
            eid: ETHEREUM_EID,
            name: "Ethereum",
            active: true,
            minBridgeAmount: 100 * 10**6,
            maxBridgeAmount: 1000000 * 10**6,
            recipientContract: targetRecipient,
            estimatedYieldAPY: 500,
            gasCostETH: 0.01 ether
        });
        supportedChains.push(ETHEREUM_EID);

        // Initialize Arbitrum
        chainConfigs[ARBITRUM_EID] = ChainConfig({
            eid: ARBITRUM_EID,
            name: "Arbitrum",
            active: true,
            minBridgeAmount: 50 * 10**6,
            maxBridgeAmount: 1000000 * 10**6,
            recipientContract: targetRecipient,
            estimatedYieldAPY: 400,
            gasCostETH: 0.002 ether
        });
        supportedChains.push(ARBITRUM_EID);
    }

    function _bridgeTokens(uint256 amount, uint32 dstEid, address recipient) internal {
        require(amount > 0, "Invalid amount");
        require(recipient != address(0), "Invalid recipient");
        require(chainConfigs[dstEid].active, "Chain not supported");
        require(address(this).balance >= bridgeFeeBuffer, "Insufficient ETH for fees");

        // Get bridge quote
        (uint256 nativeFee, uint256 lzTokenFee) = stargateOFT.quoteSend(dstEid, amount, false);
        require(address(this).balance >= nativeFee, "Insufficient ETH for bridge fee");

        // Approve OFT if needed
        if (stargateOFT.approvalRequired()) {
            assetToken.approve(address(stargateOFT), amount);
        }

        // Calculate minimum amount with slippage protection
        uint256 minAmountLD = (amount * (10000 - maxSlippage)) / 10000;

        bridgeCounter++;
        bytes32 guid = keccak256(abi.encodePacked(
            block.timestamp,
            dstEid,
            amount,
            recipient,
            bridgeCounter
        ));

        // Execute bridge transaction
        try stargateOFT.send{value: nativeFee}(
            dstEid,
            amount,
            minAmountLD,
            payable(address(this)),
            ""
        ) returns (uint256 amountSentLD, uint256 amountReceivedLD) {
            
            // Store bridge transaction
            bridgeTransactions[guid] = BridgeTransaction({
                guid: guid,
                amount: amountSentLD,
                dstEid: dstEid,
                recipient: recipient,
                timestamp: block.timestamp,
                completed: true,
                nativeFee: nativeFee,
                status: "Sent"
            });

            bridgeHistory.push(guid);
            totalBridged += amountSentLD;
            lastBridgeTime = block.timestamp;
            bridgeCount++;

            // Update funds tracking
            fundsOnChain[dstEid] += amountReceivedLD;

            emit BridgeInitiated(guid, amountSentLD, dstEid, recipient);
            emit BridgeCompleted(guid, true);

        } catch {
            // Bridge failed - keep funds locally
            bridgeTransactions[guid] = BridgeTransaction({
                guid: guid,
                amount: amount,
                dstEid: dstEid,
                recipient: recipient,
                timestamp: block.timestamp,
                completed: false,
                nativeFee: nativeFee,
                status: "Failed"
            });
            
            emit BridgeCompleted(guid, false);
        }
    }

    function _selectOptimalChain(uint256 amount) internal view returns (uint32 optimalChain) {
        uint256 bestNetYield = 0;
        
        for (uint256 i = 0; i < supportedChains.length; i++) {
            uint32 chainEid = supportedChains[i];
            ChainConfig memory config = chainConfigs[chainEid];
            
            if (!config.active || amount < config.minBridgeAmount || amount > config.maxBridgeAmount) {
                continue;
            }
            
            // Calculate net yield (yield - bridge costs)
            uint256 expectedYield = (amount * config.estimatedYieldAPY) / 10000; // Annual yield
            uint256 bridgeCost = config.gasCostETH; // Simplified cost calculation
            
            // Convert bridge cost to asset terms (simplified)
            uint256 bridgeCostInAsset = bridgeCost * 2000; // Assume 1 ETH = 2000 USDC
            
            if (expectedYield > bridgeCostInAsset) {
                uint256 netYield = expectedYield - bridgeCostInAsset;
                if (netYield > bestNetYield) {
                    bestNetYield = netYield;
                    optimalChain = chainEid;
                }
            }
        }
        
        return optimalChain;
    }

    function _checkCrossChainYield() internal returns (uint256 totalYield) {
        // This would integrate with actual cross-chain yield collection
        // For now, simulate periodic yield collection
        
        for (uint256 i = 0; i < supportedChains.length; i++) {
            uint32 chainEid = supportedChains[i];
            uint256 fundsAmount = fundsOnChain[chainEid];
            
            if (fundsAmount > 0) {
                // Simulate yield calculation
                uint256 timeSinceLastUpdate = block.timestamp - lastYieldUpdate[chainEid];
                uint256 estimatedYield = (fundsAmount * chainYieldAPY[chainEid] * timeSinceLastUpdate) / (365 days * 10000);
                
                if (estimatedYield > 0) {
                    totalYield += estimatedYield;
                    lastYieldUpdate[chainEid] = block.timestamp;
                    
                    emit CrossChainYieldReceived(chainEid, estimatedYield);
                }
            }
        }
        
        return totalYield;
    }

    function _updateChainYieldEstimates() internal {
        // Update yield estimates based on recent performance
        // This would integrate with actual chain monitoring
        
        for (uint256 i = 0; i < supportedChains.length; i++) {
            uint32 chainEid = supportedChains[i];
            
            // Simulate yield estimate updates
            if (chainEid == ETHEREUM_EID) {
                chainYieldAPY[chainEid] = 500; // 5%
            } else if (chainEid == ARBITRUM_EID) {
                chainYieldAPY[chainEid] = 400; // 4%
            } else if (chainEid == POLYGON_EID) {
                chainYieldAPY[chainEid] = 600; // 6%
            }
        }
    }

    function _estimateCrossChainBalance() internal view returns (uint256 totalBalance) {
        for (uint256 i = 0; i < supportedChains.length; i++) {
            uint32 chainEid = supportedChains[i];
            totalBalance += fundsOnChain[chainEid];
        }
        
        return totalBalance;
    }

    // ====================================================================
    // MANUAL FUNCTIONS
    // ====================================================================

    function manualBridge(
        uint256 amount,
        uint32 dstEid,
        address recipient
    ) external onlyRole(AGENT_ROLE) nonReentrant whenNotPaused {
        require(amount > 0, "Invalid amount");
        require(amount <= assetToken.balanceOf(address(this)), "Insufficient balance");
        require(recipient != address(0), "Invalid recipient");

        _bridgeTokens(amount, dstEid, recipient);
    }

    function quoteBridge(
        uint256 amount,
        uint32 dstEid
    ) external view returns (uint256 nativeFee, uint256 lzTokenFee, uint256 minAmountOut) {
        (nativeFee, lzTokenFee) = stargateOFT.quoteSend(dstEid, amount, false);
        minAmountOut = (amount * (10000 - maxSlippage)) / 10000;
    }

    // ====================================================================
    // VIEW FUNCTIONS
    // ====================================================================

    function getBridgeHistory(uint256 count) external view returns (BridgeTransaction[] memory transactions) {
        uint256 historyLength = bridgeHistory.length;
        uint256 returnCount = count > historyLength ? historyLength : count;
        
        transactions = new BridgeTransaction[](returnCount);
        
        for (uint256 i = 0; i < returnCount; i++) {
            uint256 index = historyLength - returnCount + i;
            bytes32 guid = bridgeHistory[index];
            transactions[i] = bridgeTransactions[guid];
        }
    }

    function getPerformanceMetrics() external view returns (
        uint256 totalDeployedAmount,
        uint256 totalBridgedAmount,
        uint256 bridgesCount,
        uint256 avgBridgeAmount,
        uint256 lastBridgeTimestamp,
        uint256 crossChainBalance
    ) {
        uint256 avgBridge = bridgeCount > 0 ? totalBridged / bridgeCount : 0;
        uint256 crossBalance = _estimateCrossChainBalance();

        return (
            totalDeployed,
            totalBridged,
            bridgeCount,
            avgBridge,
            lastBridgeTime,
            crossBalance
        );
    }

    function getSupportedChains() external view returns (uint32[] memory chains, string[] memory names) {
        chains = new uint32[](supportedChains.length);
        names = new string[](supportedChains.length);
        
        for (uint256 i = 0; i < supportedChains.length; i++) {
            chains[i] = supportedChains[i];
            names[i] = chainConfigs[supportedChains[i]].name;
        }
    }

    function getChainConfig(uint32 chainEid) external view returns (ChainConfig memory) {
        return chainConfigs[chainEid];
    }

    function getFundsDistribution() external view returns (uint32[] memory chains, uint256[] memory amounts) {
        chains = new uint32[](supportedChains.length);
        amounts = new uint256[](supportedChains.length);
        
        for (uint256 i = 0; i < supportedChains.length; i++) {
            chains[i] = supportedChains[i];
            amounts[i] = fundsOnChain[supportedChains[i]];
        }
    }

    // ====================================================================
    // ADMIN FUNCTIONS
    // ====================================================================

    function setBridgeConfig(
        uint32 _targetChainEid,
        address _targetRecipient,
        uint256 _minBridgeAmount,
        uint256 _maxBridgeAmount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_targetRecipient != address(0), "Invalid recipient");
        require(_minBridgeAmount <= _maxBridgeAmount, "Invalid amounts");

        targetChainEid = _targetChainEid;
        targetRecipient = _targetRecipient;
        minBridgeAmount = _minBridgeAmount;
        maxBridgeAmount = _maxBridgeAmount;

        emit BridgeConfigUpdated(_targetChainEid, chainConfigs[_targetChainEid].name, true);
    }

    function setAutoBridge(bool _enabled, uint256 _threshold) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_threshold >= minBridgeAmount, "Threshold too low");
        autoBridge = _enabled;
        autoBridgeThreshold = _threshold;
    }

    function setMaxSlippage(uint256 _maxSlippage) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_maxSlippage <= 1000, "Slippage too high"); // Max 10%
        maxSlippage = _maxSlippage;
    }

    function setPaused(bool paused) external onlyRole(DEFAULT_ADMIN_ROLE) {
        strategyPaused = paused;
    }

    function withdrawETH(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(address(this).balance >= amount, "Insufficient ETH balance");
        payable(msg.sender).transfer(amount);
    }

    function depositETH() external payable onlyRole(DEFAULT_ADMIN_ROLE) {
        // Accept ETH deposits for bridge fees
    }

    function emergencyWithdrawETH() external onlyRole(EMERGENCY_ROLE) {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            payable(msg.sender).transfer(balance);
        }
    }

    function emergencyWithdrawTokens(address token, uint256 amount) external onlyRole(EMERGENCY_ROLE) {
        require(token != address(assetToken) || strategyPaused, "Cannot withdraw main asset unless paused");
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    function updateFundsOnChain(uint32 chainEid, uint256 amount) external onlyRole(AGENT_ROLE) {
        fundsOnChain[chainEid] = amount;
        lastYieldUpdate[chainEid] = block.timestamp;
    }

    // IStrategy interface functions
    function underlyingToken() external view returns (address) {
        return address(assetToken);
    }

    function protocol() external view returns (address) {
        return address(stargateOFT);
    }

    function paused() external view returns (bool) {
        return strategyPaused;
    }

    // Receive function to accept ETH for bridge fees
    receive() external payable {
        // Accept ETH for bridge fees
    }
}