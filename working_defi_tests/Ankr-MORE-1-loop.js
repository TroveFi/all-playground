const { ethers } = require("hardhat");

async function main() {
    console.log("ANKR-MORE MARKETS LEVERAGE LOOP STRATEGY");
    console.log("========================================");
    
    const [deployer] = await ethers.getSigners();
    console.log(`Account: ${deployer.address}`);
    
    // Contract addresses
    const FLOW_STAKING_POOL = "0xFE8189A3016cb6A3668b8ccdAC520CE572D4287a";
    const ANKR_FLOW_TOKEN = "0x1b97100eA1D7126C4d60027e231EA4CB25314bdb";
    const MORE_POOL = "0xbC92aaC2DBBF42215248B5688eB3D3d2b32F2c8d";
    const WFLOW_TOKEN = "0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e";
    
    // CONFIGURATION
    const INITIAL_FLOW = "1"; // Initial FLOW to stake
    const NUM_LOOPS = 1; // Number of leverage loops
    const SAFETY_BUFFER = 0.85; // Use 85% of available borrow capacity
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
    
    // Get UI Pool Data Provider for APYs
    const uiProvider = await ethers.getContractAt([
        {"inputs":[{"internalType":"contract IPoolAddressesProvider","name":"provider","type":"address"}],"name":"getReservesData","outputs":[{"components":[{"internalType":"address","name":"underlyingAsset","type":"address"},{"internalType":"string","name":"symbol","type":"string"},{"internalType":"uint128","name":"liquidityRate","type":"uint128"},{"internalType":"uint128","name":"variableBorrowRate","type":"uint128"}],"internalType":"struct IUiPoolDataProviderV3.AggregatedReserveData[]","name":"","type":"tuple[]"},{"components":[{"internalType":"uint256","name":"marketReferenceCurrencyUnit","type":"uint256"},{"internalType":"int256","name":"marketReferenceCurrencyPriceInUsd","type":"int256"}],"internalType":"struct IUiPoolDataProviderV3.BaseCurrencyInfo","name":"","type":"tuple"}],"stateMutability":"view","type":"function"}
    ], "0x2148e6253b23122Ee78B3fa6DcdDbefae426EB78");
    
    try {
        // Variables to track throughout loops
        let totalAnkrFlowReceived = BigInt(0);
        let totalFlowBorrowed = BigInt(0);
        let totalFlowStaked = BigInt(0);
        
        console.log("\n=== GETTING MARKET DATA ===");
        const [reservesData] = await uiProvider.getReservesData("0x1830a96466d1d108935865c75B0a9548681Cfd9A");
        const RAY = BigInt("1000000000000000000000000000");
        
        let ankrFlowSupplyAPY = "Can't get";
        let flowBorrowAPY = "Can't get";
        
        for (const reserve of reservesData) {
            if (reserve.symbol === "ankrFLOWEVM") {
                ankrFlowSupplyAPY = ((Number(reserve.liquidityRate) / Number(RAY)) * 100).toFixed(2);
            } else if (reserve.symbol === "FLOW") {
                flowBorrowAPY = ((Number(reserve.variableBorrowRate) / Number(RAY)) * 100).toFixed(2);
            }
        }
        
        console.log(`Ankr Staking APY: Can't get from contract (check ankr.com)`);
        console.log(`ankrFLOW Supply APY (MORE): ${ankrFlowSupplyAPY}%`);
        console.log(`FLOW Borrow APY (MORE): ${flowBorrowAPY}%`);
        
        // LOOP EXECUTION
        for (let loop = 0; loop < NUM_LOOPS; loop++) {
            console.log(`\n${'='.repeat(60)}`);
            console.log(`LOOP ${loop + 1} OF ${NUM_LOOPS}`);
            console.log(`${'='.repeat(60)}`);
            
            let flowToStake;
            if (loop === 0) {
                flowToStake = ethers.parseEther(INITIAL_FLOW);
                console.log(`\nUsing initial FLOW: ${INITIAL_FLOW}`);
            } else {
                flowToStake = totalFlowBorrowed;
                console.log(`\nUsing borrowed FLOW from previous loop: ${ethers.formatEther(flowToStake)}`);
            }
            
            // STEP 1: Stake FLOW to get ankrFLOW
            console.log(`\n--- STEP 1: STAKE FLOW WITH ANKR ---`);
            console.log(`Staking ${ethers.formatEther(flowToStake)} FLOW...`);
            
            const ankrBalanceBefore = await ankrFlowToken.balanceOf(deployer.address);
            
            const stakeTx = await ankrStaking.stakeCerts({
                value: flowToStake,
                gasLimit: 500000
            });
            console.log(`Stake tx: ${stakeTx.hash}`);
            await stakeTx.wait();
            
            const ankrBalanceAfter = await ankrFlowToken.balanceOf(deployer.address);
            const ankrFlowReceived = ankrBalanceAfter - ankrBalanceBefore;
            
            console.log(`✓ ankrFLOW received: ${ethers.formatEther(ankrFlowReceived)}`);
            const exchangeRate = Number(flowToStake) / Number(ankrFlowReceived);
            console.log(`  Exchange rate: ${exchangeRate.toFixed(6)} FLOW per ankrFLOW`);
            
            totalAnkrFlowReceived += ankrFlowReceived;
            totalFlowStaked += flowToStake;
            
            // STEP 2: Supply ankrFLOW to MORE Markets
            console.log(`\n--- STEP 2: SUPPLY ankrFLOW TO MORE MARKETS ---`);
            
            // Approve MORE pool
            const allowance = await ankrFlowToken.allowance(deployer.address, MORE_POOL);
            if (allowance < ankrFlowReceived) {
                console.log(`Approving ankrFLOW...`);
                const approveTx = await ankrFlowToken.approve(MORE_POOL, ethers.MaxUint256);
                await approveTx.wait();
            }
            
            console.log(`Supplying ${ethers.formatEther(ankrFlowReceived)} ankrFLOW...`);
            const supplyTx = await morePool.supply(
                ANKR_FLOW_TOKEN,
                ankrFlowReceived,
                deployer.address,
                0
            );
            console.log(`Supply tx: ${supplyTx.hash}`);
            await supplyTx.wait();
            console.log(`✓ ankrFLOW supplied to MORE Markets`);
            
            // Check position after supply
            await new Promise(resolve => setTimeout(resolve, 2000));
            const accountData = await morePool.getUserAccountData(deployer.address);
            
            const totalCollateral = Number(ethers.formatUnits(accountData.totalCollateralBase, 8));
            const totalDebt = Number(ethers.formatUnits(accountData.totalDebtBase, 8));
            const availableToBorrow = Number(ethers.formatUnits(accountData.availableBorrowsBase, 8));
            const healthFactor = Number(accountData.healthFactor);
            
            console.log(`\nMORE Markets Position:`);
            console.log(`  Collateral: $${totalCollateral.toFixed(4)}`);
            console.log(`  Debt: $${totalDebt.toFixed(4)}`);
            console.log(`  Available to borrow: $${availableToBorrow.toFixed(4)}`);
            console.log(`  Health Factor: ${healthFactor === 0 ? "∞" : (healthFactor / 1e18).toFixed(3)}`);
            
            // STEP 3: Borrow WFLOW from MORE Markets
            console.log(`\n--- STEP 3: BORROW WFLOW FROM MORE MARKETS ---`);
            
            if (availableToBorrow < 0.01) {
                console.log(`Cannot borrow - available amount too low: $${availableToBorrow.toFixed(4)}`);
                totalFlowBorrowed = BigInt(0);
            } else {
                const safeBorrowUSD = availableToBorrow * SAFETY_BUFFER;
                // Assume 1:1 WFLOW to USD
                const wflowToBorrow = ethers.parseEther(safeBorrowUSD.toFixed(18));
                
                console.log(`Borrowing ${ethers.formatEther(wflowToBorrow)} WFLOW...`);
                
                const wflowBalanceBefore = await wflowToken.balanceOf(deployer.address);
                
                const borrowTx = await morePool.borrow(
                    WFLOW_TOKEN,
                    wflowToBorrow,
                    2, // Variable rate
                    0,
                    deployer.address
                );
                console.log(`Borrow tx: ${borrowTx.hash}`);
                await borrowTx.wait();
                
                const wflowBalanceAfter = await wflowToken.balanceOf(deployer.address);
                const wflowReceived = wflowBalanceAfter - wflowBalanceBefore;
                
                console.log(`✓ WFLOW received: ${ethers.formatEther(wflowReceived)}`);
                
                // STEP 4: Unwrap WFLOW to native FLOW
                console.log(`\n--- STEP 4: UNWRAP WFLOW TO NATIVE FLOW ---`);
                console.log(`Unwrapping ${ethers.formatEther(wflowReceived)} WFLOW...`);
                
                const unwrapTx = await wflowToken.withdraw(wflowReceived);
                await unwrapTx.wait();
                console.log(`✓ Unwrapped to native FLOW`);
                
                totalFlowBorrowed = wflowReceived;
                
                // Check final position
                const finalAccountData = await morePool.getUserAccountData(deployer.address);
                console.log(`\nPosition after borrow:`);
                console.log(`  Total Debt: $${ethers.formatUnits(finalAccountData.totalDebtBase, 8)}`);
                console.log(`  Health Factor: ${Number(finalAccountData.healthFactor) === 0 ? "∞" : (Number(finalAccountData.healthFactor) / 1e18).toFixed(3)}`);
            }
            
            // STEP 5: Stake borrowed FLOW again (completing the loop)
            if (totalFlowBorrowed > 0) {
                console.log(`\n--- STEP 5: STAKE BORROWED FLOW WITH ANKR (COMPLETING LOOP) ---`);
                console.log(`Staking ${ethers.formatEther(totalFlowBorrowed)} borrowed FLOW...`);
                
                const ankrBalanceBefore2 = await ankrFlowToken.balanceOf(deployer.address);
                
                const stakeTx2 = await ankrStaking.stakeCerts({
                    value: totalFlowBorrowed,
                    gasLimit: 500000
                });
                console.log(`Stake tx: ${stakeTx2.hash}`);
                await stakeTx2.wait();
                
                const ankrBalanceAfter2 = await ankrFlowToken.balanceOf(deployer.address);
                const ankrFlowReceived2 = ankrBalanceAfter2 - ankrBalanceBefore2;
                
                console.log(`✓ ankrFLOW received: ${ethers.formatEther(ankrFlowReceived2)}`);
                const exchangeRate2 = Number(totalFlowBorrowed) / Number(ankrFlowReceived2);
                console.log(`  Exchange rate: ${exchangeRate2.toFixed(6)} FLOW per ankrFLOW`);
                
                totalAnkrFlowReceived += ankrFlowReceived2;
                totalFlowStaked += totalFlowBorrowed;
                
                console.log(`\n=== LOOP ${loop + 1} COMPLETE ===`);
                console.log(`Step 1: Staked ${ethers.formatEther(flowToStake)} FLOW → got ${ethers.formatEther(ankrFlowReceived)} ankrFLOW`);
                console.log(`Step 2: Supplied ${ethers.formatEther(ankrFlowReceived)} ankrFLOW to MORE`);
                console.log(`Step 3: Borrowed ${ethers.formatEther(totalFlowBorrowed)} WFLOW from MORE`);
                console.log(`Step 4: Unwrapped to ${ethers.formatEther(totalFlowBorrowed)} native FLOW`);
                console.log(`Step 5: Staked ${ethers.formatEther(totalFlowBorrowed)} FLOW → got ${ethers.formatEther(ankrFlowReceived2)} ankrFLOW`);
            } else {
                console.log(`\n=== LOOP ${loop + 1} INCOMPLETE ===`);
                console.log(`Could not complete loop - insufficient borrowing capacity`);
            }
        }
        
        // FINAL SUMMARY
        console.log(`\n${'='.repeat(60)}`);
        console.log(`FINAL STRATEGY SUMMARY`);
        console.log(`${'='.repeat(60)}`);
        
        const finalAccountData = await morePool.getUserAccountData(deployer.address);
        const finalCollateral = Number(ethers.formatUnits(finalAccountData.totalCollateralBase, 8));
        const finalDebt = Number(ethers.formatUnits(finalAccountData.totalDebtBase, 8));
        const finalHealthFactor = Number(finalAccountData.healthFactor);
        const currentLeverage = finalDebt > 0 ? finalCollateral / (finalCollateral - finalDebt) : 1;
        
        console.log(`\nPOSITION METRICS:`);
        console.log(`Total FLOW staked: ${ethers.formatEther(totalFlowStaked)}`);
        console.log(`Total ankrFLOW received: ${ethers.formatEther(totalAnkrFlowReceived)}`);
        console.log(`Total FLOW borrowed: ${ethers.formatEther(totalFlowBorrowed)}`);
        console.log(`Final collateral: $${finalCollateral.toFixed(4)}`);
        console.log(`Final debt: $${finalDebt.toFixed(4)}`);
        console.log(`Current leverage: ${currentLeverage.toFixed(2)}x`);
        console.log(`Health Factor: ${finalHealthFactor === 0 ? "∞" : (finalHealthFactor / 1e18).toFixed(3)}`);
        
        console.log(`\nYIELD BREAKDOWN:`);
        console.log(`1. Ankr Staking APY: Can't get (check ankr.com)`);
        console.log(`   Applied to: ${ethers.formatEther(totalAnkrFlowReceived)} ankrFLOW`);
        console.log(`2. MORE Supply APY: ${ankrFlowSupplyAPY}%`);
        console.log(`   Applied to: ${ethers.formatEther(totalAnkrFlowReceived)} ankrFLOW`);
        console.log(`3. MORE Borrow APY: -${flowBorrowAPY}%`);
        console.log(`   Applied to: ${ethers.formatEther(totalFlowBorrowed)} FLOW`);
        
        console.log(`\nNET APY CALCULATION:`);
        console.log(`To calculate manually with Ankr APY from ankr.com (e.g., 7.87%):`);
        console.log(`Formula: (AnkrAPY * ${ethers.formatEther(totalAnkrFlowReceived)}) + (${ankrFlowSupplyAPY}% * ${ethers.formatEther(totalAnkrFlowReceived)}) - (${flowBorrowAPY}% * ${ethers.formatEther(totalFlowBorrowed)})`);
        
        console.log(`\nRISK METRICS:`);
        console.log(`Liquidation risk: ${finalHealthFactor < 1.5e18 ? "HIGH" : finalHealthFactor < 2e18 ? "MEDIUM" : "LOW"}`);
        console.log(`Health Factor: ${finalHealthFactor === 0 ? "∞" : (finalHealthFactor / 1e18).toFixed(3)}`);
        
        console.log(`\nLOOP EFFICIENCY:`);
        const efficiency = (Number(totalAnkrFlowReceived) / Number(totalFlowStaked)) * 100;
        console.log(`Total FLOW → ankrFLOW efficiency: ${efficiency.toFixed(2)}%`);
        
    } catch (error) {
        console.error("\n❌ STRATEGY FAILED:");
        console.error(error.message);
        throw error;
    }
}

main().catch(console.error);