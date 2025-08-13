// Flow Yield Farming System Deployment Script
// Deploys all contracts in the correct order with proper configuration

const hre = require("hardhat");
const { ethers } = require("hardhat");

// Flow mainnet addresses (you'll need to update these with real addresses)
const FLOW_ADDRESSES = {
  // Native tokens
  FLOW_TOKEN: "0x7238390d687d215c4618d59f9e72e0c9b2a8d0b7", // FLOW native token
  WETH: "0xd3bF53DAC106A0290B0483EcBC89d40FcD961c27", // Wrapped ETH
  USDC: "0x5474b38d82a7fe5b7b8da98a40f0c06b0b86f5e1", // USDC
  USDT: "0x3f2b35c5b8a6e67c7b9b4b7c5b7b8b8b7b8b7b8b", // USDT

  // Flow ecosystem protocols
  INCREMENTFI_ROUTER: "0x1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b",
  INCREMENTFI_FACTORY: "0x2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c",
  MORE_MARKETS_POOL: "0x3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d",
  STURDY_FINANCE_POOL: "0x4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e",
  ANKR_STAKING: "0x5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f",
  FLOWTY_MARKETPLACE: "0x6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a",
  CELER_BRIDGE: "0x7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b",
  FLOW_VRF: "0x8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c",

  // Governance tokens
  INCREMENTFI_TOKEN: "0x9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d",
  MORE_MARKETS_TOKEN: "0xa0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9",
  FLOW_GOVERNANCE_DAO: "0xb1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0",
};

// Configuration
const CONFIG = {
  VAULT_NAME: "Flow Mega Yield Vault",
  VAULT_SYMBOL: "FMYV",
  PERFORMANCE_FEE: 3000, // 30%
  MANAGEMENT_FEE: 200,   // 2%
  MIN_DEPOSIT: ethers.utils.parseUnits("100", 6), // 100 USDC
  MAX_DEPOSIT: ethers.utils.parseUnits("10000000", 6), // 10M USDC
  TREASURY_ADDRESS: "0xC0ffee254729296a45a3885639AC7E10F9d54979", // Update with real treasury
};

class FlowYieldSystemDeployer {
  constructor() {
    this.deployedContracts = {};
    this.signer = null;
  }

  async initialize() {
    [this.signer] = await ethers.getSigners();
    console.log("🚀 Deploying Flow Yield System with account:", this.signer.address);
    console.log("💰 Account balance:", ethers.utils.formatEther(await this.signer.getBalance()), "ETH");
  }

  // Deploy mock tokens for testing
  async deployMockTokens() {
    console.log("\n📋 Deploying Mock Tokens...");
    
    // Deploy Mock FLOW
    const MockFLOW = await ethers.getContractFactory("MockFLOW");
    const mockFlow = await MockFLOW.deploy();
    await mockFlow.deployed();
    this.deployedContracts.MockFLOW = mockFlow.address;
    console.log("✅ MockFLOW deployed to:", mockFlow.address);

    // Deploy Mock USDC
    const MockUSDC = await ethers.getContractFactory("MockUSDC");
    const mockUSDC = await MockUSDC.deploy();
    await mockUSDC.deployed();
    this.deployedContracts.MockUSDC = mockUSDC.address;
    console.log("✅ MockUSDC deployed to:", mockUSDC.address);

    // Deploy Mock WETH
    const MockWETH = await ethers.getContractFactory("MockWETH");
    const mockWETH = await MockWETH.deploy();
    await mockWETH.deployed();
    this.deployedContracts.MockWETH = mockWETH.address;
    console.log("✅ MockWETH deployed to:", mockWETH.address);

    return {
      mockFlow: mockFlow.address,
      mockUSDC: mockUSDC.address,
      mockWETH: mockWETH.address
    };
  }

