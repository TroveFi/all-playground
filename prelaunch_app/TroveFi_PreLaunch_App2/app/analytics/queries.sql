Daily Transaction Volume

Flow Daily Metric Activity


SELECT 
    block_date,
    COUNT(*) as daily_txs,
    COUNT(DISTINCT "from") as unique_senders,
    COUNT(DISTINCT "to") as unique_receivers,
    AVG(gas_used) as avg_gas_used,
    SUM(CASE WHEN success = true THEN 1 ELSE 0 END) * 100.0 / COUNT(*) as success_rate,
    LAG(COUNT(*), 7) OVER (ORDER BY block_date) as txs_7d_ago,
    (COUNT(*) - LAG(COUNT(*), 7) OVER (ORDER BY block_date)) * 100.0 / LAG(COUNT(*), 7) OVER (ORDER BY block_date) as tx_change_7d
FROM flow.transactions
WHERE block_date >= CURRENT_DATE - INTERVAL '30' day
GROUP BY block_date
ORDER BY block_date DESC


//////


Gas Usage & Transaction Success Rate

Flow Transaction Metrics

SELECT 
    block_date,
    AVG(gas_used * gas_price / 1e18) as avg_gas_cost_flow,
    AVG(gas_used * gas_price / 1e9) as avg_gas_cost_gwei, 
    COUNT(*) as total_transactions,
    SUM(CASE WHEN success = true THEN 1 ELSE 0 END) as successful_txs
FROM flow.transactions
WHERE block_date >= CURRENT_DATE - INTERVAL '7' day
GROUP BY block_date
ORDER BY block_date DESC




//////

Block Production & Size

Flow Block Production 


SELECT 
    date,
    COUNT(*) as blocks_produced,
    AVG(gas_used * 100.0 / gas_limit) as avg_gas_utilization,
    2.5 as avg_block_time, -- Flow has ~2.5s block time
    AVG(size) as avg_block_size
FROM flow.blocks
WHERE date >= CURRENT_DATE - INTERVAL '7' day
GROUP BY date
ORDER BY date DESC
LIMIT 1


///////


Address Growth & Activity

Flow Address Activity

WITH daily_addresses AS (
    SELECT 
        block_date,
        COUNT(DISTINCT "from") as unique_addresses_24h,
        COUNT(DISTINCT CASE WHEN value > 0 THEN "from" END) as value_transfer_addresses
    FROM flow.transactions
    WHERE block_date >= CURRENT_DATE - INTERVAL '7' day
    GROUP BY block_date
),
address_changes AS (
    SELECT 
        *,
        LAG(unique_addresses_24h, 1) OVER (ORDER BY block_date) as prev_unique_addresses
    FROM daily_addresses
)
SELECT 
    block_date,
    unique_addresses_24h,
    value_transfer_addresses,
    prev_unique_addresses,
    CASE 
        WHEN prev_unique_addresses IS NOT NULL AND prev_unique_addresses > 0
        THEN (unique_addresses_24h - prev_unique_addresses) * 100.0 / prev_unique_addresses
        ELSE 0 
    END as addr_change_24h
FROM address_changes
ORDER BY block_date DESC


//////
TESTING:
Increment stFlow Metrics


-- Get stFlow/FLOW price and staking data
WITH stflow_events AS (
  SELECT 
    block_time,
    block_date,
    contract_address,
    -- Parse stFlow mint/burn events to calculate price
    -- This requires decoding the specific event logs
    CASE 
      WHEN topic0 = 0x... -- stFlow mint event signature
      THEN CAST(data AS DOUBLE) / 1e18
    END as flow_amount,
    CASE 
      WHEN topic0 = 0x... -- stFlow mint event signature  
      THEN CAST(topic1 AS DOUBLE) / 1e18
    END as stflow_amount
  FROM flow.logs_decoded
  WHERE contract_address = 0x5598c0652B899EB40f169Dd5949BdBE0BF36ffDe -- stFlow EVM address
    AND block_date >= CURRENT_DATE - INTERVAL '7' day
)
SELECT 
  MAX(block_date) as latest_date,
  -- Calculate stFlow/FLOW exchange rate
  AVG(flow_amount / NULLIF(stflow_amount, 0)) as stflow_flow_rate,
  SUM(flow_amount) as total_flow_staked,
  COUNT(*) as staking_transactions
