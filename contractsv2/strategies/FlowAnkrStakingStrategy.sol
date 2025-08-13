// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./BaseStrategy.sol";

// Ankr Staking Protocol Interfaces (Liquid staking on Flow)
interface IAnkrStaking {
    function stake() external payable returns (uint256 shares);
    function unstake(uint256 shares) external returns (uint256 amount);
    function getSharesByAmount(uint256 amount) external view returns (uint256);
    function getAmountByShares(uint256 shares) external view returns (uint256);
    function getTotalPooledAmount() external view returns (uint256);
    function getTotalShares() external view returns (uint256);
    function getRewards(address account) external view returns (uint256);
    function claimRewards() external returns (uint256);
}

interface IAnkrToken is IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

/// @title FlowAnkrStakingStrategy - Ankr Liquid Staking on Flow
/// @notice Strategy for liquid staking FLOW tokens via Ankr
contract FlowAnkrStakingStrategy is BaseStrategy {
    using SafeERC20 for IERC20;

    // Ankr Staking contract addresses on Flow (you'll need to get these)
    address public constant ANKR_STAKING = address(0); // TODO: Get real address
    address public constant ANKR_FLOW_TOKEN = address(0); // ankrFLOW token address
    
    IAnkrStaking public immutable ankrStaking;
    IAnkrToken public immutable ankrToken; // ankrFLOW liquid staking token
    
    // Staking metrics
    uint256 public totalStaked;
    uint256 public totalShares;
    uint256 public lastRewardsClaimed;
    uint256 public cumulativeRewards;
    
    // Compound settings
    bool public autoCompound = true;
    uint256 public minClaimAmount = 0.1 ether; // 0.1 FLOW minimum to claim
    
    event FlowStaked(uint256 amount, uint256 shares);
    event FlowUnstaked(uint256 shares, uint256 amount);
    event RewardsClaimed(uint256 amount);
    event RewardsCompounded(uint256 amount);

    constructor(
        address _asset, // Should be FLOW token
        address _vault,
        string memory _name
    ) BaseStrategy(_asset, ANKR_STAKING, _vault, _name) {
        require(_asset != address(0), "Asset must be FLOW token");
        
        ankrStaking = IAnkrStaking(ANKR_STAKING);
        ankrToken = IAnkrToken(ANKR_FLOW_TOKEN);
    }

    function _executeStrategy(uint256 amount, bytes calldata data) internal override {
        // Decode auto-compound setting if provided
        bool autoCompoundSetting = data.length > 0 ? abi.decode(data, (bool)) : true;
        autoCompound = autoCompoundSetting;
        
        // Stake FLOW tokens
        _stakeFlow(amount);
    }

    function _stakeFlow(uint256 amount) internal {
        // For Flow native token staking, we might need to convert ERC20 to native
        // This depends on how Ankr implements Flow staking
        
        try ankrStaking.stake{value: amount}() returns (uint256 shares) {
            totalStaked += amount;
            totalShares += shares;
            
            emit FlowStaked(amount, shares);
        } catch {
            // If direct staking fails, try with token approval
            assetToken.approve(address(ankrStaking), amount);
            // Would need different function for ERC20 staking
            revert("ERC20 staking not implemented");
        }
    }

    function _harvestRewards(bytes calldata) internal override {
        // Check for staking rewards
        uint256 pendingRewards = ankrStaking.getRewards(address(this));
        
        if (pendingRewards >= minClaimAmount) {
            try ankrStaking.claimRewards() returns (uint256 claimed) {
                cumulativeRewards += claimed;
                lastRewardsClaimed = block.timestamp;
                
                emit RewardsClaimed(claimed);
                
                if (autoCompound && claimed >= minHarvestAmount) {
                    // Compound by staking the rewards
                    _stakeFlow(claimed);
                    emit RewardsCompounded(claimed);
                } else {
                    // Send rewards to vault
                    // Note: Rewards might be in native FLOW, need to handle conversion
                }
            } catch {
                // Claim failed
            }
        }
    }

    function _emergencyWithdraw(bytes calldata) internal override returns (uint256 recovered) {
        // Unstake all shares
        uint256 sharesBalance = totalShares;
        
        if (sharesBalance > 0) {
            try ankrStaking.unstake(sharesBalance) returns (uint256 amount) {
                recovered = amount;
                totalStaked = 0;
                totalShares = 0;
                
                emit FlowUnstaked(sharesBalance, amount);
            } catch {
                // Emergency unstaking failed
                // Try unstaking ankrFLOW tokens if available
                uint256 ankrBalance = ankrToken.balanceOf(address(this));
                if (ankrBalance > 0) {
                    // Transfer ankrFLOW tokens to vault
                    ankrToken.transfer(vault, ankrBalance);
                    recovered = ankrBalance; // Approximate value
                }
            }
        }
        
        return recovered;
    }

    function getBalance() external view override returns (uint256) {
        if (totalShares == 0) {
            return assetToken.balanceOf(address(this));
        }
        
        // Calculate current value of staked position
        uint256 stakedValue = ankrStaking.getAmountByShares(totalShares);
        uint256 pendingRewards = ankrStaking.getRewards(address(this));
        uint256 liquidBalance = assetToken.balanceOf(address(this));
        
        return stakedValue + pendingRewards + liquidBalance;
    }

    // View functions
    function getStakingInfo() external view returns (
        uint256 staked,
        uint256 shares,
        uint256 currentValue,
        uint256 pendingRewards,
        uint256 totalRewards,
        uint256 stakingAPY
    ) {
        staked = totalStaked;
        shares = totalShares;
        currentValue = shares > 0 ? ankrStaking.getAmountByShares(shares) : 0;
        pendingRewards = ankrStaking.getRewards(address(this));
        totalRewards = cumulativeRewards + pendingRewards;
        
        // Calculate approximate APY based on current vs initial stake
        if (totalStaked > 0 && block.timestamp > lastRewardsClaimed) {
            uint256 timeElapsed = block.timestamp - lastRewardsClaimed;
            uint256 annualizedReturn = (totalRewards * 365 days * 10000) / (totalStaked * timeElapsed);
            stakingAPY = annualizedReturn;
        }
    }

    function getShareValue() external view returns (uint256) {
        return totalShares > 0 ? ankrStaking.getAmountByShares(1 ether) : 1 ether;
    }

    // Manual operations
    function manualClaimRewards() external onlyRole(HARVESTER_ROLE) {
        uint256 pendingRewards = ankrStaking.getRewards(address(this));
        if (pendingRewards > 0) {
            ankrStaking.claimRewards();
        }
    }

    function manualCompound() external onlyRole(HARVESTER_ROLE) {
        uint256 balance = assetToken.balanceOf(address(this));
        if (balance >= minHarvestAmount) {
            _stakeFlow(balance);
        }
    }

    // Admin functions
    function setAutoCompound(bool _autoCompound) external onlyRole(DEFAULT_ADMIN_ROLE) {
        autoCompound = _autoCompound;
    }

    function setMinClaimAmount(uint256 _minClaimAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minClaimAmount = _minClaimAmount;
    }

    function emergencyUnstake(uint256 shares) external onlyRole(EMERGENCY_ROLE) {
        if (shares <= totalShares) {
            ankrStaking.unstake(shares);
            totalShares -= shares;
        }
    }

    // Handle native FLOW if needed
    receive() external payable {
        // Handle native FLOW receipts from staking rewards
    }
}