  // Deploy oracle contracts
  async deployOracles() {
    console.log("\n🔮 Deploying Oracle Contracts...");

    // Deploy Risk Oracle
    const RiskOracle = await ethers.getContractFactory("RiskOracle");
    const riskOracle = await RiskOracle.deploy();
    await riskOracle.deployed();
    this.deployedContracts.RiskOracle = riskOracle.address;
    console.log("✅ RiskOracle deployed to:", riskOracle.address);

    // Deploy Strategy Registry
    const StrategyRegistry = await ethers.getContractFactory("StrategyRegistry");
    const strategyRegistry = await StrategyRegistry.deploy();
    await strategyRegistry.deployed();
    this.deployedContracts.StrategyRegistry = strategyRegistry.address;
    console.log("✅ StrategyRegistry deployed to:", strategyRegistry.address);

    // Deploy Yield Aggregator
    const YieldAggregator = await ethers.getContractFactory("YieldAggregator");
    const yieldAggregator = await YieldAggregator.deploy(
      riskOracle.address,
      strategyRegistry.address
    );
    await yieldAggregator.deployed();
    this.deployedContracts.YieldAggregator = yieldAggregator.address;
    console.log("✅ YieldAggregator deployed to:", yieldAggregator.address);

    // Deploy Price Oracle
    const PriceOracle = await ethers.getContractFactory("PriceOracle");
    const priceOracle = await PriceOracle.deploy();
    await priceOracle.deployed();
    this.deployedContracts.PriceOracle = priceOracle.address;
    console.log("✅ PriceOracle deployed to:", priceOracle.address);

    return {
      riskOracle: riskOracle.address,
      strategyRegistry: strategyRegistry.address,
      yieldAggregator: yieldAggregator.address,
      priceOracle: priceOracle.address
    };
  }

  // Deploy bridge contracts
  async deployBridges(oracles) {
    console.log("\n🌉 Deploying Bridge Contracts...");

    // Deploy Celer Bridge (Mock)
    const FlowCelerBridge = await ethers.getContractFactory("FlowCelerBridgeStrategy");
    const celerBridge = await FlowCelerBridge.deploy(
      this.deployedContracts.MockUSDC,
      CONFIG.TREASURY_ADDRESS,
      "Celer Bridge Strategy"
    );
    await celerBridge.deployed();
    this.deployedContracts.CelerBridge = celerBridge.address;
    console.log("✅ CelerBridge deployed to:", celerBridge.address);

    return {
      celerBridge: celerBridge.address
    };
  }

