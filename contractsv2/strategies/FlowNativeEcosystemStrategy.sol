// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./BaseStrategy.sol";

// Flow Native Ecosystem Interfaces
interface IFlowTokenStaking {
    function stake(uint256 amount) external;
    function unstake(uint256 amount) external;
    function claimRewards() external returns (uint256);
    function getStakedBalance(address account) external view returns (uint256);
    function getRewards(address account) external view returns (uint256);
    function getAPY() external view returns (uint256);
}

// Flow Epoch/Validator Rewards
interface IFlowEpochRewards {
    function delegateStake(address nodeId, uint256 amount) external;
    function undelegateStake(address nodeId, uint256 amount) external;
    function claimDelegatorRewards(address nodeId) external returns (uint256);
    function getNodeInfo(address nodeId) external view returns (
        uint256 totalStaked,
        uint256 commission,
        uint256 uptime,
        bool active
    );
    function getDelegatorRewards(address nodeId, address delegator) external view returns (uint256);
}

// Flow Account Abstraction & Native Features
interface IFlowAccountModel {
    function createSubAccount(bytes32 accountType) external returns (address subAccount);
    function executeMultiSig(bytes[] calldata calls, bytes[] calldata signatures) external;
    function batchExecute(bytes[] calldata calls) external;
    function setAccountWeight(address account, uint256 weight) external;
}

// Flow Cadence Integration
interface ICadenceIntegration {
    function executeCadenceScript(string calldata script, bytes calldata args) external returns (bytes memory);
    function deployContract(bytes calldata contractCode) external returns (address);
    function callCadenceFunction(string calldata functionName, bytes calldata args) external returns (bytes memory);
}

// Cross-Protocol Yield Aggregation for Flow
interface IFlowProtocolAggregator {
    struct ProtocolInfo {
        string name;
        address contractAddress;
        uint256 tvl;
        uint256 apy;
        uint256 riskScore;
        bool active;
    }

    function getAllProtocols() external view returns (ProtocolInfo[] memory);
    function getOptimalProtocol(uint256 amount, uint256 maxRisk) external view returns (address protocol, uint256 expectedAPY);
    function executeOptimalAllocation(uint256 amount, uint256 maxRisk) external returns (address[] memory protocols, uint256[] memory amounts);
}

