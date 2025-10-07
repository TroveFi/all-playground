const { ethers } = require("hardhat");

async function main() {
    console.log("Swapping 1 USDC to ankrFLOWEVM with Rate Analysis");
    
    const [deployer] = await ethers.getSigners();
    
    // Contract addresses from your table
    const VAULT_ADDRESS = "0x048cb56B7741a3f8740E74204F8C76E68397C512";
    const USDC_ADDRESS = "0xF1815bd50389c46847f0Bda824eC8da914045D14"; // stgUSDC
    const WFLOW_ADDRESS = "0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e"; // WFLOW
    const ANKRFLOW_ADDRESS = "0x1b97100eA1D7126C4d60027e231EA4CB25314bdb"; // ankrFLOWEVM
    const PUNCH_SWAP_ROUTER = "0xf45AFe28fd5519d5f8C1d4787a4D5f724C0eFa4d";
    
    const vault = await ethers.getContractAt("CoreFlowYieldVault", VAULT_ADDRESS);
    const usdc = await ethers.getContractAt("IERC20", USDC_ADDRESS);
    const ankrFlow = await ethers.getContractAt("IERC20", ANKRFLOW_ADDRESS);
    const router = await ethers.getContractAt("contracts/components/MultiAssetManager.sol:IPunchSwapRouter", PUNCH_SWAP_ROUTER);
    
    const swapAmount = ethers.parseUnits("1", 6); // 1 USDC
    
    console.log("\n=== RATE ANALYSIS ===");
    
    // Check multiple swap routes to find the best rate
    const routes = [
        {
            name: "Direct USDC → ankrFLOWEVM",
            path: [USDC_ADDRESS, ANKRFLOW_ADDRESS]
        },
        {
            name: "USDC → WFLOW → ankrFLOWEVM", 
            path: [USDC_ADDRESS, WFLOW_ADDRESS, ANKRFLOW_ADDRESS]
        }
    ];
    
    let bestRoute = null;
    let bestOutput = 0n;
    
    for (const route of routes) {
        try {
            console.log(`\nChecking route: ${route.name}`);
            const amountsOut = await router.getAmountsOut(swapAmount, route.path);
            const finalOutput = amountsOut[amountsOut.length - 1];
            
            console.log(`Input: ${ethers.formatUnits(swapAmount, 6)} USDC`);
            console.log(`Output: ${ethers.formatUnits(finalOutput, 18)} ankrFLOWEVM`);
            
            if (route.path.length === 3) {
                console.log(`Via WFLOW: ${ethers.formatUnits(amountsOut[1], 18)} WFLOW`);
            }
            
            // Calculate rate
            const rate = Number(swapAmount) / Number(finalOutput) * 1e12; // USDC per ankrFLOWEVM
            console.log(`Rate: ${rate.toFixed(4)} USDC per ankrFLOWEVM`);
            console.log(`Rate: ${(1/rate).toFixed(4)} ankrFLOWEVM per USDC`);
            
            if (finalOutput > bestOutput) {
                bestOutput = finalOutput;
                bestRoute = route;
            }
            
        } catch (error) {
            console.log(`Route ${route.name} failed: ${error.message}`);
        }
    }
    
    if (!bestRoute) {
        console.log("No valid routes found for USDC → ankrFLOWEVM");
        return;
    }
    
    console.log(`\nBest route: ${bestRoute.name}`);
    console.log(`Best output: ${ethers.formatUnits(bestOutput, 18)} ankrFLOWEVM`);
    
    // Get current FLOW price reference
    console.log("\n=== FLOW PRICE REFERENCE ===");
    try {
        // Check USDC → WFLOW rate as baseline
        const flowPath = [USDC_ADDRESS, WFLOW_ADDRESS];
        const flowAmounts = await router.getAmountsOut(swapAmount, flowPath);
        const flowReceived = flowAmounts[1];
        
        console.log(`1 USDC → ${ethers.formatUnits(flowReceived, 18)} WFLOW`);
        const flowRate = Number(swapAmount) / Number(flowReceived) * 1e12;
        console.log(`Current FLOW rate: ${flowRate.toFixed(4)} USDC per WFLOW`);
        console.log(`Current FLOW price: $${flowRate.toFixed(4)} USD`);
        
        // Expected vs actual based on your 2.47 FLOW per USD reference
        const expectedFlow = 2.47;
        const actualFlowPerUSD = 1 / flowRate;
        console.log(`Expected: ~${expectedFlow} FLOW per USD`);
        console.log(`Actual: ${actualFlowPerUSD.toFixed(4)} FLOW per USD`);
        
        if (actualFlowPerUSD < expectedFlow * 0.5) {
            console.log("⚠️  WARNING: FLOW rate seems much lower than expected!");
            console.log("This could indicate:");
            console.log("- Low liquidity in USDC/WFLOW pool");
            console.log("- WFLOW ≠ native FLOW price");
            console.log("- Pool imbalance on PunchSwap");
        }
        
    } catch (error) {
        console.log(`FLOW reference check failed: ${error.message}`);
    }
    
    console.log("\n=== EXECUTING SWAP ===");
    
    // Extract USDC from vault
    console.log("Step 1: Extracting 1 USDC from vault...");
    
    try {
        // Grant emergency role if needed
        const EMERGENCY_ROLE = await vault.EMERGENCY_ROLE();
        const hasEmergencyRole = await vault.hasRole(EMERGENCY_ROLE, deployer.address);
        
        if (!hasEmergencyRole) {
            const grantTx = await vault.grantRole(EMERGENCY_ROLE, deployer.address);
            await grantTx.wait();
            console.log("Emergency role granted");
        }
        
        // Activate emergency mode
        const emergencyMode = await vault.emergencyMode();
        if (!emergencyMode) {
            const emergencyTx = await vault.setEmergencyMode(true);
            await emergencyTx.wait();
            console.log("Emergency mode activated");
        }
        
        // Extract USDC
        const withdrawTx = await vault.emergencyWithdraw(USDC_ADDRESS, swapAmount);
        await withdrawTx.wait();
        console.log("1 USDC extracted from vault");
        
        console.log("Step 2: Executing optimal swap...");
        
        // Calculate minimum output with 2% slippage
        const minOutput = (bestOutput * 98n) / 100n;
        
        // Approve router
        const approveTx = await usdc.approve(PUNCH_SWAP_ROUTER, swapAmount);
        await approveTx.wait();
        console.log("USDC approved");
        
        // Execute swap
        console.log(`Swapping via route: ${bestRoute.name}`);
        const swapTx = await router.swapExactTokensForTokens(
            swapAmount,
            minOutput,
            bestRoute.path,
            deployer.address,
            Math.floor(Date.now() / 1000) + 300
        );
        const receipt = await swapTx.wait();
        console.log(`Swap completed! Gas used: ${receipt.gasUsed}`);
        
        console.log("Step 3: Transferring ankrFLOWEVM to vault...");
        
        // Check received ankrFLOWEVM
        const ankrFlowReceived = await ankrFlow.balanceOf(deployer.address);
        console.log(`Received: ${ethers.formatUnits(ankrFlowReceived, 18)} ankrFLOWEVM`);
        
        // Transfer to vault
        const transferTx = await ankrFlow.transfer(VAULT_ADDRESS, ankrFlowReceived);
        await transferTx.wait();
        console.log("ankrFLOWEVM transferred to vault");
        
        console.log("Step 4: Deactivating emergency mode...");
        const deactivateTx = await vault.setEmergencyMode(false);
        await deactivateTx.wait();
        console.log("Emergency mode deactivated");
        
        console.log("\n=== SWAP RESULTS ===");
        
        // Check final vault balances
        const finalUSDC = await usdc.balanceOf(VAULT_ADDRESS);
        const finalAnkrFlow = await ankrFlow.balanceOf(VAULT_ADDRESS);
        
        console.log("Final vault balances:");
        console.log(`USDC: ${ethers.formatUnits(finalUSDC, 6)} USDC`);
        console.log(`ankrFLOWEVM: ${ethers.formatUnits(finalAnkrFlow, 18)} ankrFLOWEVM`);
        
        // Calculate actual conversion rate
        const actualRate = Number(swapAmount) / Number(ankrFlowReceived) * 1e12;
        console.log(`\nActual conversion rate: ${actualRate.toFixed(4)} USDC per ankrFLOWEVM`);
        console.log(`Actual conversion rate: ${(1/actualRate).toFixed(4)} ankrFLOWEVM per USDC`);
        
        // Compare to expected
        const expectedAnkrFlowPerUSD = 2.47; // If ankrFLOW ≈ FLOW
        const actualAnkrFlowPerUSD = 1 / actualRate;
        const efficiency = (actualAnkrFlowPerUSD / expectedAnkrFlowPerUSD) * 100;
        
        console.log(`\nEfficiency Analysis:`);
        console.log(`Expected: ~${expectedAnkrFlowPerUSD} ankrFLOW per USD`);
        console.log(`Actual: ${actualAnkrFlowPerUSD.toFixed(4)} ankrFLOW per USD`);
        console.log(`Efficiency: ${efficiency.toFixed(1)}% of expected rate`);
        
        if (efficiency < 80) {
            console.log("⚠️  Low efficiency detected - consider alternative routes or DEXs");
        } else {
            console.log("✅ Reasonable swap efficiency achieved");
        }
        
    } catch (error) {
        console.log(`Swap failed: ${error.message}`);
    }
}

main().catch(console.error);