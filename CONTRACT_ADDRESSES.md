# Flow Protocol Integration Reference Table

To Integrate with:!
Ankr Staking [might not be reliable because not 1:1 with mainnet...]
KittyPunch
Trado.one
More.Markets 
Sturdy.Finance 
Izumi.finance
Ankr Staking


BloctoSwap - CADANCE
Celer Network - CADANCE
Increment Finance - CADANCE

https://developers.flow.com/ecosystem/bridges

Other to look at:
https://flow.com/ecosystem#defi
Sudocat



## **DEX/AMM Protocols**

| Protocol Name | Type | Mainnet Address | Testnet Address | Currently Integrated | Notes |
|---------------|------|----------------|----------------|---------------------|-------|
| IncrementFi | DEX/AMM | | | ✅ Yes | Primary DEX integration |
| BloctoSwap | DEX/AMM | | | ✅ Yes (Arbitrage) | Multi-DEX arbitrage |
| KittyPunch/PunchSwap | DEX/AMM | | | ✅ Yes (Arbitrage) | Multi-DEX arbitrage |
| Trado.one | DEX/AMM | | | ✅ Yes (Arbitrage) | Permissionless DEX |
| Flowty | NFT Marketplace | | | ❌ No | Potential NFT-Fi strategies |

## **Lending/Borrowing Protocols**

| Protocol Name | Type | Mainnet Address | Testnet Address | Currently Integrated | Notes |
|---------------|------|----------------|----------------|---------------------|-------|
| More.Markets | Lending/Borrowing | | | ✅ Yes | Looping strategies |
| Sturdy.Finance | Interest-Free Borrowing | | | ✅ Yes | Leverage strategies |

## **Staking Protocols**

| Protocol Name | Type | Mainnet Address | Testnet Address | Currently Integrated | Notes |
|---------------|------|----------------|----------------|---------------------|-------|
| Ankr Staking | Liquid Staking | | | ✅ Yes | FLOW liquid staking |
| Flow Native Staking | Validator Staking | | | ❌ No | Direct validator staking |

## **Bridge/Cross-Chain Protocols**

| Protocol Name | Type | Mainnet Address | Testnet Address | Currently Integrated | Notes |
|---------------|------|----------------|----------------|---------------------|-------|
| Celer Network | Cross-Chain Bridge | | | ✅ Yes | Cross-chain yield farming |
| Flow Bridge (Native) | Official Flow Bridge | | | ❌ No | Native Flow ecosystem bridge |
| Wormhole | Cross-Chain Bridge | | | ❌ No | Alternative bridge option |
| LayerZero | Cross-Chain Bridge | | | ❌ No | Alternative bridge option |

## **Derivatives/Advanced DeFi**

| Protocol Name | Type | Mainnet Address | Testnet Address | Currently Integrated | Notes |
|---------------|------|----------------|----------------|---------------------|-------|
| Increment (Perps) | Perpetual Futures | | | ❌ No | Delta-neutral strategies |
| Flow Options Protocol | Options | | | ❌ No | Options strategies |
| Flow Prediction Markets | Prediction Markets | | | ❌ No | Prediction-based yield |

## **Infrastructure/Tools**

| Protocol Name | Type | Mainnet Address | Testnet Address | Currently Integrated | Notes |
|---------------|------|----------------|----------------|---------------------|-------|
| Sudocat | Trading Tools | | | ❌ No | Trading analytics |
| Hitdex | Trading Analytics | | | ❌ No | Portfolio management |
| Flow VRF | Randomness Oracle | | | ✅ Yes | Lottery/randomization |
| Flow Price Oracle | Price Feeds | | | ❌ No | Price data |

## **Yield Aggregators/Vaults**

| Protocol Name | Type | Mainnet Address | Testnet Address | Currently Integrated | Notes |
|---------------|------|----------------|----------------|---------------------|-------|
| Flow Yield Protocols | Yield Farming | | | ❌ No | Additional yield sources |
| Auto-Compounding Vaults | Yield Optimization | | | ❌ No | Automated compounding |

## **Insurance/Risk Management**

| Protocol Name | Type | Mainnet Address | Testnet Address | Currently Integrated | Notes |
|---------------|------|----------------|----------------|---------------------|-------|
| Flow Insurance Protocol | Insurance | | | ❌ No | Risk coverage yield |
| Protocol Insurance Funds | Insurance Pools | | | ❌ No | Insurance yield strategies |

## **Governance/DAO**

| Protocol Name | Type | Mainnet Address | Testnet Address | Currently Integrated | Notes |
|---------------|------|----------------|----------------|---------------------|-------|
| Flow DAO Governance | DAO Platform | | | ❌ No | DAO treasury management |
| Governance Token Protocols | Token Governance | | | ❌ No | Governance reward farming |

