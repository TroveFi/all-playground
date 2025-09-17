// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract IncrementOracleMirror is AccessControl, ReentrancyGuard {
    using ECDSA for bytes32;

    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");
    
    struct PriceData {
        uint256 price;
        uint256 timestamp;
        uint256 cadenceHeight;
        bool isValid;
    }
    
    struct ExchangeRateData {
        uint256 rate;
        uint256 timestamp;
        uint256 cadenceHeight;
        bool isValid;
    }
    
    mapping(string => PriceData) public priceFeeds;
    ExchangeRateData public exchangeRate;
    
    uint256 public requiredSignatures = 2;
    uint256 public maxPriceDeviation = 1000;
    uint256 public stalePriceThreshold = 3600;
    mapping(address => bool) public authorizedOracles;
    address[] public oracleList;
    
    string[] public supportedFeeds;
    mapping(string => bool) public isFeedSupported;
    
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
        
        _addPriceFeed("FLOW/USD");
        _addPriceFeed("stFLOW/USD");
        _addPriceFeed("USDC/USD");
        _addPriceFeed("USDT/USD");
        
        exchangeRate = ExchangeRateData({
            rate: 1294359605000000000,
            timestamp: block.timestamp,
            cadenceHeight: 0,
            isValid: true
        });
        
        priceFeeds["FLOW/USD"] = PriceData({
            price: 1 * 10**18,
            timestamp: block.timestamp,
            cadenceHeight: 0,
            isValid: true
        });
    }
    
    function updatePrices(
        string[] calldata feeds,
        uint256[] calldata prices,
        uint256[] calldata timestamps,
        uint256[] calldata cadenceHeights,
        bytes[] calldata signatures
    ) external nonReentrant {
        require(feeds.length == prices.length, "Array length mismatch");
        require(prices.length == timestamps.length, "Array length mismatch");
        require(timestamps.length == cadenceHeights.length, "Array length mismatch");
        require(signatures.length >= requiredSignatures, "Insufficient signatures");
        
        // Create hash of the data using abi.encode instead of abi.encodePacked
        bytes32 messageHash = keccak256(abi.encode(feeds, prices, timestamps, cadenceHeights));
        _validateSignatures(messageHash, signatures);
        
        for (uint256 i = 0; i < feeds.length; i++) {
            _updatePriceFeed(feeds[i], prices[i], timestamps[i], cadenceHeights[i]);
        }
    }
    
    function updateExchangeRate(
        uint256 rate,
        uint256 timestamp,
        uint256 cadenceHeight,
        bytes[] calldata signatures
    ) external nonReentrant {
        require(signatures.length >= requiredSignatures, "Insufficient signatures");
        require(rate > 0, "Invalid rate");
        
        // Use abi.encode for complex data types
        bytes32 messageHash = keccak256(abi.encode(rate, timestamp, cadenceHeight));
        _validateSignatures(messageHash, signatures);
        
        if (exchangeRate.isValid) {
            uint256 deviation = rate > exchangeRate.rate ? 
                rate - exchangeRate.rate : exchangeRate.rate - rate;
            uint256 deviationBps = (deviation * 10000) / exchangeRate.rate;
            require(deviationBps <= maxPriceDeviation, "Rate change too large");
        }
        
        exchangeRate = ExchangeRateData({
            rate: rate,
            timestamp: timestamp,
            cadenceHeight: cadenceHeight,
            isValid: true
        });
        
        emit ExchangeRateUpdated(rate, timestamp, cadenceHeight, msg.sender);
    }
    
    function updateSinglePrice(
        string calldata feed,
        uint256 price,
        uint256 timestamp,
        uint256 cadenceHeight,
        bytes[] calldata signatures
    ) external nonReentrant {
        require(signatures.length >= requiredSignatures, "Insufficient signatures");
        require(price > 0, "Invalid price");
        require(isFeedSupported[feed], "Unsupported feed");
        
        // Use abi.encode for string + other types
        bytes32 messageHash = keccak256(abi.encode(feed, price, timestamp, cadenceHeight));
        _validateSignatures(messageHash, signatures);
        
        _updatePriceFeed(feed, price, timestamp, cadenceHeight);
    }
    
    function emergencyUpdateExchangeRate(
        uint256 rate,
        uint256 timestamp,
        uint256 cadenceHeight
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(rate > 0, "Invalid rate");
        
        exchangeRate = ExchangeRateData({
            rate: rate,
            timestamp: timestamp,
            cadenceHeight: cadenceHeight,
            isValid: true
        });
        
        emit ExchangeRateUpdated(rate, timestamp, cadenceHeight, msg.sender);
    }
    
    function emergencyUpdatePrice(
        string calldata feed,
        uint256 price,
        uint256 timestamp,
        uint256 cadenceHeight
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(price > 0, "Invalid price");
        require(isFeedSupported[feed], "Unsupported feed");
        
        _updatePriceFeed(feed, price, timestamp, cadenceHeight);
    }
    
    function _updatePriceFeed(
        string memory feed,
        uint256 price,
        uint256 timestamp,
        uint256 cadenceHeight
    ) internal {
        require(isFeedSupported[feed], "Unsupported feed");
        require(price > 0, "Invalid price");
        
        if (priceFeeds[feed].isValid) {
            uint256 oldPrice = priceFeeds[feed].price;
            uint256 deviation = price > oldPrice ? price - oldPrice : oldPrice - price;
            uint256 deviationBps = (deviation * 10000) / oldPrice;
            require(deviationBps <= maxPriceDeviation, "Price change too large");
        }
        
        priceFeeds[feed] = PriceData({
            price: price,
            timestamp: timestamp,
            cadenceHeight: cadenceHeight,
            isValid: true
        });
        
        emit PriceUpdated(feed, price, timestamp, cadenceHeight, msg.sender);
    }
    
    function _validateSignatures(bytes32 messageHash, bytes[] calldata signatures) internal view {
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        
        uint256 validSignatures = 0;
        address[] memory signers = new address[](signatures.length);
        
        for (uint256 i = 0; i < signatures.length; i++) {
            address signer = ethSignedMessageHash.recover(signatures[i]);
            
            if (authorizedOracles[signer]) {
                bool isDuplicate = false;
                for (uint256 j = 0; j < validSignatures; j++) {
                    if (signers[j] == signer) {
                        isDuplicate = true;
                        break;
                    }
                }
                
                if (!isDuplicate) {
                    signers[validSignatures] = signer;
                    validSignatures++;
                }
            }
        }
        
        require(validSignatures >= requiredSignatures, "Invalid signatures");
    }
    
    function getStFlowPrice() external view returns (uint256 price, uint256 timestamp) {
        PriceData memory data = priceFeeds["stFLOW/USD"];
        return (data.price, data.timestamp);
    }
    
    function getExchangeRate() external view returns (uint256 rate, uint256 timestamp) {
        return (exchangeRate.rate, exchangeRate.timestamp);
    }
    
    function getPrice(string calldata feed) external view returns (uint256 price, uint256 timestamp, bool isValid) {
        PriceData memory data = priceFeeds[feed];
        return (data.price, data.timestamp, data.isValid);
    }
    
    function isPriceStale(string calldata feed) external view returns (bool) {
        return block.timestamp - priceFeeds[feed].timestamp > stalePriceThreshold;
    }
    
    function isExchangeRateStale() external view returns (bool) {
        return block.timestamp - exchangeRate.timestamp > stalePriceThreshold;
    }
    
    function getSupportedFeeds() external view returns (string[] memory) {
        return supportedFeeds;
    }
    
    function getOracleStatus() external view returns (
        uint256 authorizedCount,
        uint256 requiredSigs,
        bool exchangeRateValid,
        bool exchangeRateStale,
        uint256 lastUpdate
    ) {
        return (
            oracleList.length,
            requiredSignatures,
            exchangeRate.isValid,
            block.timestamp - exchangeRate.timestamp > stalePriceThreshold,
            exchangeRate.timestamp
        );
    }
    
    function getAllPriceData() external view returns (
        string[] memory feeds,
        uint256[] memory prices,
        uint256[] memory timestamps,
        bool[] memory validities
    ) {
        uint256 length = supportedFeeds.length;
        feeds = new string[](length);
        prices = new uint256[](length);
        timestamps = new uint256[](length);
        validities = new bool[](length);
        
        for (uint256 i = 0; i < length; i++) {
            string memory feed = supportedFeeds[i];
            PriceData memory data = priceFeeds[feed];
            feeds[i] = feed;
            prices[i] = data.price;
            timestamps[i] = data.timestamp;
            validities[i] = data.isValid;
        }
    }
    
    function _addPriceFeed(string memory feed) internal {
        if (!isFeedSupported[feed]) {
            supportedFeeds.push(feed);
            isFeedSupported[feed] = true;
        }
    }
    
    function addPriceFeed(string calldata feed) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _addPriceFeed(feed);
    }
    
    function removePriceFeed(string calldata feed) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(isFeedSupported[feed], "Feed not supported");
        
        isFeedSupported[feed] = false;
        delete priceFeeds[feed];
        
        // Remove from supportedFeeds array
        for (uint256 i = 0; i < supportedFeeds.length; i++) {
            if (keccak256(bytes(supportedFeeds[i])) == keccak256(bytes(feed))) {
                supportedFeeds[i] = supportedFeeds[supportedFeeds.length - 1];
                supportedFeeds.pop();
                break;
            }
        }
    }
    
    function authorizeOracle(address oracle) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(oracle != address(0), "Invalid oracle address");
        require(!authorizedOracles[oracle], "Oracle already authorized");
        
        authorizedOracles[oracle] = true;
        oracleList.push(oracle);
        
        emit OracleAuthorized(oracle);
    }
    
    function revokeOracle(address oracle) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(authorizedOracles[oracle], "Oracle not authorized");
        
        authorizedOracles[oracle] = false;
        
        for (uint256 i = 0; i < oracleList.length; i++) {
            if (oracleList[i] == oracle) {
                oracleList[i] = oracleList[oracleList.length - 1];
                oracleList.pop();
                break;
            }
        }
        
        emit OracleRevoked(oracle);
    }
    
    function updateConfiguration(
        uint256 _requiredSignatures,
        uint256 _maxPriceDeviation,
        uint256 _stalePriceThreshold
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_requiredSignatures > 0, "Invalid required signatures");
        require(_maxPriceDeviation <= 5000, "Max deviation too high");
        require(_stalePriceThreshold > 0, "Invalid stale threshold");
        
        // Allow zero oracle list length for initial setup
        if (oracleList.length > 0) {
            require(_requiredSignatures <= oracleList.length, "Too many required signatures");
        }
        
        requiredSignatures = _requiredSignatures;
        maxPriceDeviation = _maxPriceDeviation;
        stalePriceThreshold = _stalePriceThreshold;
        
        emit ConfigurationUpdated(_requiredSignatures, _maxPriceDeviation, _stalePriceThreshold);
    }
    
    function pauseOracle() external onlyRole(DEFAULT_ADMIN_ROLE) {
        requiredSignatures = type(uint256).max;
    }
    
    function resumeOracle(uint256 _requiredSignatures) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_requiredSignatures > 0, "Invalid required signatures");
        require(_requiredSignatures <= oracleList.length, "Too many required signatures");
        requiredSignatures = _requiredSignatures;
    }
    
    function batchAuthorizeOracles(address[] calldata oracles) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < oracles.length; i++) {
            address oracle = oracles[i];
            require(oracle != address(0), "Invalid oracle address");
            
            if (!authorizedOracles[oracle]) {
                authorizedOracles[oracle] = true;
                oracleList.push(oracle);
                emit OracleAuthorized(oracle);
            }
        }
    }
    
    function getAuthorizedOracles() external view returns (address[] memory) {
        return oracleList;
    }
}