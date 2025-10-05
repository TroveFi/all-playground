const { ethers } = require("hardhat");

async function main() {
    console.log("WITHDRAWING ASSETS FROM MORE MARKETS");
    console.log("====================================");
    
    const [deployer] = await ethers.getSigners();
    console.log(`Withdrawing to account: ${deployer.address}`);
    
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
    const ASSET_TO_WITHDRAW = "stgUSDC"; // Change this to the asset you want to withdraw
    const AMOUNT_TO_WITHDRAW = "1"; // Amount to withdraw (use "max" for maximum available)
    // END CONFIGURATION
    
    const ASSET_ADDRESS = TOKENS[ASSET_TO_WITHDRAW];
    if (!ASSET_ADDRESS) {
        throw new Error(`Asset ${ASSET_TO_WITHDRAW} not found in TOKENS list`);
    }
    
    console.log(`Asset to withdraw: ${ASSET_TO_WITHDRAW}`);
    console.log(`Asset address: ${ASSET_ADDRESS}`);
    console.log(`Amount: ${AMOUNT_TO_WITHDRAW}`);
    
    // Get contract instances
    const pool = await ethers.getContractAt([
        {"inputs":[{"internalType":"address","name":"asset","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"},{"internalType":"address","name":"to","type":"address"}],"name":"withdraw","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},
        {"inputs":[{"internalType":"address","name":"user","type":"address"}],"name":"getUserAccountData","outputs":[{"internalType":"uint256","name":"totalCollateralBase","type":"uint256"},{"internalType":"uint256","name":"totalDebtBase","type":"uint256"},{"internalType":"uint256","name":"availableBorrowsBase","type":"uint256"},{"internalType":"uint256","name":"currentLiquidationThreshold","type":"uint256"},{"internalType":"uint256","name":"ltv","type":"uint256"},{"internalType":"uint256","name":"healthFactor","type":"uint256"}],"stateMutability":"view","type":"function"}
    ], POOL_PROXY);
    
    const poolDataProvider = await ethers.getContractAt([
        {"inputs":[{"internalType":"address","name":"asset","type":"address"}],"name":"getReserveTokensAddresses","outputs":[{"internalType":"address","name":"aTokenAddress","type":"address"},{"internalType":"address","name":"stableDebtTokenAddress","type":"address"},{"internalType":"address","name":"variableDebtTokenAddress","type":"address"}],"stateMutability":"view","type":"function"},
        {"inputs":[{"internalType":"address","name":"asset","type":"address"},{"internalType":"address","name":"user","type":"address"}],"name":"getUserReserveData","outputs":[{"internalType":"uint256","name":"currentATokenBalance","type":"uint256"},{"internalType":"uint256","name":"currentStableDebt","type":"uint256"},{"internalType":"uint256","name":"currentVariableDebt","type":"uint256"},{"internalType":"uint256","name":"principalStableDebt","type":"uint256"},{"internalType":"uint256","name":"scaledVariableDebt","type":"uint256"},{"internalType":"uint256","name":"stableBorrowRate","type":"uint256"},{"internalType":"uint256","name":"liquidityRate","type":"uint256"},{"internalType":"uint40","name":"stableRateLastUpdated","type":"uint40"},{"internalType":"bool","name":"usageAsCollateralEnabled","type":"bool"}],"stateMutability":"view","type":"function"}
    ], POOL_DATA_PROVIDER);
    
    try {
        // STEP 1: Get token decimals and check current position
        console.log("\nSTEP 1: CHECKING CURRENT POSITION");
        console.log("=================================");
        
        // Get token decimals
        let decimals;
        if (ASSET_TO_WITHDRAW === "WFLOW") {
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
                if (ASSET_TO_WITHDRAW === "USDF" || ASSET_TO_WITHDRAW === "stgUSDC") {
                    decimals = 6;
                } else {
                    decimals = 18;
                }
                console.log(`Could not read decimals, assuming ${decimals}`);
            }
        }
        
        console.log(`Token decimals: ${decimals}`);
        
        // Check current aToken balance (what you have supplied)
        const reserveTokens = await poolDataProvider.getReserveTokensAddresses(ASSET_ADDRESS);
        const aTokenAddress = reserveTokens.aTokenAddress;
        console.log(`aToken address: ${aTokenAddress}`);
        
        const aToken = await ethers.getContractAt([
            {"inputs":[{"internalType":"address","name":"account","type":"address"}],"name":"balanceOf","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"}
        ], aTokenAddress);
        
        const aTokenBalance = await aToken.balanceOf(deployer.address);
        const aTokenBalanceFormatted = ethers.formatUnits(aTokenBalance, decimals);
        console.log(`Your a${ASSET_TO_WITHDRAW} balance: ${aTokenBalanceFormatted}`);
        
        if (Number(aTokenBalanceFormatted) === 0) {
            throw new Error(`No ${ASSET_TO_WITHDRAW} supplied to withdraw. Supply some first using supply-to-more.js`);
        }
        
        // Get user reserve data for more details
        const userReserveData = await poolDataProvider.getUserReserveData(ASSET_ADDRESS, deployer.address);
        const currentATokenBalance = userReserveData.currentATokenBalance;
        console.log(`Current a${ASSET_TO_WITHDRAW} balance (precise): ${ethers.formatUnits(currentATokenBalance, decimals)}`);
        
        // Check account data
        const accountDataBefore = await pool.getUserAccountData(deployer.address);
        console.log("\nBefore withdrawal:");
        console.log(`  Total Collateral: $${ethers.formatUnits(accountDataBefore.totalCollateralBase, 8)}`);
        console.log(`  Total Debt: $${ethers.formatUnits(accountDataBefore.totalDebtBase, 8)}`);
        console.log(`  Available to Borrow: $${ethers.formatUnits(accountDataBefore.availableBorrowsBase, 8)}`);
        
        const healthFactor = Number(accountDataBefore.healthFactor);
        if (healthFactor === 0) {
            console.log(`  Health Factor: ∞ (No debt)`);
        } else {
            const hfFormatted = (healthFactor / 1e18).toFixed(3);
            console.log(`  Health Factor: ${hfFormatted} ${healthFactor < 1e18 ? "DANGER" : "OK"}`);
        }
        
        // STEP 2: Calculate withdrawal amount
        console.log("\nSTEP 2: CALCULATING WITHDRAWAL AMOUNT");
        console.log("=====================================");
        
        let amountToWithdraw;
        
        if (AMOUNT_TO_WITHDRAW.toLowerCase() === "max") {
            // Withdraw maximum available
            amountToWithdraw = currentATokenBalance;
            console.log(`Withdrawing maximum available: ${ethers.formatUnits(amountToWithdraw, decimals)} ${ASSET_TO_WITHDRAW}`);
        } else {
            // Withdraw specific amount
            amountToWithdraw = ethers.parseUnits(AMOUNT_TO_WITHDRAW, decimals);
            console.log(`Withdrawing specified amount: ${AMOUNT_TO_WITHDRAW} ${ASSET_TO_WITHDRAW}`);
            
            if (amountToWithdraw > currentATokenBalance) {
                throw new Error(`Cannot withdraw ${AMOUNT_TO_WITHDRAW} ${ASSET_TO_WITHDRAW}. Available: ${ethers.formatUnits(currentATokenBalance, decimals)}`);
            }
        }
        
        // Check if withdrawal would affect health factor dangerously
        if (Number(accountDataBefore.totalDebtBase) > 0) {
            console.log("\nWARNING: You have debt positions. Withdrawing collateral may affect your health factor.");
            console.log("Make sure your health factor stays above 1.0 to avoid liquidation.");
        }
        
        // STEP 3: Check current wallet balance
        console.log("\nSTEP 3: CHECKING CURRENT WALLET BALANCE");
        console.log("======================================");
        
        const token = await ethers.getContractAt([
            {"inputs":[{"internalType":"address","name":"account","type":"address"}],"name":"balanceOf","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"}
        ], ASSET_ADDRESS);
        
        const walletBalanceBefore = await token.balanceOf(deployer.address);
        console.log(`Current ${ASSET_TO_WITHDRAW} wallet balance: ${ethers.formatUnits(walletBalanceBefore, decimals)}`);
        
        // STEP 4: Execute withdrawal
        console.log("\nSTEP 4: EXECUTING WITHDRAWAL");
        console.log("============================");
        
        console.log(`Withdrawing ${ethers.formatUnits(amountToWithdraw, decimals)} ${ASSET_TO_WITHDRAW}...`);
        console.log(`From: ${POOL_PROXY}`);
        console.log(`Asset: ${ASSET_ADDRESS}`);
        console.log(`Amount: ${amountToWithdraw.toString()}`);
        console.log(`To: ${deployer.address}`);
        
        const withdrawTx = await pool.withdraw(
            ASSET_ADDRESS,
            amountToWithdraw,
            deployer.address
        );
        
        console.log(`Withdrawal transaction sent: ${withdrawTx.hash}`);
        console.log("Waiting for confirmation...");
        
        const receipt = await withdrawTx.wait();
        console.log(`Withdrawal successful!`);
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
                    if (parsedLog.name === "Withdraw") {
                        console.log(`  Reserve: ${parsedLog.args[0]}`);
                        console.log(`  User: ${parsedLog.args[1]}`);
                        console.log(`  To: ${parsedLog.args[2]}`);
                        console.log(`  Amount: ${ethers.formatUnits(parsedLog.args[3], decimals)}`);
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
        console.log(`New ${ASSET_TO_WITHDRAW} wallet balance: ${ethers.formatUnits(walletBalanceAfter, decimals)}`);
        console.log(`${ASSET_TO_WITHDRAW} received: ${ethers.formatUnits(tokensReceived, decimals)}`);
        
        // Check new aToken balance
        const aTokenBalanceAfter = await aToken.balanceOf(deployer.address);
        const aTokenBurned = aTokenBalance - aTokenBalanceAfter;
        console.log(`New a${ASSET_TO_WITHDRAW} balance: ${ethers.formatUnits(aTokenBalanceAfter, decimals)}`);
        console.log(`a${ASSET_TO_WITHDRAW} burned: ${ethers.formatUnits(aTokenBurned, decimals)}`);
        
        // Check new account data
        const accountDataAfter = await pool.getUserAccountData(deployer.address);
        console.log("\nAfter withdrawal:");
        console.log(`  Total Collateral: $${ethers.formatUnits(accountDataAfter.totalCollateralBase, 8)}`);
        console.log(`  Total Debt: $${ethers.formatUnits(accountDataAfter.totalDebtBase, 8)}`);
        console.log(`  Available to Borrow: $${ethers.formatUnits(accountDataAfter.availableBorrowsBase, 8)}`);
        
        const healthFactorAfter = Number(accountDataAfter.healthFactor);
        if (healthFactorAfter === 0) {
            console.log(`  Health Factor: ∞ (No debt)`);
        } else {
            const hfAfterFormatted = (healthFactorAfter / 1e18).toFixed(3);
            console.log(`  Health Factor: ${hfAfterFormatted} ${healthFactorAfter < 1e18 ? "DANGER" : "OK"}`);
        }
        
        // Calculate changes
        const collateralDecrease = accountDataBefore.totalCollateralBase - accountDataAfter.totalCollateralBase;
        const borrowingPowerDecrease = accountDataBefore.availableBorrowsBase - accountDataAfter.availableBorrowsBase;
        
        console.log("\nChanges:");
        console.log(`  Collateral decreased by: ${ethers.formatUnits(collateralDecrease, 8)}`);
        console.log(`  Borrowing power decreased by: ${ethers.formatUnits(borrowingPowerDecrease, 8)}`);
        
        // STEP 6: Summary
        console.log("\nSUMMARY");
        console.log("=======");
        console.log(`Successfully withdrew ${ethers.formatUnits(tokensReceived, decimals)} ${ASSET_TO_WITHDRAW}`);
        console.log(`Your ${ASSET_TO_WITHDRAW} wallet balance increased by ${ethers.formatUnits(tokensReceived, decimals)}`);
        console.log(`Your collateral value decreased by ${ethers.formatUnits(collateralDecrease, 8)}`);
        
        if (Number(accountDataAfter.totalDebtBase) > 0) {
            console.log(`You can now borrow up to ${ethers.formatUnits(accountDataAfter.availableBorrowsBase, 8)}`);
            const hfAfter = (healthFactorAfter / 1e18).toFixed(3);
            if (healthFactorAfter < 1.2e18 && healthFactorAfter > 0) {
                console.log(`WARNING: Health factor is ${hfAfter} - consider monitoring closely`);
            }
        }
        
        const remainingSupply = ethers.formatUnits(aTokenBalanceAfter, decimals);
        if (Number(remainingSupply) > 0) {
            console.log(`Remaining ${ASSET_TO_WITHDRAW} supply: ${remainingSupply}`);
        } else {
            console.log(`All ${ASSET_TO_WITHDRAW} withdrawn - no remaining supply position`);
        }
        
        console.log("\nNext Steps:");
        console.log("   1. Check balances: npx hardhat run scripts/check-balances.js --network flow_mainnet");
        console.log("   2. Supply more assets: npx hardhat run scripts/supply-to-more.js --network flow_mainnet");
        if (Number(accountDataAfter.totalDebtBase) > 0) {
            console.log("   3. Repay debt: npx hardhat run scripts/repay-debt.js --network flow_mainnet");
        }
        
        console.log("\nTips:");
        console.log("   • Withdrawing reduces your collateral and borrowing capacity");
        console.log("   • Monitor health factor if you have outstanding debt");
        console.log("   • Consider partial withdrawals to maintain borrowing power");
        
    } catch (error) {
        console.error("\nWITHDRAWAL FAILED:");
        console.error("==================");
        console.error(error.message);
        
        if (error.message.includes("ERC20InsufficientBalance")) {
            console.log("\nSOLUTION: Insufficient aToken balance");
            console.log("   You don't have enough supplied to withdraw this amount");
            console.log("   Check your supply balance or reduce the withdrawal amount");
        } else if (error.message.includes("HEALTH_FACTOR_LOWER_THAN_LIQUIDATION_THRESHOLD")) {
            console.log("\nSOLUTION: Withdrawal would make health factor too low");
            console.log("   Either:");
            console.log("   1. Repay some debt first to improve health factor");
            console.log("   2. Withdraw a smaller amount");
            console.log("   3. Supply more collateral before withdrawing");
        } else if (error.message.includes("NOT_ENOUGH_AVAILABLE_USER_BALANCE")) {
            console.log("\nSOLUTION: Not enough balance to withdraw");
            console.log("   This might be due to:");
            console.log("   1. Some funds being used as collateral for loans");
            console.log("   2. Temporary liquidity constraints in the market");
        } else if (error.message.includes("RESERVE_PAUSED")) {
            console.log("\nSOLUTION: The reserve is currently paused");
            console.log("   Wait for the reserve to be unpaused or contact support");
        }
        
        console.log("\nDEBUG COMMANDS:");
        console.log("===============");
        console.log("// Check your aToken balance");
        console.log(`const aToken = await ethers.getContractAt("ERC20", "${aTokenAddress}");`);
        console.log(`const balance = await aToken.balanceOf("${deployer.address}");`);
        console.log(`console.log("aToken Balance:", ethers.formatUnits(balance, ${decimals}));`);
        
        console.log("\n// Check your account health");
        console.log(`const pool = await ethers.getContractAt("Pool", "${POOL_PROXY}");`);
        console.log(`const accountData = await pool.getUserAccountData("${deployer.address}");`);
        console.log(`console.log("Health Factor:", (Number(accountData.healthFactor) / 1e18).toFixed(3));`);
        
        throw error;
    }
}

main().catch(console.error);