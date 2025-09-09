// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title IncrementOracleMirror - Mirror of Cadence Increment Oracle Data
/// @notice Mirrors price feeds from Cadence Increment oracles to EVM
/// @dev Uses multi-signature validation for oracle updates
contract IncrementOracleMirror is AccessControl, ReentrancyGuard {
    using ECDSA for bytes32;

    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");
    
    struct PriceData {
        uint256 price;          // Price in USD (18 decimals)
        uint256 timestamp;      // Last update timestamp
        uint256 cadenceHeight;  // Cadence block height
        bool isValid;           // Whether data is valid
    }
    
    struct ExchangeRateData {
        uint256 rate;           // stFLOW to FLOW exchange rate (18 decimals)
        uint256 timestamp;      // Last update timestamp
        uint256 cadenceHeight;  // Cadence block height
        bool isValid;           // Whether data is valid
    }
    
    // Price feeds from Increment Cadence oracles
    mapping(string => PriceData) public priceFeeds;
    ExchangeRateData public exchangeRate;
    
    // Oracle configuration
    uint256 public requiredSignatures = 2;
    uint256 public maxPriceDeviation = 1000; // 10% max deviation
    uint256 public stalePriceThreshold = 3600; // 1 hour
    mapping(address => bool) public authorizedOracles;
    address[] public oracleList;
    
    // Price feed names (matching Cadence oracle feeds)
    string[] public supportedFeeds;
    mapping(string => bool) public isFeedSupported;
    
    // Events
    event PriceUpdated(
        string indexed feed,
        uint256 price,
        uint256 timestamp,
        uint256 cadenceHeight,
        address updater
    );
    
    event ExchangeRateUpdated(
        uint256 rate,
        uint256 timestamp,
        uint256 cadenceHeight,
        address updater
    );
    
    event OracleAuthorized(address oracle);
    event OracleRevoked(address oracle);
    event ConfigurationUpdated(uint256 requiredSigs, uint256 maxDeviation, uint256 staleThreshold);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(KEEPER_ROLE, msg.sender);
        
        // Initialize supported price feeds (matching Cadence oracle addresses)
        _addPriceFeed("FLOW/USD");
        _addPriceFeed("stFLOW/USD");
        _addPriceFeed("USDC/USD");
        _addPriceFeed("USDT/USD");
        
        // Initialize with safe defaults
        exchangeRate = ExchangeRateData({
            rate: 1294359605000000000, // Current Increment rate
            timestamp: block.timestamp,
            cadenceHeight: 0,
            isValid: true
        });
        
        // Initialize FLOW/USD price
        priceFeeds["FLOW/USD"] = PriceData({
            price: 1 * 10**18, // $1 placeholder
            timestamp: block.timestamp,
            cadenceHeight: 0,
            isValid: true
        });
    }
    
    // ====================================================================
    // ORACLE UPDATE FUNCTIONS
    // ====================================================================
    
    /// @notice Update multiple price feeds with signature validation
    function updatePrices(
        string[] calldata feeds,
        uint256[] calldata prices,
        uint256[] calldata timestamps,
        uint256[] calldata cadenceHeights,
        bytes[] calldata signatures
    ) external nonReentrant {
        require(feeds.length == prices.length, "Array length mismatch");
        require(prices.length == timestamps.length, "Array length mismatch");
        require(timestamps.length == cadenceHe