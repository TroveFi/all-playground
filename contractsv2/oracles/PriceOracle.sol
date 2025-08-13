// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title PriceOracle - Advanced price feeds for yield optimization
/// @notice Aggregates multiple price sources for accurate asset valuation
contract PriceOracle is AccessControl, ReentrancyGuard {
    bytes32 public constant PRICE_UPDATER_ROLE = keccak256("PRICE_UPDATER_ROLE");
    bytes32 public constant PYTHON_AGENT_ROLE = keccak256("PYTHON_AGENT_ROLE");

    struct PriceData {
        uint256 price; // Price in USD with 8 decimals
        uint256 timestamp;
        uint256 confidence; // Confidence level (0-10000)
        address source; // Address of price provider
        bool valid;
    }

    struct AssetConfig {
        address asset;
        uint8 decimals;
        uint256 maxDeviation; // Maximum allowed price deviation (basis points)
        uint256 stalePeriod; // Time after which price is considered stale
        bool active;
    }

    // Price storage
    mapping(address => PriceData) public latestPrices;
    mapping(address => PriceData[]) public priceHistory; // Last 24 hours
    mapping(address => AssetConfig) public assetConfigs;
    
    // Price sources
    mapping(address => bool) public trustedSources;
    mapping(address => mapping(address => PriceData)) public sourceSpecificPrices;
    
    // Aggregation settings
    uint256 public constant MAX_PRICE_SOURCES = 5;
    uint256 public constant PRICE_PRECISION = 1e8;
    uint256 public defaultStalePeriod = 1 hours;
    uint256 public defaultMaxDeviation = 1000; // 10%

    // Events
    event PriceUpdated(address indexed asset, uint256 price, address indexed source, uint256 timestamp);
    event AssetAdded(address indexed asset, uint8 decimals, uint256 maxDeviation);
    event SourceAdded(address indexed source, bool trusted);
    event PriceAggregated(address indexed asset, uint256 finalPrice, uint256 confidence);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PRICE_UPDATER_ROLE, msg.sender);
    }

    function updatePrice(
        address asset,
        uint256 price,
        uint256 confidence
    ) external onlyRole(PRICE_UPDATER_ROLE) {
        require(assetConfigs[asset].active, "Asset not supported");
        require(price > 0, "Invalid price");
        require(confidence <= 10000, "Invalid confidence");

        PriceData memory newPrice = PriceData({
            price: price,
            timestamp: block.timestamp,
            confidence: confidence,
            source: msg.sender,
            valid: true
        });

        // Validate price deviation
        if (latestPrices[asset].valid) {
            uint256 deviation = _calculateDeviation(latestPrices[asset].price, price);
            require(deviation <= assetConfigs[asset].maxDeviation, "Price deviation too high");
        }

        latestPrices[asset] = newPrice;
        sourceSpecificPrices[msg.sender][asset] = newPrice;
        
        // Store in history (keep last 24 entries)
        _updatePriceHistory(asset, newPrice);

        emit PriceUpdated(asset, price, msg.sender, block.timestamp);
    }

    function getPrice(address asset) external view returns (uint256 price, bool valid) {
        PriceData memory priceData = latestPrices[asset];
        AssetConfig memory config = assetConfigs[asset];
        
        valid = priceData.valid && 
                config.active && 
                (block.timestamp - priceData.timestamp) <= config.stalePeriod;
        
        price = valid ? priceData.price : 0;
    }

    function getPriceWithMetadata(address asset) external view returns (
        uint256 price,
        uint256 timestamp,
        uint256 confidence,
        bool valid
    ) {
        PriceData memory priceData = latestPrices[asset];
        AssetConfig memory config = assetConfigs[asset];
        
        valid = priceData.valid && 
                config.active && 
                (block.timestamp - priceData.timestamp) <= config.stalePeriod;
        
        return (
            priceData.price,
            priceData.timestamp,
            priceData.confidence,
            valid
        );
    }

    function getAggregatedPrice(address asset) external view returns (
        uint256 aggregatedPrice,
        uint256 confidence,
        bool valid
    ) {
        // Implementation would aggregate prices from multiple sources
        // For now, return the latest price
        (aggregatedPrice, valid) = this.getPrice(asset);
        confidence = latestPrices[asset].confidence;
    }

    function addAsset(
        address asset,
        uint8 decimals,
        uint256 maxDeviation,
        uint256 stalePeriod
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(asset != address(0), "Invalid asset");
        
        assetConfigs[asset] = AssetConfig({
            asset: asset,
            decimals: decimals,
            maxDeviation: maxDeviation > 0 ? maxDeviation : defaultMaxDeviation,
            stalePeriod: stalePeriod > 0 ? stalePeriod : defaultStalePeriod,
            active: true
        });

        emit AssetAdded(asset, decimals, maxDeviation);
    }

    function addTrustedSource(address source) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(source != address(0), "Invalid source");
        trustedSources[source] = true;
        _grantRole(PRICE_UPDATER_ROLE, source);
        emit SourceAdded(source, true);
    }

    function _updatePriceHistory(address asset, PriceData memory newPrice) internal {
        PriceData[] storage history = priceHistory[asset];
        
        if (history.length >= 24) {
            // Remove oldest entry
            for (uint i = 0; i < 23; i++) {
                history[i] = history[i + 1];
            }
            history[23] = newPrice;
        } else {
            history.push(newPrice);
        }
    }

    function _calculateDeviation(uint256 oldPrice, uint256 newPrice) internal pure returns (uint256) {
        if (oldPrice == 0) return 0;
        
        uint256 diff = oldPrice > newPrice ? oldPrice - newPrice : newPrice - oldPrice;
        return (diff * 10000) / oldPrice;
    }

    function getPriceHistory(address asset) external view returns (PriceData[] memory) {
        return priceHistory[asset];
    }

    function isAssetSupported(address asset) external view returns (bool) {
        return assetConfigs[asset].active;
    }

    function addPythonAgent(address agent) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(PYTHON_AGENT_ROLE, agent);
        _grantRole(PRICE_UPDATER_ROLE, agent);
    }
}