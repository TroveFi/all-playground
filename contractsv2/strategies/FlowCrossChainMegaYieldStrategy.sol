// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./BaseStrategy.sol";

// Cross-chain protocol interfaces
interface ICelerBridgeAdvanced {
    function send(
        address receiver,
        address token,
        uint256 amount,
        uint64 dstChainId,
        uint64 nonce,
        uint32 maxSlippage
    ) external;

    function estimateFee(
        address token,
        uint256 amount,
        uint64 dstChainId
    ) external view returns (uint256 fee);

    function getTransferStatus(bytes32 transferId) external view returns (uint8 status);
}

// Multi-chain yield aggregation interface
interface IMultiChainYieldAggregator {
    struct YieldOpportunity {
        uint64 chainId;
        address protocol;
        address asset;
        uint256 apy;
        uint256 tvl;
        uint256 availableCapacity;
        uint256 minDeposit;
        uint256 maxDeposit;
        uint256 lockPeriod;
        uint256 riskScore;
        bool active;
        string protocolName;
        bytes strategyData;
    }

    struct ChainMetrics {
        uint64 chainId;
        string chainName;
        uint256 totalTVL;
        uint256 avgGasPrice;
        uint256 blockTime;
        uint256 bridgeFee;
        uint256 protocolCount;
        bool active;
    }

    function getTopOpportunities(
        address asset,
        uint256 amount,
        uint256 maxRisk
    ) external view returns (YieldOpportunity[] memory);

    function getChainMetrics(uint64 chainId) external view returns (ChainMetrics memory);
    
    function calculateOptimalDistribution(
        address asset,
        uint256 totalAmount,
        uint256 maxRisk,
        uint256 maxChains
    ) external view returns (
        uint64[] memory chainIds,
        uint256[] memory amounts,
        uint256 expectedAPY
    );
}

// Cross-chain execution interface
interface ICrossChainExecutor {
    struct ExecutionPlan {
        uint64[] targetChains;
        address[] protocols;
        uint256[] amounts;
        bytes[] callData;
        uint256[] estimatedGas;
        uint256 totalBridgeFees;
        uint256 expectedReturn;
        uint256 executionDeadline;
    }

    function createExecutionPlan(
        address asset,
        uint256 amount,
        YieldOpportunity[] calldata opportunities
    ) external view returns (ExecutionPlan memory);

    function executeMultiChainDeployment(
        ExecutionPlan calldata plan
    ) external payable returns (bytes32[] memory executionIds);

    function getExecutionStatus(bytes32 executionId) external view returns (
        uint8 status,
        uint256 deployedAmount,
        uint256 currentValue,
        uint256 accruedYield
    );
}

// Real DeFi protocol interfaces for different chains
interface IEthereumProtocols {
    // Aave V3
    function supplyAave(address asset, uint256 amount) external;
    function withdrawAave(address asset, uint256 amount) external;
    function getAaveAPY(address asset) external view returns (uint256);
    
    // Compound V3
    function supplyCompound(address asset, uint256 amount) external;
    function withdrawCompound(address asset, uint256 amount) external;
    function getCompoundAPY(address asset) external view returns (uint256);
    
    // Curve Finance
    function addLiquidityCurve(address pool, uint256[] calldata amounts) external;
    function removeLiquidityCurve(address pool, uint256 amount) external;
    function getCurveAPY(address pool) external view returns (uint256);
}

interface IArbitrumProtocols {
    // GMX
    function stakeGMX(uint256 amount) external;
    function unstakeGMX(uint256 amount) external;
    function getGMXAPY() external view returns (uint256);
    
    // Plutus DAO
    function stakePLS(uint256 amount) external;
    function unstakePLS(uint256 amount) external;
    function getPLSAPY() external view returns (uint256);
}

interface IPolygonProtocols {
    // QuickSwap
    function addLiquidityQuick(address tokenA, address tokenB, uint256 amountA, uint256 amountB) external;
    function removeLiquidityQuick(address tokenA, address tokenB, uint256 liquidity) external;
    function getQuickSwapAPY(address pair) external view returns (uint256);
    
