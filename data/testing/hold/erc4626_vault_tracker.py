#!/usr/bin/env python3
# erc4626_vault_tracker.py
# Auto-discovers Flow-related ERC-4626 vaults via DeFiLlama and computes APY from pricePerShare drift.

import aiohttp, asyncio, sqlite3, json, time
from datetime import datetime, timedelta
from web3 import Web3

RPC="https://mainnet.evm.nodes.onflow.org"
DB ="erc4626_vaults.db"
LLAMA="https://yields.llama.fi/pools"

ERC4626_ABI = [
  {"inputs":[],"name":"decimals","outputs":[{"type":"uint8"}],"stateMutability":"view","type":"function"},
  {"inputs":[],"name":"symbol","outputs":[{"type":"string"}],"stateMutability":"view","type":"function"},
  {"inputs":[],"name":"name","outputs":[{"type":"string"}],"stateMutability":"view","type":"function"},
  {"inputs":[],"name":"pricePerShare","outputs":[{"type":"uint256"}],"stateMutability":"view","type":"function"},
  {"inputs":[],"name":"totalAssets","outputs":[{"type":"uint256"}],"stateMutability":"view","type":"function"},
  {"inputs":[],"name":"totalSupply","outputs":[{"type":"uint256"}],"stateMutability":"view","type":"function"}
]

def init_db():
    with sqlite3.connect(DB) as c:
        c.execute("""CREATE TABLE IF NOT EXISTS vault_apy(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          timestamp INTEGER NOT NULL,
          block_number INTEGER NOT NULL,
          vault TEXT NOT NULL,
          label TEXT,
          pps REAL NOT NULL,
          total_assets REAL,
          total_supply REAL,
          weekly_change REAL,
          apy REAL,
          meta TEXT
        )"""); c.commit()

async def llama_pools():
    async with aiohttp.ClientSession() as s:
        async with s.get(LLAMA, timeout=25) as r:
            r.raise_for_status()
            return await r.json()

def looks_like_address(s):
    if not s: return None
    s = s.lower()
    for sep in [":", "/", "#"]:
        if sep in s: s = s.split(sep)[-1]
    if s.startswith("0x") and len(s)==42:
        return s
    return None

def extract_flow_vault_addresses(llama_json):
    addrs=set(); labels={}
    for p in llama_json.get("data",[]):
        chain = (p.get("chain") or "").lower()
        proj  = (p.get("project") or "").lower()
        sym   = (p.get("symbol") or "")
        # Heuristics: Flow chain + vault-like projects/urls/symbols
        if "flow" in chain and any(k in proj for k in ["vault","kitty","punch","more"]):
            # try pool field
            cand = looks_like_address(p.get("pool"))
            if cand: addrs.add(cand); labels[cand] = f"{p.get('project')} {sym}".strip(); continue
            # try url field (sometimes links hold address)
            cand = looks_like_address(p.get("url"))
            if cand: addrs.add(cand); labels[cand] = f"{p.get('project')} {sym}".strip()
    return list(addrs), labels

def read_pps(w3, addr):
    v = w3.eth.contract(address=Web3.to_checksum_address(addr), abi=ERC4626_ABI)
    sym=name=None; dec=18
    try: sym=v.functions.symbol().call()
    except: pass
    try: name=v.functions.name().call()
    except: pass
    try: dec=v.functions.decimals().call()
    except: pass
    # PPS
    pps=None
    try:
        pps_raw = v.functions.pricePerShare().call(); pps = pps_raw/(10**dec)
    except:
        ta = v.functions.totalAssets().call(); ts = v.functions.totalSupply().call()
        pps = (ta/(10**dec))/max(ts/(10**dec),1e-18)
    ta=ts=None
    try: ta=v.functions.totalAssets().call()/(10**dec)
    except: pass
    try: ts=v.functions.totalSupply().call()/(10**dec)
    except: pass
    return dict(label=(sym or name or addr), pps=pps, ta=ta, ts=ts)

def weekly_change_and_apy(conn, vaddr):
    one_week_ago = int((datetime.utcnow()-timedelta(days=7)).timestamp())
    row_then = conn.execute("""SELECT pps FROM vault_apy WHERE vault=? AND timestamp<=?
                               ORDER BY timestamp DESC LIMIT 1""",(vaddr, one_week_ago)).fetchone()
    row_now  = conn.execute("""SELECT pps FROM vault_apy WHERE vault=? ORDER BY timestamp DESC LIMIT 1""",(vaddr,)).fetchone()
    if not (row_then and row_now): return None, None
    weekly = (row_now[0]/row_then[0]) - 1.0
    apy = ((1+weekly)**52 - 1.0)*100
    return weekly*100, apy

async def main():
    init_db()
    llama = await llama_pools()
    candidates, labels = extract_flow_vault_addresses(llama)
    w3 = Web3(Web3.HTTPProvider(RPC, request_kwargs={'timeout':30}))
    if not w3.is_connected(): raise SystemExit("RPC not connected")

    printed = 0
    with sqlite3.connect(DB) as c:
        for vaddr in candidates:
            info = read_pps(w3, vaddr)
            blk  = w3.eth.block_number
            label = labels.get(vaddr, info["label"])
            c.execute("""INSERT INTO vault_apy(timestamp, block_number, vault, label, pps, total_assets, total_supply, weekly_change, apy, meta)
                         VALUES(?,?,?,?,?,?,?,?,?,?)""",
                      (int(time.time()), blk, vaddr, label, info["pps"], info["ta"], info["ts"], None, None, json.dumps(info)))
            c.commit()
            weekly, apy = weekly_change_and_apy(c, vaddr)
            if apy is not None:
                c.execute("""UPDATE vault_apy SET weekly_change=?, apy=? WHERE id=(SELECT MAX(id) FROM vault_apy WHERE vault=?)""",
                          (weekly, apy, vaddr)); c.commit()
                print(f"vault {label} | {vaddr} | pps {info['pps']:.8f} | Δ7d {weekly:.3f}% | APY {apy:.2f}%")
            else:
                print(f"vault {label} | {vaddr} | pps {info['pps']:.8f} | need ≥1 prior week for APY.")
            printed += 1

    if printed == 0:
        print("No Flow ERC-4626 vaults auto-discovered today (from DeFiLlama). Script still ok; will pick them up when listed.")

if __name__=="__main__":
    asyncio.run(main())
