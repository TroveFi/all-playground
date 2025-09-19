const { ethers } = require("hardhat");

async function main() {
    console.log("Disabling Risk Manager on New Core Vault");
    console.log("========================================");
    
    const [deployer] = await ethers.getSigners();
    
    // NEW CONTRACT ADDRESSES from your deployment
    const CORE_VAULT_ADDRESS = "0xbD82c706e3632972A00E288a54Ea50c958b865b2";
    const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
    
    const coreVault = await ethers.getContractAt("TrueMultiAssetVaultCore", CORE_VAULT_ADDRESS);
    
    try {
        console.log("Step 1: Checking current risk manager...");
        const currentRiskManager = await coreVault.riskManager();
        console.log(`Current risk manager: ${currentRiskManager}`);
        
        if (currentRiskManager !== ZERO_ADDRESS) {
            console.log("\nStep 2: Disabling risk manager...");
            
            // Set risk manager to zero address to disable it
            const setRiskManagerTx = await coreVault.setRiskManager(ZERO_ADDRESS);
            console.log(`Setting risk manager to zero address: ${setRiskManagerTx.hash}`);
            await setRiskManagerTx.wait();
            console.log("✅ Risk manager disabled!");
            
            // Verify it's disabled
            const newRiskManager = await coreVault.riskManager();
            console.log(`New risk manager: ${newRiskManager}`);
        } else {
            console.log("✅ Risk manager is already disabled");
        }
        
        console.log("\nStep 3: Verifying vault status...");
        
        // Check vault status
        const depositsEnabled = await coreVault.depositsEnabled();
        const emergencyMode = await coreVault.emergencyMode();
        
        console.log(`Deposits enabled: ${depositsEnabled}`);
        console.log(`Emergency mode: ${emergencyMode}`);
        
        if (!depositsEnabled) {
            console.log("\n🔧 Enabling deposits...");
            const enableTx = await coreVault.toggleDeposits(true);
            await enableTx.wait();
            console.log("✅ Deposits enabled!");
        }
        
        if (emergencyMode) {
            console.log("\n🔧 Disabling emergency mode...");
            const emergencyTx = await coreVault.setEmergencyMode(false);
            await emergencyTx.wait();
            console.log("✅ Emergency mode disabled!");
        }
        
        console.log("\n🎉 SUCCESS: Risk manager disabled and vault ready for deposits!");
        console.log("\nNext step: Run the deposit script to add FLOW to your vault");
        
    } catch (error) {
        console.error("\nOperation failed:");
        console.error(error.message);
        
        if (error.message.includes("AccessControl")) {
            console.log("\n💡 ISSUE: You don't have admin rights");
            console.log("SOLUTION: Use the admin account that deployed the vault");
            console.log(`Your address: ${deployer.address}`);
        } else if (error.message.includes("Ownable")) {
            console.log("\n💡 ISSUE: Only owner can modify settings");
            console.log("SOLUTION: Use the owner account");
        }
    }
}

main().catch(console.error);