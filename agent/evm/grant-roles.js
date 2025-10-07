const { ethers } = require("hardhat");
const fs = require("fs");

async function main() {
    console.log("╔════════════════════════════════════════════════════════════╗");
    console.log("║           GRANTING ROLES FOR VAULT SYSTEM                 ║");
    console.log("╚════════════════════════════════════════════════════════════╝\n");
    
    const [deployer] = await ethers.getSigners();
    console.log(`Granting roles from: ${deployer.address}\n`);
    
    // Load deployment info
    const deploymentInfo = JSON.parse(fs.readFileSync("deployment-info.json", "utf8"));
    
    const vaultAddress = deploymentInfo.contracts.vaultCore;
    const strategies = {
        ankrStaking: deploymentInfo.contracts.ankrStaking,
        moreMarkets: deploymentInfo.contracts.moreMarkets,
        ankrLooping: deploymentInfo.contracts.ankrLooping,
        swapStrategy: deploymentInfo.contracts.swapStrategy
    };
    
    console.log(`Vault Address: ${vaultAddress}\n`);
    
    const AGENT_ROLE = ethers.keccak256(ethers.toUtf8Bytes("AGENT_ROLE"));
    
    // ================================================================
    // Grant AGENT_ROLE to Vault on all Strategy Contracts
    // ================================================================
    console.log("📍 Granting AGENT_ROLE to Vault on Strategy Contracts");
    console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
    
    for (const [name, address] of Object.entries(strategies)) {
        console.log(`Processing ${name}...`);
        console.log(`  Strategy: ${address}`);
        
        const strategy = await ethers.getContractAt("AnkrStakingStrategy", address);
        
        // Check if vault already has role
        const hasRole = await strategy.hasRole(AGENT_ROLE, vaultAddress);
        
        if (hasRole) {
            console.log(`  ✓ Vault already has AGENT_ROLE\n`);
            continue;
        }
        
        // Grant role
        console.log(`  → Granting AGENT_ROLE to vault...`);
        const tx = await strategy.grantRole(AGENT_ROLE, vaultAddress);
        await tx.wait();
        console.log(`  ✅ AGENT_ROLE granted! Tx: ${tx.hash}\n`);
    }
    
    // ================================================================
    // Verify Roles
    // ================================================================
    console.log("📍 Verifying All Roles");
    console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
    
    let allCorrect = true;
    
    for (const [name, address] of Object.entries(strategies)) {
        const strategy = await ethers.getContractAt("AnkrStakingStrategy", address);
        const hasRole = await strategy.hasRole(AGENT_ROLE, vaultAddress);
        
        const status = hasRole ? "✅" : "❌";
        console.log(`${status} ${name}: Vault has AGENT_ROLE = ${hasRole}`);
        
        if (!hasRole) allCorrect = false;
    }
    
    console.log("\n");
    
    if (allCorrect) {
        console.log("╔════════════════════════════════════════════════════════════╗");
        console.log("║              ALL ROLES CONFIGURED ✅                       ║");
        console.log("╚════════════════════════════════════════════════════════════╝\n");
        
        console.log("🎉 Your vault can now:");
        console.log("  ✓ Execute strategies");
        console.log("  ✓ Harvest yields");
        console.log("  ✓ Emergency exit strategies\n");
        
        console.log("🧪 Test with:");
        console.log("  npx hardhat run scripts/test-ankr-strategy.js --network flow_mainnet\n");
    } else {
        console.log("❌ Some roles are missing. Please run this script again.\n");
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });