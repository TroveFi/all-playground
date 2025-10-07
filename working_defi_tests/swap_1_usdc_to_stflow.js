const { ethers } = require("hardhat");

async function main() {
    console.log("Testing 1 USDC → stFLOW Swap with Rate Verification");
    
    const [deployer] = await ethers.getSigners();
    
    // Contract addresses
    const VAULT_ADDRESS = "0x048cb56B7741a3f8740E74204F8C76E68397C512";
    const USDC_ADDRESS = "0xF1815bd50389c46847f0Bda824eC8da914045D14"; // stgUSDC
    const STFLOW_ADDRESS = "0x5598c0652B899EB40f169Dd5949BdBE0BF36ffDe"; // Increment Staked FLOW
    const PUNCH_SWAP_ROUTER = "0xf45AFe28fd5519d5f8C1d4787a4D5f724C0eFa4d";
    
    const vault = await ethers.getContractAt("CoreFlowYieldVault", VAULT_ADDRESS);
    const usdc = await ethers.getContractAt("IERC20", USDC_ADDRESS);
    const stflow = await ethers.getContractAt("IERC20", STFLOW_ADDRESS);
    const router = await ethers.getContractAt("contracts/components/MultiAssetManager.sol:IPunchSwapRouter", PUNCH_SWAP_ROUTER);
    
    const swapAmount = ethers.parseUnits("1", 6); // 1 USDC
    
    console.log("=".repeat(60));
    console.log("PRE-SWAP ANALYSIS - USDC to stFLOW");
    console.log("=".repeat(60));
    
    // Check current balances
    const vaultUSDC = await usdc.balanceOf(VAULT_ADDRESS);
    const vaultStFLOW = await stflow.balanceOf(VAULT_ADDRESS);
    
    console.log(`Vault USDC: ${ethers.formatUnits(vaultUSDC, 6)} USDC`);
    console.log(`Vault stFLOW: ${ethers.formatUnits(vaultStFLOW, 18)} stFLOW`);
    
    if (vaultUSDC < swapAmount) {
        console.log("❌ Insufficient USDC in vault");
        return;
    }
    
    // Get current stFLOW price from PunchSwap
    console.log("\n📊 CURRENT EXCHANGE RATES (USDC → stFLOW):");
    
    const testAmounts = [
        ethers.parseUnits("0.1", 6),
        ethers.parseUnits("1", 6),
        ethers.parseUnits("5", 6),
        ethers.parseUnits("10", 6)
    ];
    
    const path = [USDC_ADDRESS, STFLOW_ADDRESS];
    
    for (const testAmount of testAmounts) {
        try {
            const amountsOut = await router.getAmountsOut(testAmount, path);
            const stflowOut = amountsOut[1];
            const rate = Number(testAmount) / Number(stflowOut) * 1e12; // USDC per stFLOW
            const stflowRate = Number(stflowOut) / Number(testAmount) * 1e12; // stFLOW per USDC
            
            console.log(`${ethers.formatUnits(testAmount, 6)} USDC → ${ethers.formatUnits(stflowOut, 18)} stFLOW`);
            console.log(`  Rate: ${rate.toFixed(4)} USDC per stFLOW`);
            console.log(`  Rate: ${stflowRate.toFixed(6)} stFLOW per USDC`);
            console.log("");
        } catch (error) {
            console.log(`Failed to get rate for ${ethers.formatUnits(testAmount, 6)} USDC: ${error.message}`);
        }
    }
    
    // Alternative path: USDC → WFLOW → stFLOW
    console.log("📊 ALTERNATIVE PATH (USDC → WFLOW → stFLOW):");
    const WFLOW_ADDRESS = "0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e";
    const alternatePath = [USDC_ADDRESS, WFLOW_ADDRESS, STFLOW_ADDRESS];
    
    try {
        const alternateAmounts = await router.getAmountsOut(swapAmount, alternatePath);
        const altStflowOut = alternateAmounts[2];
        const altRate = Number(swapAmount) / Number(altStflowOut) * 1e12;
        
        console.log(`1 USDC → WFLOW → ${ethers.formatUnits(altStflowOut, 18)} stFLOW`);
        console.log(`Alternative rate: ${altRate.toFixed(4)} USDC per stFLOW`);
    } catch (error) {
        console.log("Alternative path not available");
    }
    
    // Get best quote
    console.log("\n💱 SWAP QUOTE FOR 1 USDC:");
    
    let bestPath = path;
    let bestOutput = 0n;
    
    try {
        const directAmounts = await router.getAmountsOut(swapAmount, path);
        const directOutput = directAmounts[1];
        bestOutput = directOutput;
        
        console.log(`Direct path output: ${ethers.formatUnits(directOutput, 18)} stFLOW`);
        
        // Try alternative path
        try {
            const altAmounts = await router.getAmountsOut(swapAmount, alternatePath);
            const altOutput = altAmounts[2];
            
            console.log(`Alternative path output: ${ethers.formatUnits(altOutput, 18)} stFLOW`);
            
            if (altOutput > directOutput) {
                bestPath = alternatePath;
                bestOutput = altOutput;
                console.log("✅ Alternative path offers better rate!");
            } else {
                console.log("✅ Direct path is better");
            }
        } catch (altError) {
            console.log("Alternative path failed, using direct");
        }
        
        const rate = Number(swapAmount) / Number(bestOutput) * 1e12;
        console.log(`Best rate: ${rate.toFixed(4)} USDC per stFLOW`);
        console.log(`Implied stFLOW price: $${rate.toFixed(4)} USD`);
        
        // stFLOW should be slightly more valuable than FLOW due to staking rewards
        if (rate > 3.5 || rate < 1.5) {
            console.log("⚠️  WARNING: Rate seems unusual for stFLOW!");
        }
        
    } catch (error) {
        console.log(`❌ Failed to get swap quote: ${error.message}`);
        return;
    }
    
    console.log("\n" + "=".repeat(60));
    console.log("EXECUTING SWAP");
    console.log("=".repeat(60));
    
    // Execute swap
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
        
        const minOutput = (bestOutput * 98n) / 100n; // 2% slippage
        
        const approveTx = await usdc.approve(PUNCH_SWAP_ROUTER, swapAmount);
        await approveTx.wait();
        console.log("USDC approved for swap");
        
        const balanceBefore = await stflow.balanceOf(deployer.address);
        
        const swapTx = await router.swapExactTokensForTokens(
            swapAmount,
            minOutput,
            bestPath,
            deployer.address,
            Math.floor(Date.now() / 1000) + 300
        );
        const receipt = await swapTx.wait();
        console.log(`✅ Swap executed! Gas used: ${receipt.gasUsed.toString()}`);
        
        const balanceAfter = await stflow.balanceOf(deployer.address);
        const actualStFLOW = balanceAfter - balanceBefore;
        
        // Transfer stFLOW back to vault
        const transferTx = await stflow.transfer(VAULT_ADDRESS, actualStFLOW);
        await transferTx.wait();
        console.log("✅ stFLOW transferred back to vault");
        
        // Deactivate emergency mode
        const deactivateTx = await vault.setEmergencyMode(false);
        await deactivateTx.wait();
        console.log("Emergency mode deactivated");
        
        console.log("\n" + "=".repeat(60));
        console.log("SWAP RESULTS");
        console.log("=".repeat(60));
        
        const actualRate = Number(swapAmount) / Number(actualStFLOW) * 1e12;
        const slippage = (Number(bestOutput) - Number(actualStFLOW)) / Number(bestOutput) * 100;
        
        console.log(`Input: ${ethers.formatUnits(swapAmount, 6)} USDC`);
        console.log(`Output: ${ethers.formatUnits(actualStFLOW, 18)} stFLOW`);
        console.log(`Expected: ${ethers.formatUnits(bestOutput, 18)} stFLOW`);
        console.log(`Actual rate: ${actualRate.toFixed(4)} USDC per stFLOW`);
        console.log(`Slippage: ${slippage.toFixed(2)}%`);
        console.log(`Implied stFLOW price: $${actualRate.toFixed(4)} USD`);
        console.log(`Path used: ${bestPath.length === 2 ? 'Direct' : 'Via WFLOW'}`);
        
        // Final vault balances
        const finalVaultUSDC = await usdc.balanceOf(VAULT_ADDRESS);
        const finalVaultStFLOW = await stflow.balanceOf(VAULT_ADDRESS);
        
        console.log("\n📊 FINAL VAULT BALANCES:");
        console.log(`USDC: ${ethers.formatUnits(finalVaultUSDC, 6)} USDC`);
        console.log(`stFLOW: ${ethers.formatUnits(finalVaultStFLOW, 18)} stFLOW`);
        
        console.log("\n📈 RATE ANALYSIS:");
        console.log(`stFLOW represents staked FLOW with rewards`);
        console.log(`Expected premium over regular FLOW: 5-15%`);
        if (actualRate > 1.5 && actualRate < 3.5) {
            console.log("✅ Rate within reasonable range for stFLOW");
        } else {
            console.log("⚠️  Rate outside expected range");
        }
        
    } catch (error) {
        console.log(`❌ Swap failed: ${error.message}`);
    }
}

main().catch(console.error);