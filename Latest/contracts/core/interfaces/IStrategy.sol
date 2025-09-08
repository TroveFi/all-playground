// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IStrategy - Basic Strategy Interface
/// @notice Interface for basic yield strategies
interface IStrategy {
    function execute(uint256 amount, bytes calldata data) external;
    function harvest(bytes calldata data) external;
    function emergencyExit(bytes calldata data) external;
    function getBalance() external view returns (uint256 balance);
    function underlyingToken() external view returns (address token);
    function protocol() external view returns (address protocol);
    function paused() external view returns (bool paused);
    function setPaused(bool pauseState) external;
}

/// @title Enhanced IStrategy - Interface for advanced yield strategies
/// @notice Extended interface that supports looping, delta-neutral, and arbitrage strategies
interface IEnhancedStrategy is IStrategy {
    // Advanced strategy functions
    function getHealthFactor() external view returns (uint256);
    function getLeverageRatio() external view returns (uint256);
    function getPositionValue() external view returns (uint256 collateral, uint256 debt);
    function adjustLeverage(uint256 targetRatio, uint256 maxSlippage) external;
    function rebalance(bytes calldata rebalanceData) external;
    
    // Risk management
    function checkLiquidationRisk() external view returns (bool atRisk, uint256 buffer);
    function getMaxWithdrawable() external view returns (uint256);
    function emergencyDelever() external;
    
    // Strategy-specific parameters
    function setRiskParameters(
        uint256 maxLeverage,
        uint256 targetHealthFactor,
        uint256 liquidationBuffer
    ) external;

    // Events
    event LeverageAdjusted(uint256 oldRatio, uint256 newRatio, uint256 healthFactor);
    event RiskParametersUpdated(uint256 maxLeverage, uint256 targetHF, uint256 buffer);
    event EmergencyDeleverageTriggered(uint256 healthFactor);
}