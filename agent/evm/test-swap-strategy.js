const { ethers } = require("hardhat");
const fs = require("fs");

async function main() {
    console.log("Swap Test - FINAL FIX\n");
    
    const [agent] = await ethers.getSigners();
    const deploymentInfo = JSON.parse(fs.readFileSync("deployment-info.json", "utf8"));
    
    const vault = await ethers.getContractAt("TrueMultiAssetVaultCore", deploymentInfo.contracts.vaultCore);
    const swapStrategy = await ethers.getContractAt("SwapStrategy", deploymentInfo.contracts.swapStrategy);
    
    const WFLOW = "0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e";
    const ANKRFLOW = "0x1b97100eA1D7126C4d60027e231EA4CB25314bdb";
    
    const [flowVault] = await vault.getAssetBalance("0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE");
    console.log(`Vault FLOW: ${ethers.formatEther(flowVault)}\n`);
    
    if (flowVault < ethers.parseEther("0.2")) {
        console.log("Need 0.2 FLOW");
        return;
    }
    
    const swapAmount = ethers.parseEther("0.2");
    
    // Step 1: Agent wraps their own FLOW to WFLOW
    console.log("Step 1: Wrapping FLOW → WFLOW (agent's funds)...");
    const wflowInterface = new ethers.Interface([
        "function deposit() external payable"
    ]);
    const depositData = wflowInterface.encodeFunctionData("deposit", []);
    const wrapTx = await agent.sendTransaction({
        to: WFLOW,
        value: swapAmount,
        data: depositData
    });
    await wrapTx.wait();
    console.log("✅ Wrapped\n");
    
    // Step 2: Agent deposits WFLOW to vault
    console.log("Step 2: Depositing WFLOW to vault...");
    const wflowToken = await ethers.getContractAt("IERC20", WFLOW);
    const approveTx = await wflowToken.approve(deploymentInfo.contracts.vaultCore, swapAmount);
    await approveTx.wait();
    
    const depositTx = await vault.deposit(WFLOW, swapAmount, agent.address);
    await depositTx.wait();
    console.log("✅ Deposited to vault\n");
    
    // Step 3: Now vault has WFLOW, execute swap
    console.log("Step 3: Executing swap WFLOW → ankrFLOW...");
    
    const [expectedOut, path] = await swapStrategy.getSwapQuote(WFLOW, ANKRFLOW, swapAmount);
    const minOut = (expectedOut * 98n) / 100n;
    
    console.log(`Expected: ${ethers.formatEther(expectedOut)} ankrFLOW`);
    console.log(`Min: ${ethers.formatEther(minOut)} ankrFLOW\n`);
    
    const swapData = ethers.AbiCoder.defaultAbiCoder().encode(
        ["address", "uint256", "address[]"],
        [ANKRFLOW, minOut, path]
    );
    
    const tx = await vault.executeStrategy(
        deploymentInfo.contracts.swapStrategy,
        WFLOW,
        swapAmount,
        swapData
    );
    
    await tx.wait();
    console.log("✅ SWAP SUCCESS!\n");
    
    // Harvest - agent calls directly on strategy
    const ankrToken = await ethers.getContractAt("IERC20", ANKRFLOW);
    const stratBal = await ankrToken.balanceOf(deploymentInfo.contracts.swapStrategy);
    console.log(`Strategy has: ${ethers.formatEther(stratBal)} ankrFLOW`);
    
    if (stratBal > 0) {
        console.log("Harvesting...");
        const harvestData = ethers.AbiCoder.defaultAbiCoder().encode(["address"], [ANKRFLOW]);
        const harvestTx = await swapStrategy.harvest(harvestData);
        await harvestTx.wait();
        console.log("✅ Harvested to vault\n");
        
        const [, , , ankrTotal] = await vault.getAssetBalance(ANKRFLOW);
        console.log(`Vault now has: ${ethers.formatEther(ankrTotal)} ankrFLOW total`);
    }
}

main().catch(console.error);