const { ethers } = require("hardhat");

async function main() {
    console.log("DYNAMIC BORROW FROM MORE MARKETS");
    console.log("================================");
    
    const [deployer] = await ethers.getSigners();
    console.log(`Account: ${deployer.address}\n`);
    
    const MORE_POOL = "0xbC92aaC2DBBF42215248B5688eB3D3d2b32F2c8d";
    
    // ==================== CONFIGURATION ====================
    // Change these values to borrow from different pools
    const ASSET_SYMBOL = "USDF"; // Token symbol to borrow
    const ASSET_ADDRESS = "0x2aaBea2058b5aC2D339b163C6Ab6f2b6d53aabED"; // Token address
    const AMOUNT_TO_BORROW = "0.1"; // SMALL amount to borrow (requires collateral!)
    const ASSET_DECIMALS = 6; // Token decimals (6 for USDF, 18 for most)
    const INTEREST_RATE_MODE = 2; // 2 = variable (recommended)
    // =======================================================
    
    console.log(`Borrowing ${AMOUNT_TO_BORROW} ${ASSET_SYMBOL}`);
    console.log(`From pool: ${ASSET_ADDRESS}`);
    console.log(`Rate mode: ${INTEREST_RATE_MODE === 2 ? 'Variable' : 'Stable'}\n`);
    
    const pool = await ethers.getContractAt([
        {"inputs":[{"internalType":"address","name":"asset","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"},{"internalType":"uint256","name":"interestRateMode","type":"uint256"},{"internalType":"uint16","name":"referralCode","type":"uint16"},{"internalType":"address","name":"onBehalfOf","type":"address"}],"name":"borrow","outputs":[],"stateMutability":"nonpayable","type":"function"},
        {"inputs":[{"internalType":"address","name":"user","type":"address"}],"name":"getUserAccountData","outputs":[{"internalType":"uint256","name":"totalCollateralBase","type":"uint256"},{"internalType":"uint256","name":"totalDebtBase","type":"uint256"},{"internalType":"uint256","name":"availableBorrowsBase","type":"uint256"},{"internalType":"uint256","name":"currentLiquidationThreshold","type":"uint256"},{"internalType":"uint256","name":"ltv","type":"uint256"},{"internalType":"uint256","name":"healthFactor","type":"uint256"}],"stateMutability":"view","type":"function"}
    ], MORE_POOL);
    
    const token = await ethers.getContractAt([
        {"inputs":[{"internalType":"address","name":"account","type":"address"}],"name":"balanceOf","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"}
    ], ASSET_ADDRESS);
    
    try {
        // Check prerequisites
        console.log("--- CHECKING PREREQUISITES ---");
        const accountData = await pool.getUserAccountData(deployer.address);
        
        const totalCollateral = Number(ethers.formatUnits(accountData.totalCollateralBase, 8));
        const totalDebt = Number(ethers.formatUnits(accountData.totalDebtBase, 8));
        const availableToBorrow = Number(ethers.formatUnits(accountData.availableBorrowsBase, 8));
        const healthFactor = Number(accountData.healthFactor);
        
        console.log(`Collateral: $${totalCollateral.toFixed(4)}`);
        console.log(`Current Debt: $${totalDebt.toFixed(4)}`);
        console.log(`Available to borrow: $${availableToBorrow.toFixed(4)}`);
        console.log(`Health Factor: ${healthFactor === 0 ? "∞" : (healthFactor / 1e18).toFixed(3)}`);
        
        // Check if user has collateral
        if (totalCollateral === 0) {
            throw new Error("No collateral! You must supply assets first before borrowing.");
        }
        
        // Check if can borrow
        if (availableToBorrow < 0.01) {
            throw new Error("No borrowing capacity available. Supply more collateral.");
        }
        
        // Check balance before
        const balanceBefore = await token.balanceOf(deployer.address);
        console.log(`\nCurrent ${ASSET_SYMBOL} balance: ${ethers.formatUnits(balanceBefore, ASSET_DECIMALS)}`);
        
        // Parse amount
        const amountToBorrow = ethers.parseUnits(AMOUNT_TO_BORROW, ASSET_DECIMALS);
        
        // Check if amount is reasonable
        const borrowValueUSD = parseFloat(AMOUNT_TO_BORROW); // Assume 1:1 for estimation
        if (borrowValueUSD > availableToBorrow * 0.5) {
            console.log(`\n⚠️  WARNING: Borrowing ${borrowValueUSD.toFixed(2)} of ${availableToBorrow.toFixed(2)} available`);
            console.log("This will significantly impact your health factor!");
        }
        
        // Execute borrow
        console.log("\n--- EXECUTING BORROW ---");
        console.log(`Borrowing ${AMOUNT_TO_BORROW} ${ASSET_SYMBOL}...`);
        
        const borrowTx = await pool.borrow(
            ASSET_ADDRESS,
            amountToBorrow,
            INTEREST_RATE_MODE,
            0, // referral code
            deployer.address
        );
        
        console.log(`Tx: ${borrowTx.hash}`);
        await borrowTx.wait();
        console.log("✓ Borrow successful!");
        
        // Check balance after
        await new Promise(resolve => setTimeout(resolve, 2000));
        
        const balanceAfter = await token.balanceOf(deployer.address);
        const received = balanceAfter - balanceBefore;
        
        console.log("\n--- VERIFICATION ---");
        console.log(`${ASSET_SYMBOL} received: ${ethers.formatUnits(received, ASSET_DECIMALS)}`);
        console.log(`New ${ASSET_SYMBOL} balance: ${ethers.formatUnits(balanceAfter, ASSET_DECIMALS)}`);
        
        // Check new position
        const accountAfter = await pool.getUserAccountData(deployer.address);
        const finalHealthFactor = Number(accountAfter.healthFactor);
        
        console.log("\n--- POSITION AFTER BORROW ---");
        console.log(`Collateral: $${ethers.formatUnits(accountAfter.totalCollateralBase, 8)}`);
        console.log(`Total Debt: $${ethers.formatUnits(accountAfter.totalDebtBase, 8)}`);
        console.log(`Available to borrow: $${ethers.formatUnits(accountAfter.availableBorrowsBase, 8)}`);
        console.log(`Health Factor: ${finalHealthFactor === 0 ? "∞" : (finalHealthFactor / 1e18).toFixed(3)}`);
        
        const debtIncrease = accountAfter.totalDebtBase - accountData.totalDebtBase;
        
        console.log("\n--- SUMMARY ---");
        console.log(`✓ Borrowed ${ethers.formatUnits(received, ASSET_DECIMALS)} ${ASSET_SYMBOL}`);
        console.log(`Debt increased by: $${ethers.formatUnits(debtIncrease, 8)}`);
        
        if (finalHealthFactor < 1.5e18 && finalHealthFactor > 0) {
            console.log(`\n⚠️  WARNING: Health Factor is ${(finalHealthFactor / 1e18).toFixed(3)}`);
            console.log("This is in the HIGH RISK zone for liquidation!");
            console.log("Consider repaying debt or supplying more collateral.");
        }
        
        console.log("\nNext steps:");
        console.log("- Monitor health factor regularly");
        console.log("- To repay: Use repay script with this asset");
        console.log("- To check position: npx hardhat run scripts/more/check-balances.js --network flow_mainnet");
        
    } catch (error) {
        console.error("\n❌ BORROW FAILED:", error.message);
        
        if (error.message.includes("No collateral")) {
            console.log("\nSOLUTION:");
            console.log("1. First supply assets as collateral");
            console.log("2. Use: npx hardhat run scripts/more/dynamic-supply.js --network flow_mainnet");
        } else if (error.message.includes("No borrowing capacity")) {
            console.log("\nSOLUTION:");
            console.log("- Supply more collateral first");
            console.log("- Check if your collateral is enabled for borrowing");
        } else if (error.message.includes("COLLATERAL_CANNOT_COVER_NEW_BORROW")) {
            console.log("\nSOLUTION:");
            console.log("- Reduce the borrow amount");
            console.log("- Supply more collateral");
        }
        
        throw error;
    }
}

main().catch(console.error);