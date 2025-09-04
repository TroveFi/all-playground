const { ethers } = require("hardhat");

// Test script for strategy allocation and deployment
async function main() {
    console.log("🧪 Testing Strategy Allocation & Fund Deployment...\n");

    // Contract addresses from deployment
    const VAULT_ADDRESS = "0x1737E0C7a84d7505ef4aAaF063E614A738fF161e";
    const ANKR_STRATEGY = "0x3f321BB2fb882427704765683a9D1482C6A7b3a1";
    const MORE_STRATEGY = "0x587b583c9b53eF839b05ec3Ece07aFEbB2235117";
    const PUNCH_STRATEGY = "0xcB050d6731278808663BbEB4B668F7dcb510B7f3";
    const STARGATE_STRATEGY = "0x79C2e9D065C1E623AFC7804083b2fC3Ee1407E25";
    const USDC_ADDRESS = "0xF1815bd50389c46847f0Bda824eC8da914045D14";

    const [deployer] = await ethers.getSigners();
    console.log("Testing with account:", deployer.address);

    // Get contract instances
    const vault = await ethers.getContractAt("FlowYieldLotteryVault", VAULT_ADDRESS);
    const usdc = await ethers.getContractAt("IERC20", USDC_ADDRESS);

    console.log("1️⃣ Testing Current Strategy Allocations...");
    try {
        const strategies = await vault.getActiveStrategies();
        console.log("Active strategies:", strategies.length);
        
        for (let strategy of strategies) {
            const info = await vault.strategies(strategy);
            console.log(`Strategy: ${info.name} | Allocation: ${info.allocation/100}% | Balance: ${ethers.formatUnits(info.currentBalance, 6)} USDC`);
        }
    } catch (error) {
        console.error("Error fetching strategies:", error.message);
    }

    console.log("\n2️⃣ Testing Strategy Rebalancing...");
    try {
        // Test rebalancing allocations (requires agent role)
        await vault.updateStrategyAllocation(ANKR_STRATEGY, 3000); // 30%
        await vault.updateStrategyAllocation(MORE_STRATEGY, 2500); // 25%
        await vault.updateStrategyAllocation(PUNCH_STRATEGY, 2500); // 25%
        await vault.updateStrategyAllocation(STARGATE_STRATEGY, 2000); // 20%
        
        console.log("✅ Successfully rebalanced strategy allocations");
        console.log("New allocations: Ankr(30%), More(25%), Punch(25%), Stargate(20%)");
    } catch (error) {
        console.error("Rebalancing failed:", error.message);
    }

    console.log("\n3️⃣ Testing Fund Deployment to Strategies...");
    
    // Check current vault balance
    try {
        const vaultBalance = await usdc.balanceOf(VAULT_ADDRESS);
        console.log(`Current vault USDC balance: ${ethers.formatUnits(vaultBalance, 6)} USDC`);
        
        if (vaultBalance > 0) {
            // Deploy funds to strategies based on allocations
            const deployAmount = vaultBalance / BigInt(4); // Deploy 25% to each strategy
            
            const strategyAddresses = [ANKR_STRATEGY, MORE_STRATEGY, PUNCH_STRATEGY, STARGATE_STRATEGY];
            const amounts = [deployAmount, deployAmount, deployAmount, deployAmount];
            
            await vault.deployToStrategies(strategyAddresses, amounts);
            console.log("✅ Successfully deployed funds to all strategies");
            console.log(`Deployed ${ethers.formatUnits(deployAmount, 6)} USDC to each strategy`);
        } else {
            console.log("⚠️ No USDC in vault to deploy. Need to deposit first.");
        }
    } catch (error) {
        console.error("Fund deployment failed:", error.message);
    }

    console.log("\n4️⃣ Testing Harvest from Strategies...");
    try {
        const strategyAddresses = [ANKR_STRATEGY, MORE_STRATEGY, PUNCH_STRATEGY, STARGATE_STRATEGY];
        
        const balanceBefore = await usdc.balanceOf(VAULT_ADDRESS);
        await vault.harvestFromStrategies(strategyAddresses);
        const balanceAfter = await usdc.balanceOf(VAULT_ADDRESS);
        
        const harvested = balanceAfter - balanceBefore;
        console.log(`✅ Harvest completed. Yield harvested: ${ethers.formatUnits(harvested, 6)} USDC`);
    } catch (error) {
        console.error("Harvest failed:", error.message);
    }

    console.log("\n5️⃣ Testing Individual Strategy Balances...");
    try {
        const strategies = [
            { name: "Ankr", address: ANKR_STRATEGY },
            { name: "More.Markets", address: MORE_STRATEGY },
            { name: "PunchSwap", address: PUNCH_STRATEGY },
            { name: "Stargate", address: STARGATE_STRATEGY }
        ];

        for (let strategy of strategies) {
            try {
                const contract = await ethers.getContractAt("MoreMarketsStrategy", strategy.address);
                const balance = await contract.getBalance();
                console.log(`${strategy.name}: ${ethers.formatUnits(balance, 6)} USDC`);
            } catch (error) {
                console.log(`${strategy.name}: Error getting balance - ${error.message}`);
            }
        }
    } catch (error) {
        console.error("Balance check failed:", error.message);
    }

    console.log("\n📊 Strategy Allocation Test Complete!");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error("Test failed:", error);
        process.exit(1);
    });