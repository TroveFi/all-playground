#!/usr/bin/env python3
# deployable_apy_strict.py
# STRICT, agent-safe deployable APY for Flow EVM:
#  - KittyPunch UniswapV2 pools only (on-chain volume → fees)
#  - More.Markets supply APY (if local DB present)
#  - NO CLMMs, NO aggregator "headline" APYs
#  - Zero inputs; prints $1k/$5k/$10k/$100k/$1m deployable APY

import sqlite3, json, time, math
from pathlib import Path
from web3 import Web3

# ----------------- knobs (conservative) -----------------
RPC = "https://mainnet.evm.nodes.onflow.org"
FEE_TO_LPS = 0.0025                 # 0.25% v2 LP fee share
BLOCKS_PER_DAY = 108000             # ~0.8s/block on Flow EVM
LOOKBACK_BLOCKS_24H = 108000        # sample ~24h swaps
LOOKBACK_BLOCKS_7D = 108000*7       # sample ~7d swaps (smoothing)
CHUNK = 1500                        # chunk size for getLogs (avoid 413)
TOKENS = {
  # symbol:   address, decimals, approx USD (for printing only)
  "WFLOW": {"addr":"0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e","dec":18,"usd":0.62},
  "ANKRF": {"addr":"0x1b97100eA1D7126C4d60027e231EA4CB25314bdb","dec":18,"usd":0.62},
  "USDCe": {"addr":"0xA1A0f9e96cCEB7ca9aA1b3aEd9f2B0f3A2d9cC65","dec":6,"usd":1.00},  # replace if your USDC.e differs
  "USDF" : {"addr":"0x9D9d6453B9c94C7C3E00d9f405a7AA31C52aef2E","dec":18,"usd":1.00},  # replace if needed
  "WETH" : {"addr":"0x4200000000000000000000000000000000000006","dec":18,"usd":2000.0}
}
# Candidate v2 pairs (symbol tuples). Add more if you want to scan wider.
CANDIDATES = [
  ("WFLOW","USDCe"),
  ("WFLOW","ANKRF"),
  ("WFLOW","USDF"),
  ("WFLOW","WETH"),
  ("USDF","USDCe"),
]
KITTY_FACTORY_V2 = "0x29372c22459a4e373851798bFd6808e71EA34A71"  # KittyPunch factory (v2)
MORE_DB = "more_markets_dynamic_apy.db"                           # optional local DB from your tracker
UNI_DB  = "univ2_fee_apy.db"                                      # we also store a local snapshot

TICKET_SIZES = [1_000, 5_000, 10_000, 100_000, 1_000_000]

# --------------- ABIs / topics ---------------
FACTORY_ABI=[{"constant":True,"inputs":[{"name":"tokenA","type":"address"},{"name":"tokenB","type":"address"}],
              "name":"getPair","outputs":[{"name":"pair","type":"address"}],"type":"function"}]
PAIR_ABI = [
  {"constant":True,"inputs":[],"name":"getReserves","outputs":[
    {"name":"reserve0","type":"uint112"},{"name":"reserve1","type":"uint112"},{"name":"blockTimestampLast","type":"uint32"}],"type":"function"},
  {"constant":True,"inputs":[],"name":"token0","outputs":[{"name":"","type":"address"}],"type":"function"},
  {"constant":True,"inputs":[],"name":"token1","outputs":[{"name":"","type":"address"}],"type":"function"},
]
SWAP_TOPIC0 = "0xd78ad95fa46c994b6551d0da85fc275fe613ce37657fb8d5e3d130840159d822"

