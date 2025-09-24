#!/usr/bin/env python3
# ankrflow_implied_apy.py
# Auto-discovers the WFLOW/ankrFLOW pair on KittyPunch and computes implied staking APY from price drift.

import sqlite3, json, time
from datetime import datetime, timedelta
from web3 import Web3

RPC = "https://mainnet.evm.nodes.onflow.org"
DB  = "ankrflow_implied_apy.db"

# KittyPunch factory + tokens
FACTORY_V2 = "0x29372c22459a4e373851798bFd6808e71EA34A71"
WFLOW  = "0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e"
ANKRFLOW = "0x1b97100eA1D7126C4d60027e231EA4CB25314bdb"

FACTORY_ABI=[{"constant":True,"inputs":[{"name":"tokenA","type":"address"},{"name":"tokenB","type":"address"}],
              "name":"getPair","outputs":[{"name":"pair","type":"address"}],"type":"function"}]
PAIR_ABI = [
  {"constant":True,"inputs":[],"name":"getReserves","outputs":[
    {"name":"reserve0","type":"uint112"},{"name":"reserve1","type":"uint112"},{"name":"blockTimestampLast","type":"uint32"}],"type":"function"},
  {"constant":True,"inputs":[],"name":"token0","outputs":[{"name":"","type":"address"}],"type":"function"},
  {"constant":True,"inputs":[],"name":"token1","outputs":[{"name":"","type":"address"}],"type":"function"},
]

def init_db():
    with sqlite3.connect(DB) as c:
        c.execute("""CREATE TABLE IF NOT EXISTS ankrflow_implied_apy (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp INTEGER NOT NULL,
            block_number INTEGER NOT NULL,
            pair_address TEXT NOT NULL,
            price_flow_per_ankr REAL NOT NULL,
            weekly_change REAL,
            implied_apy REAL,
            reserves0 REAL, reserves1 REAL,
            raw TEXT
        )""")
        c.commit()

def discover_pair(w3):
    f = w3.eth.contract(address=Web3.to_checksum_address(FACTORY_V2), abi=FACTORY_ABI)
    p = f.functions.getPair(Web3.to_checksum_address(WFLOW), Web3.to_checksum_address(ANKRFLOW)).call()
    if int(p,16)==0:
        raise SystemExit("WFLOW/ankrFLOW pair not found on KittyPunch.")
    return p

def read_price(w3, pair):
    p = w3.eth.contract(address=Web3.to_checksum_address(pair), abi=PAIR_ABI)
    t0 = p.functions.token0().call(); t1 = p.functions.token1().call()
    r0,r1,_ = p.functions.getReserves().call()
    r0f = r0/1e18; r1f = r1/1e18
    if t0.lower()==WFLOW.lower() and t1.lower()==ANKRFLOW.lower():
        price = r0f / r1f
    elif t1.lower()==WFLOW.lower() and t0.lower()==ANKRFLOW.lower():
        price = r1f / r0f
    else:
        raise RuntimeError("Pair tokens are not WFLOW/ankrFLOW.")
    return price, {"token0":t0,"token1":t1,"r0":r0f,"r1":r1f}

def weekly_change_and_apy(conn, pair):
    from datetime import datetime, timedelta, timezone
    one_week_ago = int((datetime.now(timezone.utc) - timedelta(days=7)).timestamp())
    row_then = conn.execute("""SELECT price_flow_per_ankr FROM ankrflow_implied_apy
                               WHERE pair_address=? AND timestamp<=?
                               ORDER BY timestamp DESC LIMIT 1""",(pair, one_week_ago)).fetchone()
    row_now  = conn.execute("""SELECT price_flow_per_ankr FROM ankrflow_implied_apy
                               WHERE pair_address=? ORDER BY timestamp DESC LIMIT 1""",(pair,)).fetchone()
    if not (row_then and row_now): return None, None
    weekly = (row_now[0]/row_then[0]) - 1.0
    apy = ((1+weekly)**52 - 1.0)*100
    return weekly*100, apy

def main():
    init_db()
    w3 = Web3(Web3.HTTPProvider(RPC, request_kwargs={'timeout':30}))
    if not w3.is_connected(): raise SystemExit("RPC not connected")
    pair = discover_pair(w3)
    price, meta = read_price(w3, pair)
    blk = w3.eth.block_number
    with sqlite3.connect(DB) as c:
        c.execute("""INSERT INTO ankrflow_implied_apy(timestamp, block_number, pair_address, price_flow_per_ankr, reserves0, reserves1, raw)
                     VALUES(?,?,?,?,?,?,?)""",
                  (int(time.time()), blk, pair, price, meta["r0"], meta["r1"], json.dumps(meta)))
        c.commit()
        weekly, apy = weekly_change_and_apy(c, pair)
        if apy is not None:
            c.execute("""UPDATE ankrflow_implied_apy SET weekly_change=?, implied_apy=?
                         WHERE id=(SELECT MAX(id) FROM ankrflow_implied_apy WHERE pair_address=?)""",
                      (weekly, apy, pair)); c.commit()
            print(f"ankrFLOW implied APY | pair {pair} | price FLOW/ankr {price:.6f} | Δ7d {weekly:.3f}% | APY {apy:.2f}%")
        else:
            print(f"ankrFLOW implied APY | pair {pair} | price FLOW/ankr {price:.6f} | need ≥1 prior week for APY.")

if __name__=="__main__":
    main()
