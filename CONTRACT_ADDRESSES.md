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