# ----------------- helpers -----------------
def chunked_swap_volume(w3, pair, dec0, dec1, from_block, to_block, chunk=1500):
    vol0 = 0.0; vol1 = 0.0; swaps = 0
    for start in range(from_block, to_block+1, chunk):
        end = min(start + chunk - 1, to_block)
        try:
            logs = w3.eth.get_logs({
                "fromBlock": start, "toBlock": end,
                "address": Web3.to_checksum_address(pair),
                "topics": [SWAP_TOPIC0]
            })
        except Exception:
            continue
        for lg in logs:
            data = lg["data"]
            if not data or len(data) < 2+64*4:  # "0x" + 4 words
                continue
            words = [int(data[2+i*64: 2+(i+1)*64], 16) for i in range(4)]
            a0in,a1in,a0out,a1out = words
            vol0 += (a0in + a0out) / (10**dec0)
            vol1 += (a1in + a1out) / (10**dec1)
            swaps += 1
    return vol0, vol1, swaps

def get_pair(w3, factory, a, b):
    f = w3.eth.contract(address=Web3.to_checksum_address(factory), abi=FACTORY_ABI)
    p = f.functions.getPair(Web3.to_checksum_address(a), Web3.to_checksum_address(b)).call()
    return p if int(p,16)!=0 else None

def get_reserves(w3, pair):
    pr = w3.eth.contract(address=Web3.to_checksum_address(pair), abi=PAIR_ABI)
    r0,r1,_ = pr.functions.getReserves().call()
    t0 = pr.functions.token0().call()
    t1 = pr.functions.token1().call()
    return r0,r1,t0,t1

def usd_value(r0f,r1f,p0,p1): return r0f*p0 + r1f*p1

