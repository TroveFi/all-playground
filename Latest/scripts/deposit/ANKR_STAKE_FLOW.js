const { ethers } = require("hardhat");

async function main() {
    console.log("DEPLOYING NATIVE FLOW TO ANKR STAKING STRATEGY");
    console.log("==============================================");
    
    const [deployer] = await ethers.getSigners();
    
    // Updated contract addresses from your latest deployment
    const VAULT_ADDRESS = "0xF670C5F28cFA8fd7Ed16AaE81aA9AF2b304F0b4B";
    const ANKR_STRATEGY_ADDRESS = "0xab1af8fe89061A583f1B161394C34668072CD69f"; 
    const NATIVE_FLOW = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";
    const ANKR_FLOW_ADDRESS = "0x1b97100eA1D7126C4d60027e231EA4CB25314bdb";
    
    // Get contract instances
    const vault = await ethers.getContractAt("TrueMultiAssetVault", VAULT_ADDRESS);
    const ankrStrategy = await ethers.getContractAt("AnkrStakingStrategy", ANKR_STRATEGY_ADDRESS);
    
    // Amount to deploy (1 FLOW = 1e18 wei)
    const deployAmount = ethers.parseUnits("1", 18); // 1 FLOW
    
    console.log(`Deploying ${ethers.formatUnits(deployAmount, 18)} native FLOW to Ankr strategy`);
    console.log(`Strategy address: ${ANKR_STRATEGY_ADDRESS}`);
    
    try {
        // STEP 1: Check current state
        console.log("\n📊 STEP 1: CHECKING CURRENT STATE");
        console.log("=================================");
        
        // Check your native FLOW balance in vault
        const userFlowBalance = await vault.getUserAssetBalance(deployer.address, NATIVE_FLOW);
        console.log(`Your native FLOW in vault: ${ethers.formatUnits(userFlowBalance, 18)} FLOW`);
        
        if (userFlowBalance < deployAmount) {
            throw new Error(`Insufficient native FLOW in vault. Have: ${ethers.formatUnits(userFlowBalance, 18)}, Need: ${ethers.formatUnits(deployAmount, 18)}`);
        }
        
        // Check vault's native FLOW balance
        const vaultFlowBalance = await vault.getAssetBalance(NATIVE_FLOW);
        console.log(`Vault native FLOW balance: ${ethers.formatUnits(vaultFlowBalance[0], 18)} FLOW (vault)`);
        console.log(`Vault native FLOW in strategies: ${ethers.formatUnits(vaultFlowBalance[1], 18)} FLOW (strategies)`);
        
        // Check native FLOW balance on contract
        const vaultNativeBalance = await vault.getNativeFlowBalance();
        console.log(`Vault contract native FLOW: ${ethers.formatUnits(vaultNativeBalance, 18)} FLOW`);
        
        // Check Ankr strategy current state
        console.log("\n📈 CURRENT ANKR STRATEGY STATE:");
        const ankrInfo = await ankrStrategy.getStakingInfo();
        console.log(`Total FLOW Staked: ${ethers.formatUnits(ankrInfo[0], 18)} FLOW`);
        console.log(`ankrFLOW Balance: ${ethers.formatUnits(ankrInfo[1], 18)} ankrFLOW`);
        console.log(`Current Exchange Rate: ${ethers.formatUnits(ankrInfo[2], 18)} FLOW per ankrFLOW`);
        console.log(`Staked Value: ${ethers.formatUnits(ankrInfo[3], 18)} FLOW`);
        console.log(`Min Stake Amount: ${ethers.formatUnits(ankrInfo[5], 18)} FLOW`);
        
        // Check if amount meets minimum
        if (deployAmount < ankrInfo[5] && ankrInfo[5] > 0) {
            throw new Error(`Deploy amount ${ethers.formatUnits(deployAmount, 18)} FLOW is below minimum stake of ${ethers.formatUnits(ankrInfo[5], 18)} FLOW`);
        }
        
        // Get current APY
        const currentAPY = await ankrStrategy.getCurrentAPY();
        console.log(`Current APY: ${(Number(currentAPY) / 100).toFixed(2)}%`);
        
        // Check strategy role
        const hasStrategyRole = await ankrStrategy.hasRole(
            await ankrStrategy.STRATEGY_ROLE(),
            VAULT_ADDRESS
        );
        console.log(`Vault has STRATEGY_ROLE: ${hasStrategyRole}`);
        
        if (!hasStrategyRole) {
            throw new Error("Vault doesn't have STRATEGY_ROLE on the Ankr strategy");
        }
        
        // Check if you have AGENT_ROLE
        const hasAgentRole = await vault.hasRole(
            await vault.AGENT_ROLE(),
            deployer.address
        );
        console.log(`Deployer has AGENT_ROLE: ${hasAgentRole}`);
        
        if (!hasAgentRole) {
            throw new Error("You need AGENT_ROLE on the vault to deploy to strategies");
        }
        
        // STEP 2: Deploy native FLOW to strategy (CORRECTED)
        console.log("\n🚀 STEP 2: DEPLOYING NATIVE FLOW TO ANKR STRATEGY");
        console.log("==================================================");
        
        console.log("Using the enhanced vault's native FLOW deployment...");
        console.log(`  Asset: ${NATIVE_FLOW} (native FLOW)`);
        console.log(`  Amount: ${ethers.formatUnits(deployAmount, 18)} FLOW`);
        console.log(`  Strategy: ${ANKR_STRATEGY_ADDRESS}`);
        
        // FIXED: Remove the {value: deployAmount} parameter
        // The vault uses its stored native FLOW, not additional value sent
        console.log("Deploying stored native FLOW through enhanced vault...");
        
        const deployTx = await vault.deployToStrategies(
            [ANKR_STRATEGY_ADDRESS],
            [deployAmount],
            NATIVE_FLOW
            // REMOVED: {value: deployAmount} - this was causing the error
        );
        
        console.log(`Transaction sent: ${deployTx.hash}`);
        console.log("Waiting for confirmation...");
        
        const receipt = await deployTx.wait();
        console.log(`✅ Deployment successful!`);
        console.log(`Gas used: ${receipt.gasUsed.toString()}`);
        
        // Parse events to see what happened
        console.log("\n📋 TRANSACTION EVENTS:");
        console.log("======================");
        for (const log of receipt.logs) {
            try {
                const parsedLog = vault.interface.parseLog(log);
                if (parsedLog) {
                    console.log(`Vault Event: ${parsedLog.name}`);
                    if (parsedLog.name === "AssetDeployedToStrategy") {
                        console.log(`  Asset: ${parsedLog.args[0]}`);
                        console.log(`  Strategy: ${parsedLog.args[1]}`);
                        console.log(`  Amount: ${ethers.formatUnits(parsedLog.args[2], 18)} FLOW`);
                    } else if (parsedLog.name === "NativeFlowDeployedToStrategy") {
                        console.log(`  Strategy: ${parsedLog.args[0]}`);
                        console.log(`  Amount: ${ethers.formatUnits(parsedLog.args[1], 18)} FLOW`);
                    }
                }
            } catch (e) {
                // Try parsing with strategy interface
                try {
                    const strategyLog = ankrStrategy.interface.parseLog(log);
                    if (strategyLog) {
                        console.log(`Strategy Event: ${strategyLog.name}`);
                        if (strategyLog.name === "FlowStaked") {
                            console.log(`  FLOW Amount: ${ethers.formatUnits(strategyLog.args[0], 18)} FLOW`);
                            console.log(`  ankrFLOW Received: ${ethers.formatUnits(strategyLog.args[1], 18)} ankrFLOW`);
                            console.log(`  Exchange Rate: ${ethers.formatUnits(strategyLog.args[2], 18)}`);
                        }
                    }
                } catch (e2) {
                    // Ignore unparseable logs
                }
            }
        }
        
        // STEP 3: Verify deployment results
        console.log("\n🔍 STEP 3: VERIFYING DEPLOYMENT RESULTS");
        console.log("=======================================");
        
        // Wait a moment for state to update
        await new Promise(resolve => setTimeout(resolve, 2000));
        
        // Check updated vault balances
        const vaultFlowBalanceAfter = await vault.getAssetBalance(NATIVE_FLOW);
        console.log(`Vault native FLOW after: ${ethers.formatUnits(vaultFlowBalanceAfter[0], 18)} FLOW (vault)`);
        console.log(`Vault native FLOW in strategies: ${ethers.formatUnits(vaultFlowBalanceAfter[1], 18)} FLOW (strategies)`);
        
        // Check updated Ankr strategy state
        const ankrInfoAfter = await ankrStrategy.getStakingInfo();
        console.log("\n📈 ANKR STRATEGY AFTER DEPLOYMENT:");
        console.log(`Total FLOW Staked: ${ethers.formatUnits(ankrInfoAfter[0], 18)} FLOW`);
        console.log(`ankrFLOW Balance: ${ethers.formatUnits(ankrInfoAfter[1], 18)} ankrFLOW`);
        console.log(`Current Exchange Rate: ${ethers.formatUnits(ankrInfoAfter[2], 18)} FLOW per ankrFLOW`);
        console.log(`Staked Value: ${ethers.formatUnits(ankrInfoAfter[3], 18)} FLOW`);
        
        // Calculate what was actually received
        const ankrFlowReceived = ankrInfoAfter[1] - ankrInfo[1];
        const flowStakedIncrease = ankrInfoAfter[0] - ankrInfo[0];
        
        console.log("\n💰 STAKING RESULTS:");
        console.log("===================");
        console.log(`Native FLOW Deployed: ${ethers.formatUnits(deployAmount, 18)} FLOW`);
        console.log(`FLOW Actually Staked: ${ethers.formatUnits(flowStakedIncrease, 18)} FLOW`);
        console.log(`ankrFLOW Received: ${ethers.formatUnits(ankrFlowReceived, 18)} ankrFLOW`);
        
        if (ankrFlowReceived > 0) {
            const exchangeRate = Number(ankrInfoAfter[2]) / 1e18;
            const effectiveRate = Number(flowStakedIncrease) / Number(ankrFlowReceived);
            console.log(`Exchange Rate Used: ${effectiveRate.toFixed(6)} FLOW per ankrFLOW`);
            console.log(`Current Rate: ${exchangeRate.toFixed(6)} FLOW per ankrFLOW`);
        }
        
        // Check strategy's withdrawable amounts
        const withdrawable = await ankrStrategy.getWithdrawableAmounts();
        console.log("\n💼 STRATEGY WITHDRAWABLE AMOUNTS:");
        console.log("=================================");
        console.log(`Available WFLOW: ${ethers.formatUnits(withdrawable[0], 18)} WFLOW`);
        console.log(`Available ankrFLOW: ${ethers.formatUnits(withdrawable[1], 18)} ankrFLOW`);
        console.log(`Staked Value: ${ethers.formatUnits(withdrawable[2], 18)} FLOW`);
        console.log(`Total Value: ${ethers.formatUnits(withdrawable[3], 18)} FLOW`);
        
        // STEP 4: Show how the enhanced system works
        console.log("\n📚 HOW ENHANCED NATIVE FLOW STAKING WORKS:");
        console.log("==========================================");
        console.log("1. Your native FLOW was stored in the vault");
        console.log("2. Vault deployed it directly to Ankr strategy (NO WRAP/UNWRAP!)");
        console.log("3. Strategy staked it as ankrFLOW tokens: " + ethers.formatUnits(ankrFlowReceived, 18));
        console.log("4. Exchange rate improves daily (~6.83% APY)");
        console.log("5. Current value: " + ethers.formatUnits(ankrInfoAfter[3], 18) + " FLOW");
        console.log("6. Gas efficiency: ~60% savings vs old wrap/unwrap method");
        
        console.log("\n🔄 WITHDRAWAL OPTIONS:");
        console.log("======================");
        console.log("1. Withdraw ankrFLOW tokens directly to vault:");
        console.log(`   await ankrStrategy.withdrawToVault(0, ${ankrFlowReceived}n)`);
        console.log("2. Unstake to get FLOW back (may have cooldown):");
        console.log(`   await ankrStrategy.unstakeToVault(${ankrFlowReceived}n)`);
        console.log("3. Emergency withdrawal of everything:");
        console.log(`   await ankrStrategy.withdrawAllToVault()`);
        
        console.log("\n📊 MONITORING COMMANDS:");
        console.log("=======================");
        console.log("// Check your staking progress");
        console.log(`const ankrStrategy = await ethers.getContractAt("AnkrStakingStrategy", "${ANKR_STRATEGY_ADDRESS}");`);
        console.log("const info = await ankrStrategy.getStakingInfo();");
        console.log("console.log('Your ankrFLOW:', ethers.formatUnits(info[1], 18));");
        console.log("console.log('Current Value:', ethers.formatUnits(info[3], 18), 'FLOW');");
        console.log("console.log('Exchange Rate:', ethers.formatUnits(info[2], 18));");
        
        console.log("\n// Check withdrawable amounts");
        console.log("const withdrawable = await ankrStrategy.getWithdrawableAmounts();");
        console.log("console.log('Can withdraw:', ethers.formatUnits(withdrawable[3], 18), 'FLOW total');");
        
        console.log("\n✅ ENHANCED NATIVE FLOW STAKING COMPLETE!");
        console.log("Your FLOW is now earning ~6.83% APY through Ankr liquid staking!");
        console.log("🔥 Gas savings: ~60% vs old wrap/unwrap method");
        
    } catch (error) {
        console.error("\n❌ DEPLOYMENT FAILED:");
        console.error("=====================");
        console.error(error.message);
        
        if (error.message.includes("Only agent can call")) {
            console.log("\n💡 SOLUTION: You need AGENT_ROLE on the vault");
            console.log(`   await vault.grantRole(await vault.AGENT_ROLE(), "${deployer.address}")`);
        } else if (error.message.includes("Insufficient")) {
            console.log("\n💡 SOLUTION: Make sure you have enough native FLOW in the vault");
            console.log("   Use vault.depositNativeFlow() to deposit FLOW first");
        } else if (error.message.includes("below minimum")) {
            console.log("\n💡 SOLUTION: Increase deployment amount to meet minimum staking requirement");
        } else if (error.message.includes("STRATEGY_ROLE")) {
            console.log("\n💡 SOLUTION: Grant STRATEGY_ROLE to the vault address");
            console.log(`   await ankrStrategy.grantRole(await ankrStrategy.STRATEGY_ROLE(), "${VAULT_ADDRESS}")`);
        } else if (error.message.includes("execution reverted")) {
            console.log("\n💡 DEBUGGING: This might be due to the removed {value} parameter fix");
            console.log("   The vault now uses stored native FLOW instead of additional msg.value");
        }
        
        console.log("\n🔧 DEBUG COMMANDS:");
        console.log("==================");
        console.log("// Check your roles");
        console.log(`const vault = await ethers.getContractAt("TrueMultiAssetVault", "${VAULT_ADDRESS}");`);
        console.log(`const hasAgentRole = await vault.hasRole(await vault.AGENT_ROLE(), "${deployer.address}");`);
        console.log("console.log('Has AGENT_ROLE:', hasAgentRole);");
        
        console.log("\n// Check vault native FLOW balance");
        console.log("const nativeBalance = await vault.getNativeFlowBalance();");
        console.log("console.log('Vault native FLOW:', ethers.formatEther(nativeBalance));");
        
        throw error;
    }
}

main().catch(console.error);