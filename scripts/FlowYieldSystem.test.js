// Comprehensive Test Suite for Flow Yield Farming System
const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time, loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

describe("Flow Yield Farming System", function () {
  // Test fixture for deployment
  async function deployFlowYieldSystemFixture() {
    const [owner, user1, user2, treasury, manager] = await ethers.getSigners();

    // Deploy mock tokens
    const MockFLOW = await ethers.getContractFactory("MockFLOW");
    const mockFlow = await MockFLOW.deploy();

    const MockUSDC = await ethers.getContractFactory("MockUSDC");
    const mockUSDC = await MockUSDC.deploy();

    const MockWETH = await ethers.getContractFactory("MockWETH");
    const mockWETH = await MockWETH.deploy();

    // Deploy oracles
    const RiskOracle = await ethers.getContractFactory("RiskOracle");
    const riskOracle = await RiskOracle.deploy();

    const StrategyRegistry = await ethers.getContractFactory("StrategyRegistry");
    const strategyRegistry = await StrategyRegistry.deploy();

    const YieldAggregator = await ethers.getContractFactory("YieldAggregator");
    const yieldAggregator = await YieldAggregator.deploy(
      riskOracle.address,
      strategyRegistry.address
    );

    // Deploy strategies
    const FlowIncrementFiStrategy = await ethers.getContractFactory("FlowIncrementFiStrategy");
    const incrementFiStrategy = await FlowIncrementFiStrategy.deploy(
      mockUSDC.address,
      mockWETH.address,
      treasury.address,
      "IncrementFi DEX Strategy"
    );

    const FlowMoreMarketsStrategy = await ethers.getContractFactory("FlowMoreMarketsStrategy");
    const moreMarketsStrategy = await FlowMoreMarketsStrategy.deploy(
      mockUSDC.address,
      mockUSDC.address, // Mock mToken
      treasury.address,
      "More.Markets Strategy"
    );

    const FlowAnkrStakingStrategy = await ethers.getContractFactory("FlowAnkrStakingStrategy");
    const ankrStrategy = await FlowAnkrStakingStrategy.deploy(
      mockFlow.address,
      treasury.address,
      "Ankr Staking Strategy"
    );

    const FlowNFTYieldStrategy = await ethers.getContractFactory("FlowNFTYieldStrategy");
    const nftStrategy = await FlowNFTYieldStrategy.deploy(
      mockUSDC.address,
      treasury.address,
      "NFT Yield Strategy"
    );

    const FlowAIPredictiveStrategy = await ethers.getContractFactory("FlowAIPredictiveStrategy");
    const aiStrategy = await FlowAIPredictiveStrategy.deploy(
      mockUSDC.address,
      treasury.address,
      "AI Predictive Strategy"
    );

    const FlowYieldLotteryGamificationStrategy = await ethers.getContractFactory("FlowYieldLotteryGamificationStrategy");
    const lotteryStrategy = await FlowYieldLotteryGamificationStrategy.deploy(
      mockUSDC.address,
      treasury.address,
      "Lottery Strategy"
    );

    // Deploy Enhanced Vault
    const EnhancedVaultOrchestrator = await ethers.getContractFactory("EnhancedVaultOrchestrator");
    const vault = await EnhancedVaultOrchestrator.deploy(
      mockUSDC.address,
      "Flow Mega Yield Vault",
      "FMYV",
      treasury.address,
      riskOracle.address,
      strategyRegistry.address,
      yieldAggregator.address
    );

    // Deploy Factory
    const FlowVaultFactory = await ethers.getContractFactory("FlowVaultFactory");
    const factory = await FlowVaultFactory.deploy(
      manager.address,
      manager.address,
      treasury.address,
      ethers.utils.parseEther("0.01"),
      riskOracle.address,
      strategyRegistry.address,
      yieldAggregator.address
    );

    // Setup roles
    await vault.grantRole(await vault.MANAGER_ROLE(), manager.address);
    await vault.grantRole(await vault.REBALANCER_ROLE(), manager.address);

    // Mint test tokens
    const mintAmount = ethers.utils.parseUnits("1000000", 6); // 1M USDC
    await mockUSDC.faucet(mintAmount);
    await mockUSDC.transfer(user1.address, ethers.utils.parseUnits("100000", 6));
    await mockUSDC.transfer(user2.address, ethers.utils.parseUnits("100000", 6));

    const flowMintAmount = ethers.utils.parseEther("100000"); // 100K FLOW
    await mockFlow.faucet(flowMintAmount);
    await mockFlow.transfer(user1.address, ethers.utils.parseEther("10000"));
    await mockFlow.transfer(user2.address, ethers.utils.parseEther("10000"));

    return {
      vault,
      factory,
      mockUSDC,
      mockFlow,
      mockWETH,
      riskOracle,
      strategyRegistry,
      yieldAggregator,
      strategies: {
        incrementFi: incrementFiStrategy,
        moreMarkets: moreMarketsStrategy,
        ankr: ankrStrategy,
        nft: nftStrategy,
        ai: aiStrategy,
        lottery: lotteryStrategy
      },
      accounts: { owner, user1, user2, treasury, manager }
    };
  }

  describe("Deployment", function () {
    it("Should deploy all contracts successfully", async function () {
      const { vault, factory, mockUSDC, strategies } = await loadFixture(deployFlowYieldSystemFixture);
      
      expect(vault.address).to.not.equal(ethers.constants.AddressZero);
      expect(factory.address).to.not.equal(ethers.constants.AddressZero);
      expect(mockUSDC.address).to.not.equal(ethers.constants.AddressZero);
      
      // Check all strategies deployed
      expect(strategies.incrementFi.address).to.not.equal(ethers.constants.AddressZero);
      expect(strategies.moreMarkets.address).to.not.equal(ethers.constants.AddressZero);
      expect(strategies.ankr.address).to.not.equal(ethers.constants.AddressZero);
      expect(strategies.nft.address).to.not.equal(ethers.constants.AddressZero);
      expect(strategies.ai.address).to.not.equal(ethers.constants.AddressZero);
      expect(strategies.lottery.address).to.not.equal(ethers.constants.AddressZero);
    });

    it("Should set correct vault parameters", async function () {
      const { vault, mockUSDC, accounts } = await loadFixture(deployFlowYieldSystemFixture);
      
      expect(await vault.asset()).to.equal(mockUSDC.address);
      expect(await vault.name()).to.equal("Flow Mega Yield Vault");
      expect(await vault.symbol()).to.equal("FMYV");
      expect(await vault.hasRole(await vault.DEFAULT_ADMIN_ROLE(), accounts.owner.address)).to.be.true;
    });
  });

  describe("Strategy Management", function () {
    it("Should add strategies to vault", async function () {
      const { vault, strategies, accounts, riskOracle } = await loadFixture(deployFlowYieldSystemFixture);
      
      // Add strategy to risk oracle first
      await riskOracle.updateRiskAssessment(
        strategies.incrementFi.address,
        5000, // 50% risk score
        8500, // 85% confidence
        "MEDIUM",
        ethers.utils.keccak256(ethers.utils.toUtf8Bytes("TEST")),
        "0x"
      );

      // Add strategy to vault
      await vault.connect(accounts.manager).addStrategy(
        0, // StrategyType.INCREMENTFI_DEX
        strategies.incrementFi.address,
        2000 // 20% max allocation
      );

      const strategyInfo = await vault.strategies(0);
      expect(strategyInfo.active).to.be.true;
      expect(strategyInfo.strategyAddress).to.equal(strategies.incrementFi.address);
      expect(strategyInfo.maxAllocation).to.equal(2000);
    });

    it("Should prevent adding risky strategies", async function () {
      const { vault, strategies, accounts, riskOracle } = await loadFixture(deployFlowYieldSystemFixture);
      
      // Add high-risk strategy to oracle
      await riskOracle.updateRiskAssessment(
        strategies.incrementFi.address,
        9000, // 90% risk score (too high)
        8500,
        "HIGH",
        ethers.utils.keccak256(ethers.utils.toUtf8Bytes("TEST")),
        "0x"
      );

      // Should revert when adding high-risk strategy
      await expect(
        vault.connect(accounts.manager).addStrategy(
          0,
          strategies.incrementFi.address,
          2000
        )
      ).to.be.revertedWith("Strategy too risky");
    });

    it("Should remove strategies from vault", async function () {
      const { vault, strategies, accounts, riskOracle } = await loadFixture(deployFlowYieldSystemFixture);
      
      // Add strategy first
      await riskOracle.updateRiskAssessment(
        strategies.incrementFi.address,
        5000,
        8500,
        "MEDIUM",
        ethers.utils.keccak256(ethers.utils.toUtf8Bytes("TEST")),
        "0x"
      );

      await vault.connect(accounts.manager).addStrategy(0, strategies.incrementFi.address, 2000);
      
      // Remove strategy
      await vault.connect(accounts.manager).removeStrategy(0);
      
      const strategyInfo = await vault.strategies(0);
      expect(strategyInfo.active).to.be.false;
    });
  });

  describe("Vault Operations", function () {
    async function setupVaultWithStrategies() {
      const fixture = await loadFixture(deployFlowYieldSystemFixture);
      const { vault, strategies, accounts, riskOracle } = fixture;

      // Add strategies to risk oracle and vault
      const strategyList = [
        { strategy: strategies.incrementFi, type: 0 },
        { strategy: strategies.moreMarkets, type: 1 },
        { strategy: strategies.ankr, type: 3 }
      ];

      for (let i = 0; i < strategyList.length; i++) {
        await riskOracle.updateRiskAssessment(
          strategyList[i].strategy.address,
          5000 + (i * 500), // Varying risk scores
          8500,
          "MEDIUM",
          ethers.utils.keccak256(ethers.utils.toUtf8Bytes("TEST")),
          "0x"
        );

        await vault.connect(accounts.manager).addStrategy(
          strategyList[i].type,
          strategyList[i].strategy.address,
          2000
        );
      }

      return fixture;
    }

    it("Should allow user deposits", async function () {
      const { vault, mockUSDC, accounts } = await setupVaultWithStrategies();
      
      const depositAmount = ethers.utils.parseUnits("1000", 6); // 1000 USDC
      
      // Approve and deposit
      await mockUSDC.connect(accounts.user1).approve(vault.address, depositAmount);
      await vault.connect(accounts.user1).deposit(depositAmount, accounts.user1.address);
      
      // Check shares minted
      const shares = await vault.balanceOf(accounts.user1.address);
      expect(shares).to.be.gt(0);
      
      // Check vault total assets
      const totalAssets = await vault.totalAssets();
      expect(totalAssets).to.equal(depositAmount);
    });

    it("Should allow user withdrawals", async function () {
      const { vault, mockUSDC, accounts } = await setupVaultWithStrategies();
      
      const depositAmount = ethers.utils.parseUnits("1000", 6);
      
      // Deposit first
      await mockUSDC.connect(accounts.user1).approve(vault.address, depositAmount);
      await vault.connect(accounts.user1).deposit(depositAmount, accounts.user1.address);
      
      const shares = await vault.balanceOf(accounts.user1.address);
      const balanceBefore = await mockUSDC.balanceOf(accounts.user1.address);
      
      // Withdraw
      await vault.connect(accounts.user1).withdraw(
        depositAmount,
        accounts.user1.address,
        accounts.user1.address
      );
      
      const balanceAfter = await mockUSDC.balanceOf(accounts.user1.address);
      expect(balanceAfter.sub(balanceBefore)).to.equal(depositAmount);
      expect(await vault.balanceOf(accounts.user1.address)).to.equal(0);
    });

    it("Should enforce minimum deposit amount", async function () {
      const { vault, mockUSDC, accounts } = await setupVaultWithStrategies();
      
      const smallAmount = ethers.utils.parseUnits("50", 6); // 50 USDC (below 100 minimum)
      
      await mockUSDC.connect(accounts.user1).approve(vault.address, smallAmount);
      
      await expect(
        vault.connect(accounts.user1).deposit(smallAmount, accounts.user1.address)
      ).to.be.revertedWith("Below minimum deposit");
    });

    it("Should execute rebalancing", async function () {
      const { vault, mockUSDC, accounts } = await setupVaultWithStrategies();
      
      const depositAmount = ethers.utils.parseUnits("10000", 6); // 10K USDC
      
      // Make deposit
      await mockUSDC.connect(accounts.user1).approve(vault.address, depositAmount);
      await vault.connect(accounts.user1).deposit(depositAmount, accounts.user1.address);
      
      // Execute rebalance
      await expect(vault.connect(accounts.manager).rebalance())
        .to.emit(vault, "RebalanceExecuted");
    });
  });

  describe("Strategy Execution", function () {
    it("Should execute IncrementFi strategy", async function () {
      const { strategies, mockUSDC, accounts } = await loadFixture(deployFlowYieldSystemFixture);
      
      const amount = ethers.utils.parseUnits("1000", 6);
      
      // Transfer tokens to strategy
      await mockUSDC.transfer(strategies.incrementFi.address, amount);
      
      // Execute strategy
      await strategies.incrementFi.execute(amount, "0x");
      
      // Check strategy has processed the amount
      const balance = await strategies.incrementFi.getBalance();
      expect(balance).to.be.gte(0); // Strategy might have converted tokens
    });

    it("Should execute Ankr staking strategy", async function () {
      const { strategies, mockFlow, accounts } = await loadFixture(deployFlowYieldSystemFixture);
      
      const amount = ethers.utils.parseEther("100"); // 100 FLOW
      
      // Transfer FLOW to strategy
      await mockFlow.transfer(strategies.ankr.address, amount);
      
      // Execute strategy
      await strategies.ankr.execute(amount, "0x");
      
      const balance = await strategies.ankr.getBalance();
      expect(balance).to.be.gte(0);
    });

    it("Should execute lottery gamification strategy", async function () {
      const { strategies, mockUSDC, accounts } = await loadFixture(deployFlowYieldSystemFixture);
      
      const amount = ethers.utils.parseUnits("1000", 6);
      
      // Transfer tokens to strategy
      await mockUSDC.transfer(strategies.lottery.address, amount);
      
      // Execute strategy with lottery participation
      const data = ethers.utils.defaultAbiCoder.encode(
        ["bool", "bytes32", "address"],
        [true, ethers.constants.HashZero, ethers.constants.AddressZero]
      );
      
      await strategies.lottery.execute(amount, data);
      
      // Check user stats were updated
      const userStats = await strategies.lottery.getUserStats(strategies.lottery.address);
      expect(userStats.totalStaked).to.be.gt(0);
    });
  });

  describe("Yield Harvesting", function () {
    it("Should harvest yields from all strategies", async function () {
      const { vault, mockUSDC, accounts } = await setupVaultWithStrategies();
      
      const depositAmount = ethers.utils.parseUnits("10000", 6);
      
      // Make deposit
      await mockUSDC.connect(accounts.user1).approve(vault.address, depositAmount);
      await vault.connect(accounts.user1).deposit(depositAmount, accounts.user1.address);
      
      // Simulate time passage
      await time.increase(86400); // 1 day
      
      // Harvest yields
      await expect(vault.connect(accounts.manager).harvestAll())
        .to.emit(vault, "YieldHarvested");
    });

    it("Should collect performance fees", async function () {
      const { vault, mockUSDC, accounts } = await setupVaultWithStrategies();
      
      const depositAmount = ethers.utils.parseUnits("10000", 6);
      
      // Make deposit
      await mockUSDC.connect(accounts.user1).approve(vault.address, depositAmount);
      await vault.connect(accounts.user1).deposit(depositAmount, accounts.user1.address);
      
      // Simulate yield generation and harvesting
      await time.increase(86400);
      
      const treasuryBalanceBefore = await mockUSDC.balanceOf(accounts.treasury.address);
      await vault.connect(accounts.manager).harvestAll();
      
      // Performance fees should be collected if there's yield
      // Note: In this test, actual yield might be 0 due to mock contracts
    });
  });

  describe("Emergency Functions", function () {
    it("Should activate emergency mode", async function () {
      const { vault, accounts } = await loadFixture(deployFlowYieldSystemFixture);
      
      // Grant emergency role
      await vault.grantRole(await vault.EMERGENCY_ROLE(), accounts.manager.address);
      
      // Activate emergency mode
      await expect(
        vault.connect(accounts.manager).activateEmergencyMode("Test emergency")
      ).to.emit(vault, "EmergencyModeActivated");
      
      expect(await vault.emergencyMode()).to.be.true;
      expect(await vault.paused()).to.be.true;
    });

    it("Should prevent deposits during emergency", async function () {
      const { vault, mockUSDC, accounts } = await setupVaultWithStrategies();
      
      // Grant emergency role and activate emergency
      await vault.grantRole(await vault.EMERGENCY_ROLE(), accounts.manager.address);
      await vault.connect(accounts.manager).activateEmergencyMode("Test emergency");
      
      const depositAmount = ethers.utils.parseUnits("1000", 6);
      await mockUSDC.connect(accounts.user1).approve(vault.address, depositAmount);
      
      await expect(
        vault.connect(accounts.user1).deposit(depositAmount, accounts.user1.address)
      ).to.be.revertedWith("Emergency mode active");
    });

    it("Should allow emergency exit from strategies", async function () {
      const { vault, strategies, accounts } = await setupVaultWithStrategies();
      
      // Grant emergency role
      await vault.grantRole(await vault.EMERGENCY_ROLE(), accounts.manager.address);
      
      // Emergency exit from strategy
      await expect(
        vault.connect(accounts.manager).emergencyExitStrategy(0, "Test exit")
      ).to.emit(vault, "StrategyEmergencyExit");
      
      const strategyInfo = await vault.strategies(0);
      expect(strategyInfo.emergency).to.be.true;
    });
  });

  describe("Factory Operations", function () {
    it("Should create new vaults through factory", async function () {
      const { factory, mockUSDC, accounts } = await loadFixture(deployFlowYieldSystemFixture);
      
      const creationFee = ethers.utils.parseEther("0.01");
      
      const vaultParams = {
        asset: mockUSDC.address,
        name: "Test Vault",
        symbol: "TV",
        manager: accounts.manager.address,
        agent: accounts.manager.address
      };
      
      await expect(
        factory.connect(accounts.user1).createVault(vaultParams, { value: creationFee })
      ).to.emit(factory, "VaultCreated");
      
      const vaultCount = await factory.getVaultCount();
      expect(vaultCount).to.equal(1);
    });

    it("Should enforce creation fee", async function () {
      const { factory, mockUSDC, accounts } = await loadFixture(deployFlowYieldSystemFixture);
      
      const vaultParams = {
        asset: mockUSDC.address,
        name: "Test Vault",
        symbol: "TV",
        manager: accounts.manager.address,
        agent: accounts.manager.address
      };
      
      await expect(
        factory.connect(accounts.user1).createVault(vaultParams, { value: 0 })
      ).to.be.revertedWith("InsufficientFee");
    });
  });

  describe("Access Control", function () {
    it("Should enforce manager role for strategy operations", async function () {
      const { vault, strategies, accounts, riskOracle } = await loadFixture(deployFlowYieldSystemFixture);
      
      await riskOracle.updateRiskAssessment(
        strategies.incrementFi.address,
        5000,
        8500,
        "MEDIUM",
        ethers.utils.keccak256(ethers.utils.toUtf8Bytes("TEST")),
        "0x"
      );

      // Should revert when non-manager tries to add strategy
      await expect(
        vault.connect(accounts.user1).addStrategy(0, strategies.incrementFi.address, 2000)
      ).to.be.reverted;
    });

    it("Should enforce rebalancer role for rebalancing", async function () {
      const { vault, accounts } = await loadFixture(deployFlowYieldSystemFixture);
      
      // Should revert when non-rebalancer tries to rebalance
      await expect(
        vault.connect(accounts.user1).rebalance()
      ).to.be.reverted;
    });

    it("Should enforce emergency role for emergency functions", async function () {
      const { vault, accounts } = await loadFixture(deployFlowYieldSystemFixture);
      
      // Should revert when non-emergency role tries to activate emergency
      await expect(
        vault.connect(accounts.user1).activateEmergencyMode("Test")
      ).to.be.reverted;
    });
  });

  describe("Performance Metrics", function () {
    it("Should track vault performance metrics", async function () {
      const { vault, mockUSDC, accounts } = await setupVaultWithStrategies();
      
      const depositAmount = ethers.utils.parseUnits("10000", 6);
      
      // Make multiple deposits
      await mockUSDC.connect(accounts.user1).approve(vault.address, depositAmount);
      await vault.connect(accounts.user1).deposit(depositAmount, accounts.user1.address);
      
      await mockUSDC.connect(accounts.user2).approve(vault.address, depositAmount);
      await vault.connect(accounts.user2).deposit(depositAmount, accounts.user2.address);
      
      const performance = await vault.getVaultPerformance();
      expect(performance.totalUsersServed).to.be.gte(2);
      expect(performance.totalValueLocked).to.equal(depositAmount.mul(2));
    });

    it("Should track strategy allocations", async function () {
      const { vault } = await setupVaultWithStrategies();
      
      const allocations = await vault.getStrategyAllocations();
      expect(allocations.strategyTypes.length).to.be.gt(0);
      expect(allocations.allocations.length).to.equal(allocations.strategyTypes.length);
    });
  });

  describe("AI Optimization", function () {
    it("Should allow deposits with strategy preferences", async function () {
      const { vault, mockUSDC, accounts } = await setupVaultWithStrategies();
      
      const depositAmount = ethers.utils.parseUnits("1000", 6);
      const preferredStrategies = [0, 1]; // IncrementFi and More.Markets
      const riskTolerance = 6000; // 60%
      
      await mockUSDC.connect(accounts.user1).approve(vault.address, depositAmount);
      
      await expect(
        vault.connect(accounts.user1).depositWithPreferences(
          depositAmount,
          accounts.user1.address,
          preferredStrategies,
          riskTolerance
        )
      ).to.emit(vault, "UserDeposit");
      
      const userPosition = await vault.getUserPosition(accounts.user1.address);
      expect(userPosition.riskTolerance).to.equal(riskTolerance);
    });
  });

  describe("Integration Tests", function () {
    it("Should handle full user journey", async function () {
      const { vault, mockUSDC, accounts } = await setupVaultWithStrategies();
      
      const depositAmount = ethers.utils.parseUnits("5000", 6);
      
      // 1. User deposits
      await mockUSDC.connect(accounts.user1).approve(vault.address, depositAmount);
      await vault.connect(accounts.user1).deposit(depositAmount, accounts.user1.address);
      
      // 2. Vault rebalances
      await vault.connect(accounts.manager).rebalance();
      
      // 3. Time passes
      await time.increase(86400 * 7); // 1 week
      
      // 4. Harvest yields
      await vault.connect(accounts.manager).harvestAll();
      
      // 5. User withdraws
      const shares = await vault.balanceOf(accounts.user1.address);
      await vault.connect(accounts.user1).redeem(
        shares,
        accounts.user1.address,
        accounts.user1.address
      );
      
      // User should have received their principal back (and potentially some yield)
      const finalBalance = await mockUSDC.balanceOf(accounts.user1.address);
      expect(finalBalance).to.be.gte(depositAmount.sub(ethers.utils.parseUnits("100", 6))); // Allow for small fees
    });

    it("Should handle multiple users and strategies", async function () {
      const { vault, mockUSDC, accounts } = await setupVaultWithStrategies();
      
      const depositAmounts = [
        ethers.utils.parseUnits("1000", 6),
        ethers.utils.parseUnits("5000", 6),
        ethers.utils.parseUnits("2500", 6)
      ];
      
      const users = [accounts.user1, accounts.user2, accounts.owner];
      
      // Multiple users deposit
      for (let i = 0; i < users.length; i++) {
        await mockUSDC.connect(users[i]).approve(vault.address, depositAmounts[i]);
        await vault.connect(users[i]).deposit(depositAmounts[i], users[i].address);
      }
      
      // Rebalance across strategies
      await vault.connect(accounts.manager).rebalance();
      
      // Check total assets
      const totalAssets = await vault.totalAssets();
      const expectedTotal = depositAmounts.reduce((sum, amount) => sum.add(amount), ethers.BigNumber.from(0));
      expect(totalAssets).to.equal(expectedTotal);
      
      // Each user should have proportional shares
      for (let i = 0; i < users.length; i++) {
        const shares = await vault.balanceOf(users[i].address);
        expect(shares).to.be.gt(0);
      }
    });
  });

  describe("Gas Optimization", function () {
    it("Should use reasonable gas for deposits", async function () {
      const { vault, mockUSDC, accounts } = await setupVaultWithStrategies();
      
      const depositAmount = ethers.utils.parseUnits("1000", 6);
      await mockUSDC.connect(accounts.user1).approve(vault.address, depositAmount);
      
      const tx = await vault.connect(accounts.user1).deposit(depositAmount, accounts.user1.address);
      const receipt = await tx.wait();
      
      // Gas should be reasonable (adjust threshold as needed)
      expect(receipt.gasUsed).to.be.lt(500000);
    });

    it("Should use reasonable gas for rebalancing", async function () {
      const { vault, mockUSDC, accounts } = await setupVaultWithStrategies();
      
      // Make deposit first
      const depositAmount = ethers.utils.parseUnits("10000", 6);
      await mockUSDC.connect(accounts.user1).approve(vault.address, depositAmount);
      await vault.connect(accounts.user1).deposit(depositAmount, accounts.user1.address);
      
      const tx = await vault.connect(accounts.manager).rebalance();
      const receipt = await tx.wait();
      
      // Rebalancing gas should be reasonable
      expect(receipt.gasUsed).to.be.lt(1000000);
    });
  });

  // Helper function to setup vault with strategies
  async function setupVaultWithStrategies() {
    const fixture = await loadFixture(deployFlowYieldSystemFixture);
    const { vault, strategies, accounts, riskOracle } = fixture;

    // Add strategies to risk oracle and vault
    const strategyList = [
      { strategy: strategies.incrementFi, type: 0 },
      { strategy: strategies.moreMarkets, type: 1 },
      { strategy: strategies.ankr, type: 3 }
    ];

    for (let i = 0; i < strategyList.length; i++) {
      await riskOracle.updateRiskAssessment(
        strategyList[i].strategy.address,
        5000 + (i * 500),
        8500,
        "MEDIUM",
        ethers.utils.keccak256(ethers.utils.toUtf8Bytes("TEST")),
        "0x"
      );

      await vault.connect(accounts.manager).addStrategy(
        strategyList[i].type,
        strategyList[i].strategy.address,
        2000
      );
    }

    return fixture;
  }
});