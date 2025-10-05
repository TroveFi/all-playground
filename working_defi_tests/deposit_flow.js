const { ethers } = require("hardhat");

async function main() {
    console.log("Depositing Native FLOW to Vault");
    console.log("===============================");
    
    const [deployer] = await ethers.getSigners();
    
    // Contract addresses
    const VAULT_ADDRESS = "0xF670C5F28cFA8fd7Ed16AaE81aA9AF2b304F0b4B";
    const NATIVE_FLOW = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";
    
    const vault = await ethers.getContractAt("TrueMultiAssetVault", VAULT_ADDRESS);
    
    // Deposit amount
    const depositAmount = ethers.parseUnits("1", 18);
    
    console.log(`Depositing: ${ethers.formatEther(depositAmount)} FLOW`);
    console.log(`To vault: ${VAULT_ADDRESS}`);
    
    try {
        // Check our balance
        const balance = await deployer.provider.getBalance(deployer.address);
        console.log(`Your FLOW balance: ${ethers.formatEther(balance)} FLOW`);
        
        if (balance < depositAmount + ethers.parseUnits("0.1", 18)) {
            throw new Error("Insufficient FLOW balance for deposit + gas");
        }
        
        // Check shares before
        const sharesBefore = await vault.balanceOf(deployer.address);
        console.log(`Vault shares before: ${ethers.formatUnits(sharesBefore, 18)}`);
        
        // Estimate gas first
        console.log("\nEstimating gas...");
        const gasEstimate = await vault.depositNativeFlow.estimateGas(deployer.address, {
            value: depositAmount
        });
        console.log(`Gas estimate: ${gasEstimate.toString()}`);
        
        // Execute deposit
        console.log("\nExecuting deposit...");
        const tx = await vault.depositNativeFlow(deployer.address, {
            value: depositAmount,
            gasLimit: gasEstimate * 120n / 100n // Add 20% buffer
        });
        
        console.log(`Transaction hash: ${tx.hash}`);
        console.log("Waiting for confirmation...");
        
        const receipt = await tx.wait();
        console.log(`Transaction confirmed in block ${receipt.blockNumber}`);
        console.log(`Gas used: ${receipt.gasUsed.toString()}`);
        
        // Check results
        const sharesAfter = await vault.balanceOf(deployer.address);
        const sharesReceived = sharesAfter - sharesBefore;
        
        console.log("\nDeposit Results:");
        console.log(`FLOW deposited: ${ethers.formatEther(depositAmount)} FLOW`);
        console.log(`Shares received: ${ethers.formatUnits(sharesReceived, 18)}`);
        console.log(`Total shares: ${ethers.formatUnits(sharesAfter, 18)}`);
        
        // Check vault state
        const assetBalance = await vault.getAssetBalance(NATIVE_FLOW);
        console.log(`Vault native FLOW balance: ${ethers.formatEther(assetBalance[0])} FLOW`);
        
    } catch (error) {
        console.error("\nDeposit failed:");
        console.error(error.message);
        
        // Check if it's a contract issue
        if (error.message.includes("execution reverted")) {
            console.log("\nDebugging the revert...");
            
            // Check if the function exists and is callable
            try {
                const code = await deployer.provider.getCode(VAULT_ADDRESS);
                if (code === "0x") {
                    console.log("ERROR: No contract found at vault address");
                } else {
                    console.log("Contract exists at vault address");
                    
                    // Check specific conditions
                    const depositsEnabled = await vault.depositsEnabled();
                    const emergencyMode = await vault.emergencyMode();
                    const assetInfo = await vault.assetInfo(NATIVE_FLOW);
                    
                    console.log(`Deposits enabled: ${depositsEnabled}`);
                    console.log(`Emergency mode: ${emergencyMode}`);
                    console.log(`Native FLOW supported: ${assetInfo.supported}`);
                    console.log(`Accepting deposits: ${assetInfo.acceptingDeposits}`);
                    console.log(`Min deposit: ${ethers.formatEther(assetInfo.minDeposit)} FLOW`);
                    console.log(`Max deposit: ${ethers.formatEther(assetInfo.maxDeposit)} FLOW`);
                    
                    if (!depositsEnabled) {
                        console.log("ISSUE: Deposits are disabled");
                    }
                    if (emergencyMode) {
                        console.log("ISSUE: Emergency mode is active");
                    }
                    if (!assetInfo.supported) {
                        console.log("ISSUE: Native FLOW not supported");
                    }
                    if (!assetInfo.acceptingDeposits) {
                        console.log("ISSUE: Native FLOW not accepting deposits");
                    }
                    if (depositAmount < assetInfo.minDeposit) {
                        console.log("ISSUE: Deposit amount below minimum");
                    }
                    if (depositAmount > assetInfo.maxDeposit) {
                        console.log("ISSUE: Deposit amount above maximum");
                    }
                }
            } catch (debugError) {
                console.log("Debug check failed:", debugError.message);
            }
        }
    }
}

main().catch(console.error);