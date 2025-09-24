flow transactions send cadence/transactions/DEX_swap_FLOW–stFLOW.cdc \       
  --args-json '[
    {"type":"UFix64","value":"1.00000000"}
  ]' \
  --signer mainnet-deployer --network mainnet


  flow transactions send cadence/transactions/stake-flow-to-stflow.cdc \
  --args-json '[{"type":"UFix64","value":"1.00000000"}]' \
  --signer mainnet-deployer --network mainnet