/// @title FlowNativeEcosystemStrategy - Ultimate Flow Ecosystem Maximization
/// @notice Leverages ALL of Flow's unique features for maximum yield
contract FlowNativeEcosystemStrategy is BaseStrategy, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Flow native contract addresses (you'll need real addresses)
    address public constant FLOW_TOKEN_STAKING = address(0); // Flow native staking
    address public constant FLOW_EPOCH_REWARDS = address(0); // Validator delegation
    address public constant FLOW_ACCOUNT_MODEL = address(0); // Account abstraction
    address public constant CADENCE_INTEGRATION = address(0); // Cadence scripts
    address public constant FLOW_PROTOCOL_AGGREGATOR = address(0); // Protocol aggregator

    // Flow ecosystem protocol addresses
    address public constant FLOW_TOKEN = address(0); // Native FLOW token
    address public constant WETH_FLOW = address(0); // Wrapped ETH on Flow
    address public constant USDC_FLOW = address(0); // USDC on Flow
    address public constant USDT_FLOW = address(0); // USDT on Flow

    IFlowTokenStaking public immutable flowStaking;
    IFlowEpochRewards public immutable epochRewards;
    IFlowAccountModel public immutable accountModel;
    ICadenceIntegration public immutable cadenceIntegration;
    IFlowProtocolAggregator public immutable protocolAggregator;

    // Multi-asset support for Flow ecosystem
    struct AssetAllocation {
        address asset;
        uint256 amount;
        address[] protocols;
        uint256[] allocations;
        uint256 totalYield;
        uint256 lastUpdate;
    }

    struct FlowEcosystemPosition {
        bytes32 positionId;
        address asset;
        uint256 amount;
        EcosystemStrategy strategy;
        address[] protocols;
        uint256[] amounts;
        uint256 entryTime;
        uint256 accruedYield;
        bool active;
    }

    enum EcosystemStrategy {
        NATIVE_STAKING,           // Stake FLOW tokens
        VALIDATOR_DELEGATION,     // Delegate to validators
        MULTI_PROTOCOL_FARMING,   // Farm across all Flow protocols
        CADENCE_OPTIMIZED,        // Use Cadence for advanced strategies
        ACCOUNT_ABSTRACTION,      // Leverage Flow's account model
        CROSS_ASSET_ARBITRAGE,    // Arbitrage between FLOW/WETH/USDC/USDT
        ECOSYSTEM_MAXIMIZATION    // Maximize across entire Flow ecosystem
    }

    // State variables
    mapping(bytes32 => FlowEcosystemPosition) public ecosystemPositions;
    mapping(address => AssetAllocation) public assetAllocations;
    bytes32[] public activePositions;
    address[] public supportedAssets;
    
    // Flow validator nodes
    address[] public topValidators;
    mapping(address => uint256) public validatorAllocations;
    mapping(address => uint256) public validatorPerformance;
    
    // Protocol performance tracking
    mapping(address => uint256) public protocolAPYs;
    mapping(address => uint256) public protocolTVLs;
    mapping(address => uint256) public protocolRisks;
    
    // Native Flow features
    address[] public subAccounts;
    mapping(bytes32 => bytes) public cadenceScripts;
    
    uint256 public positionCounter;
    uint256 public totalEcosystemYield;
    uint256 public rebalanceInterval = 6 hours;
    uint256 public lastRebalanceTime;

    event EcosystemPositionCreated(bytes32 indexed positionId, EcosystemStrategy strategy, uint256 amount);
    event MultiProtocolAllocation(address[] protocols, uint256[] amounts, uint256 expectedAPY);
    event ValidatorDelegated(address indexed validator, uint256 amount, uint256 expectedRewards);
    event CadenceScriptExecuted(string script, bytes result);
    event CrossAssetArbitrage(address fromAsset, address toAsset, uint256 profit);
    event EcosystemRebalanced(uint256 totalValue, uint256 newExpectedAPY);

    constructor(
        address _asset,
        address _vault,
        string memory _name
    ) BaseStrategy(_asset, FLOW_TOKEN_STAKING, _vault, _name) {
        flowStaking = IFlowTokenStaking(FLOW_TOKEN_STAKING);
        epochRewards = IFlowEpochRewards(FLOW_EPOCH_REWARDS);
        accountModel = IFlowAccountModel(FLOW_ACCOUNT_MODEL);
        cadenceIntegration = ICadenceIntegration(CADENCE_INTEGRATION);
        protocolAggregator = IFlowProtocolAggregator(FLOW_PROTOCOL_AGGREGATOR);
        
        // Initialize supported assets for Flow ecosystem
        supportedAssets = [FLOW_TOKEN, WETH_FLOW, USDC_FLOW, USDT_FLOW];
        
        _initializeFlowEcosystem();
    }

    function _initializeFlowEcosystem() internal {
        // Initialize top Flow validators (you'll need real validator IDs)
        topValidators = [
            address(0x1), // Validator 1
            address(0x2), // Validator 2
            address(0x3), // Validator 3
            address(0x4), // Validator 4
            address(0x5)  // Validator 5
        ];
        
        // Initialize Cadence scripts for advanced operations
        cadenceScripts[keccak256("OPTIMAL_YIELD_ALLOCATION")] = "pub fun main(): [UInt64] { return [1000, 2000, 3000] }";
        cadenceScripts[keccak256("VALIDATOR_PERFORMANCE")] = "pub fun main(): {Address: UFix64} { return {} }";
        cadenceScripts[keccak256("PROTOCOL_RISK_ASSESSMENT")] = "pub fun main(): {Address: UInt8} { return {} }";
    }

    function _executeStrategy(uint256 amount, bytes calldata data) internal override {
        // Decode ecosystem strategy parameters
        (EcosystemStrategy strategy, address targetAsset, uint256 maxRisk) = data.length > 0 
            ? abi.decode(data, (EcosystemStrategy, address, uint256))
            : (EcosystemStrategy.ECOSYSTEM_MAXIMIZATION, address(assetToken), 5000);

        // Create ecosystem position
        bytes32 positionId = _createEcosystemPosition(amount, strategy, targetAsset, maxRisk);
        
        // Execute strategy-specific logic
        if (strategy == EcosystemStrategy.NATIVE_STAKING) {
            _executeNativeStaking(positionId, amount);
        } else if (strategy == EcosystemStrategy.VALIDATOR_DELEGATION) {
            _executeValidatorDelegation(positionId, amount);
        } else if (strategy == EcosystemStrategy.MULTI_PROTOCOL_FARMING) {
            _executeMultiProtocolFarming(positionId, amount, targetAsset, maxRisk);
        } else if (strategy == EcosystemStrategy.CADENCE_OPTIMIZED) {
            _executeCadenceOptimized(positionId, amount);
        } else if (strategy == EcosystemStrategy.ECOSYSTEM_MAXIMIZATION) {
            _executeEcosystemMaximization(positionId, amount, maxRisk);
        }
    }

    function _createEcosystemPosition(
        uint256 amount,
        EcosystemStrategy strategy,
        address targetAsset,
        uint256 maxRisk
    ) internal returns (bytes32 positionId) {
        positionId = keccak256(abi.encodePacked(
            strategy,
            targetAsset,
            amount,
            block.timestamp,
            positionCounter++
        ));
        
        ecosystemPositions[positionId] = FlowEcosystemPosition({
            positionId: positionId,
            asset: targetAsset,
            amount: amount,
            strategy: strategy,
            protocols: new address[](0),
            amounts: new uint256[](0),
            entryTime: block.timestamp,
            accruedYield: 0,
            active: true
        });
        
        activePositions.push(positionId);
        
        emit EcosystemPositionCreated(positionId, strategy, amount);
        return positionId;
    }

    function _executeNativeStaking(bytes32 positionId, uint256 amount) internal {
        // Stake FLOW tokens natively
        if (address(assetToken) == FLOW_TOKEN) {
            assetToken.approve(address(flowStaking), amount);
            flowStaking.stake(amount);
            
            FlowEcosystemPosition storage position = ecosystemPositions[positionId];
            position.protocols = [FLOW_TOKEN_STAKING];
            position.amounts = [amount];
        } else {
            // Convert to FLOW first, then stake
            uint256 flowAmount = _convertToFlow(amount);
            if (flowAmount > 0) {
                IERC20(FLOW_TOKEN).approve(address(flowStaking), flowAmount);
                flowStaking.stake(flowAmount);
                
                FlowEcosystemPosition storage position = ecosystemPositions[positionId];
                position.protocols = [FLOW_TOKEN_STAKING];
                position.amounts = [flowAmount];
            }
        }
    }

    function _executeValidatorDelegation(bytes32 positionId, uint256 amount) internal {
        // Delegate to best performing validators
        address bestValidator = _findBestValidator();
        
        if (bestValidator != address(0)) {
            uint256 flowAmount = _convertToFlow(amount);
            if (flowAmount > 0) {
                IERC20(FLOW_TOKEN).approve(address(epochRewards), flowAmount);
                epochRewards.delegateStake(bestValidator, flowAmount);
                
                validatorAllocations[bestValidator] += flowAmount;
                
                FlowEcosystemPosition storage position = ecosystemPositions[positionId];
                position.protocols = [bestValidator];
                position.amounts = [flowAmount];
                
                emit ValidatorDelegated(bestValidator, flowAmount, _estimateValidatorRewards(bestValidator, flowAmount));
            }
        }
    }

    function _executeMultiProtocolFarming(
        bytes32 positionId, 
        uint256 amount, 
        address targetAsset, 
        uint256 maxRisk
    ) internal {
        // Get optimal protocol allocation from aggregator
        try protocolAggregator.executeOptimalAllocation(amount, maxRisk) returns (
            address[] memory protocols,
            uint256[] memory amounts
        ) {
            FlowEcosystemPosition storage position = ecosystemPositions[positionId];
            position.protocols = protocols;
            position.amounts = amounts;
            
            // Execute allocations to each protocol
            for (uint256 i = 0; i < protocols.length; i++) {
                _deployToProtocol(protocols[i], amounts[i], targetAsset);
            }
            
            uint256 expectedAPY = _calculateExpectedAPY(protocols, amounts);
            emit MultiProtocolAllocation(protocols, amounts, expectedAPY);
        } catch {
            // Fallback to single best protocol
            try protocolAggregator.getOptimalProtocol(amount, maxRisk) returns (
                address protocol, 
                uint256 expectedAPY
            ) {
                _deployToProtocol(protocol, amount, targetAsset);
                
                FlowEcosystemPosition storage position = ecosystemPositions[positionId];
                position.protocols = [protocol];
                position.amounts = [amount];
            } catch {
                // Ultimate fallback - native staking
                _executeNativeStaking(positionId, amount);
            }
        }
    }

    function _executeCadenceOptimized(bytes32 positionId, uint256 amount) internal {
        // Use Cadence scripts for advanced yield optimization
        
        // Execute optimal allocation script
        try cadenceIntegration.executeCadenceScript(
            string(cadenceScripts[keccak256("OPTIMAL_YIELD_ALLOCATION")]),
            abi.encode(amount)
        ) returns (bytes memory result) {
            // Parse Cadence result and execute allocation
            uint256[] memory allocations = abi.decode(result, (uint256[]));
            
            if (allocations.length >= 3) {
                // Deploy to top 3 protocols based on Cadence analysis
                _deployToProtocol(address(0x1), allocations[0], address(assetToken));
                _deployToProtocol(address(0x2), allocations[1], address(assetToken));
                _deployToProtocol(address(0x3), allocations[2], address(assetToken));
                
                FlowEcosystemPosition storage position = ecosystemPositions[positionId];
                position.protocols = [address(0x1), address(0x2), address(0x3)];
                position.amounts = allocations;
            }
            
            emit CadenceScriptExecuted("OPTIMAL_YIELD_ALLOCATION", result);
        } catch {
            // Cadence execution failed, fallback to regular strategy
            _executeMultiProtocolFarming(positionId, amount, address(assetToken), 5000);
        }
    }

    function _executeEcosystemMaximization(bytes32 positionId, uint256 amount, uint256 maxRisk) internal {
        // Ultimate strategy: maximize across ALL Flow ecosystem opportunities
        
        // 1. Analyze all protocols using Cadence
        _updateProtocolData();
        
        // 2. Check for arbitrage opportunities across assets
        uint256 arbitrageProfit = _checkCrossAssetArbitrage(amount);
        
        // 3. Delegate to validators for base yield
        uint256 validatorAmount = amount / 4; // 25% to validators
        _executeValidatorDelegation(positionId, validatorAmount);
        
        // 4. Deploy to best protocols
        uint256 protocolAmount = amount / 2; // 50% to protocols
        _executeMultiProtocolFarming(positionId, protocolAmount, address(assetToken), maxRisk);
        
        // 5. Keep remainder for arbitrage and rebalancing
        uint256 remainder = amount - validatorAmount - protocolAmount;
        
        FlowEcosystemPosition storage position = ecosystemPositions[positionId];
        position.amounts = [validatorAmount, protocolAmount, remainder];
        
        // Add arbitrage profit if any
        if (arbitrageProfit > 0) {
            position.accruedYield += arbitrageProfit;
            totalEcosystemYield += arbitrageProfit;
        }
    }

    function _deployToProtocol(address protocol, uint256 amount, address asset) internal {
        // Deploy to specific Flow protocol
        // This would integrate with More.Markets, IncrementFi, etc.
        
        if (protocol == address(0)) return;
        
        // Simplified deployment - in practice would call specific protocol functions
        IERC20(asset).approve(protocol, amount);
        
        // Track protocol deployment
        protocolTVLs[protocol] += amount;
    }

    function _findBestValidator() internal view returns (address) {
        address bestValidator = address(0);
        uint256 bestScore = 0;
        
        for (uint256 i = 0; i < topValidators.length; i++) {
            address validator = topValidators[i];
            
            try epochRewards.getNodeInfo(validator) returns (
                uint256 totalStaked,
                uint256 commission,
                uint256 uptime,
                bool active
            ) {
                if (active && uptime >= 9500) { // 95% minimum uptime
                    // Score based on low commission and high uptime
                    uint256 score = (uptime * 10000) / (commission + 100);
                    if (score > bestScore) {
                        bestScore = score;
                        bestValidator = validator;
                    }
                }
            } catch {
                continue;
            }
        }
        
        return bestValidator;
    }

    function _updateProtocolData() internal {
        // Update protocol APYs, TVLs, and risk scores
        try protocolAggregator.getAllProtocols() returns (
            IFlowProtocolAggregator.ProtocolInfo[] memory protocols
        ) {
            for (uint256 i = 0; i < protocols.length; i++) {
                IFlowProtocolAggregator.ProtocolInfo memory protocol = protocols[i];
                protocolAPYs[protocol.contractAddress] = protocol.apy;
                protocolTVLs[protocol.contractAddress] = protocol.tvl;
                protocolRisks[protocol.contractAddress] = protocol.riskScore;
            }
        } catch {
            // Protocol data update failed
        }
    }

    function _checkCrossAssetArbitrage(uint256 amount) internal returns (uint256 profit) {
        // Check for arbitrage opportunities between FLOW/WETH/USDC/USDT
        
        for (uint256 i = 0; i < supportedAssets.length; i++) {
            for (uint256 j = i + 1; j < supportedAssets.length; j++) {
                address assetA = supportedAssets[i];
                address assetB = supportedAssets[j];
                
                uint256 arbProfit = _calculateArbitrageProfit(assetA, assetB, amount / 10); // Use 10% for arb
                if (arbProfit > 0) {
                    _executeArbitrage(assetA, assetB, amount / 10);
                    profit += arbProfit;
                    
                    emit CrossAssetArbitrage(assetA, assetB, arbProfit);
                }
            }
        }
        
        return profit;
    }

    function _calculateArbitrageProfit(address assetA, address assetB, uint256 amount) internal view returns (uint256) {
        // Simplified arbitrage calculation
        // In practice would check prices across multiple Flow DEXs
        return 0; // Placeholder
    }

    function _executeArbitrage(address assetA, address assetB, uint256 amount) internal {
        // Execute arbitrage between assets
        // Would use Flash loans if available on Flow
    }

    function _convertToFlow(uint256 amount) internal returns (uint256) {
        if (address(assetToken) == FLOW_TOKEN) {
            return amount;
        }
        
        // Convert other assets to FLOW via DEX
        // Simplified - would use best DEX route
        return amount; // Placeholder
    }

    function _estimateValidatorRewards(address validator, uint256 amount) internal view returns (uint256) {
        // Estimate validator delegation rewards
        // Based on validator performance and commission
        return (amount * 800) / 10000; // 8% estimated APY
    }

    function _calculateExpectedAPY(address[] memory protocols, uint256[] memory amounts) internal view returns (uint256) {
        uint256 totalAmount = 0;
        uint256 weightedAPY = 0;
        
        for (uint256 i = 0; i < protocols.length && i < amounts.length; i++) {
            uint256 protocolAPY = protocolAPYs[protocols[i]];
            weightedAPY += (amounts[i] * protocolAPY);
            totalAmount += amounts[i];
        }
        
        return totalAmount > 0 ? weightedAPY / totalAmount : 0;
    }

    function _harvestRewards(bytes calldata) internal override {
        // Harvest from all ecosystem positions
        for (uint256 i = 0; i < activePositions.length; i++) {
            _harvestEcosystemPosition(activePositions[i]);
        }
        
        // Rebalance if needed
        if (block.timestamp >= lastRebalanceTime + rebalanceInterval) {
            _rebalanceEcosystem();
        }
        
        // Execute any pending arbitrage opportunities
        _checkCrossAssetArbitrage(assetToken.balanceOf(address(this)));
    }

    function _harvestEcosystemPosition(bytes32 positionId) internal {
        FlowEcosystemPosition storage position = ecosystemPositions[positionId];
        
        if (!position.active) return;
        
        uint256 totalHarvested = 0;
        
        // Harvest from each protocol in the position
        for (uint256 i = 0; i < position.protocols.length; i++) {
            address protocol = position.protocols[i];
            
            if (protocol == FLOW_TOKEN_STAKING) {
                // Harvest native FLOW staking rewards
                try flowStaking.claimRewards() returns (uint256 rewards) {
                    totalHarvested += rewards;
                } catch {}
            } else if (_isValidator(protocol)) {
                // Harvest validator delegation rewards
                try epochRewards.claimDelegatorRewards(protocol) returns (uint256 rewards) {
                    totalHarvested += rewards;
                } catch {}
            } else {
                // Harvest from other protocols
                // Would call protocol-specific harvest functions
            }
        }
        
        position.accruedYield += totalHarvested;
        totalEcosystemYield += totalHarvested;
    }

    function _rebalanceEcosystem() internal {
        // Rebalance entire ecosystem for optimal yield
        uint256 totalValue = _getTotalEcosystemValue();
        
        // Update all protocol data
        _updateProtocolData();
        
        // Find new optimal allocation
        try protocolAggregator.getOptimalProtocol(totalValue, 6000) returns (
            address optimalProtocol,
            uint256 expectedAPY
        ) {
            // Execute rebalancing if significantly better
            if (expectedAPY > _getCurrentWeightedAPY() + 200) { // 2% improvement threshold
                _executeRebalancing(optimalProtocol, totalValue);
                
                emit EcosystemRebalanced(totalValue, expectedAPY);
            }
        } catch {}
        
        lastRebalanceTime = block.timestamp;
    }

    function _getTotalEcosystemValue() internal view returns (uint256) {
        uint256 totalValue = assetToken.balanceOf(address(this));
        
        for (uint256 i = 0; i < activePositions.length; i++) {
            FlowEcosystemPosition memory position = ecosystemPositions[activePositions[i]];
            if (position.active) {
                for (uint256 j = 0; j < position.amounts.length; j++) {
                    totalValue += position.amounts[j];
                }
                totalValue += position.accruedYield;
            }
        }
        
        return totalValue;
    }

    function _getCurrentWeightedAPY() internal view returns (uint256) {
        // Calculate current weighted APY across all positions
        uint256 totalValue = 0;
        uint256 weightedAPY = 0;
        
        for (uint256 i = 0; i < activePositions.length; i++) {
            FlowEcosystemPosition memory position = ecosystemPositions[activePositions[i]];
            if (position.active) {
                for (uint256 j = 0; j < position.protocols.length && j < position.amounts.length; j++) {
                    uint256 amount = position.amounts[j];
                    uint256 apy = protocolAPYs[position.protocols[j]];
                    
                    weightedAPY += (amount * apy);
                    totalValue += amount;
                }
            }
        }
        
        return totalValue > 0 ? weightedAPY / totalValue : 0;
    }

    function _executeRebalancing(address newOptimalProtocol, uint256 totalValue) internal {
        // Close all current positions and redeploy optimally
        // Simplified implementation
    }

    function _isValidator(address addr) internal view returns (bool) {
        for (uint256 i = 0; i < topValidators.length; i++) {
            if (topValidators[i] == addr) return true;
        }
        return false;
    }

    function _emergencyWithdraw(bytes calldata) internal override returns (uint256 recovered) {
        // Emergency withdraw from all ecosystem positions
        uint256 totalRecovered = 0;
        
        // Withdraw from native staking
        try flowStaking.claimRewards() returns (uint256 stakingRewards) {
            totalRecovered += stakingRewards;
        } catch {}
        
        // Withdraw from validators
        for (uint256 i = 0; i < topValidators.length; i++) {
            address validator = topValidators[i];
            uint256 delegated = validatorAllocations[validator];
            
            if (delegated > 0) {
                try epochRewards.undelegateStake(validator, delegated) {
                    totalRecovered += delegated;
                    validatorAllocations[validator] = 0;
                } catch {}
            }
        }
        
        // Add liquid balance
        totalRecovered += assetToken.balanceOf(address(this));
        
        return totalRecovered;
    }

    function getBalance() external view override returns (uint256) {
        return _getTotalEcosystemValue();
    }

    // View functions
    function getEcosystemPerformance() external view returns (
        uint256 totalYield,
        uint256 activePositionCount,
        uint256 currentAPY,
        uint256 totalEcosystemValue
    ) {
        totalYield = totalEcosystemYield;
        activePositionCount = activePositions.length;
        currentAPY = _getCurrentWeightedAPY();
        totalEcosystemValue = _getTotalEcosystemValue();
    }

    function getEcosystemPosition(bytes32 positionId) external view returns (FlowEcosystemPosition memory) {
        return ecosystemPositions[positionId];
    }

    function getAllActivePositions() external view returns (FlowEcosystemPosition[] memory) {
        FlowEcosystemPosition[] memory positions = new FlowEcosystemPosition[](activePositions.length);
        
        for (uint256 i = 0; i < activePositions.length; i++) {
            positions[i] = ecosystemPositions[activePositions[i]];
        }
        
        return positions;
    }

    function getProtocolData() external view returns (
        address[] memory protocols,
        uint256[] memory apys,
        uint256[] memory tvls,
        uint256[] memory risks
    ) {
        // Return data for all tracked protocols
        try protocolAggregator.getAllProtocols() returns (
            IFlowProtocolAggregator.ProtocolInfo[] memory protocolInfos
        ) {
            protocols = new address[](protocolInfos.length);
            apys = new uint256[](protocolInfos.length);
            tvls = new uint256[](protocolInfos.length);
            risks = new uint256[](protocolInfos.length);
            
            for (uint256 i = 0; i < protocolInfos.length; i++) {
                protocols[i] = protocolInfos[i].contractAddress;
                apys[i] = protocolInfos[i].apy;
                tvls[i] = protocolInfos[i].tvl;
                risks[i] = protocolInfos[i].riskScore;
            }
        } catch {
            // Return empty arrays if call fails
            protocols = new address[](0);
            apys = new uint256[](0);
            tvls = new uint256[](0);
            risks = new uint256[](0);
        }
    }

    function getSupportedAssets() external view returns (address[] memory) {
        return supportedAssets;
    }

    function getValidatorPerformance() external view returns (
        address[] memory validators,
        uint256[] memory allocations,
        uint256[] memory performance
    ) {
        validators = topValidators;
        allocations = new uint256[](topValidators.length);
        performance = new uint256[](topValidators.length);
        
        for (uint256 i = 0; i < topValidators.length; i++) {
            allocations[i] = validatorAllocations[topValidators[i]];
            performance[i] = validatorPerformance[topValidators[i]];
        }
    }

    // Admin functions
    function addSupportedAsset(address asset) external onlyRole(DEFAULT_ADMIN_ROLE) {
        supportedAssets.push(asset);
    }

    function addValidator(address validator) external onlyRole(DEFAULT_ADMIN_ROLE) {
        topValidators.push(validator);
    }

    function updateRebalanceInterval(uint256 newInterval) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newInterval >= 1 hours && newInterval <= 24 hours, "Invalid interval");
        rebalanceInterval = newInterval;
    }

    function setCadenceScript(bytes32 scriptId, bytes calldata script) external onlyRole(DEFAULT_ADMIN_ROLE) {
        cadenceScripts[scriptId] = script;
    }

    // Manual operations
    function manualRebalance() external onlyRole(HARVESTER_ROLE) {
        _rebalanceEcosystem();
    }

    function manualHarvestPosition(bytes32 positionId) external onlyRole(HARVESTER_ROLE) {
        _harvestEcosystemPosition(positionId);
    }

    function executeCadenceScript(string calldata script, bytes calldata args) external onlyRole(HARVESTER_ROLE) returns (bytes memory) {
        return cadenceIntegration.executeCadenceScript(script, args);
    }
}