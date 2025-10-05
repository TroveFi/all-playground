const { ethers } = require("hardhat");

async function main() {
    console.log("MORE MARKETS - ALL AVAILABLE POOLS");
    console.log("==================================");
    
    const [deployer] = await ethers.getSigners();
    console.log(`Querying from: ${deployer.address}\n`);
    
    const UI_POOL_DATA_PROVIDER = "0x2148e6253b23122Ee78B3fa6DcdDbefae426EB78";
    const POOL_ADDRESSES_PROVIDER = "0x1830a96466d1d108935865c75B0a9548681Cfd9A";
    
    // Complete ABI with all reserve data fields
    const uiProvider = await ethers.getContractAt([
        {
            "inputs": [{"internalType": "contract IPoolAddressesProvider", "name": "provider", "type": "address"}],
            "name": "getReservesData",
            "outputs": [
                {
                    "components": [
                        {"internalType": "address", "name": "underlyingAsset", "type": "address"},
                        {"internalType": "string", "name": "name", "type": "string"},
                        {"internalType": "string", "name": "symbol", "type": "string"},
                        {"internalType": "uint256", "name": "decimals", "type": "uint256"},
                        {"internalType": "uint256", "name": "baseLTVasCollateral", "type": "uint256"},
                        {"internalType": "uint256", "name": "reserveLiquidationThreshold", "type": "uint256"},
                        {"internalType": "uint256", "name": "reserveLiquidationBonus", "type": "uint256"},
                        {"internalType": "uint256", "name": "reserveFactor", "type": "uint256"},
                        {"internalType": "bool", "name": "usageAsCollateralEnabled", "type": "bool"},
                        {"internalType": "bool", "name": "borrowingEnabled", "type": "bool"},
                        {"internalType": "bool", "name": "stableBorrowRateEnabled", "type": "bool"},
                        {"internalType": "bool", "name": "isActive", "type": "bool"},
                        {"internalType": "bool", "name": "isFrozen", "type": "bool"},
                        {"internalType": "uint128", "name": "liquidityIndex", "type": "uint128"},
                        {"internalType": "uint128", "name": "variableBorrowIndex", "type": "uint128"},
                        {"internalType": "uint128", "name": "liquidityRate", "type": "uint128"},
                        {"internalType": "uint128", "name": "variableBorrowRate", "type": "uint128"},
                        {"internalType": "uint128", "name": "stableBorrowRate", "type": "uint128"},
                        {"internalType": "uint40", "name": "lastUpdateTimestamp", "type": "uint40"},
                        {"internalType": "address", "name": "aTokenAddress", "type": "address"},
                        {"internalType": "address", "name": "stableDebtTokenAddress", "type": "address"},
                        {"internalType": "address", "name": "variableDebtTokenAddress", "type": "address"},
                        {"internalType": "address", "name": "interestRateStrategyAddress", "type": "address"},
                        {"internalType": "uint256", "name": "availableLiquidity", "type": "uint256"},
                        {"internalType": "uint256", "name": "totalPrincipalStableDebt", "type": "uint256"},
                        {"internalType": "uint256", "name": "averageStableRate", "type": "uint256"},
                        {"internalType": "uint256", "name": "stableDebtLastUpdateTimestamp", "type": "uint256"},
                        {"internalType": "uint256", "name": "totalScaledVariableDebt", "type": "uint256"},
                        {"internalType": "uint256", "name": "priceInMarketReferenceCurrency", "type": "uint256"},
                        {"internalType": "address", "name": "priceOracle", "type": "address"},
                        {"internalType": "bool", "name": "flashLoanEnabled", "type": "bool"}
                    ],
                    "internalType": "struct IUiPoolDataProviderV3.AggregatedReserveData[]",
                    "name": "",
                    "type": "tuple[]"
                },
                {
                    "components": [
                        {"internalType": "uint256", "name": "marketReferenceCurrencyUnit", "type": "uint256"},
                        {"internalType": "int256", "name": "marketReferenceCurrencyPriceInUsd", "type": "int256"},
                        {"internalType": "int256", "name": "networkBaseTokenPriceInUsd", "type": "int256"},
                        {"internalType": "uint8", "name": "networkBaseTokenPriceDecimals", "type": "uint8"}
                    ],
                    "internalType": "struct IUiPoolDataProviderV3.BaseCurrencyInfo",
                    "name": "",
                    "type": "tuple"
                }
            ],
            "stateMutability": "view",
            "type": "function"
        }
    ], UI_POOL_DATA_PROVIDER);
    
    try {
        const [reservesData, baseCurrencyInfo] = await uiProvider.getReservesData(POOL_ADDRESSES_PROVIDER);
        const RAY = BigInt("1000000000000000000000000000");
        
        console.log(`Total markets found: ${reservesData.length}\n`);
        
        const activeSupplyPools = [];
        const activeBorrowPools = [];
        const allPools = {};
        
        for (const reserve of reservesData) {
            if (!reserve.isActive) continue;
            
            const supplyAPY = reserve.isFrozen ? "0.00" : ((Number(reserve.liquidityRate) / Number(RAY)) * 100).toFixed(2);
            const borrowAPY = reserve.isFrozen ? "0.00" : ((Number(reserve.variableBorrowRate) / Number(RAY)) * 100).toFixed(2);
            
            const poolData = {
                symbol: reserve.symbol,
                address: reserve.underlyingAsset,
                decimals: Number(reserve.decimals),
                supplyAPY: supplyAPY,
                borrowAPY: borrowAPY,
                canCollateral: reserve.usageAsCollateralEnabled,
                canBorrow: reserve.borrowingEnabled && !reserve.isFrozen,
                isFrozen: reserve.isFrozen,
                ltv: (Number(reserve.baseLTVasCollateral) / 100).toFixed(2),
                liquidationThreshold: (Number(reserve.reserveLiquidationThreshold) / 100).toFixed(2),
                availableLiquidity: ethers.formatUnits(reserve.availableLiquidity, reserve.decimals)
            };
            
            if (reserve.usageAsCollateralEnabled || !reserve.isFrozen) {
                activeSupplyPools.push(poolData);
            }
            
            if (reserve.borrowingEnabled && !reserve.isFrozen) {
                activeBorrowPools.push(poolData);
            }
            
            // Add to all pools object
            allPools[reserve.symbol] = {
                address: reserve.underlyingAsset,
                decimals: Number(reserve.decimals),
                canSupply: !reserve.isFrozen,
                canBorrow: reserve.borrowingEnabled && !reserve.isFrozen,
                canCollateral: reserve.usageAsCollateralEnabled,
                isFrozen: reserve.isFrozen
            };
        }
        
        // Display supply pools
        console.log("=== SUPPLY POOLS ===\n");
        activeSupplyPools.sort((a, b) => parseFloat(b.supplyAPY) - parseFloat(a.supplyAPY));
        
        if (activeSupplyPools.length === 0) {
            console.log("No active supply pools found\n");
        } else {
            activeSupplyPools.forEach((pool, i) => {
                console.log(`${i + 1}. ${pool.symbol}${pool.isFrozen ? ' (FROZEN)' : ''}`);
                console.log(`   Address: ${pool.address}`);
                console.log(`   Supply APY: ${pool.supplyAPY}%`);
                console.log(`   Can use as collateral: ${pool.canCollateral ? "Yes" : "No"}`);
                if (pool.canCollateral) {
                    console.log(`   LTV: ${pool.ltv}%`);
                    console.log(`   Liquidation Threshold: ${pool.liquidationThreshold}%`);
                }
                console.log(`   Available Liquidity: ${Number(pool.availableLiquidity).toLocaleString()} ${pool.symbol}`);
                console.log(`   Decimals: ${pool.decimals}`);
                console.log("");
            });
        }
        
        // Display borrow pools
        console.log("=== BORROW POOLS ===\n");
        activeBorrowPools.sort((a, b) => parseFloat(a.borrowAPY) - parseFloat(b.borrowAPY));
        
        if (activeBorrowPools.length === 0) {
            console.log("No active borrow pools found\n");
        } else {
            activeBorrowPools.forEach((pool, i) => {
                console.log(`${i + 1}. ${pool.symbol}`);
                console.log(`   Address: ${pool.address}`);
                console.log(`   Borrow APY: ${pool.borrowAPY}%`);
                console.log(`   Available Liquidity: ${Number(pool.availableLiquidity).toLocaleString()} ${pool.symbol}`);
                console.log(`   Decimals: ${pool.decimals}`);
                console.log("");
            });
        }
        
        // Export data as JSON
        console.log("=== POOL DATA (JSON for scripts) ===\n");
        console.log(JSON.stringify(allPools, null, 2));
        
        console.log("\n=== QUICK REFERENCE ===");
        console.log("\nTo supply to a pool, edit dynamic-supply.js with:");
        console.log("- ASSET_SYMBOL from list above");
        console.log("- ASSET_ADDRESS from list above");
        console.log("- ASSET_DECIMALS from list above");
        console.log("\nTo borrow from a pool, edit dynamic-borrow.js with:");
        console.log("- Same fields as supply");
        console.log("- Must have collateral first!");
        
    } catch (error) {
        console.error("Error querying pools:", error.message);
        console.error("\nFull error:", error);
        throw error;
    }
}

main().catch(console.error);