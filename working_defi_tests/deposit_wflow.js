const { ethers } = require("hardhat");

async function main() {
    console.log("Depositing Exactly 1 WFLOW to New Multi-Asset Vault");
    
    const [deployer] = await ethers.getSigners();
    
    const VAULT_ADDRESS = "0x515f0Cef60Ed0b857425917a2a1e6e88769Aa89F";
    const WFLOW_ADDRESS = "0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e";
    
    const vault = await ethers.getContractAt("TrueMultiAssetVault", VAULT_ADDRESS);
    const wflow = await ethers.getContractAt("IERC20", WFLOW_ADDRESS);
    
    // DEPOSIT EXACTLY 1 WFLOW
    const depositAmount = ethers.parseUnits("1", 18); // 1 WFLOW (18 decimals)
    
    // Check current balance
    const balance = await wflow.balanceOf(deployer.address);
    console.log(`Your WFLOW balance: ${ethers.formatUnits(balance, 18)} WFLOW`);
    console.log(`Depositing: ${ethers.formatUnits(depositAmount, 18)} WFLOW`);
    
    if (balance < depositAmount) {
        console.log("Insufficient WFLOW balance for 1 WFLOW deposit");
        return;
    }
    
    // Check current vault shares
    const sharesBefore = await vault.balanceOf(deployer.address);
    const userWFLOWBefore = await vault.getUserAssetBalance(deployer.address, WFLOW_ADDRESS);
    console.log(`Current vault shares: ${ethers.formatUnits(sharesBefore, 18)}`);
    console.log(`Current WFLOW in vault: ${ethers.formatUnits(userWFLOWBefore, 18)} WFLOW`);
    
    // Approve exactly 1 WFLOW to vault
    console.log("Approving 1 WFLOW...");
    const approveTx = await wflow.approve(VAULT_ADDRESS, depositAmount);
    await approveTx.wait();
    console.log("1 WFLOW approved");
    
    // Deposit exactly 1 WFLOW
    console.log("Depositing 1 WFLOW...");
    try {
        const depositTx = await vault.deposit(WFLOW_ADDRESS, depositAmount, deployer.address);
        const receipt = await depositTx.wait();
        
        console.log(`Deposit successful! Hash: ${receipt.hash}`);
        console.log(`Gas used: ${receipt.gasUsed.toString()}`);
        
        // Check results
        const balanceAfter = await wflow.balanceOf(deployer.address);
        const sharesAfter = await vault.balanceOf(deployer.address);
        const userWFLOWAfter = await vault.getUserAssetBalance(deployer.address, WFLOW_ADDRESS);
        const sharesReceived = sharesAfter - sharesBefore;
        
        console.log("\nDeposit Results:");
        console.log(`WFLOW deposited: 1.0 WFLOW`);
        console.log(`WFLOW remaining: ${ethers.formatUnits(balanceAfter, 18)} WFLOW`);
        console.log(`Shares received: ${ethers.formatUnits(sharesReceived, 18)}`);
        console.log(`Total shares: ${ethers.formatUnits(sharesAfter, 18)}`);
        console.log(`WFLOW in vault: ${ethers.formatUnits(userWFLOWAfter, 18)} WFLOW`);
        
        // Show vault metrics
        const vaultMetrics = await vault.getVaultMetrics();
        console.log(`Vault TVL: $${ethers.formatUnits(vaultMetrics[0], 6)}`);
        
    } catch (error) {
        console.log(`Deposit failed: ${error.message}`);
    }
}

main().catch(console.error);