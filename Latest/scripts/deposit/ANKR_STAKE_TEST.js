const { ethers } = require("hardhat");

async function main() {
    console.log("TESTING ANKR STAKING POOL INTERFACE");
    console.log("===================================");
    
    const [deployer] = await ethers.getSigners();
    
    // Contract addresses
    const FLOW_STAKING_POOL_ADDRESS = "0xFE8189A3016cb6A3668b8ccdAC520CE572D4287a";
    const ANKR_FLOW_TOKEN_ADDRESS = "0x1b97100eA1D7126C4d60027e231EA4CB25314bdb";
    
    // Test amount
    const testAmount = ethers.parseUnits("1", 18); // 1 FLOW
    
    console.log(`Testing with ${ethers.formatUnits(testAmount, 18)} FLOW`);
    console.log(`From account: ${deployer.address}`);
    
    try {
        // Get initial balances
        const initialFlow = await ethers.provider.getBalance(deployer.address);
        const ankrFlowToken = await ethers.getContractAt("IERC20", ANKR_FLOW_TOKEN_ADDRESS);
        const initialAnkrFlow = await ankrFlowToken.balanceOf(deployer.address);
        
        console.log(`\nInitial balances:`);
        console.log(`FLOW: ${ethers.formatEther(initialFlow)}`);
        console.log(`ankrFLOW: ${ethers.formatUnits(initialAnkrFlow, 18)}`);
        
        // Create contract instance with the known functions
        const stakingPool = new ethers.Contract(
            FLOW_STAKING_POOL_ADDRESS,
            [
                "function getMinStake() external view returns (uint256)",
                "function getFreeBalance() external view returns (uint256)",
                "function stakeBonds() external payable",
                "function stakeBondsWithCode(string calldata code) external payable",
                "function stakeCerts() external payable", 
                "function stakeCertsWithCode(string calldata code) external payable",
                "function getTokens() external view returns (address, address)"
            ],
            deployer
        );
        
        // Check pool status
        console.log(`\nPool status:`);
        try {
            const minStake = await stakingPool.getMinStake();
            console.log(`Min stake: ${ethers.formatUnits(minStake, 18)} FLOW`);
        } catch (e) {
            console.log(`Min stake: Could not fetch`);
        }
        
        try {
            const freeBalance = await stakingPool.getFreeBalance();
            console.log(`Pool free balance: ${ethers.formatUnits(freeBalance, 18)} FLOW`);
        } catch (e) {
            console.log(`Pool free balance: Could not fetch`);
        }
        
        try {
            const tokens = await stakingPool.getTokens();
            console.log(`Pool tokens: ${tokens[0]}, ${tokens[1]}`);
        } catch (e) {
            console.log(`Pool tokens: Could not fetch`);
        }
        
        // Test different staking methods
        console.log(`\nTesting staking methods:`);
        
        // Method 1: Try stakeCerts (most common for liquid staking)
        console.log(`\n1. Testing stakeCerts()...`);
        try {
            const stakeTx = await stakingPool.stakeCerts({
                value: testAmount,
                gasLimit: 500000
            });
            
            console.log(`stakeCerts transaction: ${stakeTx.hash}`);
            const receipt = await stakeTx.wait();
            console.log(`✅ stakeCerts SUCCESS!`);
            console.log(`Gas used: ${receipt.gasUsed.toString()}`);
            
            // Check new balances
            const newAnkrFlow = await ankrFlowToken.balanceOf(deployer.address);
            const received = newAnkrFlow - initialAnkrFlow;
            console.log(`ankrFLOW received: ${ethers.formatUnits(received, 18)}`);
            
            if (received > 0) {
                console.log(`\n🎉 SOLUTION FOUND: Use stakeCerts() function!`);
                return "stakeCerts";
            }
            
        } catch (error) {
            console.log(`❌ stakeCerts failed: ${error.message.split('(')[0]}`);
        }
        
        // Method 2: Try stakeBonds
        console.log(`\n2. Testing stakeBonds()...`);
        try {
            const stakeTx = await stakingPool.stakeBonds({
                value: testAmount,
                gasLimit: 500000
            });
            
            console.log(`stakeBonds transaction: ${stakeTx.hash}`);
            const receipt = await stakeTx.wait();
            console.log(`✅ stakeBonds SUCCESS!`);
            
            // Check new balances
            const newAnkrFlow = await ankrFlowToken.balanceOf(deployer.address);
            const received = newAnkrFlow - initialAnkrFlow;
            console.log(`ankrFLOW received: ${ethers.formatUnits(received, 18)}`);
            
            if (received > 0) {
                console.log(`\n🎉 SOLUTION FOUND: Use stakeBonds() function!`);
                return "stakeBonds";
            }
            
        } catch (error) {
            console.log(`❌ stakeBonds failed: ${error.message.split('(')[0]}`);
        }
        
        // Method 3: Try low-level call (current strategy method)
        console.log(`\n3. Testing low-level call (current strategy method)...`);
        try {
            const tx = await deployer.sendTransaction({
                to: FLOW_STAKING_POOL_ADDRESS,
                value: testAmount,
                gasLimit: 500000
            });
            
            console.log(`Low-level call transaction: ${tx.hash}`);
            await tx.wait();
            console.log(`✅ Low-level call SUCCESS!`);
            
            // Check new balances
            const newAnkrFlow = await ankrFlowToken.balanceOf(deployer.address);
            const received = newAnkrFlow - initialAnkrFlow;
            console.log(`ankrFLOW received: ${ethers.formatUnits(received, 18)}`);
            
            if (received > 0) {
                console.log(`\n🎉 SOLUTION FOUND: Low-level call works!`);
                return "lowLevel";
            }
            
        } catch (error) {
            console.log(`❌ Low-level call failed: ${error.message.split('(')[0]}`);
        }
        
        // Method 4: Try with referral code
        console.log(`\n4. Testing stakeCertsWithCode()...`);
        try {
            const stakeTx = await stakingPool.stakeCertsWithCode("", {
                value: testAmount,
                gasLimit: 500000
            });
            
            console.log(`stakeCertsWithCode transaction: ${stakeTx.hash}`);
            await stakeTx.wait();
            console.log(`✅ stakeCertsWithCode SUCCESS!`);
            
            // Check new balances
            const newAnkrFlow = await ankrFlowToken.balanceOf(deployer.address);
            const received = newAnkrFlow - initialAnkrFlow;
            console.log(`ankrFLOW received: ${ethers.formatUnits(received, 18)}`);
            
            if (received > 0) {
                console.log(`\n🎉 SOLUTION FOUND: Use stakeCertsWithCode() function!`);
                return "stakeCertsWithCode";
            }
            
        } catch (error) {
            console.log(`❌ stakeCertsWithCode failed: ${error.message.split('(')[0]}`);
        }
        
        console.log(`\n❌ All staking methods failed!`);
        console.log(`This suggests either:`);
        console.log(`1. Pool is paused or has issues`);
        console.log(`2. Different interface is required`);
        console.log(`3. Minimum amount requirements`);
        console.log(`4. Pool has no liquidity`);
        
    } catch (error) {
        console.error("Test script failed:", error.message);
    }
}

