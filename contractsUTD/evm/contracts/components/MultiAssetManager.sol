// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

interface IPunchSwapRouter {
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
}

contract MultiAssetManager is AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");

    IERC20 public immutable baseAsset;
    IPunchSwapRouter public immutable router;

    struct AssetInfo {
        bool supported;
        uint256 minDeposit;
        uint256 maxDeposit;
        uint256 conversionSlippage;
        bool requiresSwap;
        uint8 decimals;
    }

    mapping(address => AssetInfo) public supportedAssets;
    address[] public assetList;
    
    uint256 public defaultSlippage = 300; // 3%
    bool public autoConvertToBase = true;

    // Flow EVM addresses - USDF is the primary USD stablecoin
    address public constant USDF = 0x2aaBea2058b5aC2D339b163C6Ab6f2b6d53aabED;  // Main USD stablecoin
    address public constant USDT = 0x674843C06FF83502ddb4D37c2E09C01cdA38cbc8;  // Alternative stablecoin
    address public constant USDC_E = 0x7f27352D5F83Db87a5A3E00f4B07Cc2138D8ee52; // Celer bridged USDC
    address public constant STG_USDC = 0xF1815bd50389c46847f0Bda824eC8da914045D14; // Stargate USDC
    address public constant WFLOW = 0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e;
    address public constant WETH = 0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590;
    address public constant STFLOW = 0x1b97100eA1D7126C4d60027e231EA4CB25314bdb;
    address public constant PUNCH_SWAP_ROUTER = 0xf45AFe28fd5519d5f8C1d4787a4D5f724C0eFa4d;

    event AssetConverted(address indexed fromAsset, address indexed toAsset, uint256 fromAmount, uint256 toAmount);
    event AssetAdded(address indexed asset, uint256 minDeposit, uint256 maxDeposit);

    constructor(address _baseAsset) {
        require(_baseAsset != address(0), "Invalid base asset");
        
        baseAsset = IERC20(_baseAsset);
        router = IPunchSwapRouter(PUNCH_SWAP_ROUTER);
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        
        _initializeSupportedAssets();
    }

    function _initializeSupportedAssets() internal {
        // USDF - Primary USD stablecoin on Flow (NO SWAP NEEDED if base asset)
        supportedAssets[USDF] = AssetInfo({
            supported: true,
            minDeposit: 1 * 10**6,        // 1 USDF minimum
            maxDeposit: 1000000 * 10**6,  // 1M USDF maximum
            conversionSlippage: 0,        // No slippage if base asset
            requiresSwap: address(baseAsset) != USDF, // Only swap if not base asset
            decimals: 6
        });
        assetList.push(USDF);

        // USDT - Alternative stablecoin
        supportedAssets[USDT] = AssetInfo({
            supported: true,
            minDeposit: 1 * 10**6,
            maxDeposit: 1000000 * 10**6,
            conversionSlippage: 100,      // 1% slippage for stablecoin swaps
            requiresSwap: true,
            decimals: 6
        });
        assetList.push(USDT);

        // Stargate USDC (bridged)
        supportedAssets[STG_USDC] = AssetInfo({
            supported: true,
            minDeposit: 1 * 10**6,
            maxDeposit: 1000000 * 10**6,
            conversionSlippage: 100,      // 1% slippage for stablecoin swaps
            requiresSwap: true,
            decimals: 6
        });
        assetList.push(STG_USDC);

        // USDC.e (Celer bridged)
        supportedAssets[USDC_E] = AssetInfo({
            supported: true,
            minDeposit: 1 * 10**6,
            maxDeposit: 1000000 * 10**6,
            conversionSlippage: 100,      // 1% slippage for stablecoin swaps
            requiresSwap: true,
            decimals: 6
        });
        assetList.push(USDC_E);

        // WFLOW - Native Flow token
        supportedAssets[WFLOW] = AssetInfo({
            supported: true,
            minDeposit: 1 * 10**18,       // 1 FLOW minimum
            maxDeposit: 100000 * 10**18,  // 100K FLOW maximum
            conversionSlippage: 500,      // 5% slippage for volatile assets
            requiresSwap: true,
            decimals: 18
        });
        assetList.push(WFLOW);
    }

    modifier onlyVault() {
        require(hasRole(VAULT_ROLE, msg.sender), "Only vault can call");
        _;
    }

    function depositAsset(address asset, uint256 amount, address receiver) 
        external 
        onlyVault 
        returns (uint256 baseAmount) 
    {
        require(supportedAssets[asset].supported, "Asset not supported");
        require(amount >= supportedAssets[asset].minDeposit, "Below minimum deposit");
        require(amount <= supportedAssets[asset].maxDeposit, "Above maximum deposit");

        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        if (asset == address(baseAsset)) {
            // No conversion needed - direct deposit
            baseAmount = amount;
        } else if (autoConvertToBase && supportedAssets[asset].requiresSwap) {
            // Convert to base asset via DEX
            baseAmount = _convertToBaseAsset(asset, amount);
        } else {
            // Estimate value without conversion
            baseAmount = _estimateValue(asset, amount);
        }

        return baseAmount;
    }

    function withdrawToAsset(address asset, uint256 baseAmount, address receiver) 
        external 
        onlyVault 
        returns (uint256 assetAmount) 
    {
        require(supportedAssets[asset].supported, "Asset not supported");

        if (asset == address(baseAsset)) {
            baseAsset.safeTransfer(receiver, baseAmount);
            return baseAmount;
        }

        assetAmount = _convertFromBaseAsset(asset, baseAmount);
        IERC20(asset).safeTransfer(receiver, assetAmount);
        
        return assetAmount;
    }

    function convertToBase(address asset, uint256 amount) external onlyVault returns (uint256 baseAmount) {
        if (asset == address(baseAsset)) {
            return amount;
        }
        return _convertToBaseAsset(asset, amount);
    }

    function _convertToBaseAsset(address fromAsset, uint256 amount) internal returns (uint256 baseAmount) {
        if (fromAsset == address(baseAsset)) {
            return amount;
        }

        IERC20(fromAsset).safeApprove(PUNCH_SWAP_ROUTER, amount);

        address[] memory path = new address[](2);
        path[0] = fromAsset;
        path[1] = address(baseAsset);

        AssetInfo memory assetInfo = supportedAssets[fromAsset];
        uint256 maxSlippage = assetInfo.conversionSlippage > 0 ? assetInfo.conversionSlippage : defaultSlippage;

        try router.getAmountsOut(amount, path) returns (uint256[] memory amountsOut) {
            uint256 minAmountOut = (amountsOut[1] * (10000 - maxSlippage)) / 10000;

            try router.swapExactTokensForTokens(
                amount,
                minAmountOut,
                path,
                address(this),
                block.timestamp + 300
            ) returns (uint256[] memory amounts) {
                baseAmount = amounts[1];
                emit AssetConverted(fromAsset, address(baseAsset), amount, baseAmount);
            } catch {
                baseAmount = _fallbackConversion(fromAsset, amount);
            }
        } catch {
            baseAmount = _fallbackConversion(fromAsset, amount);
        }
    }

    function _convertFromBaseAsset(address toAsset, uint256 baseAmount) internal returns (uint256 assetAmount) {
        if (toAsset == address(baseAsset)) {
            return baseAmount;
        }

        baseAsset.safeApprove(PUNCH_SWAP_ROUTER, baseAmount);

        address[] memory path = new address[](2);
        path[0] = address(baseAsset);
        path[1] = toAsset;

        AssetInfo memory assetInfo = supportedAssets[toAsset];
        uint256 maxSlippage = assetInfo.conversionSlippage > 0 ? assetInfo.conversionSlippage : defaultSlippage;

        try router.getAmountsOut(baseAmount, path) returns (uint256[] memory amountsOut) {
            uint256 minAmountOut = (amountsOut[1] * (10000 - maxSlippage)) / 10000;

            try router.swapExactTokensForTokens(
                baseAmount,
                minAmountOut,
                path,
                address(this),
                block.timestamp + 300
            ) returns (uint256[] memory amounts) {
                assetAmount = amounts[1];
                emit AssetConverted(address(baseAsset), toAsset, baseAmount, assetAmount);
            } catch {
                assetAmount = baseAmount;
            }
        } catch {
            assetAmount = baseAmount;
        }
    }

    function _fallbackConversion(address fromAsset, uint256 amount) internal pure returns (uint256) {
        // All stablecoins assumed 1:1 with USDF
        if (fromAsset == USDT || fromAsset == USDC_E || fromAsset == STG_USDC) {
            return amount; // 1:1 for stablecoins
        } else if (fromAsset == WFLOW) {
            // Simplified FLOW to USDF conversion (you'd want a price oracle in production)
            return (amount * 1 * 10**6) / 10**18; // Assume 1 FLOW = 1 USDF for fallback
        } else if (fromAsset == WETH) {
            // Simplified ETH to USDF conversion
            return (amount * 2000 * 10**6) / 10**18; // Assume 1 ETH = 2000 USDF for fallback
        }
        return amount;
    }

    function _estimateValue(address asset, uint256 amount) internal pure returns (uint256) {
        return _fallbackConversion(asset, amount);
    }

    function getSupportedAssets() external view returns (address[] memory) {
        return assetList;
    }

    function isAssetSupported(address asset) external view returns (bool) {
        return supportedAssets[asset].supported;
    }

    function addSupportedAsset(
        address asset,
        uint256 minDeposit,
        uint256 maxDeposit,
        uint256 conversionSlippage,
        bool requiresSwap,
        uint8 decimals
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(asset != address(0), "Invalid asset");
        require(!supportedAssets[asset].supported, "Asset already supported");

        supportedAssets[asset] = AssetInfo({
            supported: true,
            minDeposit: minDeposit,
            maxDeposit: maxDeposit,
            conversionSlippage: conversionSlippage,
            requiresSwap: requiresSwap,
            decimals: decimals
        });

        assetList.push(asset);
        emit AssetAdded(asset, minDeposit, maxDeposit);
    }

    function setDefaultSlippage(uint256 slippage) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(slippage <= 1000, "Slippage too high");
        defaultSlippage = slippage;
    }

    function setAutoConvert(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        autoConvertToBase = enabled;
    }

    function emergencyWithdraw(address token, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(token).safeTransfer(msg.sender, amount);
    }
}