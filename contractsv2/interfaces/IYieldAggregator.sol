// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IYieldAggregator {
    struct OptimizedAllocation {
        address protocol;
        uint16 chainId;
        uint256 amount;
        uint256 expectedAPY;
        uint256 riskScore;
        uint256 allocation;
        uint256 gasEstimate;
        bool requiresBridge;
        bytes executionData;
    }

    function calculateOptimalAllocation(
        address asset,
        uint256 totalAmount,
        uint256 maxRiskTolerance
    ) external view returns (
        address[] memory strategies,
        uint256[] memory allocations,
        uint256 totalExpectedAPY
    );

    function getTopYieldOpportunities(
        address asset,
        uint256 maxRiskTolerance,
        uint256 count
    ) external view returns (OptimizedAllocation[] memory opportunities);

    function shouldRebalance(address asset) external view returns (
        bool shouldRebalance_,
        uint256 currentAPY,
        uint256 potentialAPY,
        uint256 improvementBps
    );
}