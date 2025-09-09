Expected APY Breakdown:
Agent-Managed Blend (Looping + Ankr Staking + Increment Staking)

Inputs (per-strategy, agent-optimized but realistic on Flow EVM)
• Increment (stFlow): use your historical avg 10.5% base; agent lift from execution/discounts → 11.5–13.5%
• Ankr (ankrFLOW): 6.0–7.0% base; agent lift (buffer use, timing) → 6.6–7.8%
• Looping (WFLOW/USDC on lender): regime-dependent; net after borrow → 10–14% mid, 6–10% conservative, 16–18% stretch (with clean spreads + tight LTV bands)

Scenario A — Conservative (choppy markets, tight spreads)
Weights: 55% Increment, 25% Ankr, 20% Looping
Per-leg APY (assumed): 10.8%, 7.0%, 10.0%
Weighted APY: 0.55×10.8 + 0.25×7.0 + 0.20×10.0 = 9.69%
Rotation/vol-harvest alpha: +0.3–0.6%
Total Expected APY: ~10.0–10.3%

Scenario B — Mid-Case (steady conditions)
Weights: 45% Increment, 15% Ankr, 40% Looping
Per-leg APY (assumed): 12.4%, 7.4%, 13.5%
Weighted APY: 0.45×12.4 + 0.15×7.4 + 0.40×13.5 = 12.09%
Rotation/vol-harvest alpha: +0.5–0.8%
Total Expected APY: ~12.6–12.9%

Scenario C — Stretch (favorable borrow spreads + stFlow discounts)
Weights: 35% Increment, 10% Ankr, 55% Looping
Per-leg APY (assumed): 13.8%, 7.8%, 17.0%
Weighted APY: 0.35×13.8 + 0.10×7.8 + 0.55×17.0 = 14.96%
Rotation/vol-harvest alpha: +0.8–1.2%
Total Expected APY: ~15.8–16.2%


Agent Optimizations (earning alpha)

• Epoch-aware Cadence ops (stFlow): stake/unstake just after epoch rollover; avoid last 6–12h → +0.15–0.35%
• Discount capture (stFlow): buy < NAV on EVM, redeem via queue; size-limited → +0.5–2.0%
• Cross-VM batching & buffer bands: 5–10% WFLOW cash buffer; batch bridge/stake/unstake → +0.15–0.35%
• Looping LTV governor: dynamic 1.3–1.6×, health-factor floors, auto-deleverage → +0.5–1.5% vs naïve
• Borrow-rate arb: tilt Looping only when (supply – borrow) spread > threshold; otherwise park in Increment/Ankr
• Peg MM sleeve (optional): tight CLMM near stFlow NAV with auto-exit on deviation → +0.3–1.0%
• Rotation rules: rebalance when expected after-fee APY deltas > X bps; add TWAP/vol filters to avoid churn

Risk Notes
• Looping is the variance driver (liquidation/borrow spikes); cap exposure and enforce stop bands.
• EVM AMM slippage + bridge latency: modeled in the ranges above; spikes can compress alpha temporarily.
• Use redemption-rate NAV for stFlow/ankrFLOW (don’t double-count “exchange-rate appreciation” as extra yield).
