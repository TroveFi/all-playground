// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./BaseStrategy.sol";

// Celer Network Bridge Interfaces (Real cross-chain bridge on Flow)
interface ICelerBridge {
    function send(
        address receiver,
        address token,
        uint256 amount,
        uint64 dstChainId,
        uint64 nonce,
        uint32 maxSlippage
    ) external;

    function sendNative(
        address receiver,
        uint256 amount,
        uint64 dstChainId,
        uint64 nonce,
        uint32 maxSlippage
    ) external payable;

    function calcFee(
        address token,
        uint256 amount,
        uint64 dstChainId
    ) external view returns (uint256 fee);

    function getMinSend(address token) external view returns (uint256);
    function getMaxSend(address token) external view returns (uint256);
}

// External protocol interfaces for cross-chain opportunities
interface IEthereumProtocol {
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function getAPY() external view returns (uint256);
    function getBalance(address account) external view returns (uint256);
}

/// @title FlowCelerBridgeStrategy - Cross-chain yield farming via Celer
/// @notice Bridge assets to higher-yield opportunities on other chains via Celer Network
contract FlowCelerBridgeStrategy is BaseStrategy {
    using SafeERC20 for IERC20;

    // Celer Bridge contract address on Flow (you'll need to get the real address)
    address public constant CELER_BRIDGE = address(0); // TODO: Get real Celer bridge address
    
    ICelerBridge public immutable celerBridge;
    
    // Cross-chain strategy configuration
    struct CrossChainOpportunity {
        uint64 chainId; // Target chain ID
        address targetProtocol; // Protocol address on target chain
        uint256 expectedAPY; // Expected APY (basis points)
        uint256 bridgeFee; // Bridge fee
        uint256 minAmount; // Minimum amount to bridge
        uint256 maxAmount; // Maximum amount to bridge
        bool active; // Whether this opportunity is active
        string protocolName; // e.g., "ethereum_aave", "arbitrum_compound"
    }
    
    mapping(uint64 => CrossChainOpportunity) public crossChainOpportunities;
    uint64[] public supportedChains;
    
    // Bridge tracking
    mapping(bytes32 => uint256) public bridgeRequests; // Track outbound bridges
    mapping(bytes32 => uint256) public bridgeReturns; // Track return bridges
    uint256 public totalBridgedOut;
    uint256 public totalBridgedBack;
    uint256 public bridgeNonce;
    
    // Strategy state
    uint64 public currentTargetChain;
    uint256 public deployedOnTargetChain;
    bool public crossChainActive = false;
    
    event CrossChainBridgeInitiated(uint64 indexed chainId, uint256 amount, bytes32 requestId);
    event CrossChainBridgeCompleted(uint64 indexed chainId, uint256 amount, bytes32 requestId);
    event CrossChainYieldHarvested(uint64 indexed chainId, uint256 yield);
    event OpportunityAdded(uint64 indexed chainId, string protocolName, uint256 expectedAPY);

    constructor(
        address _asset,
        address _vault,
        string memory _name
    ) BaseStrategy(_asset, CELER_BRIDGE, _vault, _name) {
        celerBridge = ICelerBridge(CELER_BRIDGE);
        
        // Initialize with some cross-chain opportunities
        _initializeCrossChainOpportunities();
    }

    function _initializeCrossChainOpportunities() internal {
        // Ethereum opportunities
        crossChainOpportunities[1] = CrossChainOpportunity({
            chainId: 1, // Ethereum mainnet
            targetProtocol: address(0), // Aave/Compound address on Ethereum
            expectedAPY: 450, // 4.5% APY
            bridgeFee: 0.01 ether,
            minAmount: 1000 * 10**6, // 1000 USDC
            maxAmount: 1000000 * 10**6, // 1M USDC
            active: false, // Set to true when protocols are integrated
            protocolName: "ethereum_aave"
        });

        // Arbitrum opportunities
        crossChainOpportunities[42161] = CrossChainOpportunity({
            chainId: 42161, // Arbitrum
            targetProtocol: address(0), // Protocol address on Arbitrum
            expectedAPY: 520, // 5.2% APY
            bridgeFee: 0.005 ether,
            minAmount: 100 * 10**6, // 100 USDC
            maxAmount: 500000 * 10**6, // 500K USDC
            active: false,
            protocolName: "arbitrum_compound"
        });

        supportedChains.push(1);
        supportedChains.push(42161);
    }

    function _executeStrategy(uint256 amount, bytes calldata data) internal override {
        // Decode target chain if provided
        uint64 targetChain = data.length > 0 ? abi.decode(data, (uint64)) : _getBestCrossChainOpportunity(amount);
        
        if (targetChain == 0) {
            revert("No suitable cross-chain opportunity found");
        }
        
        _bridgeToTargetChain(targetChain, amount);
    }

    function _bridgeToTargetChain(uint64 chainId, uint256 amount) internal {
        CrossChainOpportunity memory opportunity = crossChainOpportunities[chainId];
        
        require(opportunity.active, "Target chain not active");
        require(amount >= opportunity.minAmount, "Amount below minimum");
        require(amount <= opportunity.maxAmount, "Amount above maximum");
        
        // Calculate bridge fee
        uint256 bridgeFee = celerBridge.calcFee(address(assetToken), amount, chainId);
        require(address(this).balance >= bridgeFee, "Insufficient ETH for bridge fee");
        
        // Generate bridge request ID
        bytes32 requestId = keccak256(abi.encodePacked(
            chainId,
            amount,
            block.timestamp,
            bridgeNonce++
        ));
        
        // Approve and bridge tokens
        assetToken.approve(address(celerBridge), amount);
        
        try celerBridge.send(
            opportunity.targetProtocol, // Receiver on target chain
            address(assetToken),
            amount,
            chainId,
            uint64(bridgeNonce),
            1000 // 1% max slippage
        ) {
            // Bridge initiated successfully
            bridgeRequests[requestId] = amount;
            totalBridgedOut += amount;
            currentTargetChain = chainId;
            deployedOnTargetChain += amount;
            crossChainActive = true;
            
            emit CrossChainBridgeInitiated(chainId, amount, requestId);
        } catch {
            revert("Bridge initiation failed");
        }
    }

    function _harvestRewards(bytes calldata) internal override {
        if (!crossChainActive) return;
        
        // For cross-chain strategies, harvesting would typically involve:
        // 1. Checking yield on target chain (via oracle or bridge callback)
        // 2. Bridging back yields if profitable
        // 3. Or leaving funds deployed for compound growth
        
        // This is simplified - in reality would need cross-chain communication
        _checkCrossChainYield();
    }

    function _checkCrossChainYield() internal {
        if (currentTargetChain == 0 || deployedOnTargetChain == 0) return;
        
        CrossChainOpportunity memory opportunity = crossChainOpportunities[currentTargetChain];
        
        // Estimate yield based on time and APY
        uint256 timeDeployed = block.timestamp - lastHarvestTime;
        if (timeDeployed > 0) {
            uint256 estimatedYield = (deployedOnTargetChain * opportunity.expectedAPY * timeDeployed) / (365 days * 10000);
            
            if (estimatedYield >= minHarvestAmount) {
                emit CrossChainYieldHarvested(currentTargetChain, estimatedYield);
                
                // In real implementation, would trigger bridge back if profitable
                // For now, just update metrics
                totalHarvested += estimatedYield;
            }
        }
    }

    function _emergencyWithdraw(bytes calldata) internal override returns (uint256 recovered) {
        if (crossChainActive && deployedOnTargetChain > 0) {
            // Emergency bridge back from target chain
            recovered = _emergencyBridgeBack();
        }
        
        // Add any liquid balance
        recovered += assetToken.balanceOf(address(this));
        
        return recovered;
    }

    function _emergencyBridgeBack() internal returns (uint256 recovered) {
        if (currentTargetChain == 0 || deployedOnTargetChain == 0) return 0;
        
        // In emergency, would need to trigger withdrawal from target protocol
        // and bridge back to Flow. This requires cross-chain communication.
        
        // For now, mark as recovery in progress
        crossChainActive = false;
        recovered = deployedOnTargetChain; // Estimated recovery
        deployedOnTargetChain = 0;
        
        return recovered;
    }

    function _getBestCrossChainOpportunity(uint256 amount) internal view returns (uint64) {
        uint64 bestChain = 0;
        uint256 bestAPY = 0;
        
        for (uint i = 0; i < supportedChains.length; i++) {
            uint64 chainId = supportedChains[i];
            CrossChainOpportunity memory opportunity = crossChainOpportunities[chainId];
            
            if (opportunity.active && 
                amount >= opportunity.minAmount && 
                amount <= opportunity.maxAmount &&
                opportunity.expectedAPY > bestAPY) {
                
                bestChain = chainId;
                bestAPY = opportunity.expectedAPY;
            }
        }
        
        return bestChain;
    }

    function getBalance() external view override returns (uint256) {
        uint256 liquidBalance = assetToken.balanceOf(address(this));
        uint256 crossChainBalance = deployedOnTargetChain;
        
        // Add estimated yield from cross-chain deployment
        if (crossChainActive && currentTargetChain != 0) {
            CrossChainOpportunity memory opportunity = crossChainOpportunities[currentTargetChain];
            uint256 timeDeployed = block.timestamp - lastHarvestTime;
            uint256 estimatedYield = (crossChainBalance * opportunity.expectedAPY * timeDeployed) / (365 days * 10000);
            crossChainBalance += estimatedYield;
        }
        
        return liquidBalance + crossChainBalance;
    }

    // Admin functions for managing cross-chain opportunities
    function addCrossChainOpportunity(
        uint64 chainId,
        address targetProtocol,
        uint256 expectedAPY,
        uint256 minAmount,
        uint256 maxAmount,
        string calldata protocolName
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        crossChainOpportunities[chainId] = CrossChainOpportunity({
            chainId: chainId,
            targetProtocol: targetProtocol,
            expectedAPY: expectedAPY,
            bridgeFee: 0, // Will be calculated dynamically
            minAmount: minAmount,
            maxAmount: maxAmount,
            active: true,
            protocolName: protocolName
        });
        
        // Add to supported chains if not already present
        bool chainExists = false;
        for (uint i = 0; i < supportedChains.length; i++) {
            if (supportedChains[i] == chainId) {
                chainExists = true;
                break;
            }
        }
        if (!chainExists) {
            supportedChains.push(chainId);
        }
        
        emit OpportunityAdded(chainId, protocolName, expectedAPY);
    }

    function updateOpportunityAPY(uint64 chainId, uint256 newAPY) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(crossChainOpportunities[chainId].chainId == chainId, "Opportunity not found");
        crossChainOpportunities[chainId].expectedAPY = newAPY;
    }

    function deactivateOpportunity(uint64 chainId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        crossChainOpportunities[chainId].active = false;
    }

    function manualBridgeBack() external onlyRole(EMERGENCY_ROLE) {
        _emergencyBridgeBack();
    }

    // View functions
    function getCrossChainOpportunities() external view returns (uint64[] memory chains, uint256[] memory apys) {
        chains = supportedChains;
        apys = new uint256[](chains.length);
        
        for (uint i = 0; i < chains.length; i++) {
            apys[i] = crossChainOpportunities[chains[i]].expectedAPY;
        }
    }

    function getDeploymentInfo() external view returns (
        uint64 targetChain,
        uint256 deployedAmount,
        bool isActive,
        uint256 estimatedYield
    ) {
        targetChain = currentTargetChain;
        deployedAmount = deployedOnTargetChain;
        isActive = crossChainActive;
        
        if (isActive && targetChain != 0) {
            CrossChainOpportunity memory opportunity = crossChainOpportunities[targetChain];
            uint256 timeDeployed = block.timestamp - lastHarvestTime;
            estimatedYield = (deployedAmount * opportunity.expectedAPY * timeDeployed) / (365 days * 10000);
        }
    }

    // Handle ETH for bridge fees
    receive() external payable {}
}