// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IRiskOracle.sol";

/// @title StrategyRegistry - Enhanced registry for managing real DeFi protocol strategies
/// @notice Manages cross-chain DeFi strategies with risk scoring and real protocol data
contract StrategyRegistry is AccessControl, ReentrancyGuard {
    bytes32 public constant STRATEGY_MANAGER_ROLE = keccak256("STRATEGY_MANAGER_ROLE");
    bytes32 public constant RISK_ORACLE_ROLE = keccak256("RISK_ORACLE_ROLE");
    bytes32 public constant PYTHON_AGENT_ROLE = keccak256("PYTHON_AGENT_ROLE");

    struct StrategyInfo {
        address strategyAddress;
        uint16 chainId;
        string name;
        string protocol;
        address protocolContract;
        uint256 currentAPY;
        uint256 riskScore;
        uint256 tvl;
        uint256 maxCapacity;
        uint256 minDeposit;
        bool active;
        bool crossChainEnabled;
        uint256 lastUpdate;
        bytes strategyData;
        uint256 protocolTVL;
        uint256 liquidityRating;
        uint256 auditScore;
        address[] underlyingTokens;
    }

    struct ChainInfo {
        uint16 chainId;
        string name;
        address bridgeContract;
        bool active;
        uint256 bridgeFee;
        uint256 averageBlockTime;
        uint256 gasPrice;
        uint256 protocolCount;
    }

    struct RealTimeMetrics {
        uint256 timestamp;
        uint256 apy;
        uint256 volume24h;
        uint256 tvlChange24h;
        uint256 volatility;
        uint256 liquidityDepth;
        bool anomalyDetected;
        bytes32 dataSource;
    }

    struct ProtocolIntegration {
        string protocolName;
        address mainContract;
        string contractType;
        address[] supportedTokens;
        uint256[] poolIds;
        bool verified;
        uint256 integrationDate;
        string apiEndpoint;
    }

    // Core mappings
    mapping(bytes32 => StrategyInfo) public strategies;
    mapping(string => bytes32[]) public strategiesByName;
    mapping(uint16 => bytes32[]) public strategiesByChain;
    mapping(address => bytes32) public strategyByAddress;
    mapping(string => ProtocolIntegration) public protocolIntegrations;

    // Real-time data
    mapping(bytes32 => RealTimeMetrics) public realTimeMetrics;
    mapping(bytes32 => uint256[]) public apyHistory;
    mapping(bytes32 => uint256) public lastDataUpdate;

    // Chain management
    mapping(uint16 => ChainInfo) public chains;
    uint16[] public supportedChains;

    // Protocol-specific configurations
    uint16 public constant ETHERLINK_CHAIN_ID = 30302;
    uint256 public dataFreshnessThreshold = 1 hours;
    uint256 public minTVLForListing = 100000 * 10**6;
    uint256 public maxRiskScore = 7000;

    // Real protocol addresses
    struct KnownProtocols {
        address superlendPool;
        address pancakeFactory;
        address pancakeRouter;
        address aaveOracle;
        address aclManager;
    }

    KnownProtocols public knownProtocols;

    event StrategyRegistered(bytes32 indexed strategyHash, string name, uint16 chainId, address strategy);
    event RealTimeDataUpdated(bytes32 indexed strategyHash, uint256 apy, uint256 tvl, uint256 timestamp);
    event ProtocolIntegrationAdded(string indexed protocolName, address mainContract, string contractType);
    event AnomalyDetected(bytes32 indexed strategyHash, string anomalyType, uint256 severity);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(STRATEGY_MANAGER_ROLE, msg.sender);
        _grantRole(RISK_ORACLE_ROLE, msg.sender);

        // Initialize known protocol addresses for Flow/Etherlink
        knownProtocols = KnownProtocols({
            superlendPool: 0x5e580E0FF1981E7c916D6D9a036A8596E35fCE31,
            pancakeFactory: 0xfaAdaeBdcc60A2FeC900285516F4882930Db8Ee8,
            pancakeRouter: 0x8a7bBf269B95875FC1829901bb2c815029d8442e,
            aaveOracle: 0xE06cda30A2d4714fECE928b36497b8462A21d79a,
            aclManager: 0x3941BfFABA0db23934e67FD257cC6F724F0DDd23
        });

        _initializeEtherlinkChain();
        _initializeProtocolIntegrations();
    }

    function _initializeEtherlinkChain() internal {
        chains[ETHERLINK_CHAIN_ID] = ChainInfo({
            chainId: ETHERLINK_CHAIN_ID,
            name: "etherlink",
            bridgeContract: address(0),
            active: true,
            bridgeFee: 0,
            averageBlockTime: 15,
            gasPrice: 1 gwei,
            protocolCount: 0
        });
        supportedChains.push(ETHERLINK_CHAIN_ID);
    }

    function _initializeProtocolIntegrations() internal {
        // Superlend integration
        address[] memory superlendTokens = new address[](4);
        superlendTokens[0] = 0x744D7931B12E890b7b32A076a918B112B950B67d; // USDC aToken
        superlendTokens[1] = 0xc7DE9218466862ce30CC415eD6d5Af61Eb7FFD57; // XTZ aToken
        superlendTokens[2] = 0x71B27362B3be20Bbb91247d8CfCaB4dADfD0244A; // WBTC aToken
        superlendTokens[3] = 0xe0339800272c442dc031fF80Cd85ac4c17AB383e; // USDT aToken

        uint256[] memory emptyPools = new uint256[](0);

        protocolIntegrations["superlend"] = ProtocolIntegration({
            protocolName: "superlend",
            mainContract: knownProtocols.superlendPool,
            contractType: "lending",
            supportedTokens: superlendTokens,
            poolIds: emptyPools,
            verified: true,
            integrationDate: block.timestamp,
            apiEndpoint: "superlend_api"
        });

        // PancakeSwap integration
        address[] memory pancakeTokens = new address[](2);
        pancakeTokens[0] = 0x79b1a1445e53fe7bC9063c0d54A531D1d2f814D7; // Position Manager
        pancakeTokens[1] = 0x8a7bBf269B95875FC1829901bb2c815029d8442e; // Smart Router

        protocolIntegrations["pancakeswap"] = ProtocolIntegration({
            protocolName: "pancakeswap",
            mainContract: knownProtocols.pancakeFactory,
            contractType: "dex",
            supportedTokens: pancakeTokens,
            poolIds: emptyPools,
            verified: true,
            integrationDate: block.timestamp,
            apiEndpoint: "pancakeswap_api"
        });
    }

    function registerRealStrategy(
        string calldata name,
        uint16 chainId,
        address strategyAddress,
        string calldata protocol,
        address protocolContract,
        uint256 initialAPY,
        uint256 maxCapacity,
        uint256 minDeposit,
        address[] calldata underlyingTokens,
        bytes calldata strategyData
    ) external onlyRole(STRATEGY_MANAGER_ROLE) returns (bytes32 strategyHash) {
        strategyHash = keccak256(abi.encodePacked(name, chainId));

        require(strategies[strategyHash].strategyAddress == address(0), "Strategy already exists");
        require(chains[chainId].active, "Chain not supported");
        require(protocolIntegrations[protocol].verified, "Protocol not verified");

        strategies[strategyHash] = StrategyInfo({
            strategyAddress: strategyAddress,
            chainId: chainId,
            name: name,
            protocol: protocol,
            protocolContract: protocolContract,
            currentAPY: initialAPY,
            riskScore: 5000,
            tvl: 0,
            maxCapacity: maxCapacity,
            minDeposit: minDeposit,
            active: true,
            crossChainEnabled: false,
            lastUpdate: block.timestamp,
            strategyData: strategyData,
            protocolTVL: 0,
            liquidityRating: 5000,
            auditScore: 7000,
            underlyingTokens: underlyingTokens
        });

        strategiesByName[name].push(strategyHash);
        strategiesByChain[chainId].push(strategyHash);
        strategyByAddress[strategyAddress] = strategyHash;

        emit StrategyRegistered(strategyHash, name, chainId, strategyAddress);
        return strategyHash;
    }

    function getOptimalStrategy(
        uint256 amount,
        uint256 maxRiskTolerance,
        bool crossChainAllowed,
        uint16 preferredChain
    ) external view returns (
        bytes32 bestStrategy,
        uint256 expectedReturn,
        uint256 riskScore,
        bool requiresBridge
    ) {
        bytes32[] memory candidates = _getEligibleStrategies(amount, maxRiskTolerance, crossChainAllowed);

        if (candidates.length == 0) {
            return (bytes32(0), 0, 0, false);
        }

        uint256 bestScore = 0;
        bestStrategy = bytes32(0);

        for (uint i = 0; i < candidates.length; i++) {
            bytes32 candidateHash = candidates[i];
            StrategyInfo memory strategy = strategies[candidateHash];

            // Calculate composite score
            uint256 apyScore = strategy.currentAPY;
            uint256 riskAdjustment = (10000 - strategy.riskScore) / 10;
            uint256 liquidityBonus = strategy.liquidityRating / 100;
            uint256 auditBonus = strategy.auditScore / 100;
            uint256 chainBonus = strategy.chainId == preferredChain ? 500 : 0;

            uint256 totalScore = apyScore + riskAdjustment + liquidityBonus + auditBonus + chainBonus;

            if (totalScore > bestScore) {
                bestScore = totalScore;
                bestStrategy = candidateHash;
            }
        }

        if (bestStrategy != bytes32(0)) {
            StrategyInfo memory selected = strategies[bestStrategy];
            return (
                bestStrategy,
                selected.currentAPY,
                selected.riskScore,
                selected.chainId != preferredChain
            );
        }

        return (bytes32(0), 0, 0, false);
    }

    function _getEligibleStrategies(
        uint256 amount,
        uint256 maxRiskTolerance,
        bool crossChainAllowed
    ) internal view returns (bytes32[] memory eligible) {
        uint256 count = 0;

        // Count eligible strategies
        for (uint i = 0; i < supportedChains.length; i++) {
            if (!crossChainAllowed && supportedChains[i] != ETHERLINK_CHAIN_ID) continue;

            bytes32[] memory chainStrategies = strategiesByChain[supportedChains[i]];
            for (uint j = 0; j < chainStrategies.length; j++) {
                StrategyInfo memory strategy = strategies[chainStrategies[j]];
                if (strategy.active && 
                    strategy.riskScore <= maxRiskTolerance &&
                    (amount == 0 || amount >= strategy.minDeposit) &&
                    (strategy.maxCapacity == 0 || strategy.tvl + amount <= strategy.maxCapacity)) {
                    count++;
                }
            }
        }

        eligible = new bytes32[](count);
        uint256 index = 0;

        // Populate eligible strategies
        for (uint i = 0; i < supportedChains.length; i++) {
            if (!crossChainAllowed && supportedChains[i] != ETHERLINK_CHAIN_ID) continue;

            bytes32[] memory chainStrategies = strategiesByChain[supportedChains[i]];
            for (uint j = 0; j < chainStrategies.length; j++) {
                StrategyInfo memory strategy = strategies[chainStrategies[j]];
                if (strategy.active && 
                    strategy.riskScore <= maxRiskTolerance &&
                    (amount == 0 || amount >= strategy.minDeposit) &&
                    (strategy.maxCapacity == 0 || strategy.tvl + amount <= strategy.maxCapacity)) {
                    eligible[index] = chainStrategies[j];
                    index++;
                }
            }
        }
    }

    function updateRealTimeMetrics(
        bytes32 strategyHash,
        uint256 currentAPY,
        uint256 volume24h,
        uint256 tvlChange24h,
        uint256 volatility,
        uint256 liquidityDepth,
        bool anomalyDetected,
        bytes32 dataSource
    ) external onlyRole(PYTHON_AGENT_ROLE) {
        require(strategies[strategyHash].strategyAddress != address(0), "Strategy not found");

        realTimeMetrics[strategyHash] = RealTimeMetrics({
            timestamp: block.timestamp,
            apy: currentAPY,
            volume24h: volume24h,
            tvlChange24h: tvlChange24h,
            volatility: volatility,
            liquidityDepth: liquidityDepth,
            anomalyDetected: anomalyDetected,
            dataSource: dataSource
        });

        strategies[strategyHash].currentAPY = currentAPY;
        strategies[strategyHash].lastUpdate = block.timestamp;

        // Store APY history
        uint256[] storage history = apyHistory[strategyHash];
        if (history.length >= 30) {
            for (uint i = 0; i < 29; i++) {
                history[i] = history[i + 1];
            }
            history[29] = currentAPY;
        } else {
            history.push(currentAPY);
        }

        lastDataUpdate[strategyHash] = block.timestamp;

        if (anomalyDetected) {
            emit AnomalyDetected(strategyHash, "METRICS_ANOMALY", volatility);
        }

        emit RealTimeDataUpdated(strategyHash, currentAPY, volume24h, block.timestamp);
    }

    function getStrategyByName(string calldata name, uint16 chainId) external view returns (
        address strategyAddress,
        uint16 chainId_,
        string memory name_,
        string memory protocol,
        uint256 currentAPY,
        uint256 riskScore,
        uint256 tvl,
        uint256 maxCapacity,
        uint256 minDeposit,
        bool active,
        bool crossChainEnabled,
        uint256 lastUpdate,
        bytes memory strategyData
    ) {
        bytes32 hash = keccak256(abi.encodePacked(name, chainId));
        StrategyInfo memory strategy = strategies[hash];
        
        return (
            strategy.strategyAddress,
            strategy.chainId,
            strategy.name,
            strategy.protocol,
            strategy.currentAPY,
            strategy.riskScore,
            strategy.tvl,
            strategy.maxCapacity,
            strategy.minDeposit,
            strategy.active,
            strategy.crossChainEnabled,
            strategy.lastUpdate,
            strategy.strategyData
        );
    }

    function addPythonAgent(address pythonAgent) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(PYTHON_AGENT_ROLE, pythonAgent);
    }

    function updateProtocolContract(string calldata protocolName, address newContract) external onlyRole(DEFAULT_ADMIN_ROLE) {
        protocolIntegrations[protocolName].mainContract = newContract;
    }
}