const { ethers } = require("hardhat");

async function main() {
    console.log("Depositing Exactly 0.01 WETH to New Multi-Asset Vault");
    
    const [deployer] = await ethers.getSigners();
    
    const VAULT_ADDRESS = "0x515f0Cef60Ed0b857425917a2a1e6e88769Aa89F";
    const WETH_ADDRESS = "0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590";
    
    const vault = await ethers.getContractAt("TrueMultiAssetVault", VAULT_ADDRESS);
    const weth = await ethers.getContractAt("IERC20", WETH_ADDRESS);
    
    // DEPOSIT EXACTLY 0.01 WETH
    const depositAmount = ethers.parseUnits("0.01", 18); // 0.01 WETH (18 decimals)
    
    // Check current balance
    const balance = await weth.balanceOf(deployer.address);
    console.log(`Your WETH balance: ${ethers.formatUnits(balance, 18)} WETH`);
    console.log(`Depositing: ${ethers.formatUnits(depositAmount, 18)} WETH`);
    
    if (balance < depositAmount) {
        console.log("Insufficient WETH balance for 0.01 WETH deposit");
        console.log("You need to get some WETH first");
        return;
    }
    
    // Check vault minimum
    const assetInfo = await vault.assetInfo(WETH_ADDRESS);
    const minDeposit = assetInfo.minDeposit;
    console.log(`Vault minimum WETH: ${ethers.formatUnits(minDeposit, 18)} WETH`);
    
    if (depositAmount < minDeposit) {
        console.log(`Deposit amount below vault minimum of ${ethers.formatUnits(minDeposit, 18)} WETH`);
        return;
    }
    
    // Check current vault shares
    const sharesBefore = await vault.balanceOf(deployer.address);
    const userWETHBefore = await vault.getUserAssetBalance(deployer.address, WETH_ADDRESS);
    console.log(`Current vault shares: ${ethers.formatUnits(sharesBefore, 18)}`);
    console.log(`Current WETH in vault: ${ethers.formatUnits(userWETHBefore, 18)} WETH`);
    
    // Approve exactly 0.01 WETH to vault
    console.log("Approving 0.01 WETH...");
    const approveTx = await weth.approve(VAULT_ADDRESS, depositAmount);
    await approveTx.wait();
    console.log("0.01 WETH approved");
    
    // Deposit exactly 0.01 WETH
    console.log("Depositing 0.01 WETH...");
    try {
        const depositTx = await vault.deposit(WETH_ADDRESS, depositAmount, deployer.address);
        const receipt = await depositTx.wait();
        
        console.log(`Deposit successful! Hash: ${receipt.hash}`);
        console.log(`Gas used: ${receipt.gasUsed.toString()}`);
        
        // Check results
        const balanceAfter = await weth.balanceOf(deployer.address);
        const sharesAfter = await vault.balanceOf(deployer.address);
        const userWETHAfter = await vault.getUserAssetBalance(deployer.address, WETH_ADDRESS);
        const sharesReceived = sharesAfter - sharesBefore;
        
        console.log("\nDeposit Results:");
        console.log(`WETH deposited: 0.01 WETH`);
        console.log(`WETH remaining: ${ethers.formatUnits(balanceAfter, 18)} WETH`);
        console.log(`Shares received: ${ethers.formatUnits(sharesReceived, 18)}`);
        console.log(`Total shares: ${ethers.formatUnits(sharesAfter, 18)}`);
        console.log(`WETH in vault: ${ethers.formatUnits(userWETHAfter, 18)} WETH`);
        
        // Show vault metrics
        const vaultMetrics = await vault.getVaultMetrics();
        console.log(`Vault TVL: $${ethers.formatUnits(vaultMetrics[0], 6)}`);
        
    } catch (error) {
        console.log(`Deposit failed: ${error.message}`);
    }
}

main().catch(console.error);