## **MEV/Validator Infrastructure**

| Protocol Name | Type | Mainnet Address | Testnet Address | Currently Integrated | Notes |
|---------------|------|----------------|----------------|---------------------|-------|
| Flow Validator Network | Validator Infrastructure | | | ❌ No | MEV extraction potential |
| Flow MEV Infrastructure | MEV Tools | | | ❌ No | MEV strategy implementation |

## **Flash Loan Providers**

| Protocol Name | Type | Mainnet Address | Testnet Address | Currently Integrated | Notes |
|---------------|------|----------------|----------------|---------------------|-------|
| Flash Loan Protocols | Flash Loans | | | ❌ No | Zero-capital arbitrage |

## **Synthetic Assets/Structured Products**

| Protocol Name | Type | Mainnet Address | Testnet Address | Currently Integrated | Notes |
|---------------|------|----------------|----------------|---------------------|-------|
| Flow Synthetic Assets | Synthetic Assets | | | ❌ No | Synthetic exposure strategies |
| Structured Product Protocols | Structured Products | | | ❌ No | Complex yield products |

## **NFT-Fi Protocols**

| Protocol Name | Type | Mainnet Address | Testnet Address | Currently Integrated | Notes |
|---------------|------|----------------|----------------|---------------------|-------|
| NFT Lending Protocols | NFT-Backed Loans | | | ❌ No | NFT collateral strategies |
| NFT Yield Farming | NFT Staking | | | ❌ No | NFT-based yield |

## **Token Contracts We Need**

| Token Name | Type | Mainnet Address | Testnet Address | Currently Integrated | Notes |
|------------|------|----------------|----------------|---------------------|-------|
| FLOW | Native Token | | | ✅ Yes (Mock) | Native Flow token |
| USDC | Stablecoin | | | ✅ Yes (Mock) | Primary stablecoin |
| WETH | Wrapped ETH | | | ✅ Yes (Mock) | Ethereum representation |
| USDT | Stablecoin | | | ❌ No | Additional stablecoin |
| WBTC | Wrapped BTC | | | ❌ No | Bitcoin representation |
| ankrFLOW | Liquid Staking Token | | | ✅ Yes | Ankr staked FLOW |

---

## **Integration Priority Levels**

### **🔥 High Priority (Immediate)**
- IncrementFi Router/Factory addresses
- More.Markets lending pool address  
- Ankr Staking contract address
- Celer Bridge contract address
- Flow VRF contract address
- Native FLOW token address
- USDC/USDT token addresses

### **🟡 Medium Priority (Phase 2)**
- Sturdy.Finance contract addresses
- BloctoSwap, PunchSwap, Trado.one router addresses
- Flow native bridge addresses
- Additional DEX factory addresses
- Price oracle contract addresses

### **⚪ Low Priority (Future)**
- Derivatives protocol addresses
- Insurance protocol addresses
- NFT-Fi protocol addresses
- Governance protocol addresses
- MEV infrastructure addresses

---

**Please fill in any missing addresses and confirm protocol availability on Flow mainnet/testnet. Any protocols marked as unavailable can be noted for future integration when they launch.**



# Deployment:
ppwoork@Patricks-MacBook-Pro contract-deployment % npx hardhat run scripts/deploy-modular.js --network flow_mainnet 
WARNING: You are currently using Node.js v23.9.0, which is not supported by Hardhat. This can lead to unexpected behavior. See https://hardhat.org/nodejs-versions


🚀 Starting Complete Flow EVM Yield Lottery Deployment...

📡 Network connectivity test:
  - Chain ID: 747
  - Network name: flow_mainnet
  - Deployer balance: 2.8804066813 ETH
  ✅ Network connection successful

Deploying contracts with account: 0xbaD4374FeB7ec757027CF2186B6eb6f32412f723
Account balance: 2.8804066813 FLOW

1️⃣ Deploying Core Infrastructure...

  📌 Deploying VRF Lottery System...
    Attempt 1/3 for FlowVRFLotterySystem...
    ✅ FlowVRFLotterySystem deployed successfully: 0xeB66cC603eD2AC3E4E74D0Be392be7A747C063db
  📌 Deploying Multi-Asset Manager...
    Attempt 1/3 for MultiAssetManager...
    ✅ MultiAssetManager deployed successfully: 0x37DD94B5edE7DBA0404C5F0A4BAd3eA732F8F084
  📌 Deploying Strategy Manager...
    Attempt 1/3 for StrategyManager...
    ✅ StrategyManager deployed successfully: 0x8097bFd42E50eaEabb9c8f452E2519ED907162D6
  📌 Deploying Risk Manager...
    Attempt 1/3 for RiskManager...
    ✅ RiskManager deployed successfully: 0xC37696f3710240a38a0728DfD26396A406b30021