FROM stflow_events
WHERE flow_amount IS NOT NULL AND stflow_amount IS NOT NULL



/////


-- IncrementFi DEX trading volume and liquidity
SELECT 
  block_date,
  COUNT(*) as swap_transactions,
  -- Decode swap events from IncrementFi router
  SUM(CASE WHEN topic0 = 0x... THEN CAST(data AS DOUBLE) / 1e18 END) as total_volume_flow,
  COUNT(DISTINCT tx_from) as unique_traders
FROM flow.logs_decoded
WHERE contract_address IN (
  0xa6850776a94e6551, -- SwapRouter (Cadence)
  -- Add EVM equivalent addresses if available
) 
AND block_date >= CURRENT_DATE - INTERVAL '7' day
GROUP BY block_date
ORDER BY block_date DESC


//////


-- Track bridge volume for USDC, USDT, WETH etc
SELECT 
  block_date,
  contract_address,
  CASE 
    WHEN contract_address = 0xF1815bd50389c46847f0Bda824eC8da914045D14 THEN 'USDC'
    WHEN contract_address = 0x674843C06FF83502ddb4D37c2E09C01cdA38cbc8 THEN 'USDT'
    WHEN contract_address = 0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590 THEN 'WETH'
    ELSE 'Other'
  END as token_name,
  COUNT(*) as bridge_transactions,
  SUM(CAST(data AS DOUBLE) / 1e18) as total_volume
FROM flow.logs_decoded
WHERE contract_address IN (
  0xF1815bd50389c46847f0Bda824eC8da914045D14, -- USDC
  0x674843C06FF83502ddb4D37c2E09C01cdA38cbc8, -- USDT  
  0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590  -- WETH
)
AND block_date >= CURRENT_DATE - INTERVAL '7' day
GROUP BY block_date, contract_address
ORDER BY block_date DESC



/////

-- FLOW/USDC price from DEX trades
SELECT 
  block_date,
  AVG(CASE 
    WHEN topic1 = 'FLOW' AND topic2 = 'USDC' 
    THEN CAST(data AS DOUBLE) 
  END) as flow_usd_price
FROM flow.logs_decoded  
WHERE contract_address IN (
  0x87048a97526c4B66b71004927D24F61DEFcD6375 -- KittyPunch Router
)
AND block_date >= CURRENT_DATE - INTERVAL '1' day
GROUP BY block_date
ORDER BY block_date DESC
LIMIT 1



////

Daily transfers by token 


