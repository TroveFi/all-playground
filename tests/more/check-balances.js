const { ethers } = require("hardhat");

async function main() {
    console.log("CHECKING ALL BALANCES - WALLET & MORE MARKETS");
    console.log("=============================================");
    
    const [deployer] = await ethers.getSigners();
    console.log(`Checking balances for: ${deployer.address}`);
    
    // Contract addresses
    const POOL_DATA_PROVIDER = "0x79e71e3c0EDF2B88b0aB38E9A1eF0F6a230e56bf";
    const UI_POOL_DATA_PROVIDER = "0x2148e6253b23122Ee78B3fa6DcdDbefae426EB78";
    const POOL_ADDRESSES_PROVIDER = "0x1830a96466d1d108935865c75B0a9548681Cfd9A";
    const POOL_PROXY = "0xbC92aaC2DBBF42215248B5688eB3D3d2b32F2c8d";
    
    // Token addresses
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
    const uiPoolDataProvider = await ethers.getContractAt([
        {"inputs":[{"internalType":"contract IPoolAddressesProvider","name":"provider","type":"address"}],"name":"getReservesData","outputs":[{"components":[{"internalType":"address","name":"underlyingAsset","type":"address"},{"internalType":"string","name":"name","type":"string"},{"internalType":"string","name":"symbol","type":"string"},{"internalType":"uint256","name":"decimals","type":"uint256"},{"internalType":"uint128","name":"liquidityRate","type":"uint128"}],"internalType":"struct IUiPoolDataProviderV3.AggregatedReserveData[]","name":"","type":"tuple[]"}],"stateMutability":"view","type":"function"},
        {"inputs":[{"internalType":"contract IPoolAddressesProvider","name":"provider","type":"address"},{"internalType":"address","name":"user","type":"address"}],"name":"getUserReservesData","outputs":[{"components":[{"internalType":"address","name":"underlyingAsset","type":"address"},{"internalType":"uint256","name":"scaledATokenBalance","type":"uint256"},{"internalType":"bool","name":"usageAsCollateralEnabledOnUser","type":"bool"},{"internalType":"uint256","name":"stableBorrowRate","type":"uint256"},{"internalType":"uint256","name":"scaledVariableDebt","type":"uint256"},{"internalType":"uint256","name":"principalStableDebt","type":"uint256"},{"internalType":"uint256","name":"stableBorrowLastUpdateTimestamp","type":"uint256"}],"internalType":"struct IUiPoolDataProviderV3.UserReserveData[]","name":"","type":"tuple[]"},{"internalType":"uint8","name":"","type":"uint8"}],"stateMutability":"view","type":"function"}
    ], UI_POOL_DATA_PROVIDER);
    
    const pool = await ethers.getContractAt([
        {"inputs":[{"internalType":"address","name":"user","type":"address"}],"name":"getUserAccountData","outputs":[{"internalType":"uint256","name":"totalCollateralBase","type":"uint256"},{"internalType":"uint256","name":"totalDebtBase","type":"uint256"},{"internalType":"uint256","name":"availableBorrowsBase","type":"uint256"},{"internalType":"uint256","name":"currentLiquidationThreshold","type":"uint256"},{"internalType":"uint256","name":"ltv","type":"uint256"},{"internalType":"uint256","name":"healthFactor","type":"uint256"}],"stateMutability":"view","type":"function"}
    ], POOL_PROXY);
    
    try {
        // STEP 1: Check wallet balances
        console.log("\nWALLET BALANCES");
        console.log("==================");
        
        // Check native FLOW balance
        const nativeBalance = await ethers.provider.getBalance(deployer.address);
        console.log(`Native FLOW: ${ethers.formatEther(nativeBalance)}`);
        
        // Check all token balances
        for (const [symbol, address] of Object.entries(TOKENS)) {
            try {
                if (symbol === "WFLOW") {
                    const token = await ethers.getContractAt([
                        {"constant":true,"inputs":[{"name":"","type":"address"}],"name":"balanceOf","outputs":[{"name":"","type":"uint256"}],"payable":false,"stateMutability":"view","type":"function"},
                        {"constant":true,"inputs":[],"name":"decimals","outputs":[{"name":"","type":"uint8"}],"payable":false,"stateMutability":"view","type":"function"}
                    ], address);
                    const balance = await token.balanceOf(deployer.address);
                    const decimals = await token.decimals();
                    const formatted = ethers.formatUnits(balance, decimals);
                    console.log(`${symbol}: ${Number(formatted) > 0 ? Number(formatted).toLocaleString() : "0"}`);
                } else {
                    const token = await ethers.getContractAt([
                        {"inputs":[{"internalType":"address","name":"account","type":"address"}],"name":"balanceOf","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
                        {"inputs":[],"name":"decimals","outputs":[{"internalType":"uint8","name":"","type":"uint8"}],"stateMutability":"view","type":"function"}
                    ], address);
                    const balance = await token.balanceOf(deployer.address);
                    
                    let decimals = 18;
                    try {
                        decimals = await token.decimals();
                    } catch (e) {
                        if (symbol === "USDF" || symbol === "stgUSDC") decimals = 6;
                    }
                    
                    const formatted = ethers.formatUnits(balance, decimals);
                    console.log(`${symbol}: ${Number(formatted) > 0 ? Number(formatted).toLocaleString() : "0"}`);
                }
            } catch (error) {
                console.log(`${symbol}: Error`);
            }
        }
        
        // STEP 2: Check MORE Markets positions
        console.log("\nMORE MARKETS POSITIONS");
        console.log("=========================");
        
        // Get user account data (overall health)
        const accountData = await pool.getUserAccountData(deployer.address);
        
        if (Number(accountData.totalCollateralBase) === 0 && Number(accountData.totalDebtBase) === 0) {
            console.log("No positions in MORE Markets");
        } else {
            console.log("Account Overview:");
            console.log(`   Total Collateral: $${ethers.formatUnits(accountData.totalCollateralBase, 8)}`);
            console.log(`   Total Debt: $${ethers.formatUnits(accountData.totalDebtBase, 8)}`);
            console.log(`   Available to Borrow: $${ethers.formatUnits(accountData.availableBorrowsBase, 8)}`);
            console.log(`   Current LTV: ${(Number(accountData.ltv) / 100).toFixed(2)}%`);
            console.log(`   Liquidation Threshold: ${(Number(accountData.currentLiquidationThreshold) / 100).toFixed(2)}%`);
            
            const healthFactor = Number(accountData.healthFactor);
            if (healthFactor === 0) {
                console.log(`   Health Factor: ∞ (No debt)`);
            } else {
                const hfFormatted = (healthFactor / 1e18).toFixed(3);
                console.log(`   Health Factor: ${hfFormatted} ${healthFactor < 1e18 ? "DANGER" : "OK"}`);
            }
        }
        
        // Get detailed user reserves data
        const [userReservesData, userEMode] = await uiPoolDataProvider.getUserReservesData(POOL_ADDRESSES_PROVIDER, deployer.address);
        
        if (userReservesData.length > 0) {
            console.log(`\nDetailed Positions (E-Mode: ${userEMode}):`);
            
            // Get all reserves data to match symbols and decimals
            const [allReservesData] = await uiPoolDataProvider.getReservesData(POOL_ADDRESSES_PROVIDER);
            
            let hasSupplies = false;
            let hasDebts = false;
            
            console.log("\nSUPPLIED ASSETS:");
            for (const userReserve of userReservesData) {
                if (!userReserve.underlyingAsset) continue;
                
                const reserveData = allReservesData.find(r => 
                    r.underlyingAsset && 
                    r.underlyingAsset.toLowerCase() === userReserve.underlyingAsset.toLowerCase()
                );
                
                if (reserveData && Number(userReserve.scaledATokenBalance) > 0) {
                    hasSupplies = true;
                    const suppliedAmount = ethers.formatUnits(userReserve.scaledATokenBalance, reserveData.decimals);
                    const supplyAPY = ((Number(reserveData.liquidityRate) / 1e27) * 100).toFixed(2);
                    console.log(`   ${reserveData.symbol}: ${Number(suppliedAmount).toLocaleString()} (${supplyAPY}% APY)`);
                    console.log(`      Used as Collateral: ${userReserve.usageAsCollateralEnabledOnUser ? "Yes" : "No"}`);
                }
            }
            
            if (!hasSupplies) {
                console.log("   None");
            }
            
            console.log("\nBORROWED ASSETS:");
            for (const userReserve of userReservesData) {
                if (!userReserve.underlyingAsset) continue;
                
                const reserveData = allReservesData.find(r => 
                    r.underlyingAsset && 
                    r.underlyingAsset.toLowerCase() === userReserve.underlyingAsset.toLowerCase()
                );
                
                if (reserveData) {
                    const hasVariableDebt = Number(userReserve.scaledVariableDebt) > 0;
                    const hasStableDebt = Number(userReserve.principalStableDebt) > 0;
                    
                    if (hasVariableDebt || hasStableDebt) {
                        hasDebts = true;
                        console.log(`   ${reserveData.symbol}:`);
                        
                        if (hasVariableDebt) {
                            const variableDebt = ethers.formatUnits(userReserve.scaledVariableDebt, reserveData.decimals);
                            console.log(`      Variable: ${Number(variableDebt).toLocaleString()}`);
                        }
                        
                        if (hasStableDebt) {
                            const stableDebt = ethers.formatUnits(userReserve.principalStableDebt, reserveData.decimals);
                            const stableRate = ((Number(userReserve.stableBorrowRate) / 1e27) * 100).toFixed(2);
                            console.log(`      Stable: ${Number(stableDebt).toLocaleString()} @ ${stableRate}%`);
                        }
                    }
                }
            }
            
            if (!hasDebts) {
                console.log("   None");
            }
        }
        
        // STEP 3: Check aToken balances (if any)
        console.log("\nATOKEN BALANCES");
        console.log("==================");
        
        const aTokenAddresses = {
            "aWFLOW": "0x02BF4bd075c1b7C8D85F54777eaAA3638135c059",
            "aankrFLOWEVM": "0xD10cd10260e87eFdf36618621458eeAA996B8267", 
            "astgUSDC": "0x4B5bC00fe319f01aFed9B15Acd67e0A2F72Ba602",
            "acbBTC": "0x72756F76630DfFea4Db019960b00139aa123c2bE"
        };
        
        let hasATokens = false;
        for (const [symbol, address] of Object.entries(aTokenAddresses)) {
            try {
                const aToken = await ethers.getContractAt([
                    {"inputs":[{"internalType":"address","name":"account","type":"address"}],"name":"balanceOf","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
                    {"inputs":[],"name":"decimals","outputs":[{"internalType":"uint8","name":"","type":"uint8"}],"stateMutability":"view","type":"function"}
                ], address);
                
                const balance = await aToken.balanceOf(deployer.address);
                if (Number(balance) > 0) {
                    hasATokens = true;
                    const decimals = await aToken.decimals();
                    const formatted = ethers.formatUnits(balance, decimals);
                    console.log(`${symbol}: ${Number(formatted).toLocaleString()}`);
                }
            } catch (error) {
                // Skip if error reading aToken
            }
        }
        
        if (!hasATokens) {
            console.log("No aToken balances");
        }
        
        // STEP 4: Summary and actions
        console.log("\nSUMMARY");
        console.log("==========");
        
        const hasWalletAssets = Number(nativeBalance) > ethers.parseEther("0.01");
        const hasMarketPositions = Number(accountData.totalCollateralBase) > 0 || Number(accountData.totalDebtBase) > 0;
        
        if (hasWalletAssets) {
            console.log("You have assets in your wallet that can be supplied to MORE Markets");
        }
        
        if (hasMarketPositions) {
            console.log("You have active positions in MORE Markets");
            if (Number(accountData.availableBorrowsBase) > 0) {
                console.log(`You can borrow up to ${ethers.formatUnits(accountData.availableBorrowsBase, 8)} more`);
            }
        } else {
            console.log("No positions in MORE Markets - consider supplying assets to earn yield");
        }
        
        console.log("\nAvailable Actions:");
        if (hasWalletAssets) {
            console.log("   Supply assets: npx hardhat run scripts/supply-to-more-clean.js --network flow_mainnet");
        }
        if (hasMarketPositions) {
            console.log("   Withdraw assets: npx hardhat run scripts/withdraw-from-more.js --network flow_mainnet");
            if (Number(accountData.availableBorrowsBase) > 0) {
                console.log("   Borrow assets: npx hardhat run scripts/borrow-from-more.js --network flow_mainnet");
            }
            if (Number(accountData.totalDebtBase) > 0) {
                console.log("   Repay debt: npx hardhat run scripts/repay-debt.js --network flow_mainnet");
            }
        }
        console.log("   Market overview: npx hardhat run scripts/query-markets-data-fixed.js --network flow_mainnet");
        
    } catch (error) {
        console.error("Error checking balances:", error.message);
        throw error;
    }
}

main().catch(console.error);