  // Deploy all strategy contracts
  async deployStrategies(tokens, oracles) {
    console.log("\n⚡ Deploying Strategy Contracts...");

    const strategies = {};

    // 1. FlowIncrementFiStrategy
    console.log("Deploying FlowIncrementFiStrategy...");
    const FlowIncrementFiStrategy = await ethers.getContractFactory("FlowIncrementFiStrategy");
    const incrementFiStrategy = await FlowIncrementFiStrategy.deploy(
      tokens.mockUSDC,
      tokens.mockWETH,
      CONFIG.TREASURY_ADDRESS,
      "IncrementFi DEX Strategy"
    );
    await incrementFiStrategy.deployed();
    strategies.incrementFi = incrementFiStrategy.address;
    console.log("✅ FlowIncrementFiStrategy deployed to:", incrementFiStrategy.address);

    // 2. FlowMoreMarketsStrategy
    console.log("Deploying FlowMoreMarketsStrategy...");
    const FlowMoreMarketsStrategy = await ethers.getContractFactory("FlowMoreMarketsStrategy");
    const moreMarketsStrategy = await FlowMoreMarketsStrategy.deploy(
      tokens.mockUSDC,
      FLOW_ADDRESSES.MORE_MARKETS_TOKEN, // Mock mToken
      CONFIG.TREASURY_ADDRESS,
      "More.Markets Lending Strategy"
    );
    await moreMarketsStrategy.deployed();
    strategies.moreMarkets = moreMarketsStrategy.address;
    console.log("✅ FlowMoreMarketsStrategy deployed to:", moreMarketsStrategy.address);

    // 3. FlowSturdyFinanceStrategy
    console.log("Deploying FlowSturdyFinanceStrategy...");
    const FlowSturdyFinanceStrategy = await ethers.getContractFactory("FlowSturdyFinanceStrategy");
    const sturdyStrategy = await FlowSturdyFinanceStrategy.deploy(
      tokens.mockUSDC,
      FLOW_ADDRESSES.MORE_MARKETS_TOKEN, // Mock sToken
      tokens.mockUSDC, // Borrow asset
      CONFIG.TREASURY_ADDRESS,
      "Sturdy.Finance Strategy"
    );
    await sturdyStrategy.deployed();
    strategies.sturdy = sturdyStrategy.address;
    console.log("✅ FlowSturdyFinanceStrategy deployed to:", sturdyStrategy.address);

    // 4. FlowAnkrStakingStrategy
    console.log("Deploying FlowAnkrStakingStrategy...");
    const FlowAnkrStakingStrategy = await ethers.getContractFactory("FlowAnkrStakingStrategy");
    const ankrStrategy = await FlowAnkrStakingStrategy.deploy(
      tokens.mockFlow, // FLOW token
      CONFIG.TREASURY_ADDRESS,
      "Ankr Liquid Staking Strategy"
    );
    await ankrStrategy.deployed();
    strategies.ankr = ankrStrategy.address;
    console.log("✅ FlowAnkrStakingStrategy deployed to:", ankrStrategy.address);

    // 5. FlowMultiDEXArbitrageStrategy
    console.log("Deploying FlowMultiDEXArbitrageStrategy...");
    const FlowMultiDEXArbitrageStrategy = await ethers.getContractFactory("FlowMultiDEXArbitrageStrategy");
    const multiDexStrategy = await FlowMultiDEXArbitrageStrategy.deploy(
      tokens.mockUSDC,
      tokens.mockWETH,
      tokens.mockFlow,
      CONFIG.TREASURY_ADDRESS,
      "Multi-DEX Arbitrage Strategy"
    );
    await multiDexStrategy.deployed();
    strategies.multiDex = multiDexStrategy.address;
    console.log("✅ FlowMultiDEXArbitrageStrategy deployed to:", multiDexStrategy.address);

    // 6. FlowNFTYieldStrategy
    console.log("Deploying FlowNFTYieldStrategy...");
    const FlowNFTYieldStrategy = await ethers.getContractFactory("FlowNFTYieldStrategy");
    const nftStrategy = await FlowNFTYieldStrategy.deploy(
      tokens.mockUSDC,
      CONFIG.TREASURY_ADDRESS,
      "NFT Yield Farming Strategy"
    );
    await nftStrategy.deployed();
    strategies.nft = nftStrategy.address;
    console.log("✅ FlowNFTYieldStrategy deployed to:", nftStrategy.address);

    // 7. FlowValidatorStrategy
    console.log("Deploying FlowValidatorStrategy...");
    const FlowValidatorStrategy = await ethers.getContractFactory("FlowValidatorStrategy");
    const validatorStrategy = await FlowValidatorStrategy.deploy(
      tokens.mockFlow, // FLOW token
      CONFIG.TREASURY_ADDRESS,
      "Flow Validator Strategy"
    );
    await validatorStrategy.deployed();
    strategies.validator = validatorStrategy.address;
    console.log("✅ FlowValidatorStrategy deployed to:", validatorStrategy.address);

    // 8. FlowAIPredictiveStrategy
    console.log("Deploying FlowAIPredictiveStrategy...");
    const FlowAIPredictiveStrategy = await ethers.getContractFactory("FlowAIPredictiveStrategy");
    const aiStrategy = await FlowAIPredictiveStrategy.deploy(
      tokens.mockUSDC,
      CONFIG.TREASURY_ADDRESS,
      "AI Predictive Strategy"
    );
    await aiStrategy.deployed();
    strategies.ai = aiStrategy.address;
    console.log("✅ FlowAIPredictiveStrategy deployed to:", aiStrategy.address);

    // 9. FlowCrossChainMegaYieldStrategy
    console.log("Deploying FlowCrossChainMegaYieldStrategy...");
    const FlowCrossChainMegaYieldStrategy = await ethers.getContractFactory("FlowCrossChainMegaYieldStrategy");
    const crossChainStrategy = await FlowCrossChainMegaYieldStrategy.deploy(
      tokens.mockUSDC,
      CONFIG.TREASURY_ADDRESS,
      "Cross-Chain Mega Yield Strategy"
    );
    await crossChainStrategy.deployed();
    strategies.crossChain = crossChainStrategy.address;
    console.log("✅ FlowCrossChainMegaYieldStrategy deployed to:", crossChainStrategy.address);

    // 10. FlowDeltaNeutralStrategy
    console.log("Deploying FlowDeltaNeutralStrategy...");
    const FlowDeltaNeutralStrategy = await ethers.getContractFactory("FlowDeltaNeutralStrategy");
    const deltaNeutralStrategy = await FlowDeltaNeutralStrategy.deploy(
      tokens.mockUSDC,
      CONFIG.TREASURY_ADDRESS,
      "Delta Neutral Strategy"
    );
    await deltaNeutralStrategy.deployed();
    strategies.deltaNeutral = deltaNeutralStrategy.address;
    console.log("✅ FlowDeltaNeutralStrategy deployed to:", deltaNeutralStrategy.address);

    // 11. FlowFlashLoanArbitrageStrategy
    console.log("Deploying FlowFlashLoanArbitrageStrategy...");
    const FlowFlashLoanArbitrageStrategy = await ethers.getContractFactory("FlowFlashLoanArbitrageStrategy");
    const flashLoanStrategy = await FlowFlashLoanArbitrageStrategy.deploy(
      tokens.mockUSDC,
      CONFIG.TREASURY_ADDRESS,
      "Flash Loan Arbitrage Strategy"
    );
    await flashLoanStrategy.deployed();
    strategies.flashLoan = flashLoanStrategy.address;
    console.log("✅ FlowFlashLoanArbitrageStrategy deployed to:", flashLoanStrategy.address);

    // 12. FlowYieldLotteryGamificationStrategy
    console.log("Deploying FlowYieldLotteryGamificationStrategy...");
    const FlowYieldLotteryGamificationStrategy = await ethers.getContractFactory("FlowYieldLotteryGamificationStrategy");
    const lotteryStrategy = await FlowYieldLotteryGamificationStrategy.deploy(
      tokens.mockUSDC,
      CONFIG.TREASURY_ADDRESS,
      "Yield Lottery Gamification Strategy"
    );
    await lotteryStrategy.deployed();
    strategies.lottery = lotteryStrategy.address;
    console.log("✅ FlowYieldLotteryGamificationStrategy deployed to:", lotteryStrategy.address);

    // 13. FlowGovernanceFarmingStrategy
    console.log("Deploying FlowGovernanceFarmingStrategy...");
    const FlowGovernanceFarmingStrategy = await ethers.getContractFactory("FlowGovernanceFarmingStrategy");
    const governanceStrategy = await FlowGovernanceFarmingStrategy.deploy(
      tokens.mockUSDC,
      CONFIG.TREASURY_ADDRESS,
      "Governance Farming Strategy"
    );
    await governanceStrategy.deployed();
    strategies.governance = governanceStrategy.address;
    console.log("✅ FlowGovernanceFarmingStrategy deployed to:", governanceStrategy.address);

    this.deployedContracts.strategies = strategies;
    return strategies;
  }

