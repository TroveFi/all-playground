const { ethers } = require("hardhat");

async function main() {
    console.log("Adding 1 FLOW Worth of Yield to Extension");
    console.log("========================================");
    
    const [deployer] = await ethers.getSigners();
    
    // NEW CONTRACT ADDRESSES from your deployment
    const VAULT_EXTENSION_ADDRESS = "0xBaF543b07e01F0Ed02dFEa5dfbAd38167AC9be57";
    const USDF_ADDRESS = "0x2aaBea2058b5aC2D339b163C6Ab6f2b6d53aabED";
    const NATIVE_FLOW = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";
    
    const vaultExtension = await ethers.getContractAt("VaultExtension", VAULT_EXTENSION_ADDRESS);
    
    // Amount equivalent to 1 FLOW (using 18 decimals for internal calculation)
    const yieldAmount = ethers.parseUnits("1", 18);
    
    console.log(`Adding yield equivalent to: 1 FLOW`);
    console.log(`To vault extension: ${VAULT_EXTENSION_ADDRESS}`);
    console.log(`Your account: ${deployer.address}`);
    
    try {
        // Check current epoch status before
        console.log("\nCurrent epoch status (before yield addition):");
        const epochStatusBefore = await vaultExtension.getCurrentEpochStatus();
        console.log(`  Epoch Number: ${epochStatusBefore[0].toString()}`);
        console.log(`  Time Remaining: ${Math.floor(Number(epochStatusBefore[1]) / 3600)} hours`);
        console.log(`  Yield Pool: ${ethers.formatUnits(epochStatusBefore[2], 18)}`);
        console.log(`  Participants: ${epochStatusBefore[3].toString()}`);
        
        // Check if we have YIELD_MANAGER_ROLE
        console.log("\nChecking permissions...");
        const YIELD_MANAGER_ROLE = await vaultExtension.YIELD_MANAGER_ROLE();
        const hasYieldRole = await vaultExtension.hasRole(YIELD_MANAGER_ROLE, deployer.address);
        console.log(`Has YIELD_MANAGER_ROLE: ${hasYieldRole}`);
        
        if (!hasYieldRole) {
            throw new Error("You don't have YIELD_MANAGER_ROLE. Use the account that deployed the contracts.");
        }
        
        // Method 1: Try subsidizeYield (admin function, no token transfer needed)
        console.log("\nMethod 1: Using subsidizeYield function...");
        try {
            const subsidizeTx = await vaultExtension.subsidizeYield(yieldAmount);
            console.log(`Subsidize transaction: ${subsidizeTx.hash}`);
            await subsidizeTx.wait();
            console.log("✅ Yield subsidized successfully!");
            
        } catch (subsidizeError) {
            console.log("Subsidize method failed, trying addYield method...");
            
            // Method 2: Try addYield with NATIVE_FLOW
            console.log("\nMethod 2: Using addYield with NATIVE_FLOW...");
            const addYieldTx = await vaultExtension.addYield(NATIVE_FLOW, yieldAmount);
            console.log(`AddYield transaction: ${addYieldTx.hash}`);
            await addYieldTx.wait();
            console.log("✅ Yield added successfully!");
        }
        
        // Check epoch status after
        console.log("\nEpoch status (after yield addition):");
        const epochStatusAfter = await vaultExtension.getCurrentEpochStatus();
        console.log(`  Epoch Number: ${epochStatusAfter[0].toString()}`);
        console.log(`  Time Remaining: ${Math.floor(Number(epochStatusAfter[1]) / 3600)} hours`);
        console.log(`  Yield Pool: ${ethers.formatUnits(epochStatusAfter[2], 18)}`);
        console.log(`  Participants: ${epochStatusAfter[3].toString()}`);
        
        const yieldIncrease = epochStatusAfter[2] - epochStatusBefore[2];
        console.log(`  Yield Increase: ${ethers.formatUnits(yieldIncrease, 18)}`);
        
        // Check if you have any deposits to be eligible for rewards
        console.log("\nChecking your eligibility...");
        const userDeposit = await vaultExtension.getUserDeposit(deployer.address);
        console.log(`Your total deposited: ${ethers.formatUnits(userDeposit[0], 18)}`);
        console.log(`Your current balance: ${ethers.formatUnits(userDeposit[1], 18)}`);
        console.log(`First deposit epoch: ${userDeposit[2].toString()}`);
        
        if (userDeposit[0] > 0) {
            // Check eligibility for current epoch
            const currentEpoch = epochStatusAfter[0];
            const isEligible = await vaultExtension.isEligibleForEpoch(deployer.address, currentEpoch);
            console.log(`Eligible for current epoch (${currentEpoch}): ${isEligible}`);
            
            // Check eligibility for next epoch
            const isEligibleNext = await vaultExtension.isEligibleForEpoch(deployer.address, currentEpoch + 1n);
            console.log(`Eligible for next epoch (${currentEpoch + 1n}): ${isEligibleNext}`);
            
            // Show reward parameters for current epoch
            if (isEligible) {
                console.log("\nYour reward parameters for current epoch:");
                const rewardParams = await vaultExtension.calculateRewardParameters(deployer.address, currentEpoch);
                console.log(`  Base Weight: ${ethers.formatUnits(rewardParams[0], 18)}`);
                console.log(`  Time Weight: ${ethers.formatUnits(rewardParams[1], 18)}`);
                console.log(`  Risk Multiplier: ${rewardParams[2].toString()}`);
                console.log(`  Total Weight: ${ethers.formatUnits(rewardParams[3], 18)}`);
                console.log(`  Win Probability: ${(Number(rewardParams[4]) / 100).toFixed(2)}%`);
                console.log(`  Potential Payout: ${ethers.formatUnits(rewardParams[5], 18)}`);
            }
        } else {
            console.log("⚠️  You have no deposits. Deposit some FLOW first to be eligible for rewards!");
        }
        
        console.log("\n🎉 SUCCESS! Yield added to the extension.");
        console.log("\nWhat happens next:");
        console.log("1. The yield is now available for the current epoch rewards");
        console.log("2. Users who are eligible can claim rewards when epochs complete");
        console.log("3. Rewards are distributed via VRF lottery system");
        console.log("4. You can add more yield anytime to increase the reward pool");
        
        console.log("\nTesting commands:");
        console.log("1. Advance epoch manually (for testing):");
        console.log("   await vaultExtension.advanceEpoch()");
        console.log("2. Check claimable epochs:");
        console.log(`   await vaultExtension.getClaimableEpochs("${deployer.address}")`);
        console.log("3. Claim rewards (after epoch completes):");
        console.log("   await vaultExtension.claimEpochReward(epochNumber)");
        
    } catch (error) {
        console.error("\nYield addition failed:");
        console.error(error.message);
        
        if (error.message.includes("AccessControl")) {
            console.log("\n💡 ISSUE: You don't have YIELD_MANAGER_ROLE or ADMIN_ROLE");
            console.log("SOLUTION: Use the account that deployed the contracts");
            console.log(`Your address: ${deployer.address}`);
            console.log("Expected: The deployer address from the deployment script");
        } else if (error.message.includes("Asset not supported")) {
            console.log("\n💡 ISSUE: The asset is not supported by the extension");
            console.log("SOLUTION: Try with a different asset or add support for this asset");
        } else if (error.message.includes("Amount must be positive")) {
            console.log("\n💡 ISSUE: Yield amount must be greater than 0");
            console.log("SOLUTION: Check the yield amount calculation");
        }
        
        // Try to get more debugging info
        try {
            console.log("\nDebugging extension state...");
            const ADMIN_ROLE = await vaultExtension.ADMIN_ROLE();
            const hasAdminRole = await vaultExtension.hasRole(ADMIN_ROLE, deployer.address);
            console.log(`Has ADMIN_ROLE: ${hasAdminRole}`);
            
            const currentEpoch = await vaultExtension.currentEpoch();
            console.log(`Current epoch from extension: ${currentEpoch.toString()}`);
            
        } catch (debugError) {
            console.log("Debug failed:", debugError.message);
        }
    }
}

main().catch(console.error);