const { ethers } = require("hardhat");

async function main() {
    console.log("Disabling Risk Manager and Depositing FLOW");
    console.log("==========================================");
    
    const [deployer] = await ethers.getSigners();
    
    // Contract addresses
    const VAULT_ADDRESS = "0xF670C5F28cFA8fd7Ed16AaE81aA9AF2b304F0b4B";
    const NATIVE_FLOW = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";
    const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
    
    const vault = await ethers.getContractAt("TrueMultiAssetVault", VAULT_ADDRESS);
    
    // Deposit amount
    const depositAmount = ethers.parseUnits("1", 18);
    
    try {
        console.log("Step 1: Checking current risk manager...");
        const currentRiskManager = await vault.riskManager();
        console.log(`Current risk manager: ${currentRiskManager}`);
        
        if (currentRiskManager !== ZERO_ADDRESS) {
            console.log("\nStep 2: Disabling risk manager...");
            
            // Set risk manager to zero address to disable it
            const setRiskManagerTx = await vault.setRiskManager(ZERO_ADDRESS);
            console.log(`Setting risk manager to zero address: ${setRiskManagerTx.hash}`);
            await setRiskManagerTx.wait();
            console.log("Risk manager disabled!");
            
            // Verify it's disabled
            const newRiskManager = await vault.riskManager();
            console.log(`New risk manager: ${newRiskManager}`);
        } else {
            console.log("Risk manager is already disabled");
        }
        
        console.log("\nStep 3: Depositing native FLOW...");
        
        // Check our balance
        const balance = await deployer.provider.getBalance(deployer.address);
        console.log(`Your FLOW balance: ${ethers.formatEther(balance)} FLOW`);
        
        if (balance < depositAmount + ethers.parseUnits("0.1", 18)) {
            throw new Error("Insufficient FLOW balance for deposit + gas");
        }
        
        // Check shares before
        const sharesBefore = await vault.balanceOf(deployer.address);
        console.log(`Vault shares before: ${ethers.formatUnits(sharesBefore, 18)}`);
        
        // Execute deposit
        console.log(`Depositing ${ethers.formatEther(depositAmount)} FLOW...`);
        const depositTx = await vault.depositNativeFlow(deployer.address, {
            value: depositAmount,
            gasLimit: 500000
        });
        
        console.log(`Deposit transaction: ${depositTx.hash}`);
        console.log("Waiting for confirmation...");
        
        const receipt = await depositTx.wait();
        console.log(`Transaction confirmed in block ${receipt.blockNumber}`);
        console.log(`Gas used: ${receipt.gasUsed.toString()}`);
        
        // Check results
        const sharesAfter = await vault.balanceOf(deployer.address);
        const sharesReceived = sharesAfter - sharesBefore;
        
        console.log("\nDeposit Results:");
        console.log(`FLOW deposited: ${ethers.formatEther(depositAmount)} FLOW`);
        console.log(`Shares received: ${ethers.formatUnits(sharesReceived, 18)}`);
        console.log(`Total shares: ${ethers.formatUnits(sharesAfter, 18)}`);
        
        // Check vault state
        const assetBalance = await vault.getAssetBalance(NATIVE_FLOW);
        console.log(`Vault native FLOW balance: ${ethers.formatEther(assetBalance[0])} FLOW`);
        
        // Check vault metrics
        const vaultMetrics = await vault.getVaultMetrics();
        console.log(`Vault TVL: $${ethers.formatUnits(vaultMetrics[0], 6)}`);
        console.log(`Total users: ${vaultMetrics[1].toString()}`);
        
        console.log("\nSuccess! Your 1 FLOW has been deposited to the vault.");
        console.log("You can now deploy this to strategies or keep it in the vault.");
        
        console.log("\nNext steps:");
        console.log("1. Deploy to Ankr strategy:");
        console.log("   npx hardhat run scripts/deploy-to-ankr.js --network flow_mainnet");
        console.log("2. Check your balance:");
        console.log(`   await vault.getUserAssetBalance("${deployer.address}", "${NATIVE_FLOW}")`);
        
    } catch (error) {
        console.error("\nOperation failed:");
        console.error(error.message);
        
        if (error.message.includes("AccessControl")) {
            console.log("\nIssue: You don't have admin rights to disable risk manager");
            console.log("Solution: Use the admin account that deployed the vault");
        } else if (error.message.includes("Risk limits exceeded")) {
            console.log("\nIssue: Risk manager is still active");
            console.log("Solution: Make sure risk manager is properly disabled");
        }
    }
}

main().catch(console.error);