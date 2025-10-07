const { ethers } = require("hardhat");

async function main() {
    console.log("Testing 1 USDC → WFLOW Swap with Rate Verification");
    
    const [deployer] = await ethers.getSigners();
    
    // Contract addresses
    const VAULT_ADDRESS = "0x048cb56B7741a3f8740E74204F8C76E68397C512";
    const USDC_ADDRESS = "0xF1815bd50389c46847f0Bda824eC8da914045D14"; // stgUSDC
    const WFLOW_ADDRESS = "0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e"; // WFLOW
    const PUNCH_SWAP_ROUTER = "0xf45AFe28fd5519d5f8C1d4787a4D5f724C0eFa4d";
    
    const vault = await ethers.getContractAt("CoreFlowYieldVault", VAULT_ADDRESS);
    const usdc = await ethers.getContractAt("IERC20", USDC_ADDRESS);
    const wflow = await ethers.getContractAt("IERC20", WFLOW_ADDRESS);
    const router = await ethers.getContractAt("contracts/components/MultiAssetManager.sol:IPunchSwapRouter", PUNCH_SWAP_ROUTER);
    
    const swapAmount = ethers.parseUnits("1", 6); // 1 USDC
    
    console.log("=".repeat(60));
    console.log("PRE-SWAP ANALYSIS");
    console.log("=".repeat(60));
    
    // Check current balances
    const vaultUSDC = await usdc.balanceOf(VAULT_ADDRESS);
    const vaultWFLOW = await wflow.balanceOf(VAULT_ADDRESS);
    
    console.log(`Vault USDC: ${ethers.formatUnits(vaultUSDC, 6)} USDC`);
    console.log(`Vault WFLOW: ${ethers.formatUnits(vaultWFLOW, 18)} WFLOW`);
    
    if (vaultUSDC < swapAmount) {
        console.log("❌ Insufficient USDC in vault");
        return;
    }
    
    // Get current FLOW price from PunchSwap (multiple amounts for verification)
    console.log("\n📊 CURRENT EXCHANGE RATES:");
    
    const testAmounts = [
        ethers.parseUnits("0.1", 6),  // 0.1 USDC
        ethers.parseUnits("1", 6),    // 1 USDC
        ethers.parseUnits("5", 6),    // 5 USDC
        ethers.parseUnits("10", 6)    // 10 USDC
    ];
    
    const path = [USDC_ADDRESS, WFLOW_ADDRESS];
    
    for (const testAmount of testAmounts) {
        try {
            const amountsOut = await router.getAmountsOut(testAmount, path);
            const wflowOut = amountsOut[1];
            const rate = Number(testAmount) / Number(wflowOut) * 1e12; // USDC per WFLOW
            const flowRate = Number(wflowOut) / Number(testAmount) * 1e12; // WFLOW per USDC
            
            console.log(`${ethers.formatUnits(testAmount, 6)} USDC → ${ethers.formatUnits(wflowOut, 18)} WFLOW`);
            console.log(`  Rate: ${rate.toFixed(4)} USDC per WFLOW`);
            console.log(`  Rate: ${flowRate.toFixed(6)} WFLOW per USDC`);
            console.log("");
        } catch (error) {
            console.log(`Failed to get rate for ${ethers.formatUnits(testAmount, 6)} USDC: ${error.message}`);
        }
    }
    
    // Get quote for our swap amount
    console.log("💱 SWAP QUOTE FOR 1 USDC:");
    
    try {
        const amountsOut = await router.getAmountsOut(swapAmount, path);
        const expectedWFLOW = amountsOut[1];
        const rate = Number(swapAmount) / Number(expectedWFLOW) * 1e12;
        const impliedFLOWPrice = rate; // Since 1 USDC = rate USDC per WFLOW
        
        console.log(`Expected output: ${ethers.formatUnits(expectedWFLOW, 18)} WFLOW`);
        console.log(`Exchange rate: ${rate.toFixed(4)} USDC per WFLOW`);
        console.log(`Implied FLOW price: $${impliedFLOWPrice.toFixed(4)} USD`);
        console.log(`Expected FLOW price: ~$2.47 USD`);
        
        if (impliedFLOWPrice > 5 || impliedFLOWPrice < 0.5) {
            console.log("⚠️  WARNING: Rate seems unusual!");
            console.log("This might indicate:");
            console.log("- Low liquidity in USDC/WFLOW pool");
            console.log("- WFLOW is not 1:1 with native FLOW");
            console.log("- Wrong token contract address");
            console.log("- Pool imbalance or arbitrage opportunity");
        }
        
    } catch (error) {
        console.log(`❌ Failed to get swap quote: ${error.message}`);
        return;
    }
    
    console.log("\n" + "=".repeat(60));
    console.log("EXECUTING SWAP");
    console.log("=".repeat(60));
    
    // Emergency withdraw 1 USDC from vault
    try {
        const EMERGENCY_ROLE = await vault.EMERGENCY_ROLE();
        const hasRole = await vault.hasRole(EMERGENCY_ROLE, deployer.address);
        
        if (!hasRole) {
            const grantTx = await vault.grantRole(EMERGENCY_ROLE, deployer.address);
            await grantTx.wait();
            console.log("Emergency role granted");
        }
        
        const emergencyMode = await vault.emergencyMode();
        if (!emergencyMode) {
            const emergencyTx = await vault.setEmergencyMode(true);
            await emergencyTx.wait();
            console.log("Emergency mode activated");
        }
        
        const withdrawTx = await vault.emergencyWithdraw(USDC_ADDRESS, swapAmount);
        await withdrawTx.wait();
        console.log("✅ 1 USDC extracted from vault");
        
        // Execute swap
        const amountsOut = await router.getAmountsOut(swapAmount, path);
        const expectedWFLOW = amountsOut[1];
        const minWFLOW = (expectedWFLOW * 98n) / 100n; // 2% slippage
        
        const approveTx = await usdc.approve(PUNCH_SWAP_ROUTER, swapAmount);
        await approveTx.wait();
        console.log("USDC approved for swap");
        
        const balanceBefore = await wflow.balanceOf(deployer.address);
        
        const swapTx = await router.swapExactTokensForTokens(
            swapAmount,
            minWFLOW,
            path,
            deployer.address,
            Math.floor(Date.now() / 1000) + 300
        );
        const receipt = await swapTx.wait();
        console.log(`✅ Swap executed! Gas used: ${receipt.gasUsed.toString()}`);
        
        const balanceAfter = await wflow.balanceOf(deployer.address);
        const actualWFLOW = balanceAfter - balanceBefore;
        
        // Transfer WFLOW back to vault
        const transferTx = await wflow.transfer(VAULT_ADDRESS, actualWFLOW);
        await transferTx.wait();
        console.log("✅ WFLOW transferred back to vault");
        
        // Deactivate emergency mode
        const deactivateTx = await vault.setEmergencyMode(false);
        await deactivateTx.wait();
        console.log("Emergency mode deactivated");
        
        console.log("\n" + "=".repeat(60));
        console.log("SWAP RESULTS");
        console.log("=".repeat(60));
        
        const actualRate = Number(swapAmount) / Number(actualWFLOW) * 1e12;
        const slippage = (Number(expectedWFLOW) - Number(actualWFLOW)) / Number(expectedWFLOW) * 100;
        
        console.log(`Input: ${ethers.formatUnits(swapAmount, 6)} USDC`);
        console.log(`Output: ${ethers.formatUnits(actualWFLOW, 18)} WFLOW`);
        console.log(`Expected: ${ethers.formatUnits(expectedWFLOW, 18)} WFLOW`);
        console.log(`Actual rate: ${actualRate.toFixed(4)} USDC per WFLOW`);
        console.log(`Slippage: ${slippage.toFixed(2)}%`);
        console.log(`Implied FLOW price: $${actualRate.toFixed(4)} USD`);
        
        // Final vault balances
        const finalVaultUSDC = await usdc.balanceOf(VAULT_ADDRESS);
        const finalVaultWFLOW = await wflow.balanceOf(VAULT_ADDRESS);
        
        console.log("\n📊 FINAL VAULT BALANCES:");
        console.log(`USDC: ${ethers.formatUnits(finalVaultUSDC, 6)} USDC`);
        console.log(`WFLOW: ${ethers.formatUnits(finalVaultWFLOW, 18)} WFLOW`);
        
        // Rate analysis
        console.log("\n📈 RATE ANALYSIS:");
        if (actualRate < 1) {
            console.log("✅ Rate suggests WFLOW > USDC (expected for FLOW)");
        } else if (actualRate > 5) {
            console.log("⚠️  Rate suggests WFLOW << USDC (unusual)");
        } else {
            console.log("📊 Rate within reasonable range");
        }
        
    } catch (error) {
        console.log(`❌ Swap failed: ${error.message}`);
    }
}

main().catch(console.error);