const { ethers } = require("hardhat");
const fs = require("fs");

async function main() {
    console.log("FIX VAULT TRACKING PROPERLY\n");
    
    const [agent] = await ethers.getSigners();
    const deploymentInfo = JSON.parse(fs.readFileSync("deployment-info.json", "utf8"));
    
    const vault = await ethers.getContractAt("TrueMultiAssetVaultCore", deploymentInfo.contracts.vaultCore);
    const moreStrategy = await ethers.getContractAt("MOREMarketsStrategy", deploymentInfo.contracts.moreMarkets);
    
    const ANKRFLOW = "0x1b97100eA1D7126C4d60027e231EA4CB25314bdb";
    const WFLOW = "0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e";
    
    const ankrToken = await ethers.getContractAt("IERC20", ANKRFLOW);
    
    // Step 1: Get ankrFLOW from agent's wallet back to agent
    const agentBal = await ankrToken.balanceOf(agent.address);
    console.log(`Agent has: ${ethers.formatEther(agentBal)} ankrFLOW\n`);
    
    if (agentBal === 0n) {
        console.log("Agent has no ankrFLOW - checking vault...");
        const vaultBal = await ankrToken.balanceOf(deploymentInfo.contracts.vaultCore);
        console.log(`Vault contract has: ${ethers.formatEther(vaultBal)} ankrFLOW`);
        
        if (vaultBal > 0) {
            console.log("\nWithdrawing from vault to agent...");
            const emergencyOn = await vault.setEmergencyMode(true);
            await emergencyOn.wait();
            
            const withdrawTx = await vault.emergencyWithdraw(ANKRFLOW, vaultBal);
            await withdrawTx.wait();
            
            const emergencyOff = await vault.setEmergencyMode(false);
            await emergencyOff.wait();
            
            console.log("✅ Withdrawn to agent\n");
        }
    }
    
    const finalAgentBal = await ankrToken.balanceOf(agent.address);
    console.log(`Agent now has: ${ethers.formatEther(finalAgentBal)} ankrFLOW\n`);
    
    if (finalAgentBal < ethers.parseEther("0.5")) {
        console.log("Not enough ankrFLOW");
        return;
    }
    
    // Step 2: Deposit ankrFLOW to vault PROPERLY so it's tracked
    const depositAmount = ethers.parseEther("1.0");
    
    console.log("Enabling deposits...");
    const enableTx = await vault.toggleDeposits(true);
    await enableTx.wait();
    console.log("✅ Deposits enabled\n");
    
    console.log(`Step 1: Depositing ${ethers.formatEther(depositAmount)} ankrFLOW to vault (with tracking)...\n`);
    
    const approveTx = await ankrToken.approve(deploymentInfo.contracts.vaultCore, depositAmount);
    await approveTx.wait();
    
    const depositTx = await vault.deposit(ANKRFLOW, depositAmount, agent.address);
    await depositTx.wait();
    console.log("✅ Deposited with proper tracking\n");
    
    const [ankrVault, , , ankrTotal] = await vault.getAssetBalance(ANKRFLOW);
    console.log(`Vault now tracks: ${ethers.formatEther(ankrVault)} ankrFLOW\n`);
    
    // Step 3: Now use vault.executeStrategy properly
    const supplyAmount = ethers.parseEther("0.5");
    
    console.log(`Step 2: Supplying ${ethers.formatEther(supplyAmount)} ankrFLOW to MORE...\n`);
    
    const supplyData = ethers.AbiCoder.defaultAbiCoder().encode(["string"], ["supply"]);
    
    const supplyTx = await vault.executeStrategy(
        deploymentInfo.contracts.moreMarkets,
        ANKRFLOW,
        supplyAmount,
        supplyData
    );
    await supplyTx.wait();
    console.log("✅ SUPPLIED TO MORE!\n");
    
    const [supplied, , hf, available] = await moreStrategy.getPositionData(ANKRFLOW);
    
    console.log("MORE Position:");
    console.log(`  Supplied: ${ethers.formatEther(supplied)} ankrFLOW`);
    console.log(`  HF: ${hf === 0n ? "∞" : ethers.formatUnits(hf, 18)}`);
    console.log(`  Can borrow: $${ethers.formatUnits(available, 8)}\n`);
    
    if (available > ethers.parseUnits("0.5", 8)) {
        const borrowCapUSD = Number(ethers.formatUnits(available, 8));
        const borrowAmount = ethers.parseEther((borrowCapUSD * 0.4 / 0.80).toFixed(18));
        
        console.log(`Step 3: Borrowing ${ethers.formatEther(borrowAmount)} WFLOW...\n`);
        
        const borrowTx = await moreStrategy.borrowAsset(WFLOW, borrowAmount);
        await borrowTx.wait();
        console.log("✅ BORROWED!\n");
        
        const [, borrowed2, hf2] = await moreStrategy.getPositionData(ANKRFLOW);
        console.log(`Final borrowed: ${ethers.formatEther(borrowed2)} WFLOW`);
        console.log(`Final HF: ${ethers.formatUnits(hf2, 18)}\n`);
        
        console.log("✅✅✅ EVERYTHING WORKS NOW - PROPERLY NON-CUSTODIAL!");
    }
}

main().catch(console.error);