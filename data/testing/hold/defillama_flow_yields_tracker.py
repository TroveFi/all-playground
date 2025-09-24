#!/usr/bin/env python3
# defillama_flow_yields_tracker.py
import aiohttp, asyncio, sqlite3, time, json

DB="defillama_flow_yields.db"
API="https://yields.llama.fi/pools"

def init_db():
    with sqlite3.connect(DB) as c:
        c.execute("""CREATE TABLE IF NOT EXISTS llama_flow_yields(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp INTEGER NOT NULL,
            project TEXT, chain TEXT, symbol TEXT,
            apy REAL, tvl_usd REAL, pool TEXT, url TEXT, raw TEXT
        )""")
        c.commit()

async def fetch():
    async with aiohttp.ClientSession() as s:
        async with s.get(API, timeout=25) as r:
            r.raise_for_status()
            return await r.json()

def print_top(rows, topn=10):
    rows = sorted(rows, key=lambda x: x['apy'], reverse=True)[:topn]
    print(f"\nTop Flow-related yields (by APY):")
    for r in rows:
        print(f" - {r['project']} | {r['symbol']} | APY {r['apy']:.2f}% | TVL ${r['tvl']:.0f} | {r['url'] or r['pool']}")

async def main():
    init_db()
    data = await fetch()
    now = int(time.time())
    saved=0; snapshot=[]
    with sqlite3.connect(DB) as c:
        for p in data.get("data",[]):
            chain = (p.get("chain") or "").lower()
            project = (p.get("project") or "").lower()
            if any(k in chain for k in ["flow"]) or any(k in project for k in ["kitty","punch","trado","more","flow"]):
                apy = float(p.get("apy") or 0.0)
                tvl = float(p.get("tvlUsd") or 0.0)
                rec = (
                    now, p.get("project"), p.get("chain"), p.get("symbol"),
                    apy, tvl, p.get("pool"), p.get("url"), json.dumps(p)[:2000]
                )
                c.execute("""INSERT INTO llama_flow_yields(timestamp, project, chain, symbol, apy, tvl_usd, pool, url, raw)
                             VALUES (?,?,?,?,?,?,?,?,?)""", rec)
                saved+=1
                snapshot.append({"project":p.get("project"),"symbol":p.get("symbol"),"apy":apy,"tvl":tvl,"url":p.get("url"),"pool":p.get("pool")})
        c.commit()
    print(f"Saved {saved} Flow-related pool rows from DeFiLlama.")
    if snapshot: print_top(snapshot, topn=8)

if __name__=="__main__":
    asyncio.run(main())