-- Flow EVM Token Transfer Activity with Summary Metrics
WITH token_transfers AS (
  SELECT 
    block_date,
    CASE 
      WHEN contract_address = 0xF1815bd50389c46847f0Bda824eC8da914045D14 THEN 'USDC'
      WHEN contract_address = 0x674843C06FF83502ddb4D37c2E09C01cdA38cbc8 THEN 'USDT'
      WHEN contract_address = 0x2aaBea2058b5aC2D339b163C6Ab6f2b6d53aabED THEN 'USDF'
      WHEN contract_address = 0x7f27352D5F83Db87a5A3E00f4B07Cc2138D8ee52 THEN 'USDC.e'
      WHEN contract_address = 0x1b97100eA1D7126C4d60027e231EA4CB25314bdb THEN 'ankrFLOW'
      WHEN contract_address = 0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590 THEN 'WETH'
      WHEN contract_address = 0xA0197b2044D28b08Be34d98b23c9312158Ea9A18 THEN 'cbBTC'
      WHEN contract_address = 0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e THEN 'WFLOW'
      ELSE 'Other'
    END as token_name,
    COUNT(*) as daily_transfers,
    COUNT(DISTINCT tx_from) as unique_senders,
    COUNT(DISTINCT CAST(topic2 AS VARCHAR)) as unique_receivers
  FROM flow.logs
  WHERE contract_address IN (
    0xF1815bd50389c46847f0Bda824eC8da914045D14,  -- USDC
    0x674843C06FF83502ddb4D37c2E09C01cdA38cbc8,  -- USDT
    0x2aaBea2058b5aC2D339b163C6Ab6f2b6d53aabED,  -- USDF
    0x7f27352D5F83Db87a5A3E00f4B07Cc2138D8ee52,  -- USDC.e
    0x1b97100eA1D7126C4d60027e231EA4CB25314bdb,  -- ankrFLOW
    0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590,  -- WETH
    0xA0197b2044D28b08Be34d98b23c9312158Ea9A18,  -- cbBTC
    0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e   -- WFLOW
  )
  AND topic0 = 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef  -- Transfer event
  AND block_date >= CURRENT_DATE - INTERVAL '7' day
  GROUP BY block_date, contract_address
),
daily_data AS (
  SELECT 
    block_date,
    token_name,
    daily_transfers,
    unique_senders,
    unique_receivers
  FROM token_transfers
),
summary_metrics AS (
  SELECT 
    SUM(CASE WHEN token_name = 'USDF' THEN daily_transfers ELSE 0 END) as total_usdf_transfers,
    SUM(CASE WHEN token_name = 'USDC' THEN daily_transfers ELSE 0 END) as total_usdc_transfers,
    SUM(CASE WHEN token_name = 'ankrFLOW' THEN daily_transfers ELSE 0 END) as total_ankrflow_transfers,
    SUM(CASE WHEN token_name = 'USDT' THEN daily_transfers ELSE 0 END) as total_usdt_transfers,
    SUM(CASE WHEN token_name = 'WETH' THEN daily_transfers ELSE 0 END) as total_weth_transfers,
    SUM(unique_senders) as total_unique_senders,
    SUM(daily_transfers) as total_all_transfers,
    COUNT(DISTINCT block_date) as days_tracked
  FROM daily_data
  WHERE block_date >= CURRENT_DATE - INTERVAL '7' day
)
SELECT 
  -- Daily breakdown
  block_date,
  token_name,
  daily_transfers,
  unique_senders,
  unique_receivers,
  -- Add percentage of daily activity
  ROUND(daily_transfers * 100.0 / SUM(daily_transfers) OVER (PARTITION BY block_date), 2) as pct_of_daily_volume
FROM daily_data
WHERE token_name != 'Other'
ORDER BY block_date DESC, daily_transfers DESC





/////


Token Activity:


-- Token transfer activity (counts only, no amounts)
SELECT 
  block_date,
  CASE 
    WHEN contract_address = 0xF1815bd50389c46847f0Bda824eC8da914045D14 THEN 'USDC'
    WHEN contract_address = 0x674843C06FF83502ddb4D37c2E09C01cdA38cbc8 THEN 'USDT'
    WHEN contract_address = 0x2aaBea2058b5aC2D339b163C6Ab6f2b6d53aabED THEN 'USDF'
    WHEN contract_address = 0x1b97100eA1D7126C4d60027e231EA4CB25314bdb THEN 'ankrFLOW'
    ELSE 'Other'
  END as token_name,
  COUNT(*) as daily_transfers,
  COUNT(DISTINCT tx_from) as unique_senders,
  COUNT(DISTINCT CAST(topic2 AS VARCHAR)) as unique_receivers
FROM flow.logs
WHERE contract_address IN (
  0xF1815bd50389c46847f0Bda824eC8da914045D14,  -- USDC
  0x674843C06FF83502ddb4D37c2E09C01cdA38cbc8,  -- USDT
  0x2aaBea2058b5aC2D339b163C6Ab6f2b6d53aabED,  -- USDF
  0x1b97100eA1D7126C4d60027e231EA4CB25314bdb   -- ankrFLOW
)
AND topic0 = 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
AND block_date >= CURRENT_DATE - INTERVAL '7' day
GROUP BY block_date, contract_address
ORDER BY block_date DESC, daily_transfers DESC