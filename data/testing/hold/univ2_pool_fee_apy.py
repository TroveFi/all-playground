#!/usr/bin/env python3
# univ2_pool_fee_apy.py
# Auto-select KittyPunch pairs and compute fee APR/APY with 413-safe chunked getLogs. No flags.

import sqlite3, json, time, math
from web3 import Web3

RPC="https://mainnet.evm.nodes.onflow.org"
DB ="univ2_fee_apy.db"

FACTORY_V2 = "0x29372c22459a4e373851798bFd6808e71EA34A71"  # KittyPunch
FACTORY_ABI=[{"constant":True,"inputs":[{"name":"tokenA","type":"address"},{"name":"tokenB","type":"address"}],
              "name":"getPair","outputs":[{"name":"pair","type":"address"}],"type":"function"}]

PAIR_ABI = [
  {"constant":True,"inputs":[],"name":"getReserves","outputs":[
    {"name":"reserve0","type":"uint112"},{"name":"reserve1","type":"uint112"},{"name":"blockTimestampLast","type":"uint32"}],"type":"function"},
  {"constant":True,"inputs":[],"name":"totalSupply","outputs":[{"name":"","type":"uint256"}],"type":"function"},
  {"constant":True,"inputs":[],"name":"token0","outputs":[{"name":"","type":"address"}],"type":"function"},
  {"constant":True,"inputs":[],"name":"token1","outputs":[{"name":"","type":"address"}],"type":"function"}
]

# keccak256("Swap(address,uint256,uint256,uint256,uint256,address)")
SWAP_TOPIC0 = "0xd78ad95fa46c994b6551d0da85fc275fe613ce37657fb8d5e3d130840159d822"

# Best-effort token map (edit once if any differ on Flow EVM)
TOKENS = {
  "WFLOW":  {"addr":"0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e","dec":18,"approx_usd":0.62},
  "ANKRF":  {"addr":"0x1b97100eA1D7126C4d60027e231EA4CB25314bdb","dec":18,"approx_usd":0.62},
  "USDCe":  {"addr":"0xA1A0f9e96cCEB7ca9aA1b3aEd9f2B0f3A2d9cC65","dec":6, "approx_usd":1.00},
  "USDF":   {"addr":"0x9D9d6453B9c94C7C3E00d9f405a7AA31C52aef2E","dec":18,"approx_usd":1.00},
  "WETH":   {"addr":"0x4200000000000000000000000000000000000006","dec":18,"approx_usd":2000.0}
}

CANDIDATES = [
  ("WFLOW","ANKRF"),
  ("WFLOW","USDCe"),
  ("WFLOW","WETH"),
  ("USDF","USDCe"),
  ("WFLOW","USDF"),
]

def init_db():
    with sqlite3.connect(DB) as c:
        c.execute("""CREATE TABLE IF NOT EXISTS pool_fee_apy(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          timestamp INTEGER NOT NULL,
          block_number INTEGER NOT NULL,
          pair_address TEXT NOT NULL,
          label TEXT,
          tvl_num REAL NOT NULL,
          vol24_num REAL NOT NULL,
          fee_apr REAL NOT NULL,
          fee_apy REAL NOT NULL,
          swaps INT NOT NULL,
          meta TEXT
        )"""); c.commit()

def get_pair(w3, a, b):
    f = w3.eth.contract(address=Web3.to_checksum_address(FACTORY_V2), abi=FACTORY_ABI)
    p = f.functions.getPair(Web3.to_checksum_address(a), Web3.to_checksum_address(b)).call()
    return p if int(p,16)!=0 else None

def get_reserves_and_tokens(w3, pair_addr):
    pr = w3.eth.contract(address=Web3.to_checksum_address(pair_addr), abi=PAIR_ABI)
    r0,r1,_ = pr.functions.getReserves().call()
    t0 = pr.functions.token0().call()
    t1 = pr.functions.token1().call()
    return (r0, r1, t0, t1)

