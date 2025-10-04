# Delta Neutral Strategy - Complete Setup Guide

## 🎯 Strategy Overview

**What it does:**
1. Stakes FLOW → stFLOW on Flow blockchain (earns ~15% staking APR)
2. Shorts FLOW on Binance perpetual futures
3. Result: Market neutral position that earns staking rewards minus funding costs

**Net APR Formula:**
```
Net APR = Staking APR - Funding Rate - Fees - Gas Costs
```

---

## 📋 Prerequisites

### 1. Flow Blockchain Setup

**Option A: Using Flow CLI (Recommended for beginners)**
```bash
# Install Flow CLI
sh -ci "$(curl -fsSL https://raw.githubusercontent.com/onflow/flow-cli/master/install.sh)"

# Verify installation
flow version

# Initialize project
flow init

# Import your account (follow prompts)
flow accounts add my-account
```

**Option B: Using Flow Python SDK**
```bash
pip install flow-py-sdk
```

### 2. Binance Futures Setup

1. Create Binance account at https://www.binance.com
2. Complete KYC verification
3. Enable Futures trading
4. Generate API keys:
   - Go to: API Management
   - Create new key
   - Enable "Futures" permissions
   - Save API Key and Secret (never share these!)

### 3. Install Python Dependencies

```bash
pip install ccxt flow-py-sdk
```

---

## 🚀 Quick Start (CLI Method)

### Step 1: Save the Cadence Transaction

Save this as `stake_simple.cdc`:

```cadence
import FungibleToken from 0xf233dcee88fe0abe
import FlowToken from 0x1654653399040a61
import stFlowToken from 0xd6f80565193ad727
import LiquidStaking from 0xd6f80565193ad727

transaction(flowAmount: UFix64) {
    let flowVault: auth(FungibleToken.Withdraw) &FlowToken.Vault
    let stFlowVaultRef: &stFlowToken.Vault

    prepare(acct: auth(Storage, Capabilities) &Account) {
        self.flowVault = acct.storage
            .borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(from: /storage/flowTokenVault)
            ?? panic("Missing /storage/flowTokenVault")

        if acct.storage.borrow<&stFlowToken.Vault>(from: stFlowToken.tokenVaultPath) == nil {
            acct.storage.save(
                <-stFlowToken.createEmptyVault(vaultType: Type<@stFlowToken.Vault>()), 
                to: stFlowToken.tokenVaultPath
            )
            acct.capabilities.unpublish(stFlowToken.tokenReceiverPath)
            acct.capabilities.unpublish(stFlowToken.tokenBalancePath)
            acct.capabilities.publish(
                acct.capabilities.storage.issue<&{FungibleToken.Receiver}>(stFlowToken.tokenVaultPath),
                at: stFlowToken.tokenReceiverPath
            )
            acct.capabilities.publish(
                acct.capabilities.storage.issue<&{FungibleToken.Balance}>(stFlowToken.tokenVaultPath),
                at: stFlowToken.tokenBalancePath
            )
        }
        self.stFlowVaultRef = acct.storage.borrow<&stFlowToken.Vault>(from: stFlowToken.tokenVaultPath)!
    }

    execute {
        let flowVault <- self.flowVault.withdraw(amount: flowAmount) as! @FlowToken.Vault
        let stFlowVault <- LiquidStaking.stake(flowVault: <-flowVault)
        self.stFlowVaultRef.deposit(from: <-stFlowVault)
        log("STAKED=".concat(flowAmount.toString()))
    }
}
```

### Step 2: Execute Strategy Using Python Script

```bash
# Using the CLI orchestrator
python delta_neutral_cli_script.py \
    --amount 1000 \
    --account my-account \
    --binance-key YOUR_BINANCE_KEY \
    --binance-secret YOUR_BINANCE_SECRET \
    --leverage 3 \
    --network mainnet
```

**Parameters:**
- `--amount`: FLOW amount to stake (e.g., 1000)
- `--account`: Your Flow account name from flow.json
- `--binance-key`: Your Binance API key
- `--binance-secret`: Your Binance API secret
- `--leverage`: Perp leverage (default: 3x)
- `--network`: mainnet or testnet

