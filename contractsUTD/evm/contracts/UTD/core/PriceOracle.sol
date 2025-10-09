// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title PriceOracle - Simple price oracle for vault assets
/// @notice Provides normalized USD prices for all supported assets
contract PriceOracle is AccessControl {
    
    // ====================================================================
    // ROLES
    // ====================================================================
    bytes32 public constant PRICE_UPDATER_ROLE = keccak256("PRICE_UPDATER_ROLE");
    
    // ====================================================================
    // STRUCTS
    // ====================================================================
    struct PriceData {
        uint256 price;           // Price in USD with 18 decimals
        uint256 lastUpdate;      // Timestamp of last update
        uint256 confidence;      // Confidence score 0-10000
        bool isActive;           // Whether price feed is active
    }
    
    // ====================================================================
    // STATE VARIABLES
    // ====================================================================
    mapping(address => PriceData) public prices;
    mapping(address => bool) public isFallbackActive;
    
    uint256 public constant PRICE_DECIMALS = 18;
    uint256 public constant STALE_PRICE_THRESHOLD = 1 hours;
    
    // ====================================================================
    // EVENTS
    // ====================================================================
    event PriceUpdated(address indexed asset, uint256 price, uint256 timestamp);
    event FallbackActivated(address indexed asset, bool active);
    
    // ====================================================================
    // CONSTRUCTOR
    // ====================================================================
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PRICE_UPDATER_ROLE, msg.sender);
        
        _initializePrices();
    }
    
    // ====================================================================
    // INITIALIZATION
    // ====================================================================
    function _initializePrices() internal {
        // Initialize with reasonable starting prices
        // These should be updated by price feeds
        
        // Stablecoins - $1.00
        _setPrice(0x2aaBea2058b5aC2D339b163C6Ab6f2b6d53aabED, 1e18, 10000); // USDF
        _setPrice(0xF1815bd50389c46847f0Bda824eC8da914045D14, 1e18, 10000); // STGUSD
        _setPrice(0x674843C06FF83502ddb4D37c2E09C01cdA38cbc8, 1e18, 10000); // USDT
        _setPrice(0x7f27352D5F83Db87a5A3E00f4B07Cc2138D8ee52, 1e18, 10000); // USDC.e
        
        // FLOW tokens - ~$0.80 (update with real price)
        _setPrice(0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e, 0.8e18, 8000); // WFLOW
        _setPrice(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, 0.8e18, 8000); // Native FLOW
        
        // Liquid staking tokens - slightly higher than FLOW
        _setPrice(0x5598c0652B899EB40f169Dd5949BdBE0BF36ffDe, 0.85e18, 7500); // stFLOW
        _setPrice(0x1b97100eA1D7126C4d60027e231EA4CB25314bdb, 0.85e18, 7500); // ankrFLOW
        
        // WETH - ~$3500
        _setPrice(0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590, 3500e18, 9000); // WETH
        
        // cbBTC - ~$95000
        _setPrice(0xA0197b2044D28b08Be34d98b23c9312158Ea9A18, 95000e18, 9000); // cbBTC
    }
    
    function _setPrice(address asset, uint256 price, uint256 confidence) internal {
        prices[asset] = PriceData({
            price: price,
            lastUpdate: block.timestamp,
            confidence: confidence,
            isActive: true
        });
    }
    
    // ====================================================================
    // PRICE UPDATES
    // ====================================================================
    function updatePrice(
        address asset,
        uint256 price,
        uint256 confidence
    ) external onlyRole(PRICE_UPDATER_ROLE) {
        require(price > 0, "Invalid price");
        require(confidence <= 10000, "Invalid confidence");
        
        prices[asset] = PriceData({
            price: price,
            lastUpdate: block.timestamp,
            confidence: confidence,
            isActive: true
        });
        
        emit PriceUpdated(asset, price, block.timestamp);
    }
    
    function batchUpdatePrices(
        address[] calldata assets,
        uint256[] calldata priceList,
        uint256[] calldata confidenceList
    ) external onlyRole(PRICE_UPDATER_ROLE) {
        require(assets.length == priceList.length, "Length mismatch");
        require(assets.length == confidenceList.length, "Length mismatch");
        
        for (uint256 i = 0; i < assets.length; i++) {
            if (priceList[i] > 0 && confidenceList[i] <= 10000) {
                prices[assets[i]] = PriceData({
                    price: priceList[i],
                    lastUpdate: block.timestamp,
                    confidence: confidenceList[i],
                    isActive: true
                });
                
                emit PriceUpdated(assets[i], priceList[i], block.timestamp);
            }
        }
    }
    
    // ====================================================================
    // PRICE GETTERS
    // ====================================================================
    function getPrice(address token) external view returns (uint256 price, uint8 decimals) {
        PriceData memory priceData = prices[token];
        require(priceData.isActive, "Price feed not active");
        
        return (priceData.price, uint8(PRICE_DECIMALS));
    }
    
    function getNormalizedPrice(address token) external view returns (uint256) {
        PriceData memory priceData = prices[token];
        
        if (!priceData.isActive || _isPriceStale(priceData.lastUpdate)) {
            return _getFallbackPrice(token);
        }
        
        return priceData.price;
    }
    
    function getPriceWithConfidence(address token) external view returns (
        uint256 price,
        uint256 confidence,
        uint256 lastUpdate,
        bool isStale
    ) {
        PriceData memory priceData = prices[token];
        
        return (
            priceData.price,
            priceData.confidence,
            priceData.lastUpdate,
            _isPriceStale(priceData.lastUpdate)
        );
    }
    
    function _isPriceStale(uint256 lastUpdate) internal view returns (bool) {
        return block.timestamp - lastUpdate > STALE_PRICE_THRESHOLD;
    }
    
    function _getFallbackPrice(address token) internal view returns (uint256) {
        // Fallback pricing logic
        // Stablecoins
        if (token == 0x2aaBea2058b5aC2D339b163C6Ab6f2b6d53aabED || // USDF
            token == 0xF1815bd50389c46847f0Bda824eC8da914045D14 || // STGUSD
            token == 0x674843C06FF83502ddb4D37c2E09C01cdA38cbc8 || // USDT
            token == 0x7f27352D5F83Db87a5A3E00f4B07Cc2138D8ee52) { // USDC.e
            return 1e18; // $1.00
        }
        
        // FLOW tokens
        if (token == 0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e || // WFLOW
            token == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) { // Native FLOW
            return 0.8e18; // $0.80
        }
        
        // LSTs
        if (token == 0x5598c0652B899EB40f169Dd5949BdBE0BF36ffDe || // stFLOW
            token == 0x1b97100eA1D7126C4d60027e231EA4CB25314bdb) { // ankrFLOW
            return 0.85e18; // $0.85
        }
        
        // WETH
        if (token == 0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590) {
            return 3500e18; // $3500
        }
        
        // cbBTC
        if (token == 0xA0197b2044D28b08Be34d98b23c9312158Ea9A18) {
            return 95000e18; // $95000
        }
        
        // Default fallback
        PriceData memory priceData = prices[token];
        return priceData.price > 0 ? priceData.price : 1e18;
    }
    
    // ====================================================================
    // ADMIN FUNCTIONS
    // ====================================================================
    function setFallbackActive(address asset, bool active) external onlyRole(DEFAULT_ADMIN_ROLE) {
        isFallbackActive[asset] = active;
        emit FallbackActivated(asset, active);
    }
    
    function setPriceFeedActive(address asset, bool active) external onlyRole(DEFAULT_ADMIN_ROLE) {
        prices[asset].isActive = active;
    }
    
    // ====================================================================
    // VIEW FUNCTIONS
    // ====================================================================
    function isPriceStale(address token) external view returns (bool) {
        return _isPriceStale(prices[token].lastUpdate);
    }
    
    function getMultiplePrices(address[] calldata tokens) external view returns (uint256[] memory) {
        uint256[] memory priceList = new uint256[](tokens.length);
        
        for (uint256 i = 0; i < tokens.length; i++) {
            PriceData memory priceData = prices[tokens[i]];
            priceList[i] = priceData.isActive ? priceData.price : _getFallbackPrice(tokens[i]);
        }
        
        return priceList;
    }
}