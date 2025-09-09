Expected APY Breakdown:
WFLOW/USDC Looping Strategy:

Supply APY on WFLOW: ~8-12% (estimated based on More.Markets rates)
Borrow Cost on USDC: ~6-10%
1.5x Leverage Effect:

Gross yield: 12% × 1.5 = 18%
Borrow cost: 8% × 0.5 = 4%
Net APY: ~14% (18% - 4%)



With Optimizations:

Auto-rebalancing: +1-2% APY
Efficient gas usage: +0.5% APY
Keeper automation: +0.5% APY
Total Expected APY: 16-17%



Optimal Flow EVM Looping Setup:
1. Realistic Asset Pairs for Looping:

Primary Strategy: WFLOW (collateral) ↔ USDC/USDT (borrow)
Alternative Strategy: WETH (collateral) ↔ USDC/USDT (borrow)
Conservative Strategy: USDC (collateral) ↔ USDF (borrow)

2. Why This Works on Flow EVM:

More.Markets Integration: Uses the actual Aave V3 fork on Flow
Liquid Assets Only: WFLOW, WETH, USDC, USDT all have good liquidity
PunchSwap DEX: Uses the primary DEX with actual liquidity
Realistic Parameters: Conservative 1.5x leverage initially