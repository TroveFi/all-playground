const { ethers } = require("hardhat");

async function main() {
    console.log("ANKR-MORE MARKETS 2-LOOP LEVERAGE STRATEGY");
    console.log("==========================================");
    console.log("⚠️  WARNING: 2 loops = VERY HIGH liquidation risk!");
    console.log("⚠️  Expected Health Factor: ~1.15-1.20");
    console.log("");
    
    const [deployer] = await ethers.getSigners();
    console.log(`Account: ${deployer.address}`);
    
    // Contract addresses
    const FLOW_STAKING_POOL = "0xFE8189A3016cb6A3668b8ccdAC520CE572D4287a";
    const ANKR_FLOW_TOKEN = "0x1b97100eA1D7126C4d60027e231EA4CB25314bdb";
    const MORE_POOL = "0xbC92aaC2DBBF42215248B5688eB3D3d2b32F2c8d";
    const WFLOW_TOKEN = "0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e";
    
    // CONFIGURATION
    const INITIAL_FLOW = "1";
    const NUM_LOOPS = 2; // 2 COMPLETE LOOPS
    const SAFETY_BUFFER = 0.85;
    // END CONFIGURATION
    
    console.log(`Initial FLOW: ${INITIAL_FLOW}`);
    console.log(`Number of loops: ${NUM_LOOPS}`);
    console.log(`Safety buffer: ${(SAFETY_BUFFER * 100).toFixed(0)}%`);
    
    // Get contract instances
    const ankrStaking = new ethers.Contract(
        FLOW_STAKING_POOL,
        ["function stakeCerts() external payable"],
        deployer
    );
    
    const ankrFlowToken = await ethers.getContractAt([
        {"inputs":[{"internalType":"address","name":"account","type":"address"}],"name":"balanceOf","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
        {"inputs":[{"internalType":"address","name":"spender","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"approve","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},
        {"inputs":[{"internalType":"address","name":"owner","type":"address"},{"internalType":"address","name":"spender","type":"address"}],"name":"allowance","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"}
    ], ANKR_FLOW_TOKEN);
    
    const morePool = await ethers.getContractAt([
        {"inputs":[{"internalType":"address","name":"asset","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"},{"internalType":"address","name":"onBehalfOf","type":"address"},{"internalType":"uint16","name":"referralCode","type":"uint16"}],"name":"supply","outputs":[],"stateMutability":"nonpayable","type":"function"},
        {"inputs":[{"internalType":"address","name":"asset","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"},{"internalType":"uint256","name":"interestRateMode","type":"uint256"},{"internalType":"uint16","name":"referralCode","type":"uint16"},{"internalType":"address","name":"onBehalfOf","type":"address"}],"name":"borrow","outputs":[],"stateMutability":"nonpayable","type":"function"},
        {"inputs":[{"internalType":"address","name":"user","type":"address"}],"name":"getUserAccountData","outputs":[{"internalType":"uint256","name":"totalCollateralBase","type":"uint256"},{"internalType":"uint256","name":"totalDebtBase","type":"uint256"},{"internalType":"uint256","name":"availableBorrowsBase","type":"uint256"},{"internalType":"uint256","name":"currentLiquidationThreshold","type":"uint256"},{"internalType":"uint256","name":"ltv","type":"uint256"},{"internalType":"uint256","name":"healthFactor","type":"uint256"}],"stateMutability":"view","type":"function"}
    ], MORE_POOL);
    
    const wflowToken = await ethers.getContractAt([
        {"inputs":[],"name":"deposit","outputs":[],"stateMutability":"payable","type":"function"},
        {"inputs":[{"internalType":"uint256","name":"wad","type":"uint256"}],"name":"withdraw","outputs":[],"stateMutability":"nonpayable","type":"function"},
        {"inputs":[{"internalType":"address","name":"account","type":"address"}],"name":"balanceOf","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"}
    ], WFLOW_TOKEN);
    
    try {
        let totalAnkrFlowReceived = BigInt(0);
        let totalFlowBorrowed = BigInt(0);
        let totalFlowStaked = BigInt(0);
        let flowForNextLoop = ethers.parseEther(INITIAL_FLOW);
        
        // LOOP EXECUTION
        for (let loop = 0; loop < NUM_LOOPS; loop++) {
            console.log(`\n${'='.repeat(60)}`);
            console.log(`LOOP ${loop + 1} OF ${NUM_LOOPS}`);
            console.log(`${'='.repeat(60)}`);
            
            const flowToStake = flowForNextLoop;
            console.log(`\nStaking ${ethers.formatEther(flowToStake)} FLOW...`);
            
            // STEP 1: Stake FLOW
            const ankrBalanceBefore = await ankrFlowToken.balanceOf(deployer.address);
            const stakeTx = await ankrStaking.stakeCerts({ value: flowToStake, gasLimit: 500000 });
            await stakeTx.wait();
            const ankrBalanceAfter = await ankrFlowToken.balanceOf(deployer.address);
            const ankrFlowReceived = ankrBalanceAfter - ankrBalanceBefore;
            
            console.log(`✓ ankrFLOW received: ${ethers.formatEther(ankrFlowReceived)}`);
            totalAnkrFlowReceived += ankrFlowReceived;
            totalFlowStaked += flowToStake;
            
            // STEP 2: Supply ankrFLOW
            const allowance = await ankrFlowToken.allowance(deployer.address, MORE_POOL);
            if (allowance < ankrFlowReceived) {
                const approveTx = await ankrFlowToken.approve(MORE_POOL, ethers.MaxUint256);
                await approveTx.wait();
            }
            
            const supplyTx = await morePool.supply(ANKR_FLOW_TOKEN, ankrFlowReceived, deployer.address, 0);
            await supplyTx.wait();
            console.log(`✓ Supplied ${ethers.formatEther(ankrFlowReceived)} ankrFLOW`);
            
            await new Promise(resolve => setTimeout(resolve, 2000));
            const accountData = await morePool.getUserAccountData(deployer.address);
            const availableToBorrow = Number(ethers.formatUnits(accountData.availableBorrowsBase, 8));
            const healthFactor = Number(accountData.healthFactor);
            
            console.log(`Health Factor: ${healthFactor === 0 ? "∞" : (healthFactor / 1e18).toFixed(3)}`);
            console.log(`Available to borrow: $${availableToBorrow.toFixed(4)}`);
            
            // STEP 3-5: Borrow, unwrap, and prepare for next loop
            if (availableToBorrow < 0.01) {
                console.log(`Cannot continue - insufficient borrow capacity`);
                flowForNextLoop = BigInt(0);
                break;
            }
            
            const wflowToBorrow = ethers.parseEther((availableToBorrow * SAFETY_BUFFER).toFixed(18));
            const wflowBalanceBefore = await wflowToken.balanceOf(deployer.address);
            const borrowTx = await morePool.borrow(WFLOW_TOKEN, wflowToBorrow, 2, 0, deployer.address);
            await borrowTx.wait();
            const wflowBalanceAfter = await wflowToken.balanceOf(deployer.address);
            const wflowReceived = wflowBalanceAfter - wflowBalanceBefore;
            
            console.log(`✓ Borrowed ${ethers.formatEther(wflowReceived)} WFLOW`);
            
            const unwrapTx = await wflowToken.withdraw(wflowReceived);
            await unwrapTx.wait();
            console.log(`✓ Unwrapped to native FLOW`);
            
            totalFlowBorrowed = wflowReceived;
            flowForNextLoop = wflowReceived;
            
            const finalAccountData = await morePool.getUserAccountData(deployer.address);
            console.log(`Health Factor after borrow: ${(Number(finalAccountData.healthFactor) / 1e18).toFixed(3)}`);
        }
        
        // Final stake of last borrowed amount
        if (flowForNextLoop > 0) {
            console.log(`\n--- FINAL STAKE OF BORROWED FLOW ---`);
            const ankrBalanceBefore = await ankrFlowToken.balanceOf(deployer.address);
            const stakeTx = await ankrStaking.stakeCerts({ value: flowForNextLoop, gasLimit: 500000 });
            await stakeTx.wait();
            const ankrBalanceAfter = await ankrFlowToken.balanceOf(deployer.address);
            const ankrFlowReceived = ankrBalanceAfter - ankrBalanceBefore;
            
            console.log(`✓ Final ankrFLOW: ${ethers.formatEther(ankrFlowReceived)}`);
            totalAnkrFlowReceived += ankrFlowReceived;
            totalFlowStaked += flowForNextLoop;
        }
        
        // FINAL SUMMARY
        console.log(`\n${'='.repeat(60)}`);
        console.log(`FINAL 2-LOOP STRATEGY SUMMARY`);
        console.log(`${'='.repeat(60)}`);
        
        const finalAccountData = await morePool.getUserAccountData(deployer.address);
        const finalCollateral = Number(ethers.formatUnits(finalAccountData.totalCollateralBase, 8));
        const finalDebt = Number(ethers.formatUnits(finalAccountData.totalDebtBase, 8));
        const finalHealthFactor = Number(finalAccountData.healthFactor);
        const currentLeverage = finalDebt > 0 ? finalCollateral / (finalCollateral - finalDebt) : 1;
        
        console.log(`Total FLOW staked: ${ethers.formatEther(totalFlowStaked)}`);
        console.log(`Total ankrFLOW received: ${ethers.formatEther(totalAnkrFlowReceived)}`);
        console.log(`Total FLOW borrowed: ${ethers.formatEther(totalFlowBorrowed)}`);
        console.log(`Final collateral: $${finalCollateral.toFixed(4)}`);
        console.log(`Final debt: $${finalDebt.toFixed(4)}`);
        console.log(`Leverage: ${currentLeverage.toFixed(2)}x`);
        console.log(`Health Factor: ${finalHealthFactor === 0 ? "∞" : (finalHealthFactor / 1e18).toFixed(3)}`);
        
        if (finalHealthFactor < 1.3e18 && finalHealthFactor > 0) {
            console.log(`\n⚠️  CRITICAL WARNING: Health Factor below 1.3!`);
            console.log(`   Liquidation risk is VERY HIGH`);
            console.log(`   Monitor position constantly`);
        }
        
    } catch (error) {
        console.error("\n❌ STRATEGY FAILED:", error.message);
        throw error;
    }
}

main().catch(console.error);