// Simple Node.js script to query TroveFi vault stats
// Run with: node query-vault-simple.js

const { ethers } = require('ethers');

// Contract addresses
const CONTRACTS = {
  coreVault: "0xbD82c706e3632972A00E288a54Ea50c958b865b2",
  vaultExtension: "0xBaF543b07e01F0Ed02dFEa5dfbAd38167AC9be57"
};

// Minimal ABIs for queries
const CORE_VAULT_ABI = [
  "function getUserPosition(address user) external view returns (uint256 totalShares, uint256 lastDeposit, bool withdrawalRequested, uint256 withdrawalAvailableAt, uint8 riskLevel, uint256 totalDeposited)",
  "function getVaultMetrics() external view returns (uint256 totalValueLocked, uint256 totalUsers, uint256 totalSupply, uint256 managementFee, uint256 performanceFee, uint256 assetsCount, uint256 totalPrincipal, uint256 totalYieldGenerated, uint256 totalYieldDistributed)"
];

const VAULT_EXTENSION_ABI = [
  "function getCurrentEpochStatus() external view returns (uint256 epochNumber, uint256 timeRemaining, uint256 yieldPool, uint256 participantCount)",
  "function getUserDeposit(address user) external view returns (uint256 totalDeposited, uint256 currentBalance, uint256 firstDepositEpoch, uint256 lastDepositEpoch, uint8 riskLevel, uint256 timeWeightedBalance)",
  "function isEligibleForEpoch(address user, uint256 epochNumber) external view returns (bool)",
  "function getClaimableEpochs(address user) external view returns (uint256[] memory)",
  "function calculateRewardParameters(address user, uint256 epochNumber) external view returns (uint256 baseWeight, uint256 timeWeight, uint256 riskMultiplier, uint256 totalWeight, uint256 winProbability, uint256 potentialPayout)"
];

// Helper functions
function formatUSD(value, decimals = 18) {
  if (!value) return "0.00";
  const num = Number(ethers.formatUnits(value, decimals));
  return num.toFixed(2);
}

