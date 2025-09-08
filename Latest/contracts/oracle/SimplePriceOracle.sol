// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title SimplePriceOracle - Basic price oracle for multi-asset vault
/// @notice Provides price feeds for supported assets with manual updates
/// @dev This is a simplified oracle - in production you'd want Chainlink or similar
contract SimplePriceOracle is AccessControl {
    bytes32 public constant PRICE_UPDATER_ROLE = keccak256("PRICE_UPDATER_ROLE");

    struct PriceInfo {
        uint256 price;        // Price in USD with 18 decimals
        uint8 decimals;       // Token decimals
        uint256 lastUpdated;
        bool active;
    }

    mapping(address => PriceInfo) public priceFeeds;
    address[] public supportedTokens;

    // Flow EVM Token Addresses
    address public constant USDF = 0x2aaBea2058b5aC2D339b163C6Ab6f2b6d53aabED;
    address public constant WFLOW = 0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e;
    address public constant WETH = 0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590;
    address public constant STGUSD = 0xF1815bd50389c46847f0Bda824eC8da914045D14;
    address public constant USDT = 0x674843C06FF83502ddb4D37c2E09C01cdA38cbc8;
    address public constant USDC_E = 0x7f27352D5F83Db87a5A3E00f4B07Cc2138D8ee52;
    address public constant STFLOW = 0x5598c0652B899EB40f169Dd5949BdBE0BF36ffDe;
    address public constant ANKRFLOW = 0x1b97100eA1D7126C4d60027e231EA4CB25314bdb;
    address public constant CBBTC = 0xA0197b2044D28b08Be34d98b23c9312158Ea9A18;

    event PriceUpdated(address indexed token, uint256 price, uint256 timestamp);
    event TokenAdded(address indexed token, uint8 decimals);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PRICE_UPDATER_ROLE, msg.sender);

        _initializePrices();
    }

    function _initializePrices() internal {
        // Initialize with reasonable default prices
        
        // Stablecoins - $1.00
        _setPriceInternal(USDF, 1 * 10**18, 6);
        _setPriceInternal(STGUSD, 1 * 10**18, 6);
        _setPriceInternal(USDT, 1 * 10**18, 6);
        _setPriceInternal(USDC_E, 1 * 10**18, 6);
        
        // FLOW tokens - $1.00 (update as needed)
        _setPriceInternal(WFLOW, 1 * 10**18, 18);
        _setPriceInternal(STFLOW, 1 * 10**18, 18);
        _setPriceInternal(ANKRFLOW, 1 * 10**18, 18);
        
        // ETH - $2500
        _setPriceInternal(WETH, 2500 * 10**18, 18);
        
        // BTC - $50000
        _setPriceInternal(CBBTC, 50000 * 10**18, 8);
    }

    function _setPriceInternal(address token, uint256 price, uint8 decimals) internal {
        priceFeeds[token] = PriceInfo({
            price: price,
            decimals: decimals,
            lastUpdated: block.timestamp,
            active: true
        });
        supportedTokens.push(token);
        emit TokenAdded(token, decimals);
        emit PriceUpdated(token, price, block.timestamp);
    }

    /// @notice Update price for a single token
    function updatePrice(address token, uint256 price) external onlyRole(PRICE_UPDATER_ROLE) {
        require(priceFeeds[token].active, "Token not supported");
        require(price > 0, "Invalid price");

        priceFeeds[token].price = price;
        priceFeeds[token].lastUpdated = block.timestamp;

        emit PriceUpdated(token, price, block.timestamp);
    }

    /// @notice Update prices for multiple tokens
    function updatePrices(
        address[] calldata tokens,
        uint256[] calldata prices
    ) external onlyRole(PRICE_UPDATER_ROLE) {
        require(tokens.length == prices.length, "Array length mismatch");

        for (uint256 i = 0; i < tokens.length; i++) {
            if (priceFeeds[tokens[i]].active && prices[i] > 0) {
                priceFeeds[tokens[i]].price = prices[i];
                priceFeeds[tokens[i]].lastUpdated = block.timestamp;
                emit PriceUpdated(tokens[i], prices[i], block.timestamp);
            }
        }
    }

    /// @notice Add support for a new token
    function addToken(address token, uint256 initialPrice, uint8 decimals) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(token != address(0), "Invalid token");
        require(!priceFeeds[token].active, "Token already supported");
        require(initialPrice > 0, "Invalid price");

        _setPriceInternal(token, initialPrice, decimals);
    }

    /// @notice Get price with token decimals
    function getPrice(address token) external view returns (uint256 price, uint8 decimals) {
        PriceInfo memory info = priceFeeds[token];
        require(info.active, "Token not supported");
        return (info.price, info.decimals);
    }

    /// @notice Get normalized price (18 decimals)
    function getNormalizedPrice(address token) external view returns (uint256) {
        PriceInfo memory info = priceFeeds[token];
        require(info.active, "Token not supported");
        return info.price; // Already normalized to 18 decimals
    }

    /// @notice Get price age in seconds
    function getPriceAge(address token) external view returns (uint256) {
        require(priceFeeds[token].active, "Token not supported");
        return block.timestamp - priceFeeds[token].lastUpdated;
    }

    /// @notice Check if price is stale (older than maxAge)
    function isPriceStale(address token, uint256 maxAge) external view returns (bool) {
        if (!priceFeeds[token].active) return true;
        return (block.timestamp - priceFeeds[token].lastUpdated) > maxAge;
    }

    /// @notice Get all supported tokens
    function getSupportedTokens() external view returns (address[] memory) {
        return supportedTokens;
    }

    /// @notice Get multiple prices at once
    function getPrices(address[] calldata tokens) external view returns (
        uint256[] memory prices,
        uint8[] memory decimalsArray,
        uint256[] memory timestamps
    ) {
        prices = new uint256[](tokens.length);
        decimalsArray = new uint8[](tokens.length);
        timestamps = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            PriceInfo memory info = priceFeeds[tokens[i]];
            prices[i] = info.active ? info.price : 0;
            decimalsArray[i] = info.decimals;
            timestamps[i] = info.lastUpdated;
        }
    }

    /// @notice Emergency pause/unpause a token
    function setTokenActive(address token, bool active) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(priceFeeds[token].decimals > 0, "Token not configured");
        priceFeeds[token].active = active;
    }

    /// @notice Calculate USD value for a token amount
    function calculateUSDValue(address token, uint256 amount) external view returns (uint256) {
        PriceInfo memory info = priceFeeds[token];
        require(info.active, "Token not supported");
        
        // Price is in 18 decimals, adjust for token decimals
        if (info.decimals <= 18) {
            return (amount * info.price) / (10 ** info.decimals);
        } else {
            return (amount * info.price * (10 ** (info.decimals - 18))) / (10 ** 18);
        }
    }
}