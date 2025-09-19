const { ethers } = require("hardhat");

async function main() {
    console.log("Depositing Native FLOW to New Core Vault");
    console.log("========================================");
    
    const [deployer] = await ethers.getSigners();
    
    // NEW CONTRACT ADDRESSES from your deployment
    const CORE_VAULT_ADDRESS = "0xbD82c706e3632972A00E288a54Ea50c958b865b2";
    const VAULT_EXTENSION_ADDRESS = "0xBaF543b07e01F0Ed02dFEa5dfbAd38167AC9be57";
    const NATIVE_FLOW = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";
    
    const coreVault = await ethers.getContractAt("TrueMultiAssetVaultCore", CORE_VAULT_ADDRESS);
    const vaultExtension = await ethers.getContractAt("VaultExtension", VAULT_EXTENSION_ADDRESS);
    
    // Deposit amount
    const depositAmount = ethers.parseUnits("1", 18);
    
    console.log(`Depositing: ${ethers.formatEther(depositAmount)} FLOW`);
    console.log(`To core vault: ${CORE_VAULT_ADDRESS}`);
    console.log(`With extension: ${VAULT_EXTENSION_ADDRESS}`);
    
    try {
        // Check our balance
        const balance = await deployer.provider.getBalance(deployer.address);
        console.log(`Your FLOW balance: ${ethers.formatEther(balance)} FLOW`);
        
        if (balance < depositAmount + ethers.parseUnits("0.1", 18)) {
            throw new Error("Insufficient FLOW balance for deposit + gas");
        }
        
        // Check shares before
        const sharesBefore = await coreVault.balanceOf(deployer.address);
        console.log(`Vault shares before: ${ethers.formatUnits(sharesBefore, 18)}`);
        
        // Check vault status first
        console.log("\nChecking vault status...");
        const depositsEnabled = await coreVault.depositsEnabled();
        const emergencyMode = await coreVault.emergencyMode();
        const riskManager = await coreVault.riskManager();
        
        console.log(`Deposits enabled: ${depositsEnabled}`);
        console.log(`Emergency mode: ${emergencyMode}`);
        console.log(`Risk manager: ${riskManager}`);
        
        if (!depositsEnabled) {
            throw new Error("Deposits are disabled on the vault");
        }
        
        if (emergencyMode) {
            throw new Error("Vault is in emergency mode");
        }
        
        // Check asset info
        const supportedAssets = await coreVault.getSupportedAssets();
        console.log(`Supported assets: ${supportedAssets.length}`);
        console.log(`Native FLOW included: ${supportedAssets.includes(NATIVE_FLOW)}`);
        
        // Estimate gas first
        console.log("\nEstimating gas...");
        const gasEstimate = await coreVault.depositNativeFlow.estimateGas(
            deployer.address,
            1, // MEDIUM risk level
            {
                value: depositAmount
            }
        );
        console.log(`Gas estimate: ${gasEstimate.toString()}`);
        
        // Execute deposit with MEDIUM risk level
        console.log("\nExecuting deposit with MEDIUM risk level...");
        const tx = await coreVault.depositNativeFlow(
            deployer.address,
            1, // MEDIUM risk level (0=LOW, 1=MEDIUM, 2=HIGH)
            {
                value: depositAmount,
                gasLimit: gasEstimate * 120n / 100n // Add 20% buffer
            }
        );
        
        console.log(`Transaction hash: ${tx.hash}`);
        console.log("Waiting for confirmation...");
        
        const receipt = await tx.wait();
        console.log(`Transaction confirmed in block ${receipt.blockNumber}`);
        console.log(`Gas used: ${receipt.gasUsed.toString()}`);
        
        // Check results
        const sharesAfter = await coreVault.balanceOf(deployer.address);
        const sharesReceived = sharesAfter - sharesBefore;
        
        console.log("\nDeposit Results:");
        console.log(`FLOW deposited: ${ethers.formatEther(depositAmount)} FLOW`);
        console.log(`Shares received: ${ethers.formatUnits(sharesReceived, 18)}`);
        console.log(`Total shares: ${ethers.formatUnits(sharesAfter, 18)}`);
        
        // Check vault state
        const assetBalance = await coreVault.getAssetBalance(NATIVE_FLOW);
        console.log(`Vault native FLOW balance: ${ethers.formatEther(assetBalance[0])} FLOW`);
        
        // Check user position
        const userPosition = await coreVault.getUserPosition(deployer.address);
        const riskLevels = ["LOW", "MEDIUM", "HIGH"];
        console.log(`User risk level: ${riskLevels[userPosition[4]]}`);
        console.log(`User total deposited: ${ethers.formatUnits(userPosition[5], 18)} FLOW`);
        
        // Check epoch status
        console.log("\nChecking epoch status...");
        const epochStatus = await vaultExtension.getCurrentEpochStatus();
        console.log(`Current epoch: ${epochStatus[0].toString()}`);
        console.log(`Time remaining: ${Math.floor(Number(epochStatus[1]) / 3600)} hours`);
        console.log(`Yield pool: ${ethers.formatUnits(epochStatus[2], 18)}`);
        
        // Check user deposit in extension
        const userDeposit = await vaultExtension.getUserDeposit(deployer.address);
        console.log(`Extension total deposited: ${ethers.formatUnits(userDeposit[0], 18)}`);
        console.log(`Extension current balance: ${ethers.formatUnits(userDeposit[1], 18)}`);
        console.log(`First deposit epoch: ${userDeposit[2].toString()}`);
        
        console.log("\n🎉 SUCCESS! Your 1 FLOW has been deposited to the new core vault.");
        console.log("✅ Deposit recorded in both core vault and extension");
        console.log("✅ You're enrolled in the epoch reward system");
        console.log("✅ You can deploy this to strategies or keep it in the vault");
        
        console.log("\nNext steps:");
        console.log("1. Deploy to strategy:");
        console.log("   npx hardhat run scripts/deploy-to-strategy-new-vault.js --network flow_mainnet");
        console.log("2. Check eligibility for rewards:");
        console.log(`   await vaultExtension.getUserEpochStatus("${deployer.address}")`);
        console.log("3. Update risk level if desired:");
        console.log("   await coreVault.updateRiskLevel(0|1|2) // LOW|MEDIUM|HIGH");
        
    } catch (error) {
        console.error("\nDeposit failed:");
        console.error(error.message);
        
        // Enhanced debugging for new architecture
        if (error.message.includes("execution reverted")) {
            console.log("\nDebugging the revert...");
            
            try {
                const code = await deployer.provider.getCode(CORE_VAULT_ADDRESS);
                if (code === "0x") {
                    console.log("ERROR: No contract found at core vault address");
                } else {
                    console.log("Contract exists at core vault address");
                    
                    // Check specific conditions for new vault
                    const depositsEnabled = await coreVault.depositsEnabled();
                    const emergencyMode = await coreVault.emergencyMode();
                    const riskManager = await coreVault.riskManager();
                    const vaultExtensionAddr = await coreVault.vaultExtension();
                    
                    console.log(`Deposits enabled: ${depositsEnabled}`);
                    console.log(`Emergency mode: ${emergencyMode}`);
                    console.log(`Risk manager: ${riskManager}`);
                    console.log(`Vault extension: ${vaultExtensionAddr}`);
                    
                    // Check if extension is properly connected
                    if (vaultExtensionAddr === "0x0000000000000000000000000000000000000000") {
                        console.log("ISSUE: Vault extension not connected");
                    }
                    
                    if (!depositsEnabled) {
                        console.log("ISSUE: Deposits are disabled");
                        console.log("SOLUTION: Run disable-risk-manager script first");
                    }
                    if (emergencyMode) {
                        console.log("ISSUE: Emergency mode is active");
                        console.log("SOLUTION: Run disable-risk-manager script first");
                    }
                }
            } catch (debugError) {
                console.log("Debug check failed:", debugError.message);
            }
        } else if (error.message.includes("insufficient funds")) {
            console.log("\nISSUE: Insufficient FLOW balance");
            console.log("SOLUTION: Add more FLOW to your account");
        } else if (error.message.includes("Risk limits exceeded")) {
            console.log("\nISSUE: Risk manager is still active and blocking");
            console.log("SOLUTION: Run the disable-risk-manager script first");
        }
    }
}

main().catch(console.error);