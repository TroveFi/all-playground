// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./BaseStrategy.sol";

// IncrementFi Protocol Interfaces (Real Flow DEX)
interface IIncrementFiPool {
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
}

interface IIncrementFiFactory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IIncrementFiRouter {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external view returns (uint256[] memory amounts);
}

/// @title FlowIncrementFiStrategy - Real IncrementFi Integration on Flow
/// @notice Strategy for yield farming on IncrementFi DEX (Flow's native DEX)
contract FlowIncrementFiStrategy is BaseStrategy {
    using SafeERC20 for IERC20;

    // IncrementFi contract addresses on Flow (you'll need to get these)
    address public constant INCREMENTFI_ROUTER = address(0); // TODO: Get real address
    address public constant INCREMENTFI_FACTORY = address(0); // TODO: Get real address
    
    IERC20 public immutable pairedToken; // Token to pair with (FLOW, WETH, etc.)
    address public immutable lpToken; // LP token address
    
    IIncrementFiRouter public immutable router;
    IIncrementFiFactory public immutable factory;
    IIncrementFiPool public immutable pool;
    
    uint256 public lpTokenBalance;
    uint256 public lastRebalanceTime;
    
    // Yield farming settings
    bool public autoCompound = true;
    uint256 public slippageTolerance = 300; // 3%
    
    event LiquidityAdded(uint256 amountA, uint256 amountB, uint256 liquidity);
    event LiquidityRemoved(uint256 amountA, uint256 amountB);
    event YieldCompounded(uint256 amount);

    constructor(
        address _asset,
        address _pairedToken,
        address _vault,
        string memory _name
    ) BaseStrategy(_asset, INCREMENTFI_ROUTER, _vault, _name) {
        require(_pairedToken != address(0), "Invalid paired token");
        
        pairedToken = IERC20(_pairedToken);
        router = IIncrementFiRouter(INCREMENTFI_ROUTER);
        factory = IIncrementFiFactory(INCREMENTFI_FACTORY);
        
        // Get LP token address
        lpToken = factory.getPair(address(assetToken), _pairedToken);
        require(lpToken != address(0), "LP pair does not exist");
        
        pool = IIncrementFiPool(lpToken);
    }

    function _executeStrategy(uint256 amount, bytes calldata data) internal override {
        // Decode swap ratio if provided
        uint256 swapRatio = data.length > 0 ? abi.decode(data, (uint256)) : 5000; // 50% default
        
        // Swap portion of asset token for paired token
        uint256 swapAmount = (amount * swapRatio) / 10000;
        if (swapAmount > 0) {
            _swapForPairedToken(swapAmount);
        }
        
        // Add liquidity to IncrementFi
        _addLiquidity();
    }

    function _harvestRewards(bytes calldata) internal override {
        // IncrementFi might have staking rewards or LP fees
        // For now, we'll just compound the LP position
        if (autoCompound) {
            _compoundLiquidity();
        }
    }

    function _emergencyWithdraw(bytes calldata) internal override returns (uint256 recovered) {
        uint256 lpBalance = pool.balanceOf(address(this));
        
        if (lpBalance > 0) {
            // Remove all liquidity
            pairedToken.approve(address(router), type(uint256).max);
            assetToken.approve(address(router), type(uint256).max);
            
            try router.removeLiquidity(
                address(assetToken),
                address(pairedToken),
                lpBalance,
                0, // Accept any amount
                0, // Accept any amount
                address(this),
                block.timestamp + 300
            ) returns (uint256 amountA, uint256 amountB) {
                recovered = amountA;
                
                // Swap paired token back to asset token
                if (amountB > 0) {
                    recovered += _swapPairedTokenForAsset(amountB);
                }
            } catch {
                // Emergency exit failed
            }
        }
        
        return recovered;
    }

    function _swapForPairedToken(uint256 amountIn) internal returns (uint256 amountOut) {
        address[] memory path = new address[](2);
        path[0] = address(assetToken);
        path[1] = address(pairedToken);
        
        assetToken.approve(address(router), amountIn);
        
        try router.swapExactTokensForTokens(
            amountIn,
            0, // Accept any amount
            path,
            address(this),
            block.timestamp + 300
        ) returns (uint256[] memory amounts) {
            amountOut = amounts[amounts.length - 1];
        } catch {
            amountOut = 0;
        }
    }

    function _swapPairedTokenForAsset(uint256 amountIn) internal returns (uint256 amountOut) {
        address[] memory path = new address[](2);
        path[0] = address(pairedToken);
        path[1] = address(assetToken);
        
        pairedToken.approve(address(router), amountIn);
        
        try router.swapExactTokensForTokens(
            amountIn,
            0, // Accept any amount
            path,
            address(this),
            block.timestamp + 300
        ) returns (uint256[] memory amounts) {
            amountOut = amounts[amounts.length - 1];
        } catch {
            amountOut = 0;
        }
    }

    function _addLiquidity() internal {
        uint256 assetBalance = assetToken.balanceOf(address(this));
        uint256 pairedBalance = pairedToken.balanceOf(address(this));
        
        if (assetBalance > 0 && pairedBalance > 0) {
            assetToken.approve(address(router), assetBalance);
            pairedToken.approve(address(router), pairedBalance);
            
            try router.addLiquidity(
                address(assetToken),
                address(pairedToken),
                assetBalance,
                pairedBalance,
                (assetBalance * (10000 - slippageTolerance)) / 10000,
                (pairedBalance * (10000 - slippageTolerance)) / 10000,
                address(this),
                block.timestamp + 300
            ) returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
                lpTokenBalance += liquidity;
                emit LiquidityAdded(amountA, amountB, liquidity);
            } catch {
                // Add liquidity failed
            }
        }
    }

    function _compoundLiquidity() internal {
        // Check for any accumulated fees or rewards
        uint256 assetBalance = assetToken.balanceOf(address(this));
        uint256 pairedBalance = pairedToken.balanceOf(address(this));
        
        if (assetBalance > minHarvestAmount || pairedBalance > 0) {
            _addLiquidity();
            emit YieldCompounded(assetBalance + pairedBalance);
        }
    }

    function getBalance() external view override returns (uint256) {
        uint256 lpBalance = pool.balanceOf(address(this));
        if (lpBalance == 0) return assetToken.balanceOf(address(this));
        
        // Calculate asset token value of LP position
        uint256 totalSupply = pool.totalSupply();
        (uint112 reserve0, uint112 reserve1,) = pool.getReserves();
        
        // Determine which reserve is our asset token
        address token0 = address(assetToken) < address(pairedToken) ? address(assetToken) : address(pairedToken);
        uint256 assetReserve = token0 == address(assetToken) ? uint256(reserve0) : uint256(reserve1);
        
        // Calculate our share of the asset token reserve
        uint256 assetValue = (lpBalance * assetReserve * 2) / totalSupply; // *2 for both sides of LP
        
        return assetValue + assetToken.balanceOf(address(this));
    }

    // Admin functions
    function setAutoCompound(bool _autoCompound) external onlyRole(DEFAULT_ADMIN_ROLE) {
        autoCompound = _autoCompound;
    }

    function setSlippageTolerance(uint256 _slippageTolerance) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_slippageTolerance <= 1000, "Slippage too high"); // Max 10%
        slippageTolerance = _slippageTolerance;
    }

    function manualCompound() external onlyRole(HARVESTER_ROLE) {
        _compoundLiquidity();
    }
}