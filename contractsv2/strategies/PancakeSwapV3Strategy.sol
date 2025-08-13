// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./BaseStrategy.sol";

// Real PancakeSwap V3 Interfaces
interface INonfungiblePositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    struct IncreaseLiquidityParams {
        uint256 tokenId;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    function mint(MintParams calldata params) external payable returns (
        uint256 tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );

    function increaseLiquidity(IncreaseLiquidityParams calldata params) external payable returns (
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );

    function decreaseLiquidity(DecreaseLiquidityParams calldata params) external payable returns (
        uint256 amount0,
        uint256 amount1
    );

    function collect(CollectParams calldata params) external payable returns (
        uint256 amount0,
        uint256 amount1
    );

    function positions(uint256 tokenId) external view returns (
        uint96 nonce,
        address operator,
        address token0,
        address token1,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 feeGrowthInside0LastX128,
        uint256 feeGrowthInside1LastX128,
        uint128 tokensOwed0,
        uint128 tokensOwed1
    );

    function burn(uint256 tokenId) external payable;
    function approve(address to, uint256 tokenId) external;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function ownerOf(uint256 tokenId) external view returns (address);
}

interface ISmartRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

interface IPancakeV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

interface IPancakeV3Pool {
    function slot0() external view returns (
        uint160 sqrtPriceX96,
        int24 tick,
        uint16 observationIndex,
        uint16 observationCardinality,
        uint16 observationCardinalityNext,
        uint8 feeProtocol,
        bool unlocked
    );

    function liquidity() external view returns (uint128);
    function tickSpacing() external view returns (int24);
}

/// @title PancakeSwapV3Strategy - Real PancakeSwap V3 Integration
/// @notice Strategy that provides liquidity to PancakeSwap V3 pools for yield generation
contract PancakeSwapV3Strategy is BaseStrategy {
    using SafeERC20 for IERC20;

    // Real PancakeSwap V3 contract addresses on Etherlink
    address public constant PANCAKE_FACTORY = 0xfaAdaeBdcc60A2FeC900285516F4882930Db8Ee8;
    address public constant POSITION_MANAGER = 0x79b1a1445e53fe7bC9063c0d54A531D1d2f814D7;
    address public constant SMART_ROUTER = 0x8a7bBf269B95875FC1829901bb2c815029d8442e;

    IERC20 public immutable pairedToken; // Token to pair with (e.g., WETH, USDC)
    address public immutable poolAddress;
    uint24 public immutable poolFee;

    INonfungiblePositionManager public immutable positionManager;
    ISmartRouter public immutable smartRouter;

    // Position tracking
    uint256 public currentTokenId; // NFT token ID for our LP position
    int24 public tickLower;
    int24 public tickUpper;
    uint128 public liquidity;

    // Liquidity provision settings
    int24 public tickRangeMultiplier = 10; // Default range multiplier
    bool public autoCompound = true;

    // Price range tracking
    uint256 public lastRebalanceTime;
    int24 public lastRecordedTick;

    // Events
    event LiquidityAdded(uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
    event LiquidityRemoved(uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
    event FeesCollected(uint256 amount0, uint256 amount1);
    event PositionRebalanced(uint256 oldTokenId, uint256 newTokenId, int24 newTickLower, int24 newTickUpper);

    constructor(
        address _asset,
        address _pairedToken,
        uint24 _poolFee,
        address _vault,
        string memory _name
    ) BaseStrategy(_asset, POSITION_MANAGER, _vault, _name) {
        require(_pairedToken != address(0), "Invalid paired token");

        pairedToken = IERC20(_pairedToken);
        poolFee = _poolFee;

        positionManager = INonfungiblePositionManager(POSITION_MANAGER);
        smartRouter = ISmartRouter(SMART_ROUTER);

        // Get pool address
        poolAddress = IPancakeV3Factory(PANCAKE_FACTORY).getPool(_asset, _pairedToken, _poolFee);
        require(poolAddress != address(0), "Pool does not exist");
    }

    function _executeStrategy(uint256 amount, bytes calldata data) internal override {
        // Decode strategy-specific data if provided
        (uint256 minPairedTokenAmount, bool swapHalf) = data.length > 0 
            ? abi.decode(data, (uint256, bool))
            : (0, true);

        if (swapHalf) {
            // Swap half the asset token for paired token to create balanced liquidity
            uint256 swapAmount = amount / 2;
            _swapExactInputSingle(address(assetToken), address(pairedToken), swapAmount);
        }

        // Add liquidity to the pool
        _addLiquidity();