function formatTime(seconds) {
  const totalSeconds = Number(seconds);
  const days = Math.floor(totalSeconds / (24 * 3600));
  const hours = Math.floor((totalSeconds % (24 * 3600)) / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  return `${days}d ${hours}h ${minutes}m`;
}

async function queryVaultStats() {
  console.log("TroveFi Vault Statistics Query");
  console.log("==============================");
  
  // Setup provider (replace with your RPC)
  const provider = new ethers.JsonRpcProvider("https://mainnet.evm.nodes.onflow.org");
  
  // User address to query (replace with actual address)
  const userAddress = "0xbaD4374FeB7ec757027CF2186B6eb6f32412f723";
  
  // Create contract instances
  const coreVault = new ethers.Contract(CONTRACTS.coreVault, CORE_VAULT_ABI, provider);
  const vaultExtension = new ethers.Contract(CONTRACTS.vaultExtension, VAULT_EXTENSION_ABI, provider);
  
  try {
    console.log(`Querying for user: ${userAddress}\n`);
    
    // Get basic data
    const [userPosition, userDeposit, epochStatus, vaultMetrics] = await Promise.all([
      coreVault.getUserPosition(userAddress),
      vaultExtension.getUserDeposit(userAddress),
      vaultExtension.getCurrentEpochStatus(),
      coreVault.getVaultMetrics()
    ]);
    
    // Parse user position
    const [totalShares, lastDeposit, withdrawalRequested, withdrawalAvailableAt, riskLevel, totalDeposited] = userPosition;
    
    // Parse user deposit from extension
    const [extTotalDeposited, currentBalance, firstDepositEpoch, lastDepositEpoch, userRiskLevel, timeWeightedBalance] = userDeposit;
    
    // Parse epoch status
    const [currentEpoch, timeRemaining, yieldPool, participantCount] = epochStatus;
    
    // Parse vault metrics
    const [totalValueLocked, totalUsers, totalSupply, managementFee, performanceFee, assetsCount, totalPrincipal, totalYieldGenerated, totalYieldDistributed] = vaultMetrics;
    
    // Calculate rewards if user has deposits
    let winRate = 0;
    let estimatedNextReward = 0;
    let rewardsAvailable = 0;
    let isEligible = false;
    
    if (Number(extTotalDeposited) > 0) {
      try {
        isEligible = await vaultExtension.isEligibleForEpoch(userAddress, currentEpoch);
        
        if (isEligible) {
          const rewardParams = await vaultExtension.calculateRewardParameters(userAddress, currentEpoch);
          const [baseWeight, timeWeight, riskMultiplier, totalWeight, winProbability, potentialPayout] = rewardParams;
          
          winRate = Number(winProbability) / 100;
          estimatedNextReward = potentialPayout;
        }
        
        // Get claimable epochs
        const claimableEpochs = await vaultExtension.getClaimableEpochs(userAddress);
        console.log(`Claimable epochs: ${claimableEpochs.length > 0 ? claimableEpochs.join(', ') : 'None'}`);
        
        // Estimate total rewards available (sum first 3 claimable)
        for (let i = 0; i < Math.min(claimableEpochs.length, 3); i++) {
          try {
            const epochRewardParams = await vaultExtension.calculateRewardParameters(userAddress, claimableEpochs[i]);
            rewardsAvailable = Number(rewardsAvailable) + Number(epochRewardParams[5]);
          } catch (e) {
            // Skip failed calculations
          }
        }
        
      } catch (error) {
        console.log("Note: Could not calculate all reward parameters");
      }
    }
    
    // Calculate epoch progress
    const epochDurationSeconds = 7 * 24 * 3600; // 7 days
    const elapsed = epochDurationSeconds - Number(timeRemaining);
    const progress = Math.max(0, Math.min(100, (elapsed / epochDurationSeconds) * 100));
    
    // Display results in the format you want
    console.log("INDIVIDUAL USER STATS");
    console.log("====================");
    console.log(`$${formatUSD(totalDeposited)}`);
    console.log(`Total Deposited`);
    console.log(`Principal Protected`);
    console.log(`$${formatUSD(rewardsAvailable)}`);
    console.log(`Total Rewards Available`);
    console.log(`${winRate.toFixed(2)}% Win Rate`);
    console.log(`$${formatUSD(estimatedNextReward)}`);
    console.log(`Est. Next Reward`);
    console.log(`Epoch ${currentEpoch}`);
    
    console.log("\nVAULT TOTAL STATS");
    console.log("=================");
    console.log(`$${formatUSD(totalPrincipal)}`);
    console.log(`Total Deposited`);
    console.log(`Principal Protected`);
    console.log(`$${formatUSD(yieldPool)}`);
    console.log(`Total Rewards Available`);
    const avgWinRate = Number(participantCount) > 0 ? (Number(yieldPool) / Number(participantCount)) / 10000 : 0;
    console.log(`${avgWinRate.toFixed(2)}% Avg Win Rate`);
    console.log(`$${formatUSD(yieldPool)}`);
    console.log(`Total Yield Pool`);
    console.log(`Epoch ${currentEpoch}`);
    
    console.log("\nCOOKING STATUS");
    console.log("==============");
    console.log(`Epoch ${currentEpoch}`);
    console.log(`Current epoch in progress`);
    console.log(`${formatTime(timeRemaining)} remaining`);
    console.log(`Epoch Progress ${progress.toFixed(1)}%`);
    
    // User cooking progress
    if (Number(extTotalDeposited) > 0) {
      const epochsSinceDeposit = Number(currentEpoch) - Number(firstDepositEpoch);
      const cookingProgress = isEligible ? 100 : Math.min(100, (epochsSinceDeposit / 2) * 100);
      
      console.log("\nUSER COOKING PROGRESS");
      console.log("====================");
      console.log(`Deposited in epoch: ${firstDepositEpoch}`);
      console.log(`Epochs since deposit: ${epochsSinceDeposit}`);
      console.log(`Cooking progress: ${cookingProgress.toFixed(1)}%`);
      console.log(`Eligible for rewards: ${isEligible ? 'YES' : 'NO'}`);
      
      if (!isEligible && epochsSinceDeposit < 2) {
        console.log(`Epochs until eligible: ${2 - epochsSinceDeposit}`);
      }
    }
    
    console.log("\nADDITIONAL VAULT INFO");
    console.log("====================");
    console.log(`Total Users: ${totalUsers}`);
    console.log(`Total Value Locked: $${formatUSD(totalValueLocked)}`);
    console.log(`Participants this epoch: ${participantCount}`);
    console.log(`Total Yield Generated: $${formatUSD(totalYieldGenerated)}`);
    console.log(`Total Yield Distributed: $${formatUSD(totalYieldDistributed)}`);
    
    // JSON format for frontend reference
    console.log("\nJSON FORMAT FOR FRONTEND:");
    console.log("========================");
    
    const frontendData = {
      user: {
        totalDeposited: formatUSD(totalDeposited),
        principalProtected: formatUSD(totalDeposited),
        rewardsAvailable: formatUSD(rewardsAvailable),
        winRate: `${winRate.toFixed(2)}%`,
        estNextReward: formatUSD(estimatedNextReward),
        currentEpoch: Number(currentEpoch),
        isEligible,
        hasDeposits: Number(extTotalDeposited) > 0
      },
      vault: {
        totalDeposited: formatUSD(totalPrincipal),
        principalProtected: formatUSD(totalPrincipal),
        rewardsAvailable: formatUSD(yieldPool),
        avgWinRate: `${avgWinRate.toFixed(2)}%`,
        totalYieldPool: formatUSD(yieldPool),
        currentEpoch: Number(currentEpoch),
        totalUsers: Number(totalUsers),
        totalValueLocked: formatUSD(totalValueLocked)
      },
      cooking: {
        currentEpoch: Number(currentEpoch),
        timeRemaining: formatTime(timeRemaining),
        progress: `${progress.toFixed(1)}%`,
        participants: Number(participantCount),
        yieldPool: formatUSD(yieldPool),
        status: "Current epoch in progress"
      }
    };
    
    console.log(JSON.stringify(frontendData, null, 2));
    
  } catch (error) {
    console.error("Query failed:", error.message);
  }
}

// Run the query
queryVaultStats().catch(console.error);