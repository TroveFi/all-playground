const { ethers } = require("hardhat");
const fs = require("fs");

async function main() {
    console.log("MORE Markets Test - FINAL FIX\n");
    
    const [agent] = await ethers.getSigners();
    const deploymentInfo = JSON.parse(fs.readFileSync("deployment-info.json", "utf8"));
    
    const vault = await ethers.getContractAt("TrueMultiAssetVaultCore", deploymentInfo.contracts.vaultCore);
    const moreStrategy = await ethers.getContractAt("MOREMarketsStrategy", deploymentInfo.contracts.moreMarkets);
    
    const WFLOW = "0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e";
    const ANKRFLOW = "0x1b97100eA1D7126C4d60027e231EA4CB25314bdb";
    
    const [flowVault] = await vault.getAssetBalance("0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE");
    console.log(`Vault FLOW: ${ethers.formatEther(flowVault)}\n`);
    
    if (flowVault < ethers.parseEther("0.3")) {
        console.log("Need 0.3 FLOW");
        return;
    }
    
    const supplyAmount = ethers.parseEther("0.3");
    
    // Step 1: Agent wraps FLOW to WFLOW
    console.log("Step 1: Wrapping FLOW → WFLOW...");
    const wflowInterface = new ethers.Interface(["function deposit() external payable"]);
    const depositData = wflowInterface.encodeFunctionData("deposit", []);
    const wrapTx = await agent.sendTransaction({
        to: WFLOW,
        value: supplyAmount,
        data: depositData
    });
    await wrapTx.wait();
    console.log("✅ Wrapped\n");
    
    // Step 2: Deposit WFLOW to vault
    console.log("Step 2: Depositing WFLOW to vault...");
    const wflowToken = await ethers.getContractAt("IERC20", WFLOW);
    const approveTx = await wflowToken.approve(deploymentInfo.contracts.vaultCore, supplyAmount);
    await approveTx.wait();
    
    const depositTx = await vault.deposit(WFLOW, supplyAmount, agent.address);
    await depositTx.wait();
    console.log("✅ Deposited\n");
    
    // Step 3: Supply WFLOW to MORE
    console.log("Step 3: Supplying WFLOW to MORE Markets...");
    
    const supplyData = ethers.AbiCoder.defaultAbiCoder().encode(["string"], ["supply"]);
    
    const supplyTx = await vault.executeStrategy(
        deploymentInfo.contracts.moreMarkets,
        WFLOW,
        supplyAmount,
        supplyData
    );
    
    await supplyTx.wait();
    console.log("✅ SUPPLIED TO MORE!\n");
    
    const [supplied, , hf, available] = await moreStrategy.getPositionData(WFLOW);
    console.log("MORE Position:");
    console.log(`  Supplied: ${ethers.formatEther(supplied)} WFLOW`);
    console.log(`  HF: ${hf === 0n ? "∞" : ethers.formatUnits(hf, 18)}`);
    console.log(`  Can borrow: $${ethers.formatUnits(available, 8)}\n`);
    
    // Step 4: Borrow if possible
    if (available > ethers.parseUnits("1", 8)) { // Need at least $1 to borrow
        const borrowCapUSD = Number(ethers.formatUnits(available, 8));
        const borrowAmount = ethers.parseEther((borrowCapUSD * 0.5 / 0.80).toFixed(18)); // 50% of capacity
        
        console.log(`Step 4: Borrowing ${ethers.formatEther(borrowAmount)} WFLOW...`);
        
        const borrowTx = await moreStrategy.borrowAsset(WFLOW, borrowAmount);
        await borrowTx.wait();
        console.log("✅ BORROWED!\n");
        
        const finalHF = await moreStrategy.getHealthFactor();
        console.log(`Final HF: ${ethers.formatUnits(finalHF, 18)}\n`);
    } else {
        console.log(`\nBorrow capacity too small (${ethers.formatUnits(available, 8)})`);
        console.log("Supply more WFLOW to borrow meaningful amounts\n");
    }
}

main().catch(console.error);