def store_univ2_snapshot(pair, label, tvl_usd, vol24_usd, fee_apr, fee_apy, swaps):
    Path(UNI_DB).touch(exist_ok=True)
    with sqlite3.connect(UNI_DB) as c:
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
        )""")
        c.execute("""INSERT INTO pool_fee_apy
              (timestamp, block_number, pair_address, label, tvl_num, vol24_num, fee_apr, fee_apy, swaps, meta)
              VALUES (?,?,?,?,?,?,?,?,?,?)""",
              (int(time.time()), 0, pair, label, tvl_usd, vol24_usd, fee_apr, fee_apy, swaps,
               json.dumps(dict(source="strict"))))
        c.commit()

def load_more_markets_rows():
    if not Path(MORE_DB).exists(): return []
    rows=[]
    try:
        with sqlite3.connect(MORE_DB) as c:
            # try a common schema; fall back if different
            cols = [x[1] for x in c.execute("PRAGMA table_info(more_markets_apy_history)").fetchall()]
            if {"asset_symbol","supply_apy","total_deposits"}.issubset(set(cols)):
                q = """SELECT asset_symbol, supply_apy, total_deposits
                       FROM more_markets_apy_history
                       WHERE timestamp=(SELECT MAX(timestamp) FROM more_markets_apy_history)"""
                for asset, apy, tvl in c.execute(q).fetchall():
                    rows.append(dict(asset=str(asset or ""), apy=float(apy or 0.0), tvl=float(tvl or 0.0)))
    except Exception:
        pass
    return rows

def main():
    w3 = Web3(Web3.HTTPProvider(RPC, request_kwargs={'timeout':30}))
    if not w3.is_connected(): 
        print("RPC not connected"); return

    pairs=[]
    # discover KittyPunch v2 pairs
    for s0,s1 in CANDIDATES:
        if s0 not in TOKENS or s1 not in TOKENS: continue
        a = TOKENS[s0]["addr"]; b = TOKENS[s1]["addr"]
        p = get_pair(w3, KITTY_FACTORY_V2, a, b)
        if p: pairs.append((s0,s1,p))

    # compute v2 fee APY using 24h + 7d smoothing
    results=[]
    for s0,s1,pair in pairs:
        t0=TOKENS[s0]; t1=TOKENS[s1]
        r0,r1,tok0,tok1 = get_reserves(w3, pair)
        # match ordering to reserves
        if tok0.lower()==t0["addr"].lower() and tok1.lower()==t1["addr"].lower():
            dec0,dec1 = t0["dec"], t1["dec"]; p0,p1 = t0["usd"], t1["usd"]
        elif tok1.lower()==t0["addr"].lower() and tok0.lower()==t1["addr"].lower():
            # switched
            r0,r1 = r1,r0
            dec0,dec1 = t0["dec"], t1["dec"]; p0,p1 = t0["usd"], t1["usd"]
        else:
            # unknown ordering; skip
            continue

        r0f = r0/(10**dec0); r1f = r1/(10**dec1)
        tvl_usd = usd_value(r0f,r1f,p0,p1)

        cur = w3.eth.block_number
        frm24 = max(1, cur-LOOKBACK_BLOCKS_24H)
        frm7d  = max(1, cur-LOOKBACK_BLOCKS_7D)

        vol0_24, vol1_24, swaps24 = chunked_swap_volume(w3, pair, dec0, dec1, frm24, cur, CHUNK)
        vol0_7d, vol1_7d, swaps7d = chunked_swap_volume(w3, pair, dec0, dec1, frm7d, cur, CHUNK)

        vol24_usd = vol0_24*p0 + vol1_24*p1
        vol7d_usd = vol0_7d*p0 + vol1_7d*p1
        # use EMA-ish smoothing: 70% from 24h, 30% from (7d/7)
        vol_smoothed = 0.7*vol24_usd + 0.3*(vol7d_usd/7.0 if vol7d_usd>0 else vol24_usd)

        fees_day = vol_smoothed * FEE_TO_LPS
        fee_apr_fullrange = (fees_day / max(tvl_usd,1e-12)) * 365 * 100
        fee_apy_fullrange = ((1 + fees_day/max(tvl_usd,1e-12))**365 - 1) * 100

        # store a local snapshot for your meta tools
        store_univ2_snapshot(pair, f"{s0}-{s1}", tvl_usd, vol_smoothed, fee_apr_fullrange, fee_apy_fullrange, swaps24)

        # compute deployable for ticket sizes (pure v2: pro-rata on total TVL)
        deploy_cols={}
        for size in TICKET_SIZES:
            denom = max(tvl_usd + size, 1.0)
            apr = (fees_day / denom) * 365 * 100
            apy = ((1 + (fees_day/denom))**365 - 1) * 100
            deploy_cols[size] = apy

        results.append(dict(
            label=f"{s0}-{s1}", pair=pair, tvl=tvl_usd, vol=vol_smoothed,
            swaps=swaps24, apy_by_size=deploy_cols
        ))

    # More.Markets lending (if DB exists) — fixed APY, not size-dependent
    more_rows = load_more_markets_rows()

    # ---------- print ----------
    print(f"=== STRICT DEPLOYABLE APY (Flow EVM v2 only) @ {time.strftime('%Y-%m-%d %H:%M:%S')} ===")
    print("(on-chain fees only, UniswapV2 pools; CLMM/elastic excluded; 24h+7d-smoothed volume; fee=0.25%)\n")
    header = f"{'APY $1k':>9s} {'$5k':>8s} {'$10k':>8s} {'$100k':>8s} {'$1m':>8s}  {'TVL':>12s} {'1dVol*':>12s}  {'Pool':<14s}  Pair"
    print(header); print("-"*len(header))
    # rank by $10k
    results.sort(key=lambda r: r['apy_by_size'][10_000], reverse=True)
    for r in results:
        d=r['apy_by_size']
        print(f"{d[1_000]:9.2f}% {d[5_000]:8.2f}% {d[10_000]:8.2f}% {d[100_000]:8.2f}% {d[1_000_000]:8.2f}%  "
              f"${r['tvl']:>11,.0f} ${r['vol']:>11,.0f}  {r['label']:<14s}  {r['pair']}")
    print("-"*len(header))
    print("* vol = 0.7×24h + 0.3×(7d/7) from on-chain swaps; CLMMs are intentionally excluded.\n")

    if more_rows:
        print("More.Markets (supply APY — capacity not size-limited, but utilization may change):")
        for m in more_rows:
            print(f" - {m['asset']:<10s} | Supply APY {m['apy']:.4f}% | Deposits ${m['tvl']:,.0f}")
