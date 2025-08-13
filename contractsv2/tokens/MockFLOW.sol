// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title Mock FLOW Token
/// @notice Mock FLOW token for testing and Flow deployment
/// @dev Mimics the native FLOW token with 18 decimals
contract MockFLOW is ERC20, Ownable {
    uint8 private constant DECIMALS = 18;
    uint256 private constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** DECIMALS; // 1B FLOW

    constructor() ERC20("Flow Token", "FLOW") Ownable(msg.sender) {
        _mint(msg.sender, INITIAL_SUPPLY);
    }

    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }

    /// @notice Mint new tokens (only owner)
    /// @param to Address to mint to
    /// @param amount Amount to mint
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /// @notice Burn tokens from caller
    /// @param amount Amount to burn
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    /// @notice Faucet function for testing (anyone can call)
    /// @param amount Amount to mint to caller (max 1000 FLOW)
    function faucet(uint256 amount) external {
        require(
            amount <= 1000 * 10 ** DECIMALS,
            "MockFLOW: Max 1000 FLOW per faucet"
        );
        _mint(msg.sender, amount);
    }

    /// @notice Mint Flow for validator rewards simulation
    /// @param validator Address of validator
    /// @param amount Reward amount
    function mintValidatorReward(address validator, uint256 amount) external onlyOwner {
        _mint(validator, amount);
    }

    /// @notice Stake function for Flow native staking
    /// @param amount Amount to stake
    function stake(uint256 amount) external {
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        _burn(msg.sender, amount);
        // In real implementation, would delegate to validator network
    }

    /// @notice Unstake function for Flow native staking
    /// @param amount Amount to unstake
    function unstake(uint256 amount) external {
        // In real implementation, would handle unstaking period
        _mint(msg.sender, amount);
    }
}