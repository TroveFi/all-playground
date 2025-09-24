#!/usr/bin/env python3
# deployable_apy_strict_scan.py
# Agent-safe deployable APY for Flow EVM — KittyPunch v2 pools only (factory scan),
# adaptive lookback (1d→7d→30d), chunked getLogs, USD only for known tokens.

import json, time
from pathlib import Path
from web3 import Web3

# ---------- conservative knobs ----------
RPC = "https://mainnet.evm.nodes.onflow.org"
FEE_TO_LPS = 0.0025
BLOCKS_PER_DAY = 108000
CHUNK = 1500
MAX_PAIRS = 300          # scan first N pairs from factory (raise if you want)
MIN_TVL_USD = 10_000     # skip dust pools
TOKENS = {
  "WFLOW": {"addr":"0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e","dec":18,"usd":0.62},
  "ANKRF": {"addr":"0x1b97100eA1D7126C4d60027e231EA4CB25314bdb","dec":18,"usd":0.62},  # keep if this matches your ankrFLOW addr used in your pair
  "USDCe": {"addr":"0x7f27352D5F83Db87a5A3E00f4B07Cc2138D8ee52","dec":6,"usd":1.00},
  "USDF" : {"addr":"0x2aaBea2058b5aC2D339b163C6Ab6f2b6d53aabED","dec":18,"usd":1.00},
  "WETH" : {"addr":"0x4200000000000000000000000000000000000006","dec":18,"usd":2000.0}
}

ADDR2META = {v["addr"].lower(): {"sym":k, **v} for k,v in TOKENS.items()}

TICKET_SIZES = [1_000, 5_000, 10_000, 100_000, 1_000_000]

# ---------- ABIs / topics ----------
FACTORY = "0x29372c22459a4e373851798bFd6808e71EA34A71"  # KittyPunch v2 factory
FACTORY_ABI = [
  {"inputs":[{"internalType":"uint256","name":"","type":"uint256"}],
   "name":"allPairs","outputs":[{"internalType":"address","name":"","type":"address"}],
   "stateMutability":"view","type":"function"},
  {"inputs":[],"name":"allPairsLength","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],
   "stateMutability":"view","type":"function"}
]
PAIR_ABI = [
  {"inputs":[],"name":"getReserves","outputs":[
    {"name":"reserve0","type":"uint112"},{"name":"reserve1","type":"uint112"},{"name":"blockTimestampLast","type":"uint32"}],
   "stateMutability":"view","type":"function"},
  {"inputs":[],"name":"token0","outputs":[{"type":"address"}],"stateMutability":"view","type":"function"},
  {"inputs":[],"name":"token1","outputs":[{"type":"address"}],"stateMutability":"view","type":"function"},
]
# keccak("Swap(address,uint256,uint256,uint256,uint256,address)")
SWAP_TOPIC0 = "0xd78ad95fa46c994b6551d0da85fc275fe613ce37657fb8d5e3d130840159d822"

def chunked_volume(w3, pair, dec0, dec1, from_block, to_block, chunk=CHUNK):
    vol0 = vol1 = 0.0; swaps = 0
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

def try_windows(w3, pair, dec0, dec1, p0, p1, cur_block):
    # Try 1d, else 7d, else 30d; return (vol_per_day_usd, days, swaps)
    for days, blocks in [(1, BLOCKS_PER_DAY), (7, BLOCKS_PER_DAY*7), (30, BLOCKS_PER_DAY*30)]:
        frm = max(1, cur_block - blocks)
        v0, v1, n = chunked_volume(w3, pair, dec0, dec1, frm, cur_block)
        usd = v0*p0 + v1*p1
        if usd > 0 and n > 0:
            return usd/days, days, n
    return 0.0, 0, 0

def main():
    w3 = Web3(Web3.HTTPProvider(RPC, request_kwargs={'timeout':30}))
    if not w3.is_connected():
        print("ERROR: RPC not connected"); return

    factory = w3.eth.contract(address=Web3.to_checksum_address(FACTORY), abi=FACTORY_ABI)
    total = factory.functions.allPairsLength().call()
    total = min(total, MAX_PAIRS)

    pairs=[]
    for i in range(total):
        try:
            addr = factory.functions.allPairs(i).call()
        except Exception:
            continue
        pairs.append(addr)

    if not pairs:
        print("No pairs returned from factory (or MAX_PAIRS too low)."); return

    cur = w3.eth.block_number
    results=[]

    for pair in pairs:
        pr = w3.eth.contract(address=Web3.to_checksum_address(pair), abi=PAIR_ABI)
        try:
            t0 = pr.functions.token0().call().lower()
            t1 = pr.functions.token1().call().lower()
            r0, r1, _ = pr.functions.getReserves().call()
        except Exception:
            continue

        # only evaluate pairs where we know USD for both tokens (so $-sized deploy is meaningful)
        if t0 not in ADDR2META or t1 not in ADDR2META:
            continue

        m0, m1 = ADDR2META[t0], ADDR2META[t1]
        dec0, dec1 = m0["dec"], m1["dec"]
        p0, p1 = m0["usd"], m1["usd"]

        r0f = r0/(10**dec0); r1f = r1/(10**dec1)
        tvl_usd = r0f*p0 + r1f*p1
        if tvl_usd < MIN_TVL_USD:
            continue

        vol_per_day_usd, window_days, swaps = try_windows(w3, pair, dec0, dec1, p0, p1, cur)
        # if still 0, skip — no activity in last 30d or RPC blocked logs.
        if vol_per_day_usd <= 0 or swaps == 0:
            continue

        fees_day = vol_per_day_usd * FEE_TO_LPS
        # deployable APY for ticket sizes
        apy_by_size={}
        for size in TICKET_SIZES:
            denom = max(tvl_usd + size, 1.0)
            apy = ((1 + (fees_day/denom))**365 - 1) * 100
            apy_by_size[size] = apy

        label = f"{m0['sym']}-{m1['sym']}"
        results.append(dict(
            pair=pair, label=label, tvl=tvl_usd, vol_day=vol_per_day_usd, swaps=swaps,
            window_days=window_days, apy=apy_by_size
        ))

    if not results:
        print("No active KittyPunch v2 pools with known USD tokens + non-zero recent swaps were found.")
        print("Tip: edit TOKENS{} to include any additional priced tokens you care about.")
        return

    results.sort(key=lambda r: r['apy'][10_000], reverse=True)

    print(f"=== STRICT DEPLOYABLE APY (KittyPunch v2, factory scan) @ {time.strftime('%Y-%m-%d %H:%M:%S')} ===")
    print(f"(fees from on-chain swaps; fee={FEE_TO_LPS*100:.2f}%; lookback up to 30d if 1d/7d are empty; only priced tokens)\n")
    header = f"{'APY $1k':>9s} {'$5k':>8s} {'$10k':>8s} {'$100k':>8s} {'$1m':>8s}  {'TVL':>12s} {'Vol/day':>12s}  {'Win':>4s}  {'Pool':<12s}  Pair"
    print(header); print("-"*len(header))
    for r in results[:40]:
        d=r['apy']
        print(f"{d[1_000]:9.2f}% {d[5_000]:8.2f}% {d[10_000]:8.2f}% {d[100_000]:8.2f}% {d[1_000_000]:8.2f}%  "
              f"${r['tvl']:>11,.0f} ${r['vol_day']:>11,.0f}  {r['window_days']:>4d}  {r['label']:<12s}  {r['pair']}")
    print("-"*len(header))
    print("Notes: Vol/day computed from last non-empty window (1d,7d, or 30d). No CLMM pools included.")
    
if __name__ == "__main__":
    main()