main()
    .then((result) => {
        if (result) {
            console.log(`\n🔧 UPDATE YOUR STRATEGY:`);
            console.log(`========================`);
            console.log(`Replace your _stakeNativeFlow function with:`);
            
            if (result === "stakeCerts") {
                console.log(`
// Add to interface:
interface IAnkrFlowStakingPool {
    function stakeCerts() external payable;
    // ... other functions
}

// Replace _stakeNativeFlow:
function _stakeNativeFlow(uint256 flowAmount) internal returns (uint256 ankrFlowReceived) {
    uint256 ankrFlowBefore = ankrFlowToken.balanceOf(address(this));
    
    // Use stakeCerts function
    stakingPool.stakeCerts{value: flowAmount}();
    
    uint256 ankrFlowAfter = ankrFlowToken.balanceOf(address(this));
    ankrFlowReceived = ankrFlowAfter - ankrFlowBefore;
    
    require(ankrFlowReceived > 0, "No ankrFLOW tokens received");
    return ankrFlowReceived;
}
                `);
            } else if (result === "stakeBonds") {
                console.log(`
// Add to interface:
interface IAnkrFlowStakingPool {
    function stakeBonds() external payable;
    // ... other functions
}

// Replace _stakeNativeFlow:
function _stakeNativeFlow(uint256 flowAmount) internal returns (uint256 ankrFlowReceived) {
    uint256 ankrFlowBefore = ankrFlowToken.balanceOf(address(this));
    
    // Use stakeBonds function
    stakingPool.stakeBonds{value: flowAmount}();
    
    uint256 ankrFlowAfter = ankrFlowToken.balanceOf(address(this));
    ankrFlowReceived = ankrFlowAfter - ankrFlowBefore;
    
    require(ankrFlowReceived > 0, "No ankrFLOW tokens received");
    return ankrFlowReceived;
}
                `);
            }
        }
        
        console.log(`\nRun this test to find the correct interface!`);
        process.exit(0);
    })
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });