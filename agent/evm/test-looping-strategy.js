const { ethers } = require("hardhat");
const fs = require("fs");

async function main() {
    console.log("Testing Ankr-MORE Looping Strategy");
    console.log("==================================\n");
    
    const [agent] = await ethers.getSigners();
    console.log(`Agent: ${agent.address}`);
    
    // Load deployment info
    const deploymentInfo = JSON.parse(fs.readFileSync("deployment-info.json", "utf8"));
    const vaultAddress = deploymentInfo.contracts.vaultCore;
    const loopingStrategyAddress = deploymentInfo.contracts.ankrLooping;
    
    console.log(`Vault: ${vaultAddress}`);
    console.log(`LoopingStrategy: ${loopingStrategyAddress}\n`);
    
    const vault = await ethers.getContractAt("TrueMultiAssetVaultCore", vaultAddress);
    const loopingStrategy = await ethers.getContractAt("AnkrMORELoopingStrategy", loopingStrategyAddress);
    
    const NATIVE_FLOW = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";
    
    console.log("⚠️  WARNING: Looping strategies use leverage and carry liquidation risk!");
    console.log("This test will execute a conservative 1-loop strategy.\n");
    
    try {
        // ================================================================
        // PRE-TEST: Check Vault Balance
        // ================================================================
        console.log("PRE-TEST: Checking vault balance");
        console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        
        const [vaultBalance, strategyBalance, cadenceBalance, totalBalance] = 
            await vault.getAssetBalance(NATIVE_FLOW);
        
        console.log(`Vault FLOW balance: ${ethers.formatEther(vaultBalance)}`);
        console.log(`Strategy balance: ${ethers.formatEther(strategyBalance)}`);
        console.log(`Total balance: ${ethers.formatEther(totalBalance)}\n`);
        
        if (vaultBalance < ethers.parseEther("1")) {
            console.log("❌ Insufficient FLOW. Need at least 1 FLOW for looping test.");
            console.log("Please deposit FLOW first: npx hardhat run scripts/test-deposit.js\n");
            return;
        }
        
        // ================================================================
        // TEST 1: Execute 1-Loop Strategy (Conservative)
        // ================================================================
        console.log("TEST 1: Executing 1-Loop Leveraged Staking");
        console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        
        const initialAmount = ethers.parseEther("1"); // 1 FLOW
        const numLoops = 1; // Conservative - just 1 loop
        
        console.log(`Initial FLOW: ${ethers.formatEther(initialAmount)}`);
        console.log(`Number of loops: ${numLoops}`);
        console.log("Expected leverage: ~1.5x\n");
        
        // Encode loop count
        const loopData = ethers.AbiCoder.defaultAbiCoder().encode(
            ["uint256"],
            [numLoops]
        );
        
        console.log("Executing looping strategy...");
        console.log("This will:");
        console.log("  1. Stake FLOW → ankrFLOW");
        console.log("  2. Supply ankrFLOW to MORE");
        console.log("  3. Borrow WFLOW");
        console.log("  4. Unwrap WFLOW → FLOW");
        console.log("  5. Re-stake FLOW → ankrFLOW\n");
        
        const tx = await vault.executeStrategy(
            loopingStrategyAddress,
            NATIVE_FLOW,
            initialAmount,
            loopData
        );
        
        console.log(`Transaction: ${tx.hash}`);
        const receipt = await tx.wait();
        console.log(`✅ Looping strategy executed! Gas used: ${receipt.gasUsed}\n`);
        
        // ================================================================
        // TEST 2: Check Looping Metrics
        // ================================================================
        console.log("TEST 2: Analyzing Looping Position");
        console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        
        const [
            totalFlowStaked,
            totalAnkrFlowReceived,
            totalFlowBorrowed,
            loopCount,
            leverage,
            healthFactor
        ] = await loopingStrategy.getLoopingMetrics();
        
        console.log("Position Metrics:");
        console.log(`  Total FLOW Staked: ${ethers.formatEther(totalFlowStaked)}`);
        console.log(`  Total ankrFLOW Received: ${ethers.formatEther(totalAnkrFlowReceived)}`);
        console.log(`  Total FLOW Borrowed: ${ethers.formatEther(totalFlowBorrowed)}`);
        console.log(`  Loop Count: ${loopCount}`);
        console.log(`  Effective Leverage: ${ethers.formatUnits(leverage, 18)}x`);
        console.log(`  Health Factor: ${healthFactor === 0n ? "∞" : ethers.formatUnits(healthFactor, 18)}`);
        
        // Risk assessment
        console.log("\nRisk Assessment:");
        if (healthFactor === 0n) {
            console.log("  ✅ No debt position (shouldn't happen with looping)");
        } else if (healthFactor < ethers.parseUnits("1.2", 18)) {
            console.log("  🚨 CRITICAL: Health factor < 1.2 - HIGH liquidation risk!");
            console.log("     Action required: Unwind position or add collateral");
        } else if (healthFactor < ethers.parseUnits("1.5", 18)) {
            console.log("  ⚠️  WARNING: Health factor < 1.5 - Moderate risk");
            console.log("     Monitor closely, consider unwinding if market moves unfavorably");
        } else if (healthFactor < ethers.parseUnits("2", 18)) {
            console.log("  ℹ️  CAUTION: Health factor < 2.0 - Low-moderate risk");
            console.log("     Position is stable but monitor regularly");
        } else {
            console.log("  ✅ HEALTHY: Health factor > 2.0 - Low risk");
        }
        
        // Calculate expected APY
        const leverageRatio = Number(ethers.formatUnits(leverage, 18));
        const ankrAPY = 7.5; // Approximate Ankr staking APY
        const moreSupplyAPY = 2.0; // Approximate MORE supply APY for ankrFLOW
        const moreBorrowAPY = 3.5; // Approximate MORE borrow APY for WFLOW
        
        const estimatedNetAPY = (ankrAPY * leverageRatio) + 
                                (moreSupplyAPY * leverageRatio) - 
                                (moreBorrowAPY * (leverageRatio - 1));
        
        console.log(`\nEstimated Net APY: ~${estimatedNetAPY.toFixed(2)}%`);
        console.log(`  (Based on ${leverageRatio.toFixed(2)}x leverage)\n`);
        
        // ================================================================
        // TEST 3: Test More Aggressive Looping (Optional)
        // ================================================================
        console.log("TEST 3: Testing 2-Loop Strategy (More Aggressive)");
        console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        
        const userChoice = process.env.TEST_2_LOOPS === "true";
        
        if (userChoice && vaultBalance >= ethers.parseEther("2")) {
            console.log("⚠️  Executing 2-loop strategy (higher leverage, higher risk)...\n");
            
            const twoLoopData = ethers.AbiCoder.defaultAbiCoder().encode(
                ["uint256"],
                [2]
            );
            
            const tx2 = await vault.executeStrategy(
                loopingStrategyAddress,
                NATIVE_FLOW,
                ethers.parseEther("0.5"),
                twoLoopData
            );
            
            await tx2.wait();
            console.log("✅ 2-loop strategy executed!\n");
            
            const [, , , , leverage2, healthFactor2] = await loopingStrategy.getLoopingMetrics();
            
            console.log("2-Loop Position:");
            console.log(`  Leverage: ${ethers.formatUnits(leverage2, 18)}x`);
            console.log(`  Health Factor: ${ethers.formatUnits(healthFactor2, 18)}`);
            
            if (healthFactor2 < ethers.parseUnits("1.3", 18)) {
                console.log("  🚨 CRITICAL RISK with 2 loops!");
            }
        } else {
            console.log("Skipping 2-loop test (set TEST_2_LOOPS=true to enable)");
            console.log("2-loop provides ~2.0-2.5x leverage but increases liquidation risk\n");
        }
        
        // ================================================================
        // TEST 4: Performance Comparison
        // ================================================================
        console.log("TEST 4: Strategy Performance Summary");
        console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        
        console.log("Strategy Comparison:");
        console.log("┌─────────────────────┬──────────┬─────────┬──────────────┐");
        console.log("│ Strategy            │ Leverage │ Est APY │ Risk Level   │");
        console.log("├─────────────────────┼──────────┼─────────┼──────────────┤");
        console.log("│ Simple Ankr Staking │ 1.0x     │ ~7.5%   │ LOW          │");
        console.log("│ 1-Loop              │ ~1.5x    │ ~12%    │ MEDIUM       │");
        console.log("│ 2-Loop              │ ~2.0x    │ ~17%    │ HIGH         │");
        console.log("│ 3-Loop              │ ~2.5x    │ ~22%    │ VERY HIGH    │");
        console.log("└─────────────────────┴──────────┴─────────┴──────────────┘\n");
        
        console.log("Your Current Position:");
        console.log(`  Leverage: ${leverageRatio.toFixed(2)}x`);
        console.log(`  Est. APY: ~${estimatedNetAPY.toFixed(2)}%`);
        console.log(`  Health Factor: ${healthFactor === 0n ? "∞" : ethers.formatUnits(healthFactor, 18)}\n`);
        
        // ================================================================
        // IMPORTANT WARNINGS
        // ================================================================
        console.log("⚠️  IMPORTANT LOOPING STRATEGY WARNINGS:");
        console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        console.log("1. Monitor health factor daily");
        console.log("2. Price drops in FLOW can trigger liquidation");
        console.log("3. Borrowing rates can increase, reducing profitability");
        console.log("4. Consider unwinding if health factor < 1.5");
        console.log("5. Never use 3-loop strategy with significant funds\n");
        
        console.log("✅ LOOPING STRATEGY TESTS COMPLETE!");
        console.log("\nNext steps:");
        console.log("  - Monitor position via: await loopingStrategy.getLoopingMetrics()");
        console.log("  - Check health regularly");
        console.log("  - Use emergencyExit() if needed to unwind position\n");
        
    } catch (error) {
        console.error("❌ Test failed:", error.message);
        
        if (error.message.includes("HEALTH_FACTOR_LOWER_THAN_LIQUIDATION_THRESHOLD")) {
            console.log("\n❌ CRITICAL: Health factor would be too low!");
            console.log("This means the looping parameters are too aggressive.");
            console.log("Suggestions:");
            console.log("  - Use fewer loops");
            console.log("  - Start with less FLOW");
            console.log("  - Check that ANKR_FLOW has good liquidity on MORE Markets");
        }
        
        throw error;
    }
}

main().catch(console.error);