const { ethers } = require("hardhat");

async function main() {
    console.log("Depositing Exactly 1 USDF to New Multi-Asset Vault");
    
    const [deployer] = await ethers.getSigners();
    
    const VAULT_ADDRESS = "0x515f0Cef60Ed0b857425917a2a1e6e88769Aa89F";
    const USDF_ADDRESS = "0x2aaBea2058b5aC2D339b163C6Ab6f2b6d53aabED";
    
    const vault = await ethers.getContractAt("TrueMultiAssetVault", VAULT_ADDRESS);
    const usdf = await ethers.getContractAt("IERC20", USDF_ADDRESS);
    
    // DEPOSIT EXACTLY 1 USDF
    const depositAmount = ethers.parseUnits("1", 6); // 1 USDF (6 decimals)
    
    // Check current balance
    const balance = await usdf.balanceOf(deployer.address);
    console.log(`Your USDF balance: ${ethers.formatUnits(balance, 6)} USDF`);
    console.log(`Depositing: ${ethers.formatUnits(depositAmount, 6)} USDF`);
    
    if (balance < depositAmount) {
        console.log("Insufficient USDF balance for 1 USDF deposit");
        return;
    }
    
    // Check current vault shares
    const sharesBefore = await vault.balanceOf(deployer.address);
    const userUSDFBefore = await vault.getUserAssetBalance(deployer.address, USDF_ADDRESS);
    console.log(`Current vault shares: ${ethers.formatUnits(sharesBefore, 18)}`);
    console.log(`Current USDF in vault: ${ethers.formatUnits(userUSDFBefore, 6)} USDF`);
    
    // Approve exactly 1 USDF to vault
    console.log("Approving 1 USDF...");
    const approveTx = await usdf.approve(VAULT_ADDRESS, depositAmount);
    await approveTx.wait();
    console.log("1 USDF approved");
    
    // Deposit exactly 1 USDF
    console.log("Depositing 1 USDF...");
    try {
        const depositTx = await vault.deposit(USDF_ADDRESS, depositAmount, deployer.address);
        const receipt = await depositTx.wait();
        
        console.log(`Deposit successful! Hash: ${receipt.hash}`);
        console.log(`Gas used: ${receipt.gasUsed.toString()}`);
        
        // Check results
        const balanceAfter = await usdf.balanceOf(deployer.address);
        const sharesAfter = await vault.balanceOf(deployer.address);
        const userUSDFAfter = await vault.getUserAssetBalance(deployer.address, USDF_ADDRESS);
        const sharesReceived = sharesAfter - sharesBefore;
        
        console.log("\nDeposit Results:");
        console.log(`USDF deposited: 1.0 USDF`);
        console.log(`USDF remaining: ${ethers.formatUnits(balanceAfter, 6)} USDF`);
        console.log(`Shares received: ${ethers.formatUnits(sharesReceived, 18)}`);
        console.log(`Total shares: ${ethers.formatUnits(sharesAfter, 18)}`);
        console.log(`USDF in vault: ${ethers.formatUnits(userUSDFAfter, 6)} USDF`);
        
        // Show vault metrics
        const vaultMetrics = await vault.getVaultMetrics();
        console.log(`Vault TVL: $${ethers.formatUnits(vaultMetrics[0], 6)}`);
        
    } catch (error) {
        console.log(`Deposit failed: ${error.message}`);
    }
}

main().catch(console.error);