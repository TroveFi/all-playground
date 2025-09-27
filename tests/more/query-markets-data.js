const { ethers } = require("hardhat");

async function main() {
    console.log("QUERYING MORE MARKETS DATA ON FLOW EVM");
    console.log("=====================================");
    
    const [deployer] = await ethers.getSigners();
    console.log(`Querying from account: ${deployer.address}`);
    
    // Contract addresses
    const POOL_DATA_PROVIDER = "0x79e71e3c0EDF2B88b0aB38E9A1eF0F6a230e56bf";
    const UI_POOL_DATA_PROVIDER = "0x2148e6253b23122Ee78B3fa6DcdDbefae426EB78";
    const POOL_ADDRESSES_PROVIDER = "0x1830a96466d1d108935865c75B0a9548681Cfd9A";
    
    // Token addresses for reference
    const TOKENS = {
        "WFLOW": "0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e",
        "stgUSDC": "0xF1815bd50389c46847f0Bda824eC8da914045D14",
        "USDT": "0x674843C06FF83502ddb4D37c2E09C01cdA38cbc8",
        "USDF": "0x2aaBea2058b5aC2D339b163C6Ab6f2b6d53aabED",
        "USDC.e": "0x7f27352D5F83Db87a5A3E00f4B07Cc2138D8ee52",
        "stFLOW": "0x5598c0652B899EB40f169Dd5949BdBE0BF36ffDe",
        "ankrFLOWEVM": "0x1b97100eA1D7126C4d60027e231EA4CB25314bdb",
        "WETH": "0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590",
        "cbBTC": "0xA0197b2044D28b08Be34d98b23c9312158Ea9A18"
    };
    
    // Get contract instances
    const poolDataProvider = await ethers.getContractAt([
        {"inputs":[],"name":"getAllReservesTokens","outputs":[{"components":[{"internalType":"string","name":"symbol","type":"string"},{"internalType":"address","name":"tokenAddress","type":"address"}],"internalType":"struct IPoolDataProvider.TokenData[]","name":"","type":"tuple[]"}],"stateMutability":"view","type":"function"}
    ], POOL_DATA_PROVIDER);
    
    const uiPoolDataProvider = await ethers.getContractAt([
        {"inputs":[{"internalType":"contract IPoolAddressesProvider","name":"provider","type":"address"}],"name":"getReservesData","outputs":[{"components":[{"internalType":"address","name":"underlyingAsset","type":"address"},{"internalType":"string","name":"name","type":"string"},{"internalType":"string","name":"symbol","type":"string"},{"internalType":"uint256","name":"decimals","type":"uint256"},{"internalType":"uint256","name":"baseLTVasCollateral","type":"uint256"},{"internalType":"uint256","name":"reserveLiquidationThreshold","type":"uint256"},{"internalType":"uint256","name":"reserveLiquidationBonus","type":"uint256"},{"internalType":"uint256","name":"reserveFactor","type":"uint256"},{"internalType":"bool","name":"usageAsCollateralEnabled","type":"bool"},{"internalType":"bool","name":"borrowingEnabled","type":"bool"},{"internalType":"bool","name":"stableBorrowRateEnabled","type":"bool"},{"internalType":"bool","name":"isActive","type":"bool"},{"internalType":"bool","name":"isFrozen","type":"bool"},{"internalType":"uint128","name":"liquidityIndex","type":"uint128"},{"internalType":"uint128","name":"variableBorrowIndex","type":"uint128"},{"internalType":"uint128","name":"liquidityRate","type":"uint128"},{"internalType":"uint128","name":"variableBorrowRate","type":"uint128"},{"internalType":"uint128","name":"stableBorrowRate","type":"uint128"},{"internalType":"uint40","name":"lastUpdateTimestamp","type":"uint40"},{"internalType":"address","name":"aTokenAddress","type":"address"},{"internalType":"address","name":"stableDebtTokenAddress","type":"address"},{"internalType":"address","name":"variableDebtTokenAddress","type":"address"},{"internalType":"address","name":"interestRateStrategyAddress","type":"address"},{"internalType":"uint256","name":"availableLiquidity","type":"uint256"},{"internalType":"uint256","name":"totalPrincipalStableDebt","type":"uint256"},{"internalType":"uint256","name":"averageStableRate","type":"uint256"},{"internalType":"uint256","name":"stableDebtLastUpdateTimestamp","type":"uint256"},{"internalType":"uint256","name":"totalScaledVariableDebt","type":"uint256"},{"internalType":"uint256","name":"priceInMarketReferenceCurrency","type":"uint256"},{"internalType":"address","name":"priceOracle","type":"address"},{"internalType":"bool","name":"flashLoanEnabled","type":"bool"}],"internalType":"struct IUiPoolDataProviderV3.AggregatedReserveData[]","name":"","type":"tuple[]"},{"components":[{"internalType":"uint256","name":"marketReferenceCurrencyUnit","type":"uint256"},{"internalType":"int256","name":"marketReferenceCurrencyPriceInUsd","type":"int256"},{"internalType":"int256","name":"networkBaseTokenPriceInUsd","type":"int256"},{"internalType":"uint8","name":"networkBaseTokenPriceDecimals","type":"uint8"}],"internalType":"struct IUiPoolDataProviderV3.BaseCurrencyInfo","name":"","type":"tuple"}],"stateMutability":"view","type":"function"},
        {"inputs":[{"internalType":"contract IPoolAddressesProvider","name":"provider","type":"address"},{"internalType":"address","name":"user","type":"address"}],"name":"getUserReservesData","outputs":[{"components":[{"internalType":"address","name":"underlyingAsset","type":"address"},{"internalType":"uint256","name":"scaledATokenBalance","type":"uint256"},{"internalType":"bool","name":"usageAsCollateralEnabledOnUser","type":"bool"},{"internalType":"uint256","name":"stableBorrowRate","type":"uint256"},{"internalType":"uint256","name":"scaledVariableDebt","type":"uint256"},{"internalType":"uint256","name":"principalStableDebt","type":"uint256"},{"internalType":"uint256","name":"stableBorrowLastUpdateTimestamp","type":"uint256"}],"internalType":"struct IUiPoolDataProviderV3.UserReserveData[]","name":"","type":"tuple[]"},{"internalType":"uint8","name":"","type":"uint8"}],"stateMutability":"view","type":"function"}
    ], UI_POOL_DATA_PROVIDER);
    
    try {
        // STEP 1: Get all available reserves
        console.log("\nSTEP 1: GETTING ALL AVAILABLE RESERVES");
        console.log("=========================================");
        
        const allReserves = await poolDataProvider.getAllReservesTokens();
        console.log(`Total reserves available: ${allReserves.length}`);
        
        for (let i = 0; i < allReserves.length; i++) {
            const reserve = allReserves[i];
            console.log(`${i + 1}. ${reserve.symbol}: ${reserve.tokenAddress}`);
        }
        
        // STEP 2: Get comprehensive reserves data
        console.log("\nSTEP 2: GETTING COMPREHENSIVE RESERVES DATA");
        console.log("===============================================");
        
        const [reservesData, baseCurrencyInfo] = await uiPoolDataProvider.getReservesData(POOL_ADDRESSES_PROVIDER);
        
        console.log("Base Currency Info:");
        console.log(`  Market Reference Currency Unit: ${baseCurrencyInfo.marketReferenceCurrencyUnit}`);
        console.log(`  Market Reference Currency Price in USD: $${Number(baseCurrencyInfo.marketReferenceCurrencyPriceInUsd) / 1e8}`);
        console.log(`  Network Base Token Price in USD: $${Number(baseCurrencyInfo.networkBaseTokenPriceInUsd) / 1e8}`);
        console.log(`  Network Base Token Price Decimals: ${baseCurrencyInfo.networkBaseTokenPriceDecimals}`);
        
        console.log("\nDETAILED RESERVE INFORMATION:");
        console.log("================================");
        
        const RAY = BigInt("1000000000000000000000000000");
        
        for (let i = 0; i < reservesData.length; i++) {
            const reserve = reservesData[i];
            
            // Calculate APYs
            const liquidityRate = Number(reserve.liquidityRate);
            const variableBorrowRate = Number(reserve.variableBorrowRate);
            const stableBorrowRate = Number(reserve.stableBorrowRate);
            
            const supplyAPY = ((liquidityRate / Number(RAY)) * 100).toFixed(2);
            const variableBorrowAPY = ((variableBorrowRate / Number(RAY)) * 100).toFixed(2);
            const stableBorrowAPY = ((stableBorrowRate / Number(RAY)) * 100).toFixed(2);
            
            // Format liquidity
            const availableLiquidity = ethers.formatUnits(reserve.availableLiquidity, reserve.decimals);
            const totalDebt = ethers.formatUnits(
                BigInt(reserve.totalPrincipalStableDebt) + BigInt(reserve.totalScaledVariableDebt), 
                reserve.decimals
            );
            
            // Price in USD
            const priceInUSD = (Number(reserve.priceInMarketReferenceCurrency) * Number(baseCurrencyInfo.marketReferenceCurrencyPriceInUsd)) / (1e8 * 1e8);
            
            console.log(`\n${reserve.symbol} (${reserve.underlyingAsset})`);
            console.log("   ═══════════════════════════════════════");
            console.log(`   Market Data:`);
            console.log(`      • Decimals: ${reserve.decimals}`);
            console.log(`      • Price: $${priceInUSD.toFixed(6)}`);
            console.log(`      • Available Liquidity: ${Number(availableLiquidity).toLocaleString()} ${reserve.symbol}`);
            console.log(`      • Total Debt: ${Number(totalDebt).toLocaleString()} ${reserve.symbol}`);
            console.log(`   Interest Rates:`);
            console.log(`      • Supply APY: ${supplyAPY}%`);
            console.log(`      • Variable Borrow APY: ${variableBorrowAPY}%`);
            console.log(`      • Stable Borrow APY: ${stableBorrowAPY}%`);
            console.log(`   Configuration:`);
            console.log(`      • LTV: ${(Number(reserve.baseLTVasCollateral) / 100).toFixed(2)}%`);
            console.log(`      • Liquidation Threshold: ${(Number(reserve.reserveLiquidationThreshold) / 100).toFixed(2)}%`);
            console.log(`      • Liquidation Bonus: ${(Number(reserve.reserveLiquidationBonus) / 100 - 100).toFixed(2)}%`);
            console.log(`      • Can be Collateral: ${reserve.usageAsCollateralEnabled ? "Yes" : "No"}`);
            console.log(`      • Borrowing Enabled: ${reserve.borrowingEnabled ? "Yes" : "No"}`);
            console.log(`      • Stable Borrowing: ${reserve.stableBorrowRateEnabled ? "Yes" : "No"}`);
            console.log(`      • Active: ${reserve.isActive ? "Yes" : "No"}`);
            console.log(`      • Frozen: ${reserve.isFrozen ? "Yes" : "No"}`);
            console.log(`      • Flash Loans: ${reserve.flashLoanEnabled ? "Yes" : "No"}`);
            console.log(`   Contracts:`);
            console.log(`      • aToken: ${reserve.aTokenAddress}`);
            console.log(`      • Stable Debt: ${reserve.stableDebtTokenAddress}`);
            console.log(`      • Variable Debt: ${reserve.variableDebtTokenAddress}`);
        }
        
        // STEP 3: Check wallet balances
        console.log("\nSTEP 3: CHECKING YOUR WALLET BALANCES");
        console.log("=========================================");
        
        for (const [symbol, address] of Object.entries(TOKENS)) {
            try {
                let balance;
                if (symbol === "WFLOW") {
                    const token = await ethers.getContractAt([
                        {"constant":true,"inputs":[{"name":"","type":"address"}],"name":"balanceOf","outputs":[{"name":"","type":"uint256"}],"payable":false,"stateMutability":"view","type":"function"},
                        {"constant":true,"inputs":[],"name":"decimals","outputs":[{"name":"","type":"uint8"}],"payable":false,"stateMutability":"view","type":"function"}
                    ], address);
                    balance = await token.balanceOf(deployer.address);
                    const decimals = await token.decimals();
                    console.log(`${symbol}: ${ethers.formatUnits(balance, decimals)}`);
                } else {
                    const token = await ethers.getContractAt([
                        {"inputs":[{"internalType":"address","name":"account","type":"address"}],"name":"balanceOf","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
                        {"inputs":[],"name":"decimals","outputs":[{"internalType":"uint8","name":"","type":"uint8"}],"stateMutability":"view","type":"function"}
                    ], address);
                    balance = await token.balanceOf(deployer.address);
                    
                    let decimals = 18;
                    try {
                        decimals = await token.decimals();
                    } catch (e) {
                        if (symbol === "USDF" || symbol === "stgUSDC") decimals = 6;
                    }
                    
                    console.log(`${symbol}: ${ethers.formatUnits(balance, decimals)}`);
                }
            } catch (error) {
                console.log(`${symbol}: Error reading balance`);
            }
        }
        
        // Check native FLOW balance
        const nativeBalance = await ethers.provider.getBalance(deployer.address);
        console.log(`Native FLOW: ${ethers.formatEther(nativeBalance)}`);
        
        // STEP 4: Check user positions
        console.log("\nSTEP 4: CHECKING YOUR MORE MARKETS POSITIONS");
        console.log("==============================================");
        
        const [userReservesData, userEMode] = await uiPoolDataProvider.getUserReservesData(POOL_ADDRESSES_PROVIDER, deployer.address);
        
        console.log(`E-Mode Category: ${userEMode}`);
        
        if (userReservesData.length === 0) {
            console.log("No positions found in MORE Markets");
        } else {
            for (let i = 0; i < userReservesData.length; i++) {
                const userReserve = userReservesData[i];
                
                // Find corresponding reserve data
                const reserveData = reservesData.find(r => 
                    r.underlyingAsset && userReserve.underlyingAsset && 
                    r.underlyingAsset.toLowerCase() === userReserve.underlyingAsset.toLowerCase()
                );
                
                if (!reserveData) continue;
                
                const hasSupplied = Number(userReserve.scaledATokenBalance) > 0;
                const hasVariableDebt = Number(userReserve.scaledVariableDebt) > 0;
                const hasStableDebt = Number(userReserve.principalStableDebt) > 0;
                
                if (hasSupplied || hasVariableDebt || hasStableDebt) {
                    console.log(`\n${reserveData.symbol}:`);
                    
                    if (hasSupplied) {
                        const suppliedAmount = ethers.formatUnits(userReserve.scaledATokenBalance, reserveData.decimals);
                        console.log(`   Supplied: ${Number(suppliedAmount).toLocaleString()} ${reserveData.symbol}`);
                        console.log(`   Used as Collateral: ${userReserve.usageAsCollateralEnabledOnUser ? "Yes" : "No"}`);
                    }
                    
                    if (hasVariableDebt) {
                        const variableDebt = ethers.formatUnits(userReserve.scaledVariableDebt, reserveData.decimals);
                        console.log(`   Variable Debt: ${Number(variableDebt).toLocaleString()} ${reserveData.symbol}`);
                    }
                    
                    if (hasStableDebt) {
                        const stableDebt = ethers.formatUnits(userReserve.principalStableDebt, reserveData.decimals);
                        const stableRate = ((Number(userReserve.stableBorrowRate) / Number(RAY)) * 100).toFixed(2);
                        console.log(`   Stable Debt: ${Number(stableDebt).toLocaleString()} ${reserveData.symbol} @ ${stableRate}%`);
                    }
                }
            }
        }
        
        // STEP 5: Recommendations
        console.log("\nSTEP 5: SUMMARY & RECOMMENDATIONS");
        console.log("====================================");
        
        console.log("Best Supply Opportunities (Highest APY):");
        
        // Create a copy of the array to avoid read-only error
        const activeReserves = [...reservesData]
            .filter(r => r.isActive && !r.isFrozen && Number(r.liquidityRate) > 0)
            .sort((a, b) => Number(b.liquidityRate) - Number(a.liquidityRate))
            .slice(0, 5);
            
        activeReserves.forEach((reserve, index) => {
            const supplyAPY = ((Number(reserve.liquidityRate) / Number(RAY)) * 100).toFixed(2);
            console.log(`   ${index + 1}. ${reserve.symbol}: ${supplyAPY}% APY`);
        });
        
        console.log("\nAvailable for Borrowing (if you have collateral):");
        const borrowableAssets = [...reservesData]
            .filter(r => r.isActive && !r.isFrozen && r.borrowingEnabled)
            .sort((a, b) => Number(a.variableBorrowRate) - Number(b.variableBorrowRate))
            .slice(0, 5);
            
        borrowableAssets.forEach((reserve, index) => {
            const borrowAPY = ((Number(reserve.variableBorrowRate) / Number(RAY)) * 100).toFixed(2);
            console.log(`   ${index + 1}. ${reserve.symbol}: ${borrowAPY}% APY (Variable)`);
        });
        
        console.log("\nNext Steps:");
        console.log("   1. Supply assets: npx hardhat run scripts/supply-to-more-clean.js --network flow_mainnet");
        console.log("   2. Check balances: npx hardhat run scripts/check-balances-fixed.js --network flow_mainnet");
        console.log("   3. Withdraw assets: npx hardhat run scripts/withdraw-from-more.js --network flow_mainnet");
        
    } catch (error) {
        console.error("Error querying market data:", error.message);
        throw error;
    }
}

main().catch(console.error);