# 1. Get all available farm pools
flow scripts execute cadence/scripts/get-increment-pools.cdc --network mainnet

# 2. Calculate liquidity amounts (example with 1 FLOW and 0.77 stFLOW, 1% slippage)
flow scripts execute cadence/scripts/calculate-liquidity-amounts.cdc \
  --args-json '[{"type":"UFix64","value":"1.0"},{"type":"UFix64","value":"0.77"},{"type":"UFix64","value":"0.01"}]' \
  --network mainnet

# 3. Get your current LP positions
flow scripts execute cadence/scripts/get-user-lp-positions.cdc \
  --args-json '[{"type":"Address","value":"0x79f5b5b0f95a160b"}]' \
  --network mainnet