---

## 🔧 Manual Execution (Step by Step)

If you prefer to execute each step manually:

### Step 1: Stake FLOW on Flow

```bash
flow transactions send stake_simple.cdc \
    --arg UFix64:1000.0 \
    --signer my-account \
    --network mainnet
```

### Step 2: Short on Binance (Python)

```python
import ccxt

binance = ccxt.binance({
    'apiKey': 'YOUR_KEY',
    'secret': 'YOUR_SECRET',
    'options': {'defaultType': 'future'}
})

# Set leverage
binance.set_leverage(3, 'FLOW/USDT:USDT')

# Open short
order = binance.create_market_sell_order(
    symbol='FLOW/USDT:USDT',
    amount=1000  # Match your staked amount
)

print(f"Short opened: {order}")
```

---

## 📊 Monitoring Your Position

### Using Your Risk Scripts

```python
from main_agent_script import FlowStakingAgent
from data_fetcher_script import FlowDataFetcher

# Initialize
agent = FlowStakingAgent()
fetcher = FlowDataFetcher()

# Get market data
market_data = fetcher.get_all_market_data()
agent.update_market_data(market_data)

# Add your position
agent.add_delta_neutral_position('my_position', {
    'staked_flow': 1000,
    'stflow_amount': 1000,
    'perp_size': 1000,
    'perp_entry_price': 0.75,
    'perp_margin': 250,  # For 3x leverage
    'perp_leverage': 3,
    'perp_maintenance_margin_ratio': 0.05,
    'spot_liquidity_usd': 3000000,
    'perp_liquidity_usd': 10000000
})

# Calculate metrics
results = agent.calculate_delta_neutral_metrics('my_position')
print(results)
```

### Key Metrics to Monitor

1. **Hedge Drift**: Should stay < 5%
   - If > 5%: Rebalance by adjusting perp size

2. **Perp Liquidation Distance**: Should stay > 20%
   - If < 20%: Add margin or reduce leverage

3. **Net APR**: Should be positive
   - If negative: Funding rate too high, consider closing

4. **Basis Risk**: Perp vs spot spread
   - If > 5%: High execution risk

---

## 🔄 Rebalancing

### When to Rebalance

Run this check regularly (every 6-24 hours):

```python
status = executor.get_status()
hedge_drift = status['hedge_drift_pct']

if hedge_drift > 5:
    print(f"⚠️ Hedge drift at {hedge_drift:.2f}% - rebalance needed!")
    # Calculate adjustment
    target_short = status['staked_flow']
    current_short = status['perp_size']
    adjustment = target_short - current_short
    
    if adjustment > 0:
        print(f"Need to SHORT {adjustment} more FLOW")
    else:
        print(f"Need to CLOSE {abs(adjustment)} FLOW short")
```

### Execute Rebalance

```python
# If need to increase short
binance.create_market_sell_order('FLOW/USDT:USDT', amount=adjustment)

# If need to reduce short
binance.create_market_buy_order('FLOW/USDT:USDT', amount=abs(adjustment), 
                                params={'reduceOnly': True})
```

---

## 💰 Expected Returns

### Sample Calculation

**Position:**
- Staked: 10,000 FLOW @ $0.75 = $7,500
- Perp Short: 10,000 FLOW @ 3x leverage
- Margin Posted: $2,500

**Income:**
- Staking APR: 15% = $1,125/year
- Funding Rate: +0.01% per 8h = +11% APR = +$825/year (YOU RECEIVE as short)

**Costs:**
- Trading Fees: ~0.5% annually = -$37.50/year
- Gas Costs: ~$50/year
- Slippage: ~0.2% annually = -$15/year

**Net APR:**
```
Net = $1,125 + $825 - $37.50 - $50 - $15
    = $1,847.50 per year
    = 24.6% APR on $7,500 position
```

*Note: Funding rates vary. This assumes positive funding (shorts receive).*

---

## ⚠️ Risks & Mitigation

