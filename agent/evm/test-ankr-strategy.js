const { ethers } = require("hardhat");
const fs = require("fs");

async function main() {
    console.log("Testing Ankr Staking Strategy");
    console.log("==============================\n");
    
    const [agent] = await ethers.getSigners();
    console.log(`Agent: ${agent.address}`);
    
    // Load deployment info
    const deploymentInfo = JSON.parse(fs.readFileSync("deployment-info.json", "utf8"));
    const vaultAddress = deploymentInfo.contracts.vaultCore;
    const ankrStrategyAddress = deploymentInfo.contracts.ankrStaking;
    
    console.log(`Vault: ${vaultAddress}`);
    console.log(`AnkrStrategy: ${ankrStrategyAddress}\n`);
    
    const vault = await ethers.getContractAt("TrueMultiAssetVaultCore", vaultAddress);
    const ankrStrategy = await ethers.getContractAt("AnkrStakingStrategy", ankrStrategyAddress);
    
    const NATIVE_FLOW = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";
    const ANKR_FLOW = "0x1b97100eA1D7126C4d60027e231EA4CB25314bdb";
    
    try {
        // Step 1: Check vault balance
        console.log("STEP 1: Checking vault balance");
        console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        
        const [vaultBalance, strategyBalance, cadenceBalance, totalBalance] = 
            await vault.getAssetBalance(NATIVE_FLOW);
        
        console.log(`Vault FLOW balance: ${ethers.formatEther(vaultBalance)}`);
        console.log(`Strategy balance: ${ethers.formatEther(strategyBalance)}`);
        console.log(`Total balance: ${ethers.formatEther(totalBalance)}\n`);
        
        if (vaultBalance < ethers.parseEther("0.1")) {
            console.log("❌ Insufficient vault balance. Deposit FLOW first.");
            return;
        }
        
        // Step 2: Execute strategy
        console.log("STEP 2: Executing Ankr staking strategy");
        console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        
        const amountToStake = ethers.parseEther("0.5"); // Stake 0.5 FLOW
        
        console.log(`Staking ${ethers.formatEther(amountToStake)} FLOW via strategy...`);
        
        const tx = await vault.executeStrategy(
            ankrStrategyAddress,
            NATIVE_FLOW,
            amountToStake,
            "0x" // empty data
        );
        
        console.log(`Transaction: ${tx.hash}`);
        const receipt = await tx.wait();
        console.log(`✅ Strategy executed! Gas used: ${receipt.gasUsed}\n`);
        
        // Step 3: Check strategy balance
        console.log("STEP 3: Checking strategy results");
        console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        
        const ankrToken = await ethers.getContractAt("IERC20", ANKR_FLOW);
        const ankrBalance = await ankrToken.balanceOf(ankrStrategyAddress);
        
        console.log(`ankrFLOW received: ${ethers.formatEther(ankrBalance)}`);
        
        const [totalStaked, totalAnkrReceived, currentAnkrBalance, exchangeRate] = 
            await ankrStrategy.getStakingMetrics();
        
        console.log(`\nStaking Metrics:`);
        console.log(`  Total FLOW staked: ${ethers.formatEther(totalStaked)}`);
        console.log(`  Total ankrFLOW received: ${ethers.formatEther(totalAnkrReceived)}`);
        console.log(`  Current ankrFLOW balance: ${ethers.formatEther(currentAnkrBalance)}`);
        console.log(`  Exchange rate: ${ethers.formatEther(exchangeRate)} FLOW per ankrFLOW\n`);
        
        // Step 4: Harvest (return ankrFLOW to vault)
        console.log("STEP 4: Harvesting ankrFLOW back to vault");
        console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        
        const harvestTx = await vault.harvestStrategy(ankrStrategyAddress, "0x");
        await harvestTx.wait();
        console.log("✅ Harvest complete!\n");
        
        // Step 5: Check vault metrics
        console.log("STEP 5: Final vault state");
        console.log("━━━━━━━━━━━━━━━━━━━━━━━━");
        
        const [
            tvl,
            totalUsers,
            totalSupply,
            totalPrincipal,
            totalYieldGenerated
        ] = await vault.getVaultMetrics();
        
        console.log(`Vault Metrics:`);
        console.log(`  TVL: $${ethers.formatUnits(tvl, 6)}`);
        console.log(`  Total Users: ${totalUsers}`);
        console.log(`  Total Supply: ${ethers.formatEther(totalSupply)}`);
        console.log(`  Total Principal: ${ethers.formatEther(totalPrincipal)}`);
        console.log(`  Total Yield Generated: ${ethers.formatEther(totalYieldGenerated)}\n`);
        
        console.log("✅ ALL TESTS PASSED!");
        
    } catch (error) {
        console.error("❌ Test failed:", error.message);
        throw error;
    }
}

main().catch(console.error);