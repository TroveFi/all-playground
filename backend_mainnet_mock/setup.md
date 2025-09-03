# Flow EVM Yield Strategy Deployment Structure

TEST EACH COMPONENT 1 BY 1

## FULL Project Structure
```
flow-yield-strategies/
├── contracts/
│   ├── core/
│   │   ├── EtherlinkVaultCore.sol              # Main vault (rename to FlowVaultCore.sol)
│   │   ├── VaultFactory.sol                    # Factory for creating vaults
│   │   └── AutoDepositProxy.sol                # Auto-deposit proxy for bridges
│   │   └── LotteryExtension.sol                # Auto-deposit proxy for bridges
│   ├── strategies/
│   │   ├── lending/
│   │   │   ├── MoreMarketsStrategy.sol         # More.Markets (Aave-style) lending
│   │   │   └── BaseStrategy.sol                # Base strategy contract
│   │   ├── dex/
│   │   │   ├── PunchSwapV2Strategy.sol         # PunchSwap V2 liquidity provision
│   │   │   ├── IZiSwapV3Strategy.sol           # iZiSwap V3 concentrated liquidity
│   │   │   └── SimpleDEXStrategy.sol           # Simplified DEX strategy base
│   │   ├── staking/
│   │   │   ├── IncrementStakingStrategy.sol    # stFlow staking strategy
│   │   │   └── AnkrStakingStrategy.sol         # ankrFLOW staking strategy
│   │   └── bridge/
│   │       └── StargateStrategy.sol            # Cross-chain yield via Stargate
│   ├── extensions/
│   │   ├── LotteryExtension.sol                # Lottery functionality
│   │   └── OptimizationExtension.sol           # Strategy optimization
│   ├── registries/
│   │   ├── FlowProtocolRegistry.sol            # Real protocol registry for Flow
│   │   └── StrategyRegistry.sol                # Strategy management
│   ├── bridges/
│   │   ├── StargateBridge.sol                  # Stargate LayerZero integration
│   │   └── IBridge.sol                         # Bridge interface
│   ├── oracles/
│   │   ├── PythOracle.sol                      # Pyth price oracle integration
│   │   ├── StorkOracle.sol                     # Stork oracle integration
│   │   ├── RiskOracle.sol                      # ML risk assessment oracle
│   │   └── YieldAggregator.sol                 # Yield aggregation oracle
│   ├── vrf/
│   │   ├── FlowVRF.sol                         # Flow Cadence Arch VRF
│   │   └── LotteryRandomness.sol               # Lottery randomness provider
│   ├── interfaces/
│   │   ├── IStrategies.sol                     # Strategy interface
│   │   ├── IStrategyRegistry.sol                     # ??? maybe needed
│   │   ├── IFlowProtocols.sol                  # Flow protocol interfaces
│   │   └── IOracles.sol                        # Oracle interfaces
│   └── utils/
│       ├── FlowConstants.sol                   # Flow EVM protocol addresses
│       └── FlowHelpers.sol                     # Helper functions
│   └── yield/
│       ├── YieldAggregator.sol                   # duped with the one at oracles??
│       ├── YieldAmplifierExtension.sol                   # is this the right place?
├── deployment/
│   ├── deploy-core.js                          # Core contracts deployment
│   ├── deploy-strategies.js                    # Strategy deployment
│   ├── deploy-oracles.js                       # Oracle deployment
│   └── configure-protocols.js                 # Protocol configuration
├── config/
│   ├── flow-mainnet.json                       # Flow mainnet configuration
│   ├── ethereum-mainnet.json                   # Ethereum config for bridging
│   └── supported-tokens.json                   # Supported token addresses
└── python-agent/
    ├── yield_optimizer.py                      # ML yield optimization
    ├── risk_assessor.py                        # Risk assessment model
    ├── rebalancer.py                           # Strategy rebalancing
    └── bridge_monitor.py                       # Cross-chain monitoring
```

## Real Protocol Addresses (Flow EVM Mainnet)

### Core Assets
- WFLOW: 0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e
- USDC: 0xF1815bd50389c46847f0Bda824eC8da914045D14
- USDT: 0x674843C06FF83502ddb4D37c2E09C01cdA38cbc8
- USDF: 0x2aaBea2058b5aC2D339b163C6Ab6f2b6d53aabED
- WETH: 0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590
- stFlow: 0x5598c0652B899EB40f169Dd5949BdBE0BF36ffDe
- ankrFLOWEVM: 0x1b97100eA1D7126C4d60027e231EA4CB25314bdb

### DEX Protocols
- PunchSwap V2 Router: 0xf45AFe28fd5519d5f8C1d4787a4D5f724C0eFa4d
- PunchSwap V2 Factory: 0x29372c22459a4e373851798bFd6808e71EA34A71
- iZiSwap Factory: 0x8c7d3063579BdB0b90997e18A770eaE32E1eBb08
- iZiSwap Router: 0x3EF68D3f7664b2805D4E88381b64868a56f88bC4
- iZiSwap Liquidity Manager: 0x19b683A2F45012318d9B2aE1280d68d3eC54D663

### Lending Protocols
- More.Markets Pool Provider: 0x1830a96466d1d108935865c75B0a9548681Cfd9A
- More.Markets Pool: 0xbC92aaC2DBBF42215248B5688eB3D3d2b32F2c8d

### Bridges
- Stargate USDC: 0xF1815bd50389c46847f0Bda824eC8da914045D14
- Stargate USDT: 0x674843C06FF83502ddb4D37c2E09C01cdA38cbc8
- Stargate ETH: 0x3E628d164EeD30eBd3C78C616D0B6DEa5bE7d063

### Oracles
- Pyth Oracle: 0x2880aB155794e7179c9eE2e38200202908C17B43
- Stork Oracle: 0xacC0a0cF13571d30B4b8637996F5D6D774d4fd62

### VRF
- Flow Cadence Arch VRF: 0x0000000000000000000000010000000000000001

## Strategy Priority Order
1. **More.Markets Lending** - Low risk, steady yield
2. **PunchSwap V2 LP** - Medium risk, DEX fees
3. **iZiSwap V3 Concentrated LP** - Higher risk, concentrated liquidity
4. **stFlow/ankrFLOW Staking** - Low risk, FLOW staking rewards
5. **Cross-chain Bridge to Ethereum** - For accessing higher yields on mainnet

## Deployment Steps
1. Deploy core vault infrastructure
2. Deploy and register strategies
3. Configure oracles and risk assessment
4. Set up cross-chain bridging
5. Initialize Python agent with strategy parameters
6. Begin yield optimization and rebalancing


SUPER IMPORTANT -> ADD A REALLY NICE UI FOR WHEN THE PERSON CLAIMS THEIR YIELD TO CLEARLY SHOW THE OPTIONS THEY HAVE WITH 100X-ing THE YIELD FOR A 1% CHANCE -> LEVELS OF GAMBLING REPRESENTED BY COLORS OR ICONS ETC, SHOWING THE DIFFERENT PAYOUTS FOR EACH RISK TIER

TOTAL APY = X%

MAKE SURE USERS YIELD = X% OF FUNDS STAKED

# INSENTIVE SYSTEM:

ADD INSENTIVE FOR BETTER ODDS IN THE FUTURE TO PROMOTE USE?!? 

-> A TOKEN SYSTEM?!?! USERS CAN COLLECT TOKENS WHICH THEY GET FROM STAKING TO GET BETTER ODDS -> ODDS WEIGH THEIR TOKEN BALANCE INTO CALCULATION!!