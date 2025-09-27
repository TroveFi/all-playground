const { ethers } = require("hardhat");

async function main() {
    console.log("REPAYING DEBT TO MORE MARKETS");
    console.log("=============================");
    
    const [deployer] = await ethers.getSigners();
    console.log(`Repaying from account: ${deployer.address}`);
    
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
    const ASSET_TO_REPAY = "USDF"; // Asset to repay debt for
    const AMOUNT_TO_REPAY = "max"; // Amount to repay ("max" for full debt or specific amount)
    const INTEREST_RATE_MODE = 2; // 1 = stable, 2 = variable 
    // END CONFIGURATION
    
    const ASSET_ADDRESS = TOKENS[ASSET_TO_REPAY];
    if (!ASSET_ADDRESS) {
        throw new Error(`Asset ${ASSET_TO_REPAY} not found in TOKENS list`);
    }
    
    console.log(`Asset to repay: ${ASSET_TO_REPAY}`);
    console.log(`Asset address: ${ASSET_ADDRESS}`);
    console.log(`Amount: ${AMOUNT_TO_REPAY}`);
    console.log(`Interest rate mode: ${INTEREST_RATE_MODE === 1 ? 'Stable' : 'Variable'}`);
    
    // Get contract instances
    const pool = await ethers.getContractAt([
        {"inputs":[{"internalType":"address","name":"asset","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"},{"internalType":"uint256","name":"interestRateMode","type":"uint256"},{"internalType":"address","name":"onBehalfOf","type":"address"}],"name":"repay","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},
        {"inputs":[{"internalType":"address","name":"user","type":"address"}],"name":"getUserAccountData","outputs":[{"internalType":"uint256","name":"totalCollateralBase","type":"uint256"},{"internalType":"uint256","name":"totalDebtBase","type":"uint256"},{"internalType":"uint256","name":"availableBorrowsBase","type":"uint256"},{"internalType":"uint256","name":"currentLiquidationThreshold","type":"uint256"},{"internalType":"uint256","name":"ltv","type":"uint256"},{"internalType":"uint256","name":"healthFactor","type":"uint256"}],"stateMutability":"view","type":"function"}
    ], POOL_PROXY);
    
    const poolDataProvider = await ethers.getContractAt([
        {"inputs":[{"internalType":"address","name":"asset","type":"address"},{"internalType":"address","name":"user","type":"address"}],"name":"getUserReserveData","outputs":[{"internalType":"uint256","name":"currentATokenBalance","type":"uint256"},{"internalType":"uint256","name":"currentStableDebt","type":"uint256"},{"internalType":"uint256","name":"currentVariableDebt","type":"uint256"},{"internalType":"uint256","name":"principalStableDebt","type":"uint256"},{"internalType":"uint256","name":"scaledVariableDebt","type":"uint256"},{"internalType":"uint256","name":"stableBorrowRate","type":"uint256"},{"internalType":"uint256","name":"liquidityRate","type":"uint256"},{"internalType":"uint40","name":"stableRateLastUpdated","type":"uint40"},{"internalType":"bool","name":"usageAsCollateralEnabled","type":"bool"}],"stateMutability":"view","type":"function"}
    ], POOL_DATA_PROVIDER);
    
    try {
        // STEP 1: Check current debt position
        console.log("\nSTEP 1: CHECKING CURRENT DEBT POSITION");
        console.log("======================================");
        
        // Get token decimals
        let decimals;
        if (ASSET_TO_REPAY === "WFLOW") {
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
                if (ASSET_TO_REPAY === "USDF" || ASSET_TO_REPAY === "stgUSDC") {
                    decimals = 6;
                } else {
                    decimals = 18;
                }
                console.log(`Could not read decimals, assuming ${decimals}`);
            }
        }
        
        console.log(`Token decimals: ${decimals}`);
        
        // Check current debt
        const userReserveDataBefore = await poolDataProvider.getUserReserveData(ASSET_ADDRESS, deployer.address);
        const currentVariableDebt = userReserveDataBefore.currentVariableDebt;
        const currentStableDebt = userReserveDataBefore.currentStableDebt;
        const totalCurrentDebt = BigInt(currentVariableDebt) + BigInt(currentStableDebt);
        
        console.log(`Current ${ASSET_TO_REPAY} debt:`);
        console.log(`  Variable debt: ${ethers.formatUnits(currentVariableDebt, decimals)}`);
        console.log(`  Stable debt: ${ethers.formatUnits(currentStableDebt, decimals)}`);
        console.log(`  Total debt: ${ethers.formatUnits(totalCurrentDebt, decimals)}`);
        
        // Check which type of debt to repay
        let debtToRepay;
        if (INTEREST_RATE_MODE === 1) {
            debtToRepay = currentStableDebt;
            console.log(`Repaying stable debt: ${ethers.formatUnits(debtToRepay, decimals)}`);
        } else {
            debtToRepay = currentVariableDebt;
            console.log(`Repaying variable debt: ${ethers.formatUnits(debtToRepay, decimals)}`);
        }
        
        if (Number(debtToRepay) === 0) {
            throw new Error(`No ${INTEREST_RATE_MODE === 1 ? 'stable' : 'variable'} debt to repay for ${ASSET_TO_REPAY}`);
        }
        
        if (Number(totalCurrentDebt) === 0) {
            throw new Error(`No debt to repay for ${ASSET_TO_REPAY}`);
        }
        
        // STEP 2: Check wallet balance and calculate repay amount
        console.log("\nSTEP 2: CHECKING WALLET BALANCE");
        console.log("===============================");
        
        const token = await ethers.getContractAt([
            {"inputs":[{"internalType":"address","name":"account","type":"address"}],"name":"balanceOf","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"spender","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"approve","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"owner","type":"address"},{"internalType":"address","name":"spender","type":"address"}],"name":"allowance","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"}
        ], ASSET_ADDRESS);
        
        const walletBalance = await token.balanceOf(deployer.address);
        const walletBalanceFormatted = ethers.formatUnits(walletBalance, decimals);
        console.log(`Your ${ASSET_TO_REPAY} wallet balance: ${walletBalanceFormatted}`);
        
        // Calculate amount to repay
        let amountToRepay;
        if (AMOUNT_TO_REPAY.toLowerCase() === "max") {
            // Repay maximum possible (limited by debt amount and wallet balance)
            amountToRepay = walletBalance < debtToRepay ? walletBalance : debtToRepay;
            console.log(`Repaying maximum possible: ${ethers.formatUnits(amountToRepay, decimals)} ${ASSET_TO_REPAY}`);
        } else {
            // Repay specific amount
            amountToRepay = ethers.parseUnits(AMOUNT_TO_REPAY, decimals);
            console.log(`Repaying specified amount: ${AMOUNT_TO_REPAY} ${ASSET_TO_REPAY}`);
            
            if (amountToRepay > debtToRepay) {
                console.log(`Warning: Repay amount (${AMOUNT_TO_REPAY}) exceeds debt (${ethers.formatUnits(debtToRepay, decimals)})`);
                console.log(`Will repay maximum debt amount: ${ethers.formatUnits(debtToRepay, decimals)}`);
                amountToRepay = debtToRepay;
            }
        }
        
        if (Number(amountToRepay) === 0) {
            throw new Error("Nothing to repay - amount is 0");
        }
        
        if (amountToRepay > walletBalance) {
            throw new Error(`Insufficient balance. Have: ${walletBalanceFormatted}, Need: ${ethers.formatUnits(amountToRepay, decimals)}`);
        }
        
        // STEP 3: Check and set allowance
        console.log("\nSTEP 3: CHECKING/SETTING ALLOWANCE");
        console.log("==================================");
        
        const currentAllowance = await token.allowance(deployer.address, POOL_PROXY);
        console.log(`Current allowance: ${ethers.formatUnits(currentAllowance, decimals)}`);
        
        if (currentAllowance < amountToRepay) {
            console.log("Approval needed for repayment...");
            
            // Add 10% buffer to handle interest accrual during transaction
            const approvalAmount = (amountToRepay * BigInt(110)) / BigInt(100);
            console.log(`Approving ${ethers.formatUnits(approvalAmount, decimals)} ${ASSET_TO_REPAY}...`);
            
            const approveTx = await token.approve(POOL_PROXY, approvalAmount);
            console.log(`Approval transaction sent: ${approveTx.hash}`);
            console.log("Waiting for approval confirmation...");
            
            await approveTx.wait();
            console.log("Approval confirmed!");
            
            const newAllowance = await token.allowance(deployer.address, POOL_PROXY);
            console.log(`New allowance: ${ethers.formatUnits(newAllowance, decimals)}`);
        } else {
            console.log("Sufficient allowance already exists");
        }
        
        // STEP 4: Check current account status
        console.log("\nSTEP 4: CHECKING CURRENT ACCOUNT STATUS");
        console.log("======================================");
        
        const accountDataBefore = await pool.getUserAccountData(deployer.address);
        console.log("Before repayment:");
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
        
        // STEP 5: Execute repayment
        console.log("\nSTEP 5: EXECUTING REPAYMENT");
        console.log("===========================");
        
        console.log(`Repaying ${ethers.formatUnits(amountToRepay, decimals)} ${ASSET_TO_REPAY}...`);
        console.log(`To: ${POOL_PROXY}`);
        console.log(`Asset: ${ASSET_ADDRESS}`);
        console.log(`Amount: ${amountToRepay.toString()}`);
        console.log(`Interest Rate Mode: ${INTEREST_RATE_MODE} (${INTEREST_RATE_MODE === 1 ? 'Stable' : 'Variable'})`);
        console.log(`On behalf of: ${deployer.address}`);
        
        // For max repayment, use type(uint256).max to repay all debt
        const repayAmount = AMOUNT_TO_REPAY.toLowerCase() === "max" && amountToRepay >= debtToRepay 
            ? ethers.MaxUint256 
            : amountToRepay;
        
        const repayTx = await pool.repay(
            ASSET_ADDRESS,
            repayAmount,
            INTEREST_RATE_MODE,
            deployer.address
        );
        
        console.log(`Repay transaction sent: ${repayTx.hash}`);
        console.log("Waiting for confirmation...");
        
        const receipt = await repayTx.wait();
        console.log(`Repayment successful!`);
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
                    if (parsedLog.name === "Repay") {
                        console.log(`  Reserve: ${parsedLog.args[0]}`);
                        console.log(`  User: ${parsedLog.args[1]}`);
                        console.log(`  Repayer: ${parsedLog.args[2]}`);
                        console.log(`  Amount: ${ethers.formatUnits(parsedLog.args[3], decimals)}`);
                        console.log(`  Use ATokens: ${parsedLog.args[4]}`);
                    }
                }
            } catch (e) {
                // Ignore unparseable logs
            }
        }
        
        // STEP 6: Verify results
        console.log("\nSTEP 6: VERIFYING RESULTS");
        console.log("=========================");
        
        // Wait for state to update
        await new Promise(resolve => setTimeout(resolve, 2000));
        
        // Check new wallet balance
        const walletBalanceAfter = await token.balanceOf(deployer.address);
        const tokensUsed = walletBalance - walletBalanceAfter;
        console.log(`New ${ASSET_TO_REPAY} wallet balance: ${ethers.formatUnits(walletBalanceAfter, decimals)}`);
        console.log(`${ASSET_TO_REPAY} used for repayment: ${ethers.formatUnits(tokensUsed, decimals)}`);
        
        // Check new debt position
        const userReserveDataAfter = await poolDataProvider.getUserReserveData(ASSET_ADDRESS, deployer.address);
        const newVariableDebt = userReserveDataAfter.currentVariableDebt;
        const newStableDebt = userReserveDataAfter.currentStableDebt;
        const newTotalDebt = BigInt(newVariableDebt) + BigInt(newStableDebt);
        
        console.log(`New ${ASSET_TO_REPAY} debt:`);
        console.log(`  Variable debt: ${ethers.formatUnits(newVariableDebt, decimals)}`);
        console.log(`  Stable debt: ${ethers.formatUnits(newStableDebt, decimals)}`);
        console.log(`  Total debt: ${ethers.formatUnits(newTotalDebt, decimals)}`);
        
        const debtReduction = totalCurrentDebt - newTotalDebt;
        console.log(`Debt reduced by: ${ethers.formatUnits(debtReduction, decimals)} ${ASSET_TO_REPAY}`);
        
        // Check new account data
        const accountDataAfter = await pool.getUserAccountData(deployer.address);
        console.log("\nAfter repayment:");
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
        
        // Calculate improvements
        const debtReductionUSD = accountDataBefore.totalDebtBase - accountDataAfter.totalDebtBase;
        const borrowingCapacityIncrease = accountDataAfter.availableBorrowsBase - accountDataBefore.availableBorrowsBase;
        
        console.log("\nImprovements:");
        console.log(`  Total debt reduced by: $${ethers.formatUnits(debtReductionUSD, 8)}`);
        console.log(`  Borrowing capacity increased by: $${ethers.formatUnits(borrowingCapacityIncrease, 8)}`);
        
        if (healthFactor > 0 && healthFactorAfter > 0) {
            const hfImprovement = (healthFactorAfter - healthFactor) / 1e18;
            console.log(`  Health factor improved by: ${hfImprovement.toFixed(3)}`);
        }
        
        // STEP 7: Summary
        console.log("\nSUMMARY");
        console.log("=======");
        console.log(`Successfully repaid ${ethers.formatUnits(debtReduction, decimals)} ${ASSET_TO_REPAY} debt`);
        console.log(`Used ${ethers.formatUnits(tokensUsed, decimals)} ${ASSET_TO_REPAY} from wallet`);
        console.log(`Total debt reduced by $${ethers.formatUnits(debtReductionUSD, 8)}`);
        console.log(`Borrowing capacity increased by $${ethers.formatUnits(borrowingCapacityIncrease, 8)}`);
        
        if (Number(newTotalDebt) === 0) {
            console.log(`All ${ASSET_TO_REPAY} debt repaid!`);
        } else {
            console.log(`Remaining ${ASSET_TO_REPAY} debt: ${ethers.formatUnits(newTotalDebt, decimals)}`);
        }
        
        const finalHF = healthFactorAfter === 0 ? "∞" : (healthFactorAfter / 1e18).toFixed(3);
        console.log(`Current health factor: ${finalHF}`);
        
        console.log("\nNext Steps:");
        console.log("   1. Check balances: npx hardhat run scripts/check-balances.js --network flow_mainnet");
        if (Number(newTotalDebt) > 0) {
            console.log("   2. Repay more debt: npx hardhat run scripts/repay-debt.js --network flow_mainnet");
        }
        console.log("   3. Borrow more if needed: npx hardhat run scripts/borrow-from-more.js --network flow_mainnet");
        console.log("   4. Withdraw collateral: npx hardhat run scripts/withdraw-from-more.js --network flow_mainnet");
        
        console.log("\nBenefits of repaying debt:");
        console.log("   • Reduces interest payments");
        console.log("   • Improves health factor");
        console.log("   • Increases borrowing capacity");
        console.log("   • Reduces liquidation risk");
        
    } catch (error) {
        console.error("\nREPAYMENT FAILED:");
        console.error("=================");
        console.error(error.message);
        
        if (error.message.includes("No debt to repay")) {
            console.log("\nSOLUTION: No debt found");
            console.log("   You don't have any debt for this asset/rate type");
            console.log("   Check your debt positions or choose a different asset");
        } else if (error.message.includes("Insufficient balance")) {
            console.log("\nSOLUTION: Not enough tokens to repay");
            console.log("   Get more tokens or reduce the repayment amount");
        } else if (error.message.includes("ERC20InsufficientAllowance")) {
            console.log("\nSOLUTION: Insufficient allowance");
            console.log("   The approval transaction may have failed");
            console.log("   Try running the script again");
        } else if (error.message.includes("RESERVE_PAUSED")) {
            console.log("\nSOLUTION: Reserve is paused");
            console.log("   Wait for the reserve to be unpaused");
        }
        
        console.log("\nDEBUG COMMANDS:");
        console.log("===============");
        console.log("// Check your debt");
        console.log(`const poolDataProvider = await ethers.getContractAt("PoolDataProvider", "${POOL_DATA_PROVIDER}");`);
        console.log(`const userData = await poolDataProvider.getUserReserveData("${ASSET_ADDRESS}", "${deployer.address}");`);
        console.log(`console.log("Variable debt:", ethers.formatUnits(userData.currentVariableDebt, ${decimals}));`);
        console.log(`console.log("Stable debt:", ethers.formatUnits(userData.currentStableDebt, ${decimals}));`);
        
        console.log("\n// Check your balance");
        console.log(`const token = await ethers.getContractAt("ERC20", "${ASSET_ADDRESS}");`);
        console.log(`const balance = await token.balanceOf("${deployer.address}");`);
        console.log(`console.log("Balance:", ethers.formatUnits(balance, ${decimals}));`);
        
        throw error;
    }
}

main().catch(console.error);