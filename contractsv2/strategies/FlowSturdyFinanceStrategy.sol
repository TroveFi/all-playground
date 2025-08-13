// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./BaseStrategy.sol";

// Sturdy.Finance Protocol Interfaces (Interest-free borrowing on Flow)
interface ISturdyFinancePool {
    function deposit(address asset, uint256 amount, address onBehalfOf) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
    function borrow(address asset, uint256 amount, address onBehalfOf) external;
    function repay(address asset, uint256 amount, address onBehalfOf) external returns (uint256);
    
    function getReserveData(address asset) external view returns (
        uint256 availableLiquidity,
        uint256 totalDeposits,
        uint256 utilizationRate,
        address sTokenAddress,
        bool isActive
    );
    
    function getUserAccountData(address user) external view returns (
        uint256 totalCollateralETH,
        uint256 totalDebtETH,
        uint256 availableBorrowsETH,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    );
}

interface ISturdyToken is IERC20 {
    function balanceOfUnderlying(address account) external view returns (uint256);
}

/// @title FlowSturdyFinanceStrategy - Sturdy.Finance Integration on Flow
/// @notice Strategy for interest-free borrowing and leverage on Sturdy.Finance
contract FlowSturdyFinanceStrategy is BaseStrategy {
    using SafeERC20 for IERC20;

    // Sturdy.Finance contract addresses on Flow (you'll need to get these)
    address public constant STURDY_POOL = address(0); // TODO: Get real address
    
    ISturdyFinancePool public immutable pool;
    ISturdyToken public immutable sToken; // Sturdy interest-bearing token
    IERC20 public immutable borrowAsset; // Asset to borrow (could be different from deposit asset)
    
    // Interest-free leverage strategy
    bool public leverageEnabled = false;
    uint256 public targetLTV = 7000; // 70% LTV for interest-free borrowing
    uint256 public maxLeverageRounds = 3;
    
    // Strategy state
    uint256 public totalDeposited;
    uint256 public totalBorrowed;
    uint256 public leverageRounds;
    
    event DepositExecuted(uint256 amount);
    event LeverageExecuted(uint256 rounds, uint256 totalDeposited, uint256 totalBorrowed);
    event LeverageUnwound(uint256 recovered);
    event InterestFreeBorrow(uint256 amount);

    constructor(
        address _asset,
        address _sToken,
        address _borrowAsset,
        address _vault,
        string memory _name
    ) BaseStrategy(_asset, STURDY_POOL, _vault, _name) {
        require(_sToken != address(0), "Invalid sToken");
        require(_borrowAsset != address(0), "Invalid borrow asset");
        
        pool = ISturdyFinancePool(STURDY_POOL);
        sToken = ISturdyToken(_sToken);
        borrowAsset = IERC20(_borrowAsset);
    }

    function _executeStrategy(uint256 amount, bytes calldata data) internal override {
        // Decode leverage parameters
        (bool enableLeverage, uint256 ltv, uint256 maxRounds) = data.length > 0 
            ? abi.decode(data, (bool, uint256, uint256))
            : (false, 7000, 3);
        
        if (enableLeverage) {
            leverageEnabled = true;
            targetLTV = ltv;
            maxLeverageRounds = maxRounds;
            _executeLeverageStrategy(amount);
        } else {
            _executeSimpleDeposit(amount);
        }
    }

    function _executeSimpleDeposit(uint256 amount) internal {
        assetToken.approve(address(pool), amount);
        pool.deposit(address(assetToken), amount, address(this));
        
        totalDeposited += amount;
        emit DepositExecuted(amount);
    }

    function _executeLeverageStrategy(uint256 initialAmount) internal {
        uint256 currentDeposit = initialAmount;
        uint256 totalNewDeposits = 0;
        uint256 totalNewBorrows = 0;
        
        // Initial deposit
        assetToken.approve(address(pool), currentDeposit);
        pool.deposit(address(assetToken), currentDeposit, address(this));
        totalNewDeposits += currentDeposit;
        
        // Leverage rounds: borrow and re-deposit
        for (uint256 i = 0; i < maxLeverageRounds; i++) {
            // Calculate borrowable amount based on LTV
            uint256 borrowAmount = (currentDeposit * targetLTV) / 10000;
            
            try pool.borrow(address(borrowAsset), borrowAmount, address(this)) {
                totalNewBorrows += borrowAmount;
                emit InterestFreeBorrow(borrowAmount);
                
                // If borrowed asset is different, would need to swap here
                if (address(borrowAsset) != address(assetToken)) {
                    // For simplicity, assume 1:1 conversion or skip
                    // In reality, you'd swap via DEX
                    break;
                }
                
                // Re-deposit the borrowed amount
                borrowAsset.approve(address(pool), borrowAmount);
                pool.deposit(address(borrowAsset), borrowAmount, address(this));
                totalNewDeposits += borrowAmount;
                
                currentDeposit = borrowAmount;
                leverageRounds++;
            } catch {
                break; // Stop if borrowing fails
            }
        }
        
        totalDeposited += totalNewDeposits;
        totalBorrowed += totalNewBorrows;
        
        emit LeverageExecuted(leverageRounds, totalNewDeposits, totalNewBorrows);
    }

    function _harvestRewards(bytes calldata) internal override {
        // Sturdy.Finance is interest-free borrowing, so main yield comes from
        // the amplified exposure to the deposited asset
        
        // Check for any yield in the sToken
        uint256 currentBalance = sToken.balanceOfUnderlying(address(this));
        uint256 earnedYield = currentBalance > totalDeposited ? currentBalance - totalDeposited : 0;
        
        if (earnedYield >= minHarvestAmount) {
            // Withdraw earned yield
            try pool.withdraw(address(assetToken), earnedYield, address(this)) {
                // Yield harvested
            } catch {
                // Harvest failed
            }
        }
    }

    function _emergencyWithdraw(bytes calldata) internal override returns (uint256 recovered) {
        if (leverageEnabled && totalBorrowed > 0) {
            recovered = _unwindLeveragePosition();
        } else {
            // Simple withdrawal
            uint256 balance = sToken.balanceOfUnderlying(address(this));
            if (balance > 0) {
                try pool.withdraw(address(assetToken), type(uint256).max, address(this)) returns (uint256 withdrawn) {
                    recovered = withdrawn;
                } catch {
                    // Emergency exit failed
                }
            }
        }
        
        return recovered;
    }

    function _unwindLeveragePosition() internal returns (uint256 recovered) {
        uint256 totalRecovered = 0;
        
        // Gradually unwind leverage (reverse order)
        for (uint256 i = 0; i < maxLeverageRounds && totalBorrowed > 0; i++) {
            uint256 currentBorrow = totalBorrowed / (maxLeverageRounds - i); // Simplified
            
            // Withdraw assets to repay loan
            try pool.withdraw(address(assetToken), currentBorrow, address(this)) returns (uint256 withdrawn) {
                // Repay the interest-free loan
                assetToken.approve(address(pool), withdrawn);
                try pool.repay(address(borrowAsset), withdrawn, address(this)) returns (uint256 repaid) {
                    totalBorrowed = totalBorrowed > repaid ? totalBorrowed - repaid : 0;
                    totalRecovered += (withdrawn - repaid);
                } catch {
                    break;
                }
            } catch {
                break;
            }
        }
        
        // Final withdrawal
        try pool.withdraw(address(assetToken), type(uint256).max, address(this)) returns (uint256 finalWithdrawal) {
            totalRecovered += finalWithdrawal;
        } catch {
            // Final withdrawal failed
        }
        
        // Reset state
        leverageRounds = 0;
        totalDeposited = 0;
        totalBorrowed = 0;
        leverageEnabled = false;
        
        emit LeverageUnwound(totalRecovered);
        return totalRecovered;
    }

    function getBalance() external view override returns (uint256) {
        if (address(sToken) == address(0)) {
            return assetToken.balanceOf(address(this));
        }
        
        uint256 deposited = sToken.balanceOfUnderlying(address(this));
        uint256 borrowed = totalBorrowed;
        uint256 liquid = assetToken.balanceOf(address(this));
        
        // Since borrowing is interest-free, net position is deposit - borrowed + liquid
        return deposited > borrowed ? (deposited - borrowed) + liquid : liquid;
    }

    // View functions
    function getHealthFactor() external view returns (uint256) {
        try pool.getUserAccountData(address(this)) returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256 healthFactor
        ) {
            return healthFactor;
        } catch {
            return type(uint256).max; // No debt, infinite health
        }
    }

    function getLeverageInfo() external view returns (
        uint256 deposited,
        uint256 borrowed,
        uint256 netPosition,
        uint256 currentLTV,
        uint256 rounds,
        uint256 healthFactor
    ) {
        deposited = totalDeposited;
        borrowed = totalBorrowed;
        netPosition = deposited > borrowed ? deposited - borrowed : 0;
        currentLTV = deposited > 0 ? (borrowed * 10000) / deposited : 0;
        rounds = leverageRounds;
        healthFactor = this.getHealthFactor();
    }

    // Admin functions
    function enableLeverage(uint256 ltv, uint256 maxRounds) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(ltv <= 8000, "LTV too high for interest-free borrowing");
        require(maxRounds <= 5, "Too many leverage rounds");
        
        leverageEnabled = true;
        targetLTV = ltv;
        maxLeverageRounds = maxRounds;
    }

    function disableLeverage() external onlyRole(DEFAULT_ADMIN_ROLE) {
        leverageEnabled = false;
    }

    function emergencyUnwindLeverage() external onlyRole(EMERGENCY_ROLE) {
        _unwindLeveragePosition();
    }
}