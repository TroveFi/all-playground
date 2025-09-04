// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IStrategy - Interface for yield strategies
/// @notice Standard interface that all strategies must implement
interface IStrategy {
    /// @notice Execute the strategy with given amount and data
    /// @param amount Amount of tokens to deploy
    /// @param data Strategy-specific execution data
    function execute(uint256 amount, bytes calldata data) external;

    /// @notice Harvest yield from the strategy
    /// @param data Strategy-specific harvest data
    function harvest(bytes calldata data) external;

    /// @notice Emergency exit - withdraw all funds
    /// @param data Emergency exit data
    function emergencyExit(bytes calldata data) external;

    /// @notice Get current balance/value in the strategy
    /// @return balance Current balance in underlying token terms
    function getBalance() external view returns (uint256 balance);

    /// @notice Get the underlying token address
    /// @return token Address of the underlying token
    function underlyingToken() external view returns (address token);

    /// @notice Get the protocol address this strategy interacts with
    /// @return protocol Address of the main protocol contract
    function protocol() external view returns (address protocol);

    /// @notice Check if strategy is paused
    /// @return paused True if strategy is paused
    function paused() external view returns (bool paused);

    /// @notice Set strategy pause state (admin only)
    /// @param pauseState New pause state
    function setPaused(bool pauseState) external;
}