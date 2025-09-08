const { ethers } = require("hardhat");

async function main() {
    console.log("Depositing Native FLOW Directly to Multi-Asset Vault");
    console.log("====================================================");
    
    const [deployer] = await ethers.getSigners();
    
    // Contract addresses
    const VAULT_ADDRESS = "0x515f0Cef60Ed0b857425917a2a1e6e88769Aa89F";
    const NATIVE_FLOW = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";
    
    const vault = await ethers.getContractAt("TrueMultiAssetVault", VAULT_ADDRESS);
    
    // DEPOSIT EXACTLY 1 FLOW DIRECTLY
    const depositAmount = ethers.parseUnits("1", 18);
    
    // Check current native FLOW balance
    const nativeBalance = await deployer.provider.getBalance(deployer.address);
    console.log(`Your native FLOW balance: ${ethers.formatEther(nativeBalance)} FLOW`);
    console.log(`Depositing: ${ethers.formatEther(depositAmount)} FLOW`);
    
    // Reserve some FLOW for gas
    const gasReserve = ethers.parseUnits("0.1", 18);
    if (nativeBalance < depositAmount + gasReserve) {
        console.log("Insufficient FLOW balance (need extra for gas fees)");
        return;
    }
    
    // Check current vault state
    const sharesBefore = await vault.balanceOf(deployer.address);
    console.log(`Current vault shares: ${ethers.formatUnits(sharesBefore, 18)}`);
    
    try {
        // The contract has depositNativeFlow(address receiver) that calls _executeDeposit internally
        // _executeDeposit for NATIVE_FLOW expects msg.value == amount
        console.log("\nDepositing native FLOW to vault...");
        
        const depositTx = await vault.depositNativeFlow(deployer.address, { 
            value: depositAmount,
            gasLimit: 500000
        });
        const receipt = await depositTx.wait();
        
        console.log(`Deposit successful! Hash: ${receipt.hash}`);
        console.log(`Gas used: ${receipt.gasUsed.toString()}`);
        
        // Check results
        const nativeBalanceAfter = await deployer.provider.getBalance(deployer.address);
        const sharesAfter = await vault.balanceOf(deployer.address);
        const sharesReceived = sharesAfter - sharesBefore;
        const totalUsed = nativeBalance - nativeBalanceAfter;
        const gasUsed = totalUsed - depositAmount;
        
        console.log("\nResults:");
        console.log(`FLOW deposited: ${ethers.formatEther(depositAmount)} FLOW`);
        console.log(`Gas used: ${ethers.formatEther(gasUsed)} FLOW`);
        console.log(`Shares received: ${ethers.formatUnits(sharesReceived, 18)}`);
        console.log(`Remaining FLOW: ${ethers.formatEther(nativeBalanceAfter)} FLOW`);
        
        // Check vault metrics
        const vaultMetrics = await vault.getVaultMetrics();
        console.log(`Vault TVL: $${ethers.formatUnits(vaultMetrics[0], 6)}`);
        
    } catch (error) {
        console.log(`\nOperation failed: ${error.message}`);
        
        // Let's debug what's actually happening
        console.log("\nDebugging contract state...");
        
        try {
            // Check if deposits are actually enabled
            const depositsEnabled = await vault.depositsEnabled();
            console.log(`Deposits enabled: ${depositsEnabled}`);
            
            // Check if emergency mode is active
            const emergencyMode = await vault.emergencyMode();
            console.log(`Emergency mode: ${emergencyMode}`);
            
            // Check native FLOW asset info more carefully
            const assetInfo = await vault.assetInfo(NATIVE_FLOW);
            console.log(`Native FLOW supported: ${assetInfo.supported}`);
            console.log(`Accepting deposits: ${assetInfo.acceptingDeposits}`);
            console.log(`Min deposit: ${ethers.formatEther(assetInfo.minDeposit)}`);
            
            // Check if we can call the contract at all
            const totalSupply = await vault.totalSupply();
            console.log(`Vault total supply: ${ethers.formatUnits(totalSupply, 18)}`);
            
        } catch (debugError) {
            console.log(`Debug failed: ${debugError.message}`);
        }
        
        // Alternative: Try the depositNativeFlowAsWFlow function
        console.log("\nTrying alternative: depositNativeFlowAsWFlow...");
        try {
            const altTx = await vault.depositNativeFlowAsWFlow(deployer.address, { 
                value: depositAmount,
                gasLimit: 500000
            });
            const altReceipt = await altTx.wait();
            
            console.log(`Alternative deposit successful! Hash: ${altReceipt.hash}`);
            
            const sharesAfter = await vault.balanceOf(deployer.address);
            const sharesReceived = sharesAfter - sharesBefore;
            console.log(`Shares received: ${ethers.formatUnits(sharesReceived, 18)}`);
            
        } catch (altError) {
            console.log(`Alternative also failed: ${altError.message}`);
            
            // Final fallback: Use the regular WFLOW deposit method
            console.log("\nFinal fallback: Manual WFLOW wrapping...");
            try {
                const WFLOW_ADDRESS = "0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e";
                
                // Get WFLOW contract
                const wflowABI = [
                    "function deposit() external payable",
                    "function approve(address spender, uint256 amount) external returns (bool)",
                    "function balanceOf(address owner) view returns (uint256)"
                ];
                const wflow = new ethers.Contract(WFLOW_ADDRESS, wflowABI, deployer);
                
                // Wrap FLOW to WFLOW
                console.log("Wrapping FLOW to WFLOW...");
                const wrapTx = await wflow.deposit({ value: depositAmount });
                await wrapTx.wait();
                
                // Approve WFLOW to vault
                console.log("Approving WFLOW...");
                const approveTx = await wflow.approve(VAULT_ADDRESS, depositAmount);
                await approveTx.wait();
                
                // Deposit WFLOW
                console.log("Depositing WFLOW...");
                const depositTx = await vault.deposit(WFLOW_ADDRESS, depositAmount, deployer.address);
                const receipt = await depositTx.wait();
                
                console.log(`Fallback deposit successful! Hash: ${receipt.hash}`);
                
                const sharesAfter = await vault.balanceOf(deployer.address);
                const sharesReceived = sharesAfter - sharesBefore;
                console.log(`Shares received: ${ethers.formatUnits(sharesReceived, 18)}`);
                
            } catch (fallbackError) {
                console.log(`All methods failed: ${fallbackError.message}`);
            }
        }
    }
}

main().catch(console.error);