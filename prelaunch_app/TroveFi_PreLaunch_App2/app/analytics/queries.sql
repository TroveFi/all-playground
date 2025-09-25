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