    // Aave Polygon
    function supplyAavePolygon(address asset, uint256 amount) external;
    function withdrawAavePolygon(address asset, uint256 amount) external;
    function getAavePolygonAPY(address asset) external view returns (uint256);
}

/// @title FlowCrossChainMegaYieldStrategy - Ultimate Cross-Chain Yield Aggregation
/// @notice Revolutionary strategy that scans and deploys to highest yields across all major chains
contract FlowCrossChainMegaYieldStrategy is BaseStrategy, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Cross-chain infrastructure addresses
    address public constant CELER_BRIDGE = address(0); // Celer bridge on Flow
    address public constant YIELD_AGGREGATOR = address(0); // Multi-chain yield aggregator
    address public constant CROSS_CHAIN_EXECUTOR = address(0); // Execution engine

    // External protocol interfaces
    ICelerBridgeAdvanced public immutable celerBridge;
    IMultiChainYieldAggregator public immutable yieldAggregator;
    ICrossChainExecutor public immutable crossChainExecutor;
    IEthereumProtocols public immutable ethereumProtocols;
    IArbitrumProtocols public immutable arbitrumProtocols;
    IPolygonProtocols public immutable polygonProtocols;

    // Chain configuration
    struct ChainConfig {
        uint64 chainId;
        string name;
        address bridgeAddress;
        address executorAddress;
        uint256 minDeployment;
        uint256 maxDeployment;
        uint256 bridgeFeeBase;
        bool active;
        uint256 trustScore; // 0-10000 based on security/reliability
    }

    // Multi-chain position tracking
    struct CrossChainPosition {
        bytes32 positionId;
        uint64 chainId;
        address protocol;
        address asset;
        uint256 deployedAmount;
        uint256 currentValue;
        uint256 entryAPY;
        uint256 accruedYield;
        uint256 deploymentTime;
        uint256 lastUpdate;
        bool active;
        string protocolName;
        bytes strategyData;
    }

    // Yield optimization configuration
    struct OptimizationConfig {
        uint256 maxChainsSimultaneous; // Max chains to deploy to
        uint256 minAPYDifference; // Minimum APY diff to justify rebalancing
        uint256 maxBridgeFeePercent; // Max bridge fee as % of deployment
        uint256 rebalanceThreshold; // Minimum improvement to rebalance
        uint256 maxRiskScore; // Maximum acceptable risk per protocol
        uint256 diversificationTarget; // Target number of protocols
        bool enableAutoRebalancing; // Automatic cross-chain rebalancing
        bool enableYieldCompounding; // Auto-compound yields
        uint256 compoundingThreshold; // Minimum yield to compound
    }

    // State variables
    mapping(uint64 => ChainConfig) public chainConfigs;
    uint64[] public supportedChains;
    mapping(bytes32 => CrossChainPosition) public crossChainPositions;
    bytes32[] public activePositions;
    mapping(uint64 => bytes32[]) public positionsByChain;
    mapping(address => bytes32[]) public positionsByProtocol;

    OptimizationConfig public optimizationConfig;
    
    // Performance tracking
    uint256 public totalDeployedAcrossChains;
    uint256 public totalYieldEarnedAcrossChains;
    uint256 public totalBridgeFeesSpent;
    uint256 public successfulDeployments;
    uint256 public failedDeployments;
    uint256 public rebalanceCount;
    
    // Cross-chain metrics
    mapping(uint64 => uint256) public chainTVL;
    mapping(uint64 => uint256) public chainYieldEarned;
    mapping(uint64 => uint256) public chainDeploymentCount;
    mapping(string => uint256) public protocolPerformance;

    // Events
    event CrossChainDeploymentInitiated(
        bytes32 indexed positionId,
        uint64 indexed chainId,
        address indexed protocol,
        uint256 amount,
        uint256 expectedAPY
    );
    
    event CrossChainDeploymentCompleted(
        bytes32 indexed positionId,
        uint64 indexed chainId,
        uint256 actualAmount,
        bool success
    );
    
    event CrossChainYieldHarvested(
        bytes32 indexed positionId,
        uint64 indexed chainId,
        uint256 yieldAmount,
        bool compounded
    );
    
    event CrossChainRebalanceExecuted(
        uint64 fromChain,
        uint64 toChain,
        uint256 amount,
        uint256 expectedImprovement
    );
    
    event OpportunityScanned(
        uint64 indexed chainId,
        address indexed protocol,
        uint256 apy,
        uint256 tvl,
        uint256 riskScore
    );

    constructor(
        address _asset,
        address _vault,
        string memory _name
    ) BaseStrategy(_asset, CELER_BRIDGE, _vault, _name) {
        celerBridge = ICelerBridgeAdvanced(CELER_BRIDGE);
        yieldAggregator = IMultiChainYieldAggregator(YIELD_AGGREGATOR);
        crossChainExecutor = ICrossChainExecutor(CROSS_CHAIN_EXECUTOR);
        ethereumProtocols = IEthereumProtocols(address(0)); // TODO: Set real address
        arbitrumProtocols = IArbitrumProtocols(address(0)); // TODO: Set real address
        polygonProtocols = IPolygonProtocols(address(0)); // TODO: Set real address
        
        // Initialize optimization configuration
        optimizationConfig = OptimizationConfig({
            maxChainsSimultaneous: 5,
            minAPYDifference: 200, // 2%
            maxBridgeFeePercent: 50, // 0.5%
            rebalanceThreshold: 300, // 3%
            maxRiskScore: 7000, // 70%
            diversificationTarget: 3,
            enableAutoRebalancing: true,
            enableYieldCompounding: true,
            compoundingThreshold: 100 * 10**6 // 100 USDC
        });

        _initializeSupportedChains();
    }

    function _initializeSupportedChains() internal {
        // Ethereum - Highest TVL, most mature protocols
        chainConfigs[1] = ChainConfig({
            chainId: 1,
            name: "Ethereum",
            bridgeAddress: address(0), // TODO: Set real Celer bridge
            executorAddress: address(0), // TODO: Set real executor
            minDeployment: 1000 * 10**6, // 1000 USDC
            maxDeployment: 10000000 * 10**6, // 10M USDC
            bridgeFeeBase: 0.01 ether,
            active: true,
            trustScore: 9500 // Highest trust
        });

        // Arbitrum - Lower fees, high yields
        chainConfigs[42161] = ChainConfig({
            chainId: 42161,
            name: "Arbitrum",
            bridgeAddress: address(0),
            executorAddress: address(0),
            minDeployment: 100 * 10**6, // 100 USDC
            maxDeployment: 5000000 * 10**6, // 5M USDC
            bridgeFeeBase: 0.005 ether,
            active: true,
            trustScore: 9000
        });

        // Polygon - Very low fees, good DeFi ecosystem
        chainConfigs[137] = ChainConfig({
            chainId: 137,
            name: "Polygon",
            bridgeAddress: address(0),
            executorAddress: address(0),
            minDeployment: 50 * 10**6, // 50 USDC
            maxDeployment: 2000000 * 10**6, // 2M USDC
            bridgeFeeBase: 0.001 ether,
            active: true,
            trustScore: 8500
        });

        // Optimism - L2 with good yields
        chainConfigs[10] = ChainConfig({
            chainId: 10,
            name: "Optimism",
            bridgeAddress: address(0),
            executorAddress: address(0),
            minDeployment: 100 * 10**6,
            maxDeployment: 3000000 * 10**6,
            bridgeFeeBase: 0.005 ether,
            active: true,
            trustScore: 8800
        });

        // Avalanche - High yields, fast finality
        chainConfigs[43114] = ChainConfig({
            chainId: 43114,
            name: "Avalanche",
            bridgeAddress: address(0),
            executorAddress: address(0),
            minDeployment: 100 * 10**6,
            maxDeployment: 2000000 * 10**6,
            bridgeFeeBase: 0.01 ether,
            active: true,
            trustScore: 8200
        });

        supportedChains = [1, 42161, 137, 10, 43114];
    }

    function _executeStrategy(uint256 amount, bytes calldata data) internal override {
        // Decode cross-chain parameters
        (uint256 maxChains, uint256 minAPY, bool forceOptimal) = data.length > 0 
            ? abi.decode(data, (uint256, uint256, bool))
            : (optimizationConfig.maxChainsSimultaneous, 500, false); // 5% default min APY

        // Step 1: Scan all chains for opportunities
        IMultiChainYieldAggregator.YieldOpportunity[] memory opportunities = 
            _scanCrossChainOpportunities(amount, optimizationConfig.maxRiskScore);

        // Step 2: Calculate optimal distribution
        (uint64[] memory targetChains, uint256[] memory amounts, uint256 expectedAPY) = 
            yieldAggregator.calculateOptimalDistribution(
                address(assetToken),
                amount,
                optimizationConfig.maxRiskScore,
                maxChains
            );

        // Step 3: Execute cross-chain deployment
        if (expectedAPY >= minAPY || forceOptimal) {
            _executeCrossChainDeployment(targetChains, amounts, opportunities);
        }
    }

    function _scanCrossChainOpportunities(
        uint256 amount,
        uint256 maxRisk
    ) internal returns (IMultiChainYieldAggregator.YieldOpportunity[] memory) {
        IMultiChainYieldAggregator.YieldOpportunity[] memory opportunities = 
            yieldAggregator.getTopOpportunities(address(assetToken), amount, maxRisk);

        // Log opportunities for analysis
        for (uint256 i = 0; i < opportunities.length; i++) {
            IMultiChainYieldAggregator.YieldOpportunity memory opp = opportunities[i];
            emit OpportunityScanned(opp.chainId, opp.protocol, opp.apy, opp.tvl, opp.riskScore);
        }

        return opportunities;
    }

    function _executeCrossChainDeployment(
        uint64[] memory targetChains,
        uint256[] memory amounts,
        IMultiChainYieldAggregator.YieldOpportunity[] memory opportunities
    ) internal {
        for (uint256 i = 0; i < targetChains.length && i < amounts.length; i++) {
            uint64 chainId = targetChains[i];
            uint256 amount = amounts[i];

            if (amount > 0 && chainConfigs[chainId].active) {
                // Find the opportunity for this chain
                IMultiChainYieldAggregator.YieldOpportunity memory opportunity;
                for (uint256 j = 0; j < opportunities.length; j++) {
                    if (opportunities[j].chainId == chainId) {
                        opportunity = opportunities[j];
                        break;
                    }
                }

                if (opportunity.chainId != 0) {
                    _deployToChain(chainId, amount, opportunity);
                }
            }
        }
    }

    function _deployToChain(
        uint64 chainId,
        uint256 amount,
        IMultiChainYieldAggregator.YieldOpportunity memory opportunity
    ) internal {
        ChainConfig memory chainConfig = chainConfigs[chainId];
        
        // Validate deployment parameters
        require(amount >= chainConfig.minDeployment, "Below minimum deployment");
        require(amount <= chainConfig.maxDeployment, "Above maximum deployment");

        // Calculate bridge fee
        uint256 bridgeFee = celerBridge.estimateFee(address(assetToken), amount, chainId);
        require(bridgeFee <= (amount * optimizationConfig.maxBridgeFeePercent) / 10000, "Bridge fee too high");

        // Create position ID
        bytes32 positionId = keccak256(abi.encodePacked(
            chainId,
            opportunity.protocol,
            amount,
            block.timestamp
        ));

        // Record position (optimistically)
        crossChainPositions[positionId] = CrossChainPosition({
            positionId: positionId,
            chainId: chainId,
            protocol: opportunity.protocol,
            asset: address(assetToken),
            deployedAmount: amount,
            currentValue: amount, // Will be updated
            entryAPY: opportunity.apy,
            accruedYield: 0,
            deploymentTime: block.timestamp,
            lastUpdate: block.timestamp,
            active: true,
            protocolName: opportunity.protocolName,
            strategyData: opportunity.strategyData
        });

        activePositions.push(positionId);
        positionsByChain[chainId].push(positionId);
        positionsByProtocol[opportunity.protocol].push(positionId);

        // Execute bridge transaction
        assetToken.approve(address(celerBridge), amount);
        
        try celerBridge.send{value: bridgeFee}(
            opportunity.protocol, // Receiver (will execute strategy on destination)
            address(assetToken),
            amount,
            chainId,
            uint64(block.timestamp), // Nonce
            1000 // 1% max slippage
        ) {
            // Bridge successful
            totalDeployedAcrossChains += amount;
            totalBridgeFeesSpent += bridgeFee;
            chainTVL[chainId] += amount;
            chainDeploymentCount[chainId]++;
            successfulDeployments++;

            emit CrossChainDeploymentInitiated(positionId, chainId, opportunity.protocol, amount, opportunity.apy);
        } catch {
            // Bridge failed - remove position
            crossChainPositions[positionId].active = false;
            failedDeployments++;
        }
    }

    function _harvestRewards(bytes calldata) internal override {
        // Harvest yields from all active cross-chain positions
        for (uint256 i = 0; i < activePositions.length; i++) {
            bytes32 positionId = activePositions[i];
            CrossChainPosition storage position = crossChainPositions[positionId];

            if (position.active) {
                _harvestCrossChainYield(positionId);
            }
        }

        // Check for rebalancing opportunities
        if (optimizationConfig.enableAutoRebalancing) {
            _checkRebalancingOpportunities();
        }
    }

    function _harvestCrossChainYield(bytes32 positionId) internal {
        CrossChainPosition storage position = crossChainPositions[positionId];
        
        // Estimate accrued yield based on time and APY
        uint256 timeElapsed = block.timestamp - position.lastUpdate;
        uint256 estimatedYield = (position.deployedAmount * position.entryAPY * timeElapsed) / (365 days * 10000);

        if (estimatedYield >= optimizationConfig.compoundingThreshold) {
            // Update position
            position.accruedYield += estimatedYield;
            position.currentValue += estimatedYield;
            position.lastUpdate = block.timestamp;

            // Track metrics
            totalYieldEarnedAcrossChains += estimatedYield;
            chainYieldEarned[position.chainId] += estimatedYield;
            protocolPerformance[position.protocolName] += estimatedYield;

            bool shouldCompound = optimizationConfig.enableYieldCompounding && 
                                 estimatedYield >= optimizationConfig.compoundingThreshold;

            emit CrossChainYieldHarvested(positionId, position.chainId, estimatedYield, shouldCompound);

            if (shouldCompound) {
                _compoundCrossChainYield(positionId, estimatedYield);
            }
        }
    }

    function _compoundCrossChainYield(bytes32 positionId, uint256 yieldAmount) internal {
        CrossChainPosition storage position = crossChainPositions[positionId];
        
        // For simplification, assume yield is compounded on the same chain
        // In reality, would need cross-chain communication to compound
        position.deployedAmount += yieldAmount;
        position.accruedYield = 0; // Reset after compounding
    }

    function _checkRebalancingOpportunities() internal {
        // Get current best opportunities
        IMultiChainYieldAggregator.YieldOpportunity[] memory newOpportunities = 
            yieldAggregator.getTopOpportunities(
                address(assetToken), 
                totalDeployedAcrossChains, 
                optimizationConfig.maxRiskScore
            );

        // Compare with current positions
        for (uint256 i = 0; i < activePositions.length; i++) {
            bytes32 positionId = activePositions[i];
            CrossChainPosition storage position = crossChainPositions[positionId];

            if (position.active) {
                _evaluatePositionForRebalancing(positionId, newOpportunities);
            }
        }
    }

    function _evaluatePositionForRebalancing(
        bytes32 positionId,
        IMultiChainYieldAggregator.YieldOpportunity[] memory newOpportunities
    ) internal {
        CrossChainPosition storage position = crossChainPositions[positionId];
        
        // Find best alternative opportunity
        uint256 bestAlternativeAPY = 0;
        uint64 bestChainId = 0;
        
        for (uint256 i = 0; i < newOpportunities.length; i++) {
            IMultiChainYieldAggregator.YieldOpportunity memory opp = newOpportunities[i];
            if (opp.apy > bestAlternativeAPY && opp.chainId != position.chainId) {
                bestAlternativeAPY = opp.apy;
                bestChainId = opp.chainId;
            }
        }

        // Check if rebalancing is worthwhile
        uint256 apyImprovement = bestAlternativeAPY > position.entryAPY 
            ? bestAlternativeAPY - position.entryAPY 
            : 0;

        if (apyImprovement >= optimizationConfig.rebalanceThreshold) {
            _executeRebalancing(positionId, bestChainId, apyImprovement);
        }
    }

    function _executeRebalancing(bytes32 positionId, uint64 newChainId, uint256 expectedImprovement) internal {
        CrossChainPosition storage position = crossChainPositions[positionId];
        
        // For simplification, mark old position as inactive and create new one
        position.active = false;
        rebalanceCount++;

        emit CrossChainRebalanceExecuted(
            position.chainId,
            newChainId,
            position.currentValue,
            expectedImprovement
        );

        // In reality, would execute bridge withdrawal and redeployment
    }

    function _emergencyWithdraw(bytes calldata) internal override returns (uint256 recovered) {
        // Emergency withdrawal from all cross-chain positions
        uint256 totalRecovered = 0;

        for (uint256 i = 0; i < activePositions.length; i++) {
            bytes32 positionId = activePositions[i];
            CrossChainPosition storage position = crossChainPositions[positionId];

            if (position.active) {
                // Mark position as inactive (emergency exit)
                position.active = false;
                totalRecovered += position.currentValue;
                
                // In reality, would execute emergency bridge withdrawal
            }
        }

        // Add liquid balance on Flow
        totalRecovered += assetToken.balanceOf(address(this));

        return totalRecovered;
    }

    function getBalance() external view override returns (uint256) {
        uint256 totalBalance = assetToken.balanceOf(address(this));

        // Add value of all cross-chain positions
        for (uint256 i = 0; i < activePositions.length; i++) {
            bytes32 positionId = activePositions[i];
            CrossChainPosition memory position = crossChainPositions[positionId];

            if (position.active) {
                totalBalance += position.currentValue;
            }
        }

        return totalBalance;
    }

    // Manual operations
    function manualDeployToChain(
        uint64 chainId,
        uint256 amount,
        address protocol,
        uint256 expectedAPY
    ) external onlyRole(HARVESTER_ROLE) {
        require(chainConfigs[chainId].active, "Chain not supported");
        
        IMultiChainYieldAggregator.YieldOpportunity memory opportunity = IMultiChainYieldAggregator.YieldOpportunity({
            chainId: chainId,
            protocol: protocol,
            asset: address(assetToken),
            apy: expectedAPY,
            tvl: 0,
            availableCapacity: amount,
            minDeposit: 0,
            maxDeposit: amount,
            lockPeriod: 0,
            riskScore: 5000, // Default medium risk
            active: true,
            protocolName: "Manual",
            strategyData: ""
        });

        _deployToChain(chainId, amount, opportunity);
    }

    function manualRebalance() external onlyRole(HARVESTER_ROLE) {
        _checkRebalancingOpportunities();
    }

    function manualHarvestPosition(bytes32 positionId) external onlyRole(HARVESTER_ROLE) {
        require(crossChainPositions[positionId].active, "Position not active");
        _harvestCrossChainYield(positionId);
    }

    // Admin functions
    function updateOptimizationConfig(
        uint256 maxChains,
        uint256 minAPYDiff,
        uint256 maxBridgeFee,
        uint256 rebalanceThreshold,
        bool enableAutoRebalancing,
        bool enableCompounding
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        optimizationConfig.maxChainsSimultaneous = maxChains;
        optimizationConfig.minAPYDifference = minAPYDiff;
        optimizationConfig.maxBridgeFeePercent = maxBridgeFee;
        optimizationConfig.rebalanceThreshold = rebalanceThreshold;
        optimizationConfig.enableAutoRebalancing = enableAutoRebalancing;
        optimizationConfig.enableYieldCompounding = enableCompounding;
    }

    function addSupportedChain(
        uint64 chainId,
        string calldata name,
        address bridgeAddress,
        uint256 minDeployment,
        uint256 maxDeployment,
        uint256 trustScore
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        chainConfigs[chainId] = ChainConfig({
            chainId: chainId,
            name: name,
            bridgeAddress: bridgeAddress,
            executorAddress: address(0),
            minDeployment: minDeployment,
            maxDeployment: maxDeployment,
            bridgeFeeBase: 0.01 ether,
            active: true,
            trustScore: trustScore
        });

        supportedChains.push(chainId);
    }

    function deactivateChain(uint64 chainId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        chainConfigs[chainId].active = false;
    }

    function emergencyDeactivatePosition(bytes32 positionId) external onlyRole(EMERGENCY_ROLE) {
        crossChainPositions[positionId].active = false;
    }

    // View functions
    function getCrossChainPerformance() external view returns (
        uint256 totalDeployed,
        uint256 totalYieldEarned,
        uint256 totalBridgeFees,
        uint256 successfulDeploymentCount,
        uint256 failedDeploymentCount,
        uint256 activePositionCount
    ) {
        totalDeployed = totalDeployedAcrossChains;
        totalYieldEarned = totalYieldEarnedAcrossChains;
        totalBridgeFees = totalBridgeFeesSpent;
        successfulDeploymentCount = successfulDeployments;
        failedDeploymentCount = failedDeployments;
        activePositionCount = activePositions.length;
    }

    function getChainMetrics(uint64 chainId) external view returns (
        uint256 tvl,
        uint256 yieldEarned,
        uint256 deploymentCount,
        ChainConfig memory config
    ) {
        tvl = chainTVL[chainId];
        yieldEarned = chainYieldEarned[chainId];
        deploymentCount = chainDeploymentCount[chainId];
        config = chainConfigs[chainId];
    }

    function getAllActivePositions() external view returns (CrossChainPosition[] memory) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < activePositions.length; i++) {
            if (crossChainPositions[activePositions[i]].active) {
                activeCount++;
            }
        }

        CrossChainPosition[] memory positions = new CrossChainPosition[](activeCount);
        uint256 index = 0;

        for (uint256 i = 0; i < activePositions.length; i++) {
            CrossChainPosition memory position = crossChainPositions[activePositions[i]];
            if (position.active) {
                positions[index] = position;
                index++;
            }
        }

        return positions;
    }

    function getPositionsByChain(uint64 chainId) external view returns (CrossChainPosition[] memory) {
        bytes32[] memory chainPositionIds = positionsByChain[chainId];
        CrossChainPosition[] memory positions = new CrossChainPosition[](chainPositionIds.length);

        for (uint256 i = 0; i < chainPositionIds.length; i++) {
            positions[i] = crossChainPositions[chainPositionIds[i]];
        }

        return positions;
    }

    function getSupportedChains() external view returns (uint64[] memory) {
        return supportedChains;
    }

    function getProtocolPerformance(string calldata protocolName) external view returns (uint256) {
        return protocolPerformance[protocolName];
    }

    function getCurrentOpportunities(uint256 amount) external view returns (IMultiChainYieldAggregator.YieldOpportunity[] memory) {
        return yieldAggregator.getTopOpportunities(address(assetToken), amount, optimizationConfig.maxRiskScore);
    }

    // Handle native token for bridge fees
    receive() external payable {}
}