  // Deploy the main vault
  async deployVault(tokens, oracles) {
    console.log("\n🏦 Deploying Enhanced Vault...");

    const EnhancedVaultOrchestrator = await ethers.getContractFactory("EnhancedVaultOrchestrator");
    const vault = await EnhancedVaultOrchestrator.deploy(
      tokens.mockUSDC,
      CONFIG.VAULT_NAME,
      CONFIG.VAULT_SYMBOL,
      CONFIG.TREASURY_ADDRESS,
      oracles.riskOracle,
      oracles.strategyRegistry,
      oracles.yieldAggregator
    );
    await vault.deployed();
    this.deployedContracts.EnhancedVault = vault.address;
    console.log("✅ EnhancedVault deployed to:", vault.address);

    return vault.address;
  }

  // Deploy factory contract
  async deployFactory(tokens, oracles) {
    console.log("\n🏭 Deploying Vault Factory...");

    const FlowVaultFactory = await ethers.getContractFactory("FlowVaultFactory");
    const factory = await FlowVaultFactory.deploy(
      this.signer.address, // Default manager
      this.signer.address, // Default agent
      CONFIG.TREASURY_ADDRESS,
      ethers.utils.parseEther("0.01"), // Creation fee
      oracles.riskOracle,
      oracles.strategyRegistry,
      oracles.yieldAggregator
    );
    await factory.deployed();
    this.deployedContracts.VaultFactory = factory.address;
    console.log("✅ FlowVaultFactory deployed to:", factory.address);

    return factory.address;
  }

