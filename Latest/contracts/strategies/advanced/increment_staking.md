Expected APY Breakdown:
Increment Staking (stFlow) — using 10.5% historical average

Baseline (staking-only)
• Base staking APY (historical avg): 10.5%
• EVM operational friction (bridge latency/fees, idle buffer, thin AMM slippage if naïve): −0.2% to −0.6%

Realized APY (naïve EVM): ~9.9–10.3%


With Agent Optimizations (additive to realized APY)

1) Epoch-aware scheduling & compounding
   • Stake/unstake just after epoch rollover; avoid last 6–12h of epoch downtime
   • +0.15% to +0.35%

2) Cross-VM batching & buffer minimization
   • Batch stake/unstake; keep dynamic 5–10% WFLOW buffer; auto-replenish
   • +0.15% to +0.35%

3) Discount capture vs redemption (when EVM AMMs trade below NAV)
   • Accumulate stFlow at 0.3–1.0% discounts; redeem via queue; 20–40% monthly turnover
   • +0.5% to +2.0% (volume-limited)

4) Peg market-making (tight CLMM bands around redemption with auto-exit)
   • Earn swap fees near NAV; strict IL guards/TWAP exits
   • +0.3% to +1.0%

5) Optional funding/basis overlay (only when positive)
   • Hedge FLOW exposure with small perp short when funding > 0
   • +0.0% to +1.5%


Total Expected APY (agent-optimized, EVM-side)
• Conservative: ~11.2%  (≈ 9.9% + 1.3%)
• Mid-case:     ~12.9%  (≈ 10.1% + 2.8%)
• Stretch:      ~14–15% (requires persistent discounts, healthy CLMM volume, and positive funding)

Assumptions: redemption-based NAV (no double-counting), bridge fees low-single bps, discounts appear intermittently, and risk guards (max deviation, epoch windows, CLMM auto-exit) are enforced.




On-chain components (EVM)
1) SafeVault (ERC-4626)

Assets accepted: WFLOW (primary).

Shares: ERC-20 vault shares.

Buffers: keep X% WFLOW buffer for instant withdrawals; rest allocated to strategies.

Hooks: afterDeposit/ beforeWithdraw to talk to StrategyManager.

Core fns:

deposit(amountWFLOW, receiver)

withdraw(shares, receiver, owner)

totalAssets() (sums: buffer + strategy assets via IBaseStrategy.totalAssets())

2) StrategyManager

Registry of strategies, target weights, caps, and emergency pause.

Routing: allocate(amount, strategy) / deallocate(amount, strategy) from/to Vault.

Rate-limits cross-VM notional per block/epoch.

3) IncrementStakingStrategy

Single source of truth for positions staked on Cadence Increment.

No ERC-20 position token is held on EVM; instead you track position notional and Cadence exchange rate.

Uses precompile to:

stake: bridge WFLOW → FLOW, call Increment stake(amount).

unstake: call Increment unstake(amount), bridge FLOW → WFLOW.

Pulls the stFlow exchange rate (or totalFlow/totalShares) from Cadence via a view call through precompile for accurate totalAssets().

Core fns:

stakeWFLOW(uint256 amount) → (precompile) → emits CadenceStake(id, amount, receiptsHash)

unstakeToWFLOW(uint256 amountWFLOW) → (precompile) → emits CadenceUnstake(id, amount, receiptsHash)

totalAssets() → reads cached exchange rate (see Oracle below) and local position notional.

Guards:

minExchangeRate, maxSlippageBps, maxBridgeLatency, retryWindow.

onlyStrategyManager modifiers for mutation.

4) CrossVMLane (facade)

Thin library/contract that wraps the precompile ABI for:

callCadence(bytes cadenceTx, bytes[] proofs, BridgeAction[] actions) returns (bytes receipts)

Minimal idempotency: include a nonce (EVM chainId + vault + opId).

Standardizes error codes (bridge timeout, Cadence revert, proof invalid, partial fill).

Implementation note: Package this as a library so Strategy bytecode stays compact.

5) StFlowRateOracle

Truth source: Cadence stFlow exchange rate.

Two modes (you can support both, feature flag):

Pull mode (preferred): pullRate() calls Cadence view via precompile every HARVEST_INTERVAL.

Push mode (fallback): a keeper quorum posts updateRate(rate, sigs[]) with threshold signatures.

Emits RateUpdated(rate, cadenceBlockHeight, receiptsHash).

IncrementStakingStrategy.totalAssets() uses:

assets = (positionShares * exchangeRate)  // or positionFlowNotional, depending on how you book it

Cadence side (Increment)

Existing Increment staking contracts own validator delegation & reward accounting.

You will need two Cadence entry points your precompile can call:

stake(flowAmount, beneficiaryEvmAddress, nonce)

unstake(stFlowShares, beneficiaryEvmAddress, nonce)

Each returns receipts (amount in/out, fee, epoch, new exchange rate, tx id).

A small VM-bridge adapter (Cadence) may be required to map beneficiary EVM addresses and emit receipt data in a fixed ABI.

End-to-end flows
A) Deposit (WFLOW → staked on Increment)

User calls SafeVault.deposit(WFLOW).

StrategyManager.allocate pushes surplus buffer to IncrementStakingStrategy.

IncrementStakingStrategy.stakeWFLOW(amount)

Calls CrossVMLane.callCadence(...) with payload:

Bridge WFLOW → FLOW

Cadence call: stake(amountFlow, vaultEvmAddr, nonce)

Receives receipts: stFlow minted, exchange rate, cadence height.

Strategy updates internal position shares/notional; StFlowRateOracle is refreshed on schedule.

B) Withdraw (WFLOW)

If vault buffer ≥ request → instant pay.

Else StrategyManager.deallocate → IncrementStakingStrategy.unstakeToWFLOW(amountNeeded)

Precompile calls Cadence: unstake(shares, vaultEvmAddr, nonce) → bridge FLOW → WFLOW → back to Strategy.

Strategy transfers WFLOW back to Vault; Vault pays user.

Any shortfall becomes queued withdrawal with max T+N window and partial fills allowed.