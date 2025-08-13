// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IRiskOracle {
    struct RiskAssessment {
        uint256 riskScore;
        uint256 confidenceLevel;
        string riskLevel;
        uint256 timestamp;
        address assessor;
        bytes32 dataHash;
        bool valid;
        uint256 expiryTime;
    }

    function getRiskAssessment(address protocol) external view returns (
        uint256 riskScore,
        uint256 confidenceLevel,
        string memory riskLevel,
        uint256 timestamp,
        address assessor,
        bytes32 dataHash,
        bool valid,
        uint256 expiryTime,
        bool isValid
    );
    
    function assessStrategyRisk(address strategy) external view returns (
        uint256 riskScore,
        string memory riskLevel,
        bool approved,
        uint256 maxRecommendedAmount
    );

    function updateRiskAssessment(
        address protocol,
        uint256 riskScore,
        uint256 confidenceLevel,
        string calldata riskLevel,
        bytes32 dataHash,
        bytes calldata mlModelData
    ) external;

    function isEmergencyProtocol(address protocol) external view returns (bool);
}