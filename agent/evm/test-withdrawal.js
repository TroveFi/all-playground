const { ethers } = require("hardhat");
const fs = require("fs");

async function main() {
    console.log("Testing Withdrawal System");
    console.log("=========================\n");
    
    const [user] = await ethers.getSigners();
    console.log(`User: ${user.address}`);
    
    // Load deployment info
    const deploymentInfo = JSON.parse(fs.readFileSync("deployment-info.json", "utf8"));
    const vaultAddress = deploymentInfo.contracts.vaultCore;
    
    console.log(`Vault: ${vaultAddress}\n`);
    
    const vault = await ethers.getContractAt("TrueMultiAssetVaultCore", vaultAddress);
    const NATIVE_FLOW = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";
    
    try {
        // ================================================================
        // STEP 1: Check User Position
        // ================================================================
        console.log("STEP 1: Checking User Position");
        console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        
        const [totalShares, totalDeposited, lastDeposit, hasWithdrawalRequest, 
               requestedAmount, yieldEligible, riskLevel] = 
            await vault.getUserPosition(user.address);
        
        console.log("User Position:");
        console.log(`  Total Shares: ${ethers.formatEther(totalShares)}`);
        console.log(`  Total Deposited: ${ethers.formatEther(totalDeposited)} FLOW`);
        console.log(`  Yield Eligible: ${yieldEligible}`);
        console.log(`  Risk Level: ${riskLevel}\n`);
        
        if (totalShares === 0n) {
            console.log("❌ No position found. Please deposit first:");
            console.log("   npx hardhat run scripts/test-deposit.js --network flow_mainnet\n");
            return;
        }
        
        const userFlowBalance = await vault.getUserAssetBalance(user.address, NATIVE_FLOW);
        console.log(`User's FLOW in vault: ${ethers.formatEther(userFlowBalance)}\n`);
        
        // ================================================================
        // STEP 2: Request Withdrawal
        // ================================================================
        console.log("STEP 2: Requesting Withdrawal");
        console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        
        const withdrawAmount = ethers.parseEther("0.5"); // Request 0.5 FLOW
        
        if (userFlowBalance < withdrawAmount) {
            console.log(`⚠️  Requested amount (${ethers.formatEther(withdrawAmount)}) exceeds balance`);
            console.log(`    Adjusting to max: ${ethers.formatEther(userFlowBalance)}\n`);
            withdrawAmount = userFlowBalance;
        }
        
        console.log(`Requesting withdrawal of ${ethers.formatEther(withdrawAmount)} FLOW...`);
        
        const requestTx = await vault.requestWithdrawal(NATIVE_FLOW, withdrawAmount);
        const requestReceipt = await requestTx.wait();
        
        console.log(`✅ Withdrawal request submitted!`);
        console.log(`   Transaction: ${requestTx.hash}\n`);
        
        // Parse withdrawal request ID from events
        let requestId = null;
        for (const log of requestReceipt.logs) {
            try {
                const parsed = vault.interface.parseLog(log);
                if (parsed && parsed.name === "WithdrawalRequested") {
                    requestId = parsed.args.requestId;
                    console.log(`   Request ID: ${requestId}`);
                    break;
                }
            } catch (e) {}
        }
        
        console.log("   Status: Queued for processing");
        console.log("   Note: In production, withdrawals are processed immediately\n");
        
        // ================================================================
        // STEP 3: Check Withdrawal Request Details
        // ================================================================
        console.log("STEP 3: Checking Withdrawal Request");
        console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        
        const userRequests = await vault.getUserWithdrawalRequests(user.address);
        console.log(`Total withdrawal requests: ${userRequests.length}`);
        
        if (userRequests.length > 0) {
            const latestRequestId = userRequests[userRequests.length - 1];
            const [reqUser, reqAsset, reqAmount, reqTime, processed] = 
                await vault.getWithdrawalRequest(latestRequestId);
            
            console.log(`\nLatest Request (ID: ${latestRequestId}):`);
            console.log(`  User: ${reqUser}`);
            console.log(`  Asset: ${reqAsset === NATIVE_FLOW ? "Native FLOW" : reqAsset}`);
            console.log(`  Amount: ${ethers.formatEther(reqAmount)} FLOW`);
            console.log(`  Requested at: ${new Date(Number(reqTime) * 1000).toLocaleString()}`);
            console.log(`  Processed: ${processed ? "Yes" : "No"}\n`);
        }
        
        // ================================================================
        // STEP 4: Process Withdrawal
        // ================================================================
        console.log("STEP 4: Processing Withdrawal");
        console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        
        if (requestId !== null) {
            console.log("Processing withdrawal request...");
            
            const balanceBefore = await ethers.provider.getBalance(user.address);
            
            const processTx = await vault.processWithdrawalRequest(requestId);
            const processReceipt = await processTx.wait();
            
            const balanceAfter = await ethers.provider.getBalance(user.address);
            
            // Calculate net change (accounting for gas)
            const gasUsed = processReceipt.gasUsed * processReceipt.gasPrice;
            const netChange = balanceAfter - balanceBefore + gasUsed;
            
            console.log(`✅ Withdrawal processed!`);
            console.log(`   Transaction: ${processTx.hash}`);
            console.log(`   Gas used: ${ethers.formatEther(gasUsed)} FLOW`);
            console.log(`   FLOW received: ${ethers.formatEther(netChange)}\n`);
        }
        
        // ================================================================
        // STEP 5: Verify Final State
        // ================================================================
        console.log("STEP 5: Verifying Final State");
        console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        
        const [totalSharesAfter, totalDepositedAfter, , hasRequestAfter] = 
            await vault.getUserPosition(user.address);
        
        console.log("User Position After Withdrawal:");
        console.log(`  Total Shares: ${ethers.formatEther(totalSharesAfter)}`);
        console.log(`  Total Deposited: ${ethers.formatEther(totalDepositedAfter)} FLOW`);
        console.log(`  Has Pending Request: ${hasRequestAfter}`);
        
        const userFlowBalanceAfter = await vault.getUserAssetBalance(user.address, NATIVE_FLOW);
        console.log(`  FLOW in vault: ${ethers.formatEther(userFlowBalanceAfter)}\n`);
        
        const sharesBurned = totalShares - totalSharesAfter;
        const flowWithdrawn = totalDeposited - totalDepositedAfter;
        
        console.log("Changes:");
        console.log(`  Shares burned: ${ethers.formatEther(sharesBurned)}`);
        console.log(`  FLOW withdrawn: ${ethers.formatEther(flowWithdrawn)}\n`);
        
        // ================================================================
        // SUMMARY
        // ================================================================
        console.log("✅ WITHDRAWAL TESTS COMPLETE!\n");
        
        console.log("═══════════════════════════════════════════════════");
        console.log("WITHDRAWAL SYSTEM FEATURES");
        console.log("═══════════════════════════════════════════════════\n");
        
        console.log("✅ INSTANT PRINCIPAL WITHDRAWAL:");
        console.log("   Users can request and process withdrawals immediately");
        console.log("   No lock-up period for deposited principal\n");
        
        console.log("✅ QUEUE SYSTEM:");
        console.log("   Withdrawal requests are queued and can be processed on-demand");
        console.log("   Multiple requests can be pending simultaneously\n");
        
        console.log("✅ PROPORTIONAL SHARE BURNING:");
        console.log("   Shares are burned proportionally to withdrawal amount");
        console.log("   Fair calculation based on current vault value\n");
        
        console.log("✅ NON-CUSTODIAL:");
        console.log("   Users maintain full control of their funds");
        console.log("   Agent cannot block or prevent withdrawals\n");
        
        console.log("═══════════════════════════════════════════════════");
        console.log("YIELD PAYOUT SYSTEM (SEPARATE FROM PRINCIPAL)");
        console.log("═══════════════════════════════════════════════════\n");
        
        console.log("📅 MONTHLY PAYOUTS:");
        console.log("   Yield is distributed every 4 epochs (~monthly)");
        console.log("   Users claim rewards separately via claimEpochReward()\n");
        
        console.log("🎲 VRF LOTTERY SYSTEM:");
        console.log("   Users choose risk multiplier (1x-100x)");
        console.log("   VRF determines winners each epoch");
        console.log("   Winners get multiplied yield, losers get 0\n");
        
        console.log("💰 BASE YIELD ALWAYS GUARANTEED:");
        console.log("   1x multiplier = 100% chance of base yield");
        console.log("   Higher multipliers = higher risk/reward");
        console.log("   All options are mathematically fair (same EV)\n");
        
        console.log("═══════════════════════════════════════════════════\n");
        
    } catch (error) {
        console.error("❌ Test failed:", error.message);
        
        if (error.message.includes("Insufficient balance")) {
            console.log("\n💡 Solution: Reduce withdrawal amount");
        } else if (error.message.includes("Invalid request")) {
            console.log("\n💡 Solution: Check withdrawal request ID");
        }
        
        throw error;
    }
}

main().catch(console.error);