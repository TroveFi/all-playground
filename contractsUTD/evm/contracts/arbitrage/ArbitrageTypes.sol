// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library ArbitrageTypes {
    struct ArbitrageOpportunity {
        address tokenA;
        address tokenB;
        address dexA;
        address dexB;
        uint256 profitAmount;
        uint256 inputAmount;
        uint256 gasEstimate;
        uint256 profitabilityScore;
        bool isValid;
        bool requiresFlashLoan;
        uint256 timestamp;
        bytes routingData;
    }

    struct TriangularArbitrage {
        address tokenA;
        address tokenB;
        address tokenC;
        address[] dexPath;
        uint256 expectedProfit;
        uint256 minimumInput;
        bool isValid;
    }

    struct DEXInfo {
        address router;
        string name;
        bool active;
        uint256 gasOverhead;
        uint256 feeRate;
        bool supportsMultihop;
        bool supportsV3;
    }

    enum ArbitrageType {
        SIMPLE_DUAL_DEX,
        TRIANGULAR,
        FLASH_LOAN_ARBITRAGE,
        CROSS_ASSET_ARBITRAGE,
        LIQUIDITY_ARBITRAGE
    }
}

interface IPunchSwapV2Router02 {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function getAmountsOut(uint amountIn, address[] calldata path)
        external view returns (uint[] memory amounts);
}

interface IIncrementRouter {
    function exactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        address recipient,
        uint256 deadline,
        uint256 amountIn,
        uint256 amountOutMinimum,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountOut);
    
    function quoter() external view returns (address);
}

interface IQuoter {
    function quoteExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountOut);
}