  // Configure all contracts
  async configureContracts(tokens, oracles, strategies, vault) {
    console.log("\n⚙️  Configuring Contracts...");

    // Configure Risk Oracle
    const riskOracle = await ethers.getContractAt("RiskOracle", oracles.riskOracle);
    
    // Add strategies to risk oracle with assessments
    const strategyAddresses = Object.values(strategies);
    for (let i = 0; i < strategyAddresses.length; i++) {
      const strategyAddress = strategyAddresses[i];
      console.log(`Adding strategy ${strategyAddress} to risk oracle...`);
      
      await riskOracle.updateRiskAssessment(
        strategyAddress,
        5000 + (i * 200), // Risk scores from 5000 to 7400
        8500, // 85% confidence
        i < 5 ? "LOW" : i < 10 ? "MEDIUM" : "HIGH", // Risk levels
        ethers.utils.keccak256(ethers.utils.toUtf8Bytes("ML_MODEL_V1")),
        "0x" // Empty ML model data
      );
    }

    // Configure Strategy Registry
    const strategyRegistry = await ethers.getContractAt("StrategyRegistry", oracles.strategyRegistry);
    
    // Register all strategies
    const strategyNames = [
      "IncrementFi DEX Strategy",
      "More.Markets Lending Strategy", 
      "Sturdy.Finance Strategy",
      "Ankr Liquid Staking Strategy",
      "Multi-DEX Arbitrage Strategy",
      "NFT Yield Farming Strategy",
      "Flow Validator Strategy",
      "AI Predictive Strategy",
      "Cross-Chain Mega Strategy",
      "Delta Neutral Strategy",
      "Flash Loan Arbitrage Strategy",
      "Yield Lottery Strategy",
      "Governance Farming Strategy"
    ];

    let i = 0;
    for (const [key, address] of Object.entries(strategies)) {
      console.log(`Registering strategy: ${strategyNames[i]}`);
      
      await strategyRegistry.registerRealStrategy(
        strategyNames[i],
        30302, // Flow chain ID
        address,
        key,
        address, // Protocol contract (simplified)
        500 + (i * 100), // Initial APY from 5% to 17%
        ethers.utils.parseUnits("1000000", 6), // 1M USDC max capacity
        ethers.utils.parseUnits("100", 6), // 100 USDC min deposit
        [tokens.mockUSDC], // Underlying tokens
        "0x" // Strategy data
      );
      i++;
    }

    // Configure Enhanced Vault
    const vaultContract = await ethers.getContractAt("EnhancedVaultOrchestrator", vault);
    
    // Add strategies to vault
    const strategyTypes = [
      0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 // StrategyType enum values
    ];

    i = 0;
    for (const [key, address] of Object.entries(strategies)) {
      console.log(`Adding strategy ${key} to vault...`);
      
      await vaultContract.addStrategy(
        strategyTypes[i],
        address,
        2000 // 20% max allocation per strategy
      );
      i++;
    }

    console.log("✅ All contracts configured successfully!");
  }

