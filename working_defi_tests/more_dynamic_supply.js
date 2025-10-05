const { ethers } = require("hardhat");

async function main() {
    console.log("DYNAMIC SUPPLY TO MORE MARKETS");
    console.log("==============================");
    
    const [deployer] = await ethers.getSigners();
    console.log(`Account: ${deployer.address}\n`);
    
    const MORE_POOL = "0xbC92aaC2DBBF42215248B5688eB3D3d2b32F2c8d";
    
    // ==================== CONFIGURATION ====================
    // Change these values to supply to different pools
    const ASSET_SYMBOL = "ankrFLOWEVM"; // Token symbol to supply
    const ASSET_ADDRESS = "0x1b97100eA1D7126C4d60027e231EA4CB25314bdb"; // Token address
    const AMOUNT_TO_SUPPLY = "0.5"; // Amount to supply
    const ASSET_DECIMALS = 18; // Token decimals (18 for most, 6 for stablecoins)
    // =======================================================
    
    console.log(`Supplying ${AMOUNT_TO_SUPPLY} ${ASSET_SYMBOL}`);
    console.log(`To pool: ${ASSET_ADDRESS}\n`);
    
    const pool = await ethers.getContractAt([
        {"inputs":[{"internalType":"address","name":"asset","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"},{"internalType":"address","name":"onBehalfOf","type":"address"},{"internalType":"uint16","name":"referralCode","type":"uint16"}],"name":"supply","outputs":[],"stateMutability":"nonpayable","type":"function"},
        {"inputs":[{"internalType":"address","name":"user","type":"address"}],"name":"getUserAccountData","outputs":[{"internalType":"uint256","name":"totalCollateralBase","type":"uint256"},{"internalType":"uint256","name":"totalDebtBase","type":"uint256"},{"internalType":"uint256","name":"availableBorrowsBase","type":"uint256"},{"internalType":"uint256","name":"currentLiquidationThreshold","type":"uint256"},{"internalType":"uint256","name":"ltv","type":"uint256"},{"internalType":"uint256","name":"healthFactor","type":"uint256"}],"stateMutability":"view","type":"function"}
    ], MORE_POOL);
    
    const token = await ethers.getContractAt([
        {"inputs":[{"internalType":"address","name":"account","type":"address"}],"name":"balanceOf","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
        {"inputs":[{"internalType":"address","name":"spender","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"approve","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},
        {"inputs":[{"internalType":"address","name":"owner","type":"address"},{"internalType":"address","name":"spender","type":"address"}],"name":"allowance","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"}
    ], ASSET_ADDRESS);
    
    try {
        // Check balance
        console.log("--- CHECKING BALANCE ---");
        const balance = await token.balanceOf(deployer.address);
        const balanceFormatted = ethers.formatUnits(balance, ASSET_DECIMALS);
        console.log(`Your ${ASSET_SYMBOL} balance: ${balanceFormatted}`);
        
        const amountToSupply = ethers.parseUnits(AMOUNT_TO_SUPPLY, ASSET_DECIMALS);
        
        if (balance < amountToSupply) {
            throw new Error(`Insufficient balance. Have: ${balanceFormatted}, Need: ${AMOUNT_TO_SUPPLY}`);
        }
        
        // Check position before
        console.log("\n--- POSITION BEFORE ---");
        const accountBefore = await pool.getUserAccountData(deployer.address);
        console.log(`Collateral: $${ethers.formatUnits(accountBefore.totalCollateralBase, 8)}`);
        console.log(`Debt: $${ethers.formatUnits(accountBefore.totalDebtBase, 8)}`);
        console.log(`Available to borrow: $${ethers.formatUnits(accountBefore.availableBorrowsBase, 8)}`);
        
        // Approve
        console.log("\n--- APPROVING TOKEN ---");
        const allowance = await token.allowance(deployer.address, MORE_POOL);
        if (allowance < amountToSupply) {
            console.log(`Approving ${ASSET_SYMBOL}...`);
            const approveTx = await token.approve(MORE_POOL, ethers.MaxUint256);
            await approveTx.wait();
            console.log("✓ Approved");
        } else {
            console.log("✓ Already approved");
        }
        
        // Supply
        console.log("\n--- SUPPLYING TO MORE MARKETS ---");
        console.log(`Supplying ${AMOUNT_TO_SUPPLY} ${ASSET_SYMBOL}...`);
        
        const supplyTx = await pool.supply(
            ASSET_ADDRESS,
            amountToSupply,
            deployer.address,
            0
        );
        
        console.log(`Tx: ${supplyTx.hash}`);
        await supplyTx.wait();
        console.log("✓ Supply successful!");
        
        // Check position after
        await new Promise(resolve => setTimeout(resolve, 2000));
        
        console.log("\n--- POSITION AFTER ---");
        const accountAfter = await pool.getUserAccountData(deployer.address);
        console.log(`Collateral: $${ethers.formatUnits(accountAfter.totalCollateralBase, 8)}`);
        console.log(`Debt: $${ethers.formatUnits(accountAfter.totalDebtBase, 8)}`);
        console.log(`Available to borrow: $${ethers.formatUnits(accountAfter.availableBorrowsBase, 8)}`);
        
        const collateralIncrease = accountAfter.totalCollateralBase - accountBefore.totalCollateralBase;
        const borrowIncrease = accountAfter.availableBorrowsBase - accountBefore.availableBorrowsBase;
        
        console.log("\n--- SUMMARY ---");
        console.log(`✓ Supplied ${AMOUNT_TO_SUPPLY} ${ASSET_SYMBOL}`);
        console.log(`Collateral increased by: $${ethers.formatUnits(collateralIncrease, 8)}`);
        console.log(`Borrowing power increased by: $${ethers.formatUnits(borrowIncrease, 8)}`);
        
    } catch (error) {
        console.error("\n❌ SUPPLY FAILED:", error.message);
        throw error;
    }
}

main().catch(console.error);