### 1. Perp Liquidation Risk
- **Risk**: Perp gets liquidated if FLOW price rises too much
- **Mitigation**: 
  - Use conservative leverage (3x max)
  - Monitor liquidation price daily
  - Add margin if distance < 20%

### 2. Negative Funding Rate
- **Risk**: If funding goes strongly negative, you pay to hold short
- **Mitigation**:
  - Monitor funding rate
  - Close position if funding < -10% annually
  - Your scripts calculate breakeven funding rate

### 3. stFLOW Depeg
- **Risk**: stFLOW price deviates from FLOW
- **Mitigation**:
  - Monitor peg ratio (should be ~1.0)
  - Close if depeg > 5%

### 4. Smart Contract Risk
- **Risk**: Bug in Increment Finance contracts
- **Mitigation**:
  - Contracts are audited (check Increment docs)
  - Don't deploy more than you can afford to lose
  - Consider insurance protocols when available

### 5. Exchange Risk
- **Risk**: Binance freezes withdrawals or has issues
- **Mitigation**:
  - Use reputable exchange
  - Don't keep excess funds on exchange
  - Have backup exchange ready

---

## 🛠️ Troubleshooting

### Issue: Staking succeeded but shorting failed

```python
# Your position is NOT delta neutral!
# Manually open short on Binance to complete hedge

# Check your staked amount
# Then execute:
binance.create_market_sell_order('FLOW/USDT:USDT', amount=YOUR_STAKED_AMOUNT)
```

### Issue: Hedge drift is high

```bash
# Check current positions
python -c "
from delta_neutral_cli_script import SimpleDeltaNeutralExecutor
executor = SimpleDeltralExecutor(...)
print(executor.get_status())
"

# Rebalance as needed
```

### Issue: Gas estimation failed

```bash
# Increase gas limit in flow.json
# Or use --gas-limit flag with Flow CLI
flow transactions send stake_simple.cdc --gas-limit 9999
```

---

## 📈 Advanced: Automated Monitoring

Set up cron job for monitoring (Linux/Mac):

```bash
# Create monitoring script
cat > monitor_delta_neutral.sh << 'EOF'
#!/bin/bash
python3 << PYTHON
from delta_neutral_cli_script import SimpleDeltaNeutralExecutor
import json

executor = SimpleDeltaNeutralExecutor(
    flow_account_name="my-account",
    binance_api_key="YOUR_KEY",
    binance_secret="YOUR_SECRET"
)

status = executor.get_status()
if status['hedge_drift_pct'] > 5:
    print(f"ALERT: Hedge drift {status['hedge_drift_pct']:.2f}%")
    # Send notification (email, Discord, etc.)
PYTHON
EOF

chmod +x monitor_delta_neutral.sh

# Add to crontab (run every 6 hours)
crontab -e
# Add line:
0 */6 * * * /path/to/monitor_delta_neutral.sh
```

---

## 📚 Next Steps

1. **Start Small**: Test with small amount first (100-500 FLOW)
2. **Monitor Daily**: Check metrics for first week
3. **Optimize**: Use your APR scripts to find optimal parameters
4. **Scale Up**: Increase position size once comfortable
5. **Automate**: Set up monitoring and alerts

## 🔗 Resources

- Flow Documentation: https://developers.flow.com
- Increment Finance: https://docs.increment.fi
- Binance Futures: https://www.binance.com/en/futures
- Your Risk Scripts: Use the Python suite for monitoring

---

## ⚡ Quick Command Reference

```bash
# Execute delta neutral
python delta_neutral_cli_script.py --amount 1000 --account my-account --binance-key KEY --binance-secret SECRET

# Check Flow balance
flow accounts get 0xYOUR_ADDRESS --network mainnet

# Check stFLOW balance
flow scripts execute check_stflow_balance.cdc --arg Address:0xYOUR_ADDRESS

# Monitor Binance position
python -c "import ccxt; b=ccxt.binance({'apiKey':'KEY','secret':'SECRET'}); print(b.fetch_positions(['FLOW/USDT:USDT']))"
```

Good luck with your delta neutral strategy! 🚀