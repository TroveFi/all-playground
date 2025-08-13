// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./BaseStrategy.sol";

// More.Markets Protocol Interfaces (Real Flow Lending Protocol)
interface IMoreMarketsPool {
    function supply(address asset, uint256 amount, address onBehalfOf) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
    function borrow(address asset, uint256 amount, address onBehalfOf) external;
    function repay(address asset, uint256 amount, address onBehalfOf) external returns (uint256);
    
    function getReserveData(address asset) external view returns (
        uint256 availableLiquidity,
        uint256 totalBorrows,
        uint256 liquidityRate,
        uint256 borrowRate,
        uint256 liquidityIndex,
        uint256 borrowIndex,
        uint40 lastUpdateTimestamp
    );
    
    function getUserReserveData(address asset, address user) external view returns (
        uint256 currentBalance,
        uint256 currentBorrowBalance,
        uint256 principalBorrowBalance,
        uint256 borrowRateMode,
        uint256 borrowRate,
        uint256 liquidityRate,
        uint40 lastUpdateTimestamp,
        bool usageAsCollateralEnabled
    );
}

interface IMoreMarketsToken is IERC20 {
    function redeem(uint256 amount) external;
    function mint(uint256 amount) external;
    function balanceOfUnderlying(address account) external view returns (uint256);
}