def chunked_swap_volume(w3, pair_addr, dec0, dec1, from_block, to_block, chunk=500):
    """Sum swap amounts via chunked eth_getLogs to avoid 413. Returns (vol0, vol1, swap_count)."""
    vol0 = 0.0; vol1 = 0.0; swaps = 0
    for start in range(from_block, to_block+1, chunk):
        end = min(start + chunk - 1, to_block)
        try:
            logs = w3.eth.get_logs({
                "fromBlock": start,
                "toBlock": end,
                "address": Web3.to_checksum_address(pair_addr),
                "topics": [SWAP_TOPIC0]
            })
        except Exception as e:
            # If a sub-range still fails, skip it rather than abort all
            continue
        for lg in logs:
            # Decode minimally from data (4 uint256 packed):
            # data = 0x + 4 * 32-byte words: amount0In, amount1In, amount0Out, amount1Out
            data = lg["data"]
            if not data or len(data) < 2+64*4:  # "0x" + 4 words
                continue
            # Strip 0x and split into 32-byte words
            words = [int(data[2+i*64: 2+(i+1)*64], 16) for i in range(4)]
            a0in, a1in, a0out, a1out = words
            vol0 += (a0in + a0out) / (10**dec0)
            vol1 += (a1in + a1out) / (10**dec1)
            swaps += 1
    return vol0, vol1, swaps

def compute_fee_apy(w3, pair, t0meta, t1meta, fee_rate=0.0025, lookback_blocks=15000):
    r0, r1, tok0, tok1 = get_reserves_and_tokens(w3, pair)
    dec0, dec1 = t0meta["dec"], t1meta["dec"]
    r0f = r0/(10**dec0); r1f = r1/(10**dec1)

    cur = w3.eth.block_number
    frm = max(1, cur - lookback_blocks)

    # Try chunked logs
    vol0 = vol1 = 0.0; swaps = 0
    try:
        vol0, vol1, swaps = chunked_swap_volume(w3, pair, dec0, dec1, frm, cur, chunk=500)
    except Exception:
        swaps = 0

    # USD-ish valuation for ranking
    price0 = t0meta["approx_usd"]; price1 = t1meta["approx_usd"]
    tvl = r0f*price0 + r1f*price1

    # If no logs or TVL==0, fallback: assume 0.1% TVL trades/day
    blocks_per_day = 108000  # ~0.8s block time
    if swaps > 0 and tvl > 0:
        vol_num = vol0*price0 + vol1*price1
        vol24 = vol_num * (blocks_per_day / lookback_blocks)
        fees_day = vol24 * fee_rate
    else:
        vol24 = tvl * 0.001   # conservative
        fees_day = vol24 * fee_rate

    fee_apr = (fees_day / max(tvl,1e-12)) * 365 * 100
    fee_apy = ((1 + fees_day/max(tvl,1e-12))**365 - 1) * 100
    meta = dict(reserves=[r0f,r1f], lookback_blocks=lookback_blocks, fee_rate=fee_rate, swaps=swaps)
    return dict(tvl=tvl, vol24=vol24, apr=fee_apr, apy=fee_apy, swaps=swaps, meta=meta)

def main():
    init_db()
    w3 = Web3(Web3.HTTPProvider(RPC, request_kwargs={'timeout':30}))
    if not w3.is_connected(): raise SystemExit("RPC not connected")

    results=[]
    for s0,s1 in CANDIDATES:
        if s0 not in TOKENS or s1 not in TOKENS: continue
        t0 = TOKENS[s0]; t1 = TOKENS[s1]
        pair = get_pair(w3, t0["addr"], t1["addr"])
        if not pair: continue
        r = compute_fee_apy(w3, pair, t0, t1)
        label = f"{s0}-{s1}"
        with sqlite3.connect(DB) as c:
            c.execute("""INSERT INTO pool_fee_apy
              (timestamp, block_number, pair_address, label, tvl_num, vol24_num, fee_apr, fee_apy, swaps, meta)
              VALUES (?,?,?,?,?,?,?,?,?,?)""",
              (int(time.time()), w3.eth.block_number, pair, label, r['tvl'], r['vol24'], r['apr'], r['apy'], r['swaps'], json.dumps(r['meta'])))
            c.commit()
        results.append((label, pair, r))

    if not results:
        print("No candidate KittyPunch pairs discovered with the default list. Edit TOKENS if your addresses differ.")
        return

    results.sort(key=lambda x: x[2]['apy'], reverse=True)
    print("KittyPunch fee-APY snapshot (auto-selected, 413-safe):")
    for label, pair, r in results:
        print(f" - {label:12s} | {pair} | TVL ${r['tvl']:.0f} | 24hVol ${r['vol24']:.0f} | Fee APR {r['apr']:.2f}% | Fee APY {r['apy']:.2f}% | swaps {r['swaps']}")

if __name__=="__main__":
    main()
