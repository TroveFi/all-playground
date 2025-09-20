# Core Loop:

Stake FLOW → Get stFLOW (liquid staking token)
Borrow FLOW against stFLOW collateral
Repeat to amplify exposure and yield


# Current Looping Challenges:

Manual monitoring of liquidation ratios
Manual rebalancing when positions drift
Gas costs for frequent adjustments
Timing risks during market volatility

Native Flow looping 

borrow stETH against ETH

Flow for automation logic, bridge to other chains for yields


# Scheduled txn integration:
## Automated Monitoring Intervals:

Emergency situations (LTV >75%): Every 30 minutes
High risk (LTV 65-75%): Every 2 hours
Normal operations: Every 24 hours
Optimization opportunities: Every 8 hours

## Flow Actions Atomic Composition
Single Transaction Operations:

Check LTV ratio
Calculate optimal action (leverage up/down)
Execute position adjustment
Update monitoring schedule

# Further Optimisations


Could trigger based on:
- Volatility thresholds (reduce leverage in high vol)
- Yield rate changes (rebalance when rates shift)
- Liquidation cascade detection (emergency exits)
- Gas price optimization (execute during low congestion)

## Advanced Scheduling:

Yield harvesting: Compound rewards daily at optimal times
Rebalancing: Weekly optimization during low volatility periods
Risk management: Continuous monitoring with escalating frequencies

## Advanced Scheduling:

Yield harvesting: Compound rewards daily at optimal times
Rebalancing: Weekly optimization during low volatility periods
Risk management: Continuous monitoring with escalating frequencies

