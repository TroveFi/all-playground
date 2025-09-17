// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import "./ArbitrageTypes.sol";

interface IArbitrageDEXManager {
    function getPrice(address tokenIn, address tokenOut, uint256 amountIn, address dex) external returns (uint256 amountOut);
    function getActiveDEXs() external view returns (address[] memory);
    function getDEXInfo(address dex) external view returns (ArbitrageTypes.DEXInfo memory);
}

contract ArbitrageScanner is AccessControl {
    bytes32 public constant STRATEGY_ROLE = keccak256("STRATEGY_ROLE");

    IArbitrageDEXManager public dexManager;
    
    // Token whitelist
    mapping(address => bool) public whitelistedTokens;
    address[] public tradingTokens;
    
    // Arbitrage settings
    uint256 public minProfitThreshold = 5 * 10**6;
    
    // Flow EVM addresses
    address public constant WFLOW = 0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e;
    address public constant USDC = 0xF1815bd50389c46847f0Bda824eC8da914045D14;
    address public constant USDT = 0x674843C06FF83502ddb4D37c2E09C01cdA38cbc8;
    address public constant WETH = 0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590;
    address public constant STFLOW = 0x1b97100eA1D7126C4d60027e231EA4CB25314bdb;

    constructor(address _dexManager) {
        require(_dexManager != address(0), "Invalid DEX manager");
        
        dexManager = IArbitrageDEXManager(_dexManager);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        
        _initializeTokens();
    }

    function _initializeTokens() internal {
        address[] memory tokens = new address[](5);
        tokens[0] = WFLOW;
        tokens[1] = USDC;
        tokens[2] = USDT;
        tokens[3] = WETH;
        tokens[4] = STFLOW;
        
        for (uint256 i = 0; i < tokens.length; i++) {
            whitelistedTokens[tokens[i]] = true;
            tradingTokens.push(tokens[i]);
        }
    }

    modifier onlyStrategy() {
        require(hasRole(STRATEGY_ROLE, msg.sender), "Only strategy can call");
        _;
    }

    function scanForBestArbitrageOpportunity() 
        external 
        onlyStrategy 
        returns (ArbitrageTypes.ArbitrageOpportunity memory bestOpportunity) 
    {
        uint256 maxProfitabilityScore = 0;
        address[] memory activeDEXs = dexManager.getActiveDEXs();
        
        for (uint256 i = 0; i < tradingTokens.length; i++) {
            for (uint256 j = i + 1; j < tradingTokens.length; j++) {
                address tokenA = tradingTokens[i];
                address tokenB = tradingTokens[j];
                
                for (uint256 dexA = 0; dexA < activeDEXs.length; dexA++) {
                    for (uint256 dexB = 0; dexB < activeDEXs.length; dexB++) {
                        if (dexA == dexB) continue;
                        
                        ArbitrageTypes.ArbitrageOpportunity memory opportunity = _checkArbitrageOpportunity(
                            tokenA, 
                            tokenB, 
                            activeDEXs[dexA], 
                            activeDEXs[dexB]
                        );
                        
                        if (opportunity.isValid && opportunity.profitabilityScore > maxProfitabilityScore) {
                            maxProfitabilityScore = opportunity.profitabilityScore;
                            bestOpportunity = opportunity;
                        }
                    }
                }
            }
        }
    }

    function _checkArbitrageOpportunity(
        address tokenA, 
        address tokenB, 
        address dexA, 
        address dexB
    ) internal returns (ArbitrageTypes.ArbitrageOpportunity memory opportunity) {
        uint256 testAmount = 1000 * 10**6;
        
        uint256 priceA = dexManager.getPrice(tokenA, tokenB, testAmount, dexA);
        uint256 priceB = dexManager.getPrice(tokenA, tokenB, testAmount, dexB);
        
        if (priceA == 0 || priceB == 0) return opportunity;
        
        uint256 profit = 0;
        bool isValid = false;
        
        if (priceB > priceA) {
            profit = priceB - priceA;
            isValid = true;
        } else if (priceA > priceB) {
            profit = priceA - priceB;
            isValid = true;
            address temp = dexA;
            dexA = dexB;
            dexB = temp;
        }
        
        if (isValid && profit > minProfitThreshold) {
            ArbitrageTypes.DEXInfo memory dexInfoA = dexManager.getDEXInfo(dexA);
            ArbitrageTypes.DEXInfo memory dexInfoB = dexManager.getDEXInfo(dexB);
            
            uint256 estimatedGas = dexInfoA.gasOverhead + dexInfoB.gasOverhead;
            uint256 profitabilityScore = (profit * 1e18) / (estimatedGas * tx.gasprice);
            
            opportunity = ArbitrageTypes.ArbitrageOpportunity({
                tokenA: tokenA,
                tokenB: tokenB,
                dexA: dexA,
                dexB: dexB,
                profitAmount: profit,
                inputAmount: testAmount,
                gasEstimate: estimatedGas,
                profitabilityScore: profitabilityScore,
                isValid: true,
                requiresFlashLoan: false,
                timestamp: block.timestamp,
                routingData: ""
            });
        }
    }

    function scanForTriangularArbitrage() 
        external 
        onlyStrategy 
        returns (ArbitrageTypes.TriangularArbitrage memory bestOpportunity) 
    {
        for (uint256 i = 0; i < tradingTokens.length; i++) {
            for (uint256 j = 0; j < tradingTokens.length; j++) {
                for (uint256 k = 0; k < tradingTokens.length; k++) {
                    if (i == j || j == k || i == k) continue;
                    
                    address tokenA = tradingTokens[i];
                    address tokenB = tradingTokens[j];
                    address tokenC = tradingTokens[k];
                    
                    ArbitrageTypes.TriangularArbitrage memory opportunity = _checkTriangularOpportunity(tokenA, tokenB, tokenC);
                    
                    if (opportunity.isValid && opportunity.expectedProfit > bestOpportunity.expectedProfit) {
                        bestOpportunity = opportunity;
                    }
                }
            }
        }
    }

    function _checkTriangularOpportunity(
        address tokenA, 
        address tokenB, 
        address tokenC
    ) internal returns (ArbitrageTypes.TriangularArbitrage memory opportunity) {
        uint256 startAmount = 1000 * 10**6;
        address[] memory activeDEXs = dexManager.getActiveDEXs();
        
        if (activeDEXs.length < 2) return opportunity;
        
        uint256 amountB = dexManager.getPrice(tokenA, tokenB, startAmount, activeDEXs[0]);
        if (amountB == 0) return opportunity;
        
        uint256 amountC = dexManager.getPrice(tokenB, tokenC, amountB, activeDEXs[1]);
        if (amountC == 0) return opportunity;
        
        uint256 finalAmountA = dexManager.getPrice(tokenC, tokenA, amountC, activeDEXs[0]);
        if (finalAmountA == 0) return opportunity;
        
        if (finalAmountA > startAmount) {
            uint256 profit = finalAmountA - startAmount;
            
            if (profit > minProfitThreshold) {
                address[] memory dexPath = new address[](3);
                dexPath[0] = activeDEXs[0];
                dexPath[1] = activeDEXs[1];
                dexPath[2] = activeDEXs[0];
                
                opportunity = ArbitrageTypes.TriangularArbitrage({
                    tokenA: tokenA,
                    tokenB: tokenB,
                    tokenC: tokenC,
                    dexPath: dexPath,
                    expectedProfit: profit,
                    minimumInput: startAmount,
                    isValid: true
                });
            }
        }
    }

    function checkStFLOWArbitrage() external onlyStrategy returns (uint256 profit) {
        uint256 testAmount = 100 * 10**18;
        address[] memory activeDEXs = dexManager.getActiveDEXs();
        
        if (activeDEXs.length < 2) return 0;
        
        uint256 stFlowPrice = dexManager.getPrice(WFLOW, STFLOW, testAmount, activeDEXs[0]);
        uint256 flowPrice = dexManager.getPrice(STFLOW, WFLOW, stFlowPrice, activeDEXs[1]);
        
        if (flowPrice > testAmount) {
            profit = flowPrice - testAmount;
        }
    }

    function getTradingTokens() external view returns (address[] memory) {
        return tradingTokens;
    }

    function setMinProfitThreshold(uint256 _minProfitThreshold) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minProfitThreshold = _minProfitThreshold;
    }

    function addWhitelistedToken(address token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(token != address(0), "Invalid token");
        require(!whitelistedTokens[token], "Already whitelisted");
        
        whitelistedTokens[token] = true;
        tradingTokens.push(token);
    }

    function removeWhitelistedToken(address token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(whitelistedTokens[token], "Not whitelisted");
        
        whitelistedTokens[token] = false;
        
        for (uint256 i = 0; i < tradingTokens.length; i++) {
            if (tradingTokens[i] == token) {
                tradingTokens[i] = tradingTokens[tradingTokens.length - 1];
                tradingTokens.pop();
                break;
            }
        }
    }
}