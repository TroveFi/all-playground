// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IStrategyRegistry {
    struct StrategyInfo {
        address strategyAddress;
        uint16 chainId;
        string name;
        string protocol;
        uint256 currentAPY;
        uint256 riskScore;
        uint256 tvl;
        uint256 maxCapacity;
        uint256 minDeposit;
        bool active;
        bool crossChainEnabled;
        uint256 lastUpdate;
        bytes strategyData;
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
    );

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
    );

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
    ) external returns (bytes32 strategyHash);
}