2️⃣ Deploying Core Vault...
    Attempt 1/3 for CoreFlowYieldVault...
    ✅ CoreFlowYieldVault deployed successfully: 0xb844E10D7a293D1B9b5E49631A1C017C631f3B3C
  📌 Deploying Lottery Manager...
    Attempt 1/3 for LotteryManager...
    ✅ LotteryManager deployed successfully: 0x3C7278042E9BAB5F58BB04E2b538F6A8e7D77cc5

3️⃣ Deploying Arbitrage Infrastructure...
  📌 Deploying Arbitrage DEX Manager...
    Attempt 1/3 for ArbitrageDEXManager...
    ✅ ArbitrageDEXManager deployed successfully: 0x0922E33168463E92e53E53BBF28cfA65096DeFe3
  📌 Deploying Arbitrage Scanner...
    Attempt 1/3 for ArbitrageScanner...
    ✅ ArbitrageScanner deployed successfully: 0x7D5CEc4C3d204b3B190C70D997e384Ad19ebA3ef
  📌 Deploying Arbitrage Core...
    Attempt 1/3 for ArbitrageCore...
    ✅ ArbitrageCore deployed successfully: 0x20E5812C56b48461285af2bF16A83D6aB4d05ee2

4️⃣ Deploying Active Strategies...

  📌 Deploying Ankr Staking Strategy...
    Attempt 1/3 for AnkrStakingStrategy...
    ✅ AnkrStakingStrategy deployed successfully: 0x0eF0250cfE8923A6652aAb4249B26be23C1949FE
  📌 Deploying More.Markets Strategy...
    Attempt 1/3 for MoreMarketsStrategy...
    ✅ MoreMarketsStrategy deployed successfully: 0xca1C60CFB1354D83a7d37928f3Fd87ae80BFd33F
  📌 Deploying Stargate Bridge Strategy...
    Attempt 1/3 for StargateBridgeStrategy...
    ✅ StargateBridgeStrategy deployed successfully: 0x5b84B6813799D1b382b9cF3148f5323Bb72B89f9
  📌 Deploying More.Markets Looping Strategy...
    Attempt 1/3 for MoreMarketsLoopingStrategy...
    ✅ MoreMarketsLoopingStrategy deployed successfully: 0xdCC9FDC6f3F497522B11343a481D2b38CDAAf51d
  📌 Deploying Enhanced Arbitrage Strategy...
    Attempt 1/3 for MinimalArbitrageStrategy...
    ✅ MinimalArbitrageStrategy deployed successfully: 0x5097E217a77ebc8EF40eAEaB28122F5b678C7315

5️⃣ Deploying Advanced Strategies (Inactive)...

  📌 Deploying Delta Neutral Strategy...
    Attempt 1/3 for DeltaNeutralStrategy...
    ✅ DeltaNeutralStrategy deployed successfully: 0x0001C2D813FcC3Fd16Ba8940e2a72035cAF4D537
  📌 Deploying Concentrated Liquidity Strategy...
    Attempt 1/3 for ConcentratedLiquidityStrategy...
    ✅ ConcentratedLiquidityStrategy deployed successfully: 0xa77E2F25d9432DFB65d76104C25aD0024833E67D

6️⃣ Connecting Components to Vault...

    Attempt 1/3 for Set MultiAssetManager...
    ✅ Set MultiAssetManager completed successfully
    Attempt 1/3 for Set StrategyManager...
    ✅ Set StrategyManager completed successfully
    Attempt 1/3 for Set LotteryManager...
    ✅ Set LotteryManager completed successfully
    Attempt 1/3 for Set RiskManager...
    ✅ Set RiskManager completed successfully
  📌 Granting vault roles...
    Attempt 1/3 for Grant vault role to MultiAssetManager...
    ✅ Grant vault role to MultiAssetManager completed successfully
    Attempt 1/3 for Grant vault role to StrategyManager...
    ✅ Grant vault role to StrategyManager completed successfully
    Attempt 1/3 for Grant vault role to RiskManager...
    ✅ Grant vault role to RiskManager completed successfully
    Attempt 1/3 for Grant strategy manager role to RiskManager...
    ✅ Grant strategy manager role to RiskManager completed successfully
    Attempt 1/3 for Grant strategy role to DEX Manager...
    ✅ Grant strategy role to DEX Manager completed successfully
    Attempt 1/3 for Grant strategy role to Arbitrage Scanner...
    ✅ Grant strategy role to Arbitrage Scanner completed successfully
    Attempt 1/3 for Grant strategy role to Arbitrage Core...
    ✅ Grant strategy role to Arbitrage Core completed successfully