  // Setup initial liquidity and test deposits
  async setupInitialLiquidity(tokens, vault) {
    console.log("\n💧 Setting up Initial Liquidity...");

    const mockUSDC = await ethers.getContractAt("MockUSDC", tokens.mockUSDC);
    const vaultContract = await ethers.getContractAt("EnhancedVaultOrchestrator", vault);

    // Mint test tokens
    const mintAmount = ethers.utils.parseUnits("1000000", 6); // 1M USDC
    await mockUSDC.faucet(mintAmount);
    console.log("✅ Minted 1M USDC for testing");

    // Approve vault
    await mockUSDC.approve(vault, mintAmount);
    console.log("✅ Approved vault to spend USDC");

    // Make initial deposit
    const depositAmount = ethers.utils.parseUnits("10000", 6); // 10K USDC
    await vaultContract.deposit(depositAmount, this.signer.address);
    console.log("✅ Made initial deposit of 10K USDC");

    // Test harvest
    await vaultContract.harvestAll();
    console.log("✅ Executed initial harvest");
  }

  // Generate deployment report
  generateReport() {
    console.log("\n📊 DEPLOYMENT REPORT");
    console.log("=" .repeat(50));
    console.log("🏦 VAULT SYSTEM");
    console.log(`Enhanced Vault: ${this.deployedContracts.EnhancedVault}`);
    console.log(`Vault Factory: ${this.deployedContracts.VaultFactory}`);
    
    console.log("\n🔮 ORACLES");
    console.log(`Risk Oracle: ${this.deployedContracts.RiskOracle}`);
    console.log(`Strategy Registry: ${this.deployedContracts.StrategyRegistry}`);
    console.log(`Yield Aggregator: ${this.deployedContracts.YieldAggregator}`);
    console.log(`Price Oracle: ${this.deployedContracts.PriceOracle}`);
    
    console.log("\n🪙 MOCK TOKENS");
    console.log(`MockFLOW: ${this.deployedContracts.MockFLOW}`);
    console.log(`MockUSDC: ${this.deployedContracts.MockUSDC}`);
    console.log(`MockWETH: ${this.deployedContracts.MockWETH}`);
    
    console.log("\n⚡ STRATEGIES");
    const strategies = this.deployedContracts.strategies;
    for (const [name, address] of Object.entries(strategies)) {
      console.log(`${name}: ${address}`);
    }
    
    console.log("\n🌉 BRIDGES");
    console.log(`Celer Bridge: ${this.deployedContracts.CelerBridge}`);
    
    console.log("\n🎯 NEXT STEPS");
    console.log("1. Update real protocol addresses in the strategies");
    console.log("2. Configure risk parameters for each strategy");
    console.log("3. Set up monitoring and alerting");
    console.log("4. Deploy to Flow mainnet");
    console.log("5. Set up governance and timelock");
    
    console.log("\n✅ DEPLOYMENT COMPLETED SUCCESSFULLY!");
    
    return this.deployedContracts;
  }

  // Main deployment function
  async deploy() {
    try {
      await this.initialize();
      
      // Deploy in dependency order
      const tokens = await this.deployMockTokens();
      const oracles = await this.deployOracles();
      const bridges = await this.deployBridges(oracles);
      const strategies = await this.deployStrategies(tokens, oracles);
      const vault = await this.deployVault(tokens, oracles);
      const factory = await this.deployFactory(tokens, oracles);
      
      // Configure everything
      await this.configureContracts(tokens, oracles, strategies, vault);
      
      // Setup initial liquidity
      await this.setupInitialLiquidity(tokens, vault);
      
      // Generate report
      return this.generateReport();
      
    } catch (error) {
      console.error("❌ Deployment failed:", error);
      throw error;
    }
  }
}

// Main execution
async function main() {
  const deployer = new FlowYieldSystemDeployer();
  await deployer.deploy();
}

// Error handling
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Script failed:", error);
    process.exit(1);
  });

module.exports = {
  FlowYieldSystemDeployer,
  FLOW_ADDRESSES,
  CONFIG
};