/// @title FlowMoreMarketsStrategy - Real More.Markets Integration on Flow
/// @notice Strategy for lending/borrowing on More.Markets (Flow's lending protocol)
contract FlowMoreMarketsStrategy is BaseStrategy {
    using SafeERC20 for IERC20;

    // More.Markets contract addresses on Flow (you'll need to get these)
    address public constant MORE_MARKETS_POOL = address(0); // TODO: Get real address
    
    IMoreMarketsPool public immutable pool;
    IMoreMarketsToken public immutable mToken; // More.Markets interest-bearing token
    
    // Looping strategy parameters
    bool public loopingEnabled = false;
    uint256 public targetLTV = 7500; // 75% loan-to-value ratio
    uint256 public maxLoops = 5;
    uint256 public currentLoops = 0;
    
    // Strategy metrics
    uint256 public totalSupplied;
    uint256 public totalBorrowed;
    uint256 public lastSupplyRate;
    
    event SupplyExecuted(uint256 amount);
    event WithdrawExecuted(uint256 amount);
    event LoopingExecuted(uint256 loops, uint256 totalSupplied, uint256 totalBorrowed);
    event LoopingUnwound(uint256 totalRecovered);

    constructor(
        address _asset,
        address _mToken,
        address _vault,
        string memory _name
    ) BaseStrategy(_asset, MORE_MARKETS_POOL, _vault, _name) {
        require(_mToken != address(0), "Invalid mToken");
        
        pool = IMoreMarketsPool(MORE_MARKETS_POOL);
        mToken = IMoreMarketsToken(_mToken);
    }

    function _executeStrategy(uint256 amount, bytes calldata data) internal override {
        // Decode looping parameters if provided
        (bool enableLooping, uint256 ltv, uint256 maxLoopsParam) = data.length > 0 
            ? abi.decode(data, (bool, uint256, uint256))
            : (false, 7500, 3);
        
        if (enableLooping) {
            loopingEnabled = true;
            targetLTV = ltv;
            maxLoops = maxLoopsParam;
            _executeLoopingStrategy(amount);
        } else {
            _executeSimpleSupply(amount);
        }
    }

    function _executeSimpleSupply(uint256 amount) internal {
        // Simple supply to More.Markets
        assetToken.approve(address(pool), amount);
        pool.supply(address(assetToken), amount, address(this));
        
        totalSupplied += amount;
        emit SupplyExecuted(amount);
    }

    function _executeLoopingStrategy(uint256 initialAmount) internal {
        uint256 currentSupply = initialAmount;
        uint256 totalNewSupply = 0;
        uint256 totalNewBorrow = 0;
        
        // Initial supply
        assetToken.approve(address(pool), currentSupply);
        pool.supply(address(assetToken), currentSupply, address(this));
        totalNewSupply += currentSupply;
        
        // Looping: borrow and re-supply
        for (uint256 i = 0; i < maxLoops; i++) {
            uint256 borrowAmount = (currentSupply * targetLTV) / 10000;
            
            try pool.borrow(address(assetToken), borrowAmount, address(this)) {
                totalNewBorrow += borrowAmount;
                
                // Re-supply the borrowed amount
                assetToken.approve(address(pool), borrowAmount);
                pool.supply(address(assetToken), borrowAmount, address(this));
                totalNewSupply += borrowAmount;
                
                currentSupply = borrowAmount;
                currentLoops++;
            } catch {
                break; // Stop if borrowing fails
            }
        }
        
        totalSupplied += totalNewSupply;
        totalBorrowed += totalNewBorrow;
        
        emit LoopingExecuted(currentLoops, totalNewSupply, totalNewBorrow);
    }

    function _harvestRewards(bytes calldata) internal override {
        // Check for accrued interest
        uint256 currentBalance = mToken.balanceOfUnderlying(address(this));
        uint256 earnedInterest = currentBalance > totalSupplied ? currentBalance - totalSupplied : 0;
        
        if (earnedInterest >= minHarvestAmount) {
            // Withdraw the earned interest
            try pool.withdraw(address(assetToken), earnedInterest, address(this)) {
                // Interest harvested successfully
            } catch {
                // Harvest failed
            }
        }
        
        _updateMetrics();
    }

    function _emergencyWithdraw(bytes calldata) internal override returns (uint256 recovered) {
        if (loopingEnabled && totalBorrowed > 0) {
            // Unwind looping position
            recovered = _unwindLoopingPosition();
        } else {
            // Simple withdrawal
            uint256 balance = mToken.balanceOfUnderlying(address(this));
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

    function _unwindLoopingPosition() internal returns (uint256 recovered) {
        uint256 totalRecovered = 0;
        
        // Gradually unwind the looping position
        for (uint256 i = 0; i < maxLoops && totalBorrowed > 0; i++) {
            uint256 currentBorrow = totalBorrowed;
            
            // Withdraw what we can
            try pool.withdraw(address(assetToken), currentBorrow, address(this)) returns (uint256 withdrawn) {
                // Repay the loan
                assetToken.approve(address(pool), withdrawn);
                try pool.repay(address(assetToken), withdrawn, address(this)) returns (uint256 repaid) {
                    totalBorrowed = totalBorrowed > repaid ? totalBorrowed - repaid : 0;
                    totalRecovered += (withdrawn - repaid);
                } catch {
                    break;
                }
            } catch {
                break;
            }
        }
        
        // Final withdrawal of remaining supplied assets
        try pool.withdraw(address(assetToken), type(uint256).max, address(this)) returns (uint256 finalWithdrawal) {
            totalRecovered += finalWithdrawal;
        } catch {
            // Final withdrawal failed
        }
        
        // Reset state
        currentLoops = 0;
        totalSupplied = 0;
        totalBorrowed = 0;
        loopingEnabled = false;
        
        emit LoopingUnwound(totalRecovered);
        return totalRecovered;
    }

    function getBalance() external view override returns (uint256) {
        if (address(mToken) == address(0)) {
            return assetToken.balanceOf(address(this));
        }
        
        uint256 supplied = mToken.balanceOfUnderlying(address(this));
        uint256 borrowed = totalBorrowed; // Simplified - would need actual borrowed balance
        uint256 liquid = assetToken.balanceOf(address(this));
        
        return supplied > borrowed ? (supplied - borrowed) + liquid : liquid;
    }

    function _updateMetrics() internal {
        try pool.getReserveData(address(assetToken)) returns (
            uint256,
            uint256,
            uint256 liquidityRate,
            uint256,
            uint256,
            uint256,
            uint40
        ) {
            lastSupplyRate = liquidityRate;
        } catch {
            // Update failed
        }
    }

    // View functions
    function getCurrentSupplyRate() external view returns (uint256) {
        try pool.getReserveData(address(assetToken)) returns (
            uint256,
            uint256,
            uint256 liquidityRate,
            uint256,
            uint256,
            uint256,
            uint40
        ) {
            return liquidityRate;
        } catch {
            return lastSupplyRate;
        }
    }

    function getPositionInfo() external view returns (
        uint256 supplied,
        uint256 borrowed,
        uint256 netPosition,
        uint256 currentLTV,
        uint256 loops
    ) {
        supplied = totalSupplied;
        borrowed = totalBorrowed;
        netPosition = supplied > borrowed ? supplied - borrowed : 0;
        currentLTV = supplied > 0 ? (borrowed * 10000) / supplied : 0;
        loops = currentLoops;
    }

    // Admin functions
    function enableLooping(uint256 ltv, uint256 maxLoopsParam) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(ltv <= 8500, "LTV too high"); // Max 85%
        require(maxLoopsParam <= 10, "Too many loops");
        
        loopingEnabled = true;
        targetLTV = ltv;
        maxLoops = maxLoopsParam;
    }

    function disableLooping() external onlyRole(DEFAULT_ADMIN_ROLE) {
        loopingEnabled = false;
    }

    function emergencyUnwindLooping() external onlyRole(EMERGENCY_ROLE) {
        _unwindLoopingPosition();
    }
}