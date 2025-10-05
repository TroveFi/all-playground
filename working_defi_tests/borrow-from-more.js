const { ethers } = require("hardhat");

async function main() {
    console.log("BORROWING ASSETS FROM MORE MARKETS");
    console.log("==================================");
    
    const [deployer] = await ethers.getSigners();
    console.log(`Borrowing to account: ${deployer.address}`);
    
    // Contract addresses
    const POOL_PROXY = "0xbC92aaC2DBBF42215248B5688eB3D3d2b32F2c8d";
    const POOL_DATA_PROVIDER = "0x79e71e3c0EDF2B88b0aB38E9A1eF0F6a230e56bf";
    
    // Available tokens
    const TOKENS = {
        "WFLOW": "0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e",
        "stgUSDC": "0xF1815bd50389c46847f0Bda824eC8da914045D14", 
        "USDF": "0x2aaBea2058b5aC2D339b163C6Ab6f2b6d53aabED",
        "ankrFLOWEVM": "0x1b97100eA1D7126C4d60027e231EA4CB25314bdb",
        "cbBTC": "0xA0197b2044D28b08Be34d98b23c9312158Ea9A18"
    };
    
    // CONFIGURATION - MODIFY THESE VALUES
    const ASSET_TO_BORROW = "USDF"; // Asset to borrow
    const AMOUNT_TO_BORROW = "5"; // Amount to borrow 
    const INTEREST_RATE_MODE = 2; // 1 = stable, 2 = variable (recommended)
    // END CONFIGURATION
    
    const ASSET_ADDRESS = TOKENS[ASSET_TO_BORROW];
    if (!ASSET_ADDRESS) {
        throw new Error(`Asset ${ASSET_TO_BORROW} not found in TOKENS list`);
    }
    
    console.log(`Asset to borrow: ${ASSET_TO_BORROW}`);
    console.log(`Asset address: ${ASSET_ADDRESS}`);
    console.log(`Amount: ${AMOUNT_TO_BORROW}`);
    console.log(`Interest rate mode: ${INTEREST_RATE_MODE === 1 ? 'Stable' : 'Variable'}`);
    
    // Get contract instances
    const pool = await ethers.getContractAt([
        {"inputs":[{"internalType":"address","name":"asset","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"},{"internalType":"uint256","name":"interestRateMode","type":"uint256"},{"internalType":"uint16","name":"referralCode","type":"uint16"},{"internalType":"address","name":"onBehalfOf","type":"address"}],"name":"borrow","outputs":[],"stateMutability":"nonpayable","type":"function"},
        {"inputs":[{"internalType":"address","name":"user","type":"address"}],"name":"getUserAccountData","outputs":[{"internalType":"uint256","name":"totalCollateralBase","type":"uint256"},{"internalType":"uint256","name":"totalDebtBase","type":"uint256"},{"internalType":"uint256","name":"availableBorrowsBase","type":"uint256"},{"internalType":"uint256","name":"currentLiquidationThreshold","type":"uint256"},{"internalType":"uint256","name":"ltv","type":"uint256"},{"internalType":"uint256","name":"healthFactor","type":"uint256"}],"stateMutability":"view","type":"function"}
    ], POOL_PROXY);
    
    const poolDataProvider = await ethers.getContractAt([
        {"inputs":[{"internalType":"address","name":"asset","type":"address"}],"name":"getReserveTokensAddresses","outputs":[{"internalType":"address","name":"aTokenAddress","type":"address"},{"internalType":"address","name":"stableDebtTokenAddress","type":"address"},{"internalType":"address","name":"variableDebtTokenAddress","type":"address"}],"stateMutability":"view","type":"function"},
        {"inputs":[{"internalType":"address","name":"asset","type":"address"},{"internalType":"address","name":"user","type":"address"}],"name":"getUserReserveData","outputs":[{"internalType":"uint256","name":"currentATokenBalance","type":"uint256"},{"internalType":"uint256","name":"currentStableDebt","type":"uint256"},{"internalType":"uint256","name":"currentVariableDebt","type":"uint256"},{"internalType":"uint256","name":"principalStableDebt","type":"uint256"},{"internalType":"uint256","name":"scaledVariableDebt","type":"uint256"},{"internalType":"uint256","name":"stableBorrowRate","type":"uint256"},{"internalType":"uint256","name":"liquidityRate","type":"uint256"},{"internalType":"uint40","name":"stableRateLastUpdated","type":"uint40"},{"internalType":"bool","name":"usageAsCollateralEnabled","type":"bool"}],"stateMutability":"view","type":"function"},
        {"inputs":[{"internalType":"address","name":"asset","type":"address"}],"name":"getReserveData","outputs":[{"internalType":"uint256","name":"unbacked","type":"uint256"},{"internalType":"uint256","name":"accruedToTreasuryScaled","type":"uint256"},{"internalType":"uint256","name":"totalAToken","type":"uint256"},{"internalType":"uint256","name":"totalStableDebt","type":"uint256"},{"internalType":"uint256","name":"totalVariableDebt","type":"uint256"},{"internalType":"uint256","name":"liquidityRate","type":"uint256"},{"internalType":"uint256","name":"variableBorrowRate","type":"uint256"},{"internalType":"uint256","name":"stableBorrowRate","type":"uint256"},{"internalType":"uint256","name":"averageStableBorrowRate","type":"uint256"},{"internalType":"uint256","name":"liquidityIndex","type":"uint256"},{"internalType":"uint256","name":"variableBorrowIndex","type":"uint256"},{"internalType":"uint40","name":"lastUpdateTimestamp","type":"uint40"}],"stateMutability":"view","type":"function"}
    ], POOL_DATA_PROVIDER);
    
    try {
        // STEP 1: Check prerequisites 
        console.log("\nSTEP 1: CHECKING BORROWING PREREQUISITES");
        console.log("========================================");
        
        // Get token decimals
        let decimals;
        if (ASSET_TO_BORROW === "WFLOW") {
            const token = await ethers.getContractAt([
                {"constant":true,"inputs":[],"name":"decimals","outputs":[{"name":"","type":"uint8"}],"payable":false,"stateMutability":"view","type":"function"}
            ], ASSET_ADDRESS);
            decimals = await token.decimals();
        } else {
            try {
                const token = await ethers.getContractAt([
                    {"inputs":[],"name":"decimals","outputs":[{"internalType":"uint8","name":"","type":"uint8"}],"stateMutability":"view","type":"function"}
                ], ASSET_ADDRESS);
                decimals = await token.decimals();
            } catch (e) {
                if (ASSET_TO_BORROW === "USDF" || ASSET_TO_BORROW === "stgUSDC") {
                    decimals = 6;
                } else {
                    decimals = 18;
                }
                console.log(`Could not read decimals, assuming ${decimals}`);
            }
        }
        
        console.log(`Token decimals: ${decimals}`);
        
        // Check current account data
        const accountDataBefore = await pool.getUserAccountData(deployer.address);
        console.log("\nCurrent account status:");
        console.log(`  Total Collateral: $${ethers.formatUnits(accountDataBefore.totalCollateralBase, 8)}`);
        console.log(`  Total Debt: $${ethers.formatUnits(accountDataBefore.totalDebtBase, 8)}`);
        console.log(`  Available to Borrow: $${ethers.formatUnits(accountDataBefore.availableBorrowsBase, 8)}`);
        console.log(`  Current LTV: ${(Number(accountDataBefore.ltv) / 100).toFixed(2)}%`);
        console.log(`  Liquidation Threshold: ${(Number(accountDataBefore.currentLiquidationThreshold) / 100).toFixed(2)}%`);
        
        const healthFactor = Number(accountDataBefore.healthFactor);
        if (healthFactor === 0) {
            console.log(`  Health Factor: ∞ (No debt)`);
        } else {
            const hfFormatted = (healthFactor / 1e18).toFixed(3);
            console.log(`  Health Factor: ${hfFormatted} ${healthFactor < 1e18 ? "DANGER" : "OK"}`);
        }
        
        // Check if user has collateral
        if (Number(accountDataBefore.totalCollateralBase) === 0) {
            throw new Error("No collateral supplied. You must supply assets as collateral before borrowing.");
        }
        
        // Check if user can borrow
        if (Number(accountDataBefore.availableBorrowsBase) === 0) {
            throw new Error("No borrowing capacity available. Your collateral may not be enabled for borrowing or is already fully utilized.");
        }
        
        // Parse amount to borrow
        const amountToBorrow = ethers.parseUnits(AMOUNT_TO_BORROW, decimals);
        console.log(`\nAmount to borrow: ${AMOUNT_TO_BORROW} ${ASSET_TO_BORROW}`);
        console.log(`Amount in wei: ${amountToBorrow.toString()}`);
        
        // Get reserve data to check interest rates and availability
        const reserveData = await poolDataProvider.getReserveData(ASSET_ADDRESS);
        const variableBorrowRate = Number(reserveData.variableBorrowRate);
        const stableBorrowRate = Number(reserveData.stableBorrowRate);
        const variableAPY = ((variableBorrowRate / 1e27) * 100).toFixed(2);
        const stableAPY = ((stableBorrowRate / 1e27) * 100).toFixed(2);
        
        console.log(`\nCurrent ${ASSET_TO_BORROW} borrow rates:`);
        console.log(`  Variable APY: ${variableAPY}%`);
        console.log(`  Stable APY: ${stableAPY}%`);
        console.log(`  You are borrowing at: ${INTEREST_RATE_MODE === 1 ? 'Stable' : 'Variable'} rate (${INTEREST_RATE_MODE === 1 ? stableAPY : variableAPY}%)`);
        
        // STEP 2: Check current debt position for this asset
        console.log("\nSTEP 2: CHECKING CURRENT DEBT POSITION");
        console.log("======================================");
        
        const userReserveDataBefore = await poolDataProvider.getUserReserveData(ASSET_ADDRESS, deployer.address);
        const currentVariableDebt = userReserveDataBefore.currentVariableDebt;
        const currentStableDebt = userReserveDataBefore.currentStableDebt;
        
        console.log(`Current ${ASSET_TO_BORROW} debt:`);
        console.log(`  Variable debt: ${ethers.formatUnits(currentVariableDebt, decimals)}`);
        console.log(`  Stable debt: ${ethers.formatUnits(currentStableDebt, decimals)}`);
        console.log(`  Total debt: ${ethers.formatUnits(BigInt(currentVariableDebt) + BigInt(currentStableDebt), decimals)}`);
        
        // Check current wallet balance
        const token = await ethers.getContractAt([
            {"inputs":[{"internalType":"address","name":"account","type":"address"}],"name":"balanceOf","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"}
        ], ASSET_ADDRESS);
        
        const walletBalanceBefore = await token.balanceOf(deployer.address);
        console.log(`Current ${ASSET_TO_BORROW} wallet balance: ${ethers.formatUnits(walletBalanceBefore, decimals)}`);
        
        // STEP 3: Safety check for health factor impact
        console.log("\nSTEP 3: SAFETY CHECKS");
        console.log("=====================");
        
        // Rough estimate of health factor impact (simplified calculation)
        if (Number(accountDataBefore.totalDebtBase) > 0) {
            const currentHF = healthFactor / 1e18;
            console.log(`Current health factor: ${currentHF.toFixed(3)}`);
            
            if (currentHF < 2.0) {
                console.log("WARNING: Health factor is below 2.0 - borrowing will reduce it further");
                console.log("Consider supplying more collateral before borrowing");
            }
        }
        
        // Estimate impact on available borrowing capacity
        const availableBorrowCapacityUSD = Number(ethers.formatUnits(accountDataBefore.availableBorrowsBase, 8));
        console.log(`Available borrowing capacity: $${availableBorrowCapacityUSD}`);
        
        // STEP 4: Execute borrow
        console.log("\nSTEP 4: EXECUTING BORROW");
        console.log("========================");
        
        console.log(`Borrowing ${AMOUNT_TO_BORROW} ${ASSET_TO_BORROW}...`);
        console.log(`From: ${POOL_PROXY}`);
        console.log(`Asset: ${ASSET_ADDRESS}`);
        console.log(`Amount: ${amountToBorrow.toString()}`);
        console.log(`Interest Rate Mode: ${INTEREST_RATE_MODE} (${INTEREST_RATE_MODE === 1 ? 'Stable' : 'Variable'})`);
        console.log(`On behalf of: ${deployer.address}`);
        console.log(`Referral code: 0`);
        
        const borrowTx = await pool.borrow(
            ASSET_ADDRESS,
            amountToBorrow,
            INTEREST_RATE_MODE,
            0, // referral code
            deployer.address
        );
        
        console.log(`Borrow transaction sent: ${borrowTx.hash}`);
        console.log("Waiting for confirmation...");
        
        const receipt = await borrowTx.wait();
        console.log(`Borrow successful!`);
        console.log(`Gas used: ${receipt.gasUsed.toString()}`);
        console.log(`Block number: ${receipt.blockNumber}`);
        
        // Parse events
        console.log("\nTRANSACTION EVENTS:");
        console.log("===================");
        for (const log of receipt.logs) {
            try {
                const parsedLog = pool.interface.parseLog(log);
                if (parsedLog) {
                    console.log(`Event: ${parsedLog.name}`);
                    if (parsedLog.name === "Borrow") {
                        console.log(`  Reserve: ${parsedLog.args[0]}`);
                        console.log(`  User: ${parsedLog.args[1]}`);
                        console.log(`  OnBehalfOf: ${parsedLog.args[2]}`);
                        console.log(`  Amount: ${ethers.formatUnits(parsedLog.args[3], decimals)}`);
                        console.log(`  Interest Rate Mode: ${parsedLog.args[4]}`);
                        console.log(`  Borrow Rate: ${parsedLog.args[5]}`);
                        console.log(`  Referral: ${parsedLog.args[6]}`);
                    }
                }
            } catch (e) {
                // Ignore unparseable logs
            }
        }
        
        // STEP 5: Verify results
        console.log("\nSTEP 5: VERIFYING RESULTS");
        console.log("=========================");
        
        // Wait for state to update
        await new Promise(resolve => setTimeout(resolve, 2000));
        
        // Check new wallet balance
        const walletBalanceAfter = await token.balanceOf(deployer.address);
        const tokensReceived = walletBalanceAfter - walletBalanceBefore;
        console.log(`New ${ASSET_TO_BORROW} wallet balance: ${ethers.formatUnits(walletBalanceAfter, decimals)}`);
        console.log(`${ASSET_TO_BORROW} received: ${ethers.formatUnits(tokensReceived, decimals)}`);
        
        // Check new debt position
        const userReserveDataAfter = await poolDataProvider.getUserReserveData(ASSET_ADDRESS, deployer.address);
        const newVariableDebt = userReserveDataAfter.currentVariableDebt;
        const newStableDebt = userReserveDataAfter.currentStableDebt;
        
        console.log(`New ${ASSET_TO_BORROW} debt:`);
        console.log(`  Variable debt: ${ethers.formatUnits(newVariableDebt, decimals)}`);
        console.log(`  Stable debt: ${ethers.formatUnits(newStableDebt, decimals)}`);
        console.log(`  Total debt: ${ethers.formatUnits(BigInt(newVariableDebt) + BigInt(newStableDebt), decimals)}`);
        
        const debtIncrease = (BigInt(newVariableDebt) + BigInt(newStableDebt)) - (BigInt(currentVariableDebt) + BigInt(currentStableDebt));
        console.log(`Debt increased by: ${ethers.formatUnits(debtIncrease, decimals)} ${ASSET_TO_BORROW}`);
        
        // Check new account data
        const accountDataAfter = await pool.getUserAccountData(deployer.address);
        console.log("\nAfter borrow:");
        console.log(`  Total Collateral: $${ethers.formatUnits(accountDataAfter.totalCollateralBase, 8)}`);
        console.log(`  Total Debt: $${ethers.formatUnits(accountDataAfter.totalDebtBase, 8)}`);
        console.log(`  Available to Borrow: $${ethers.formatUnits(accountDataAfter.availableBorrowsBase, 8)}`);
        
        const healthFactorAfter = Number(accountDataAfter.healthFactor);
        if (healthFactorAfter === 0) {
            console.log(`  Health Factor: ∞ (No debt - unexpected)`);
        } else {
            const hfAfterFormatted = (healthFactorAfter / 1e18).toFixed(3);
            console.log(`  Health Factor: ${hfAfterFormatted} ${healthFactorAfter < 1e18 ? "DANGER" : "OK"}`);
            
            if (healthFactorAfter < 1.2e18) {
                console.log("  WARNING: Health factor is getting low - monitor closely!");
            }
        }
        
        // Calculate changes
        const debtIncreaseBorrowed = accountDataAfter.totalDebtBase - accountDataBefore.totalDebtBase;
        const borrowingCapacityDecrease = accountDataBefore.availableBorrowsBase - accountDataAfter.availableBorrowsBase;
        
        console.log("\nChanges:");
        console.log(`  Total debt increased by: $${ethers.formatUnits(debtIncreaseBorrowed, 8)}`);
        console.log(`  Borrowing capacity decreased by: $${ethers.formatUnits(borrowingCapacityDecrease, 8)}`);
        
        // STEP 6: Summary and recommendations
        console.log("\nSUMMARY");
        console.log("=======");
        console.log(`Successfully borrowed ${ethers.formatUnits(tokensReceived, decimals)} ${ASSET_TO_BORROW}`);
        console.log(`Interest rate: ${INTEREST_RATE_MODE === 1 ? 'Stable' : 'Variable'} (${INTEREST_RATE_MODE === 1 ? stableAPY : variableAPY}%)`);
        console.log(`Your debt increased by $${ethers.formatUnits(debtIncreaseBorrowed, 8)}`);
        console.log(`Remaining borrowing capacity: $${ethers.formatUnits(accountDataAfter.availableBorrowsBase, 8)}`);
        
        const finalHF = (healthFactorAfter / 1e18).toFixed(3);
        console.log(`Current health factor: ${finalHF}`);
        
        if (healthFactorAfter < 1.5e18) {
            console.log("\nWARNING: Your health factor is below 1.5");
            console.log("Consider:");
            console.log("• Supplying more collateral");
            console.log("• Repaying some debt");
            console.log("• Monitoring your position closely");
        }
        
        console.log("\nNext Steps:");
        console.log("   1. Monitor health factor: npx hardhat run scripts/check-balances.js --network flow_mainnet");
        console.log("   2. Repay debt when ready: npx hardhat run scripts/repay-debt.js --network flow_mainnet");
        console.log("   3. Supply more collateral: npx hardhat run scripts/supply-to-more.js --network flow_mainnet");
        
        console.log("\nImportant Reminders:");
        console.log("   • Interest accrues on your debt over time");
        console.log("   • Monitor your health factor to avoid liquidation");
        console.log("   • Health factor must stay above 1.0 to avoid liquidation");
        console.log("   • Consider repaying debt if health factor gets too low");
        
    } catch (error) {
        console.error("\nBORROW FAILED:");
        console.error("==============");
        console.error(error.message);
        
        if (error.message.includes("No collateral supplied")) {
            console.log("\nSOLUTION: Supply collateral first");
            console.log("   Use: npx hardhat run scripts/supply-to-more.js --network flow_mainnet");
        } else if (error.message.includes("No borrowing capacity")) {
            console.log("\nSOLUTION: Increase borrowing capacity");
            console.log("   • Supply more collateral");
            console.log("   • Check if your collateral is enabled for borrowing");
            console.log("   • Repay existing debt to free up capacity");
        } else if (error.message.includes("COLLATERAL_CANNOT_COVER_NEW_BORROW")) {
            console.log("\nSOLUTION: Not enough collateral for this borrow amount");
            console.log("   • Reduce the amount to borrow");
            console.log("   • Supply more collateral first");
        } else if (error.message.includes("HEALTH_FACTOR_LOWER_THAN_LIQUIDATION_THRESHOLD")) {
            console.log("\nSOLUTION: Borrowing would make health factor too low");
            console.log("   • Reduce the borrow amount");
            console.log("   • Supply more collateral");
            console.log("   • Repay some existing debt");
        } else if (error.message.includes("RESERVE_PAUSED")) {
            console.log("\nSOLUTION: The reserve is currently paused");
            console.log("   Wait for the reserve to be unpaused");
        } else if (error.message.includes("BORROWING_NOT_ENABLED")) {
            console.log("\nSOLUTION: Borrowing is not enabled for this asset");
            console.log("   Choose a different asset to borrow");
        }
        
        console.log("DEBUG COMMANDS:");
        console.log("===============");
        console.log("// Check your account data");
        console.log(`const pool = await ethers.getContractAt("Pool", "${POOL_PROXY}");`);
        console.log(`const accountData = await pool.getUserAccountData("${deployer.address}");`);
        console.log(`console.log("Available to borrow:", ethers.formatUnits(accountData.availableBorrowsBase, 8));`);
        console.log(`console.log("Health factor:", (Number(accountData.healthFactor) / 1e18).toFixed(3));`);
        
        throw error;
    }
}

main().catch(console.error);