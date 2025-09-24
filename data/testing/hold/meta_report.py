#!/usr/bin/env python3
# meta_report.py — merge + rank latest APYs across your trackers (no flags)
import sqlite3, os, time
from pathlib import Path

DBS = [
  ("KittyPunch LP Fees", "univ2_fee_apy.db", "SELECT label AS name, fee_apy AS apy, tvl_num AS tvl, pair_address AS ref FROM pool_fee_apy ORDER BY timestamp DESC LIMIT 200"),
  ("Ankr Implied",       "ankrflow_implied_apy.db", "SELECT 'ankrFLOW implied' AS name, implied_apy AS apy, NULL AS tvl, pair_address AS ref FROM ankrflow_implied_apy WHERE implied_apy IS NOT NULL ORDER BY timestamp DESC LIMIT 1"),
  ("DeFiLlama (Flow)",   "defillama_flow_yields.db", "SELECT project||' '||symbol AS name, apy, tvl_usd AS tvl, url AS ref FROM llama_flow_yields ORDER BY timestamp DESC LIMIT 200"),
  ("More.Markets",       "more_markets_dynamic_apy.db", "SELECT asset_symbol AS name, supply_apy AS apy, total_deposits AS tvl, asset_address AS ref FROM more_markets_apy_history ORDER BY timestamp DESC LIMIT 200"),
  ("KittyPunch Legacy",  "fixed_kittypunch_apy.db", "SELECT pair_symbol AS name, total_apy AS apy, tvl_usd AS tvl, pair_address AS ref FROM kittypunch_apy_snapshots ORDER BY timestamp DESC LIMIT 200"),
]

def latest_rows(dbfile, sql):
    if not Path(dbfile).exists():
        return []
    try:
        with sqlite3.connect(dbfile) as c:
            rows = []
            for r in c.execute(sql).fetchall():
                name, apy, tvl, ref = r
                if apy is None: continue
                rows.append(dict(source=dbfile, name=str(name), apy=float(apy), tvl=(float(tvl) if tvl is not None else None), ref=str(ref) if ref is not None else ""))
            return rows
    except Exception:
        return []

def main():
    allrows=[]
    for label, db, sql in DBS:
        rows = latest_rows(db, sql)
        for r in rows: r["label"]=label
        allrows.extend(rows)

    if not allrows:
        print("No data yet. Run your trackers first.")
        return

    # Keep only most recent entries per (label,name) pair
    # (Our SQL already sorts by timestamp desc in each table, so just first occurrence wins)
    seen=set(); uniq=[]
    for r in allrows:
        key=(r["label"], r["name"])
        if key in seen: continue
        seen.add(key); uniq.append(r)

    # rank by APY desc
    uniq.sort(key=lambda x: x["apy"], reverse=True)

    print(f"=== FLOW EVM YIELD META-REPORT @ {time.strftime('%Y-%m-%d %H:%M:%S')} ===")
    for r in uniq[:30]:
        tvl = (f"${r['tvl']:,.0f}" if r['tvl'] is not None else "-")
        print(f"{r['apy']:>7.2f}%  | {r['label']:<20s} | {r['name']:<28s} | TVL {tvl:<10s} | {r['ref']}")
    print("=======================================================================")

if __name__=="__main__":
    main()