7️⃣ Adding Active Strategies to Strategy Manager...

    Attempt 1/3 for Add Ankr strategy (25%)...
    ✅ Add Ankr strategy (25%) completed successfully
    Attempt 1/3 for Add More.Markets strategy (35%)...
    ✅ Add More.Markets strategy (35%) completed successfully
    Attempt 1/3 for Add Stargate strategy (15%)...
    ✅ Add Stargate strategy (15%) completed successfully
    Attempt 1/3 for Add Looping strategy (20%, High Risk)...
    ✅ Add Looping strategy (20%, High Risk) completed successfully
    Attempt 1/3 for Add Arbitrage strategy (5%, Medium Risk)...
    ✅ Add Arbitrage strategy (5%, Medium Risk) completed successfully
    Attempt 1/3 for Add Looping strategy to risk monitoring...
    ✅ Add Looping strategy to risk monitoring completed successfully
    Attempt 1/3 for Add Arbitrage strategy to risk monitoring...
    ✅ Add Arbitrage strategy to risk monitoring completed successfully

8️⃣ Configuring Lottery System...

    Attempt 1/3 for Grant vault role to lottery system...
    ✅ Grant vault role to lottery system completed successfully




    # NEWEST:

🏗️  STEP 1: DEPLOYING CORE INFRASTRUCTURE
==========================================
1. Deploying SimplePriceOracle...
✅ SimplePriceOracle: 0x777C515eDAC5D3c5019408DD483f6eD197bd3c0e

2. Deploying TrueMultiAssetVault...
✅ TrueMultiAssetVault: 0x32607bcA2a2F0f8Fc14ab05781a487adAB6d45A4

3. Deploying MultiAssetStrategyManager...
✅ MultiAssetStrategyManager: 0xf4b25F941e59df707CD903F8b5b579c9fB959f4D

4. Deploying LotteryManager...
✅ LotteryManager: 0x879ac7b36FE027fE98883bcCFd309A6c3064B9e0

5. Deploying RiskManager...
✅ RiskManager: 0xAAa7b4d344061Ebc1996CEE28d1097aaE7E47576

🔗 STEP 2: CONNECTING INFRASTRUCTURE TO VAULT
==============================================
Setting StrategyManager on vault...
✅ StrategyManager connected
Setting LotteryManager on vault...
✅ LotteryManager connected
Setting RiskManager on vault...
✅ RiskManager connected
✅ Price updater role granted

⚡ STEP 3: DEPLOYING UPDATED STRATEGIES
======================================
1. Deploying AnkrStakingStrategy...
✅ AnkrStakingStrategy: 0xad582458E86B256016c79aC86ef76C1768E82E28

2. Deploying MoreMarketsStrategy...
✅ MoreMarketsStrategy: 0xc36BB4e16a21F11F3f33E056E8c2F77AaAEa4c19

3. Deploying MinimalArbitrageStrategy...
✅ MinimalArbitrageStrategy: 0x9B9200084b3d679A1080AD5eBBC262e9Ff84b2a0

4. Deploying MoreMarketsLoopingStrategy...
✅ MoreMarketsLoopingStrategy: 0xA6E703d9B684B4b124dDADdBbA35D7FDC1305Ba0

📝 STEP 4: REGISTERING STRATEGIES
=================================
Registering AnkrStakingStrategy...
✅ AnkrStakingStrategy registered
Registering MoreMarketsStrategy...
✅ MoreMarketsStrategy registered
Registering ArbitrageStrategy...
✅ ArbitrageStrategy registered
Registering LoopingStrategy...
✅ LoopingStrategy registered



NEW NEWEST:
📋 DEPLOYED CONTRACT ADDRESSES:
===============================
priceOracle         : 0x6ceAfE90D0804c0736252aE1ac2AC3883F10fd5C
vault               : 0x801aaAa568B519EdE5DB39EA1b6Af287631f7Fdb
strategyManager     : 0x5A7F59b5B987Ba7022DF7Cc438be17C52683b12a
lotteryManager      : 0x530050F3E471e750FA611581074F48B7333EB9AB
riskManager         : 0x8c8d87cbE4A2273C4450a80DAc6a8DDc6eF030dF
ankrStrategy        : 0xD612C7c84b3F37c84c5eBfe81D110FE231C6bD6f
moreMarketsStrategy : 0xcbFd08923dC3cb5E63084d31B486462Ec41ab560
arbitrageStrategy   : 0x552DC31602284878b90Ff2c09Ae4f33403F9AcD7
loopingStrategy     : 0x1A029BCD103447205c2365CE969540bE7E4B9120