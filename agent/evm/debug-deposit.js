const { ethers } = require("hardhat");
const fs = require("fs");

async function main() {
    console.log("Debugging Deposit Issue");
    console.log("========================\n");
    
    const [user] = await ethers.getSigners();
    const deploymentInfo = JSON.parse(fs.readFileSync("deployment-info.json", "utf8"));
    const vaultAddress = deploymentInfo.contracts.vaultCore;
    
    const vault = await ethers.getContractAt("TrueMultiAssetVaultCore", vaultAddress);
    const NATIVE_FLOW = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";
    
    console.log("Checking vault state...\n");
    
    try {
        // 1. Check if deposits are enabled
        const depositsEnabled = await vault.depositsEnabled();
        console.log(`✓ Deposits enabled: ${depositsEnabled}`);
        
        // 2. Check emergency mode
        const emergencyMode = await vault.emergencyMode();
        console.log(`✓ Emergency mode: ${emergencyMode}`);
        
        // 3. Check if NATIVE_FLOW is supported
        const isSupported = await vault.isAssetSupported(NATIVE_FLOW);
        console.log(`✓ NATIVE_FLOW supported: ${isSupported}`);
        
        // 4. Check asset info
        const assetInfo = await vault.assetInfo(NATIVE_FLOW);
        console.log(`\nAsset Info:`);
        console.log(`  Supported: ${assetInfo.supported}`);
        console.log(`  Accepting deposits: ${assetInfo.acceptingDeposits}`);
        console.log(`  Min deposit: ${ethers.formatEther(assetInfo.minDeposit)} FLOW`);
        console.log(`  Max deposit: ${ethers.formatEther(assetInfo.maxDeposit)} FLOW`);
        
        // 5. Check vault extension
        const extensionAddress = await vault.vaultExtension();
        console.log(`\nVault Extension: ${extensionAddress}`);
        
        // 6. Try to estimate gas
        console.log(`\nEstimating gas for 1 FLOW deposit...`);
        const depositAmount = ethers.parseEther("1");
        
        try {
            const gasEstimate = await vault["depositNativeFlow(address)"].estimateGas(
                user.address,
                { value: depositAmount }
            );
            console.log(`✓ Gas estimate: ${gasEstimate.toString()}`);
            
            // If estimation works, try actual deposit with higher gas
            console.log(`\nAttempting deposit with ${gasEstimate * 2n} gas...`);
            const tx = await vault["depositNativeFlow(address)"](user.address, {
                value: depositAmount,
                gasLimit: gasEstimate * 2n
            });
            
            console.log(`Transaction: ${tx.hash}`);
            await tx.wait();
            console.log("✅ DEPOSIT SUCCESSFUL!");
            
        } catch (estimateError) {
            console.log(`\n❌ Gas estimation failed!`);
            console.log(`Error: ${estimateError.message}`);
            
            // Try to get more details
            if (estimateError.data) {
                console.log(`Error data: ${estimateError.data}`);
            }
            
            // Check if it's a revert with a reason
            if (estimateError.reason) {
                console.log(`Revert reason: ${estimateError.reason}`);
            }
        }
        
    } catch (error) {
        console.error("\n❌ Error:", error.message);
    }
}

main().catch(console.error);