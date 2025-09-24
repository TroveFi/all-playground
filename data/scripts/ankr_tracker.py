#!/usr/bin/env python3
"""
Fixed Ankr Tracker - Working API Method
Uses the working Ankr API from bulletproof tracker + exchange rate monitoring
"""

import asyncio
import aiohttp
import pandas as pd
import numpy as np
import json
import logging
import sqlite3
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple
from web3 import Web3
from dataclasses import dataclass
import time
import os
import sys

# Change working directory to script directory
script_dir = os.path.dirname(os.path.abspath(__file__))
os.chdir(script_dir)

@dataclass
class AnkrAPYSnapshot:
    """Ankr APY snapshot"""
    timestamp: datetime
    block_number: int
    current_apy: float
    total_staked: float
    apy_basis: str
    source: str
    exchange_rate_flow_per_ankr: float = None
    raw_data: Dict = None

class FixedAnkrTracker:
    """Fixed Ankr tracker using working methods"""
    
    def __init__(self, db_path: str = "fixed_ankr_apy.db"):
        self.db_path = db_path
        self.w3 = None
        self._init_web3()
        self._init_database()
        
        # Working API endpoint
        self.ankr_api = "https://api.staking.ankr.com/v1alpha/metrics"
        self.ankr_token = "0x1b97100eA1D7126C4d60027e231EA4CB25314bdb"

    def _init_web3(self):
        """Initialize Web3"""
        endpoint = "https://mainnet.evm.nodes.onflow.org"
        self.w3 = Web3(Web3.HTTPProvider(endpoint, request_kwargs={'timeout': 30}))
        if not self.w3.is_connected():
            raise Exception("Failed to connect to Flow EVM")
        logging.info(f"✅ Connected to Flow EVM (Block: {self.w3.eth.block_number:,})")

    def _init_database(self):
        """Initialize database"""
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS ankr_apy_snapshots (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp INTEGER NOT NULL,
                    block_number INTEGER NOT NULL,
                    current_apy REAL NOT NULL,
                    total_staked REAL NOT NULL,
                    apy_basis TEXT NOT NULL,
                    exchange_rate REAL,
                    source TEXT NOT NULL,
                    raw_data TEXT,
                    created_at INTEGER DEFAULT (strftime('%s','now'))
                )
            """)
            
            conn.execute("""
                CREATE TABLE IF NOT EXISTS ankr_apy_changes (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp INTEGER NOT NULL,
                    previous_apy REAL NOT NULL,
                    new_apy REAL NOT NULL,
                    change_percent REAL NOT NULL,
                    change_reason TEXT,
                    created_at INTEGER DEFAULT (strftime('%s','now'))
                )
            """)
            
            conn.commit()

    async def get_current_ankr_apy(self) -> Optional[AnkrAPYSnapshot]:
        """Get current Ankr APY using working API"""
        
        current_block = self.w3.eth.block_number
        current_time = datetime.now()
        
        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(self.ankr_api, timeout=10) as response:
                    if response.status == 200:
                        data = await response.json()
                        
                        # Find Flow service in the response
                        for service in data.get('services', []):
                            service_name = service.get('serviceName', '').lower()
                            
                            if service_name in ['flow', 'flowevm']:
                                apy = float(service.get('apy', 0))
                                total_staked = float(service.get('totalStaked', 0))
                                apy_basis = service.get('apyBasis', 'UNKNOWN')
                                
                                print(f"✅ Found {service_name.upper()} staking data:")
                                print(f"   APY: {apy:.3f}%")
                                print(f"   Total Staked: {total_staked:,.2f} FLOW")
                                print(f"   APY Basis: {apy_basis}")
                                
                                return AnkrAPYSnapshot(
                                    timestamp=current_time,
                                    block_number=current_block,
                                    current_apy=apy,
                                    total_staked=total_staked,
                                    apy_basis=apy_basis,
                                    source='ankr_official_api',
                                    raw_data=service
                                )
                        
                        print("⚠️ Flow/FlowEVM service not found in API response")
                        print(f"Available services: {[s.get('serviceName') for s in data.get('services', [])]}")
                    else:
                        print(f"❌ API returned status {response.status}")
        
        except Exception as e:
            print(f"❌ Ankr API failed: {e}")
        
        return None

    async def get_exchange_rate_growth(self) -> Optional[float]:
        """Calculate exchange rate growth as alternative APY measure"""
        
        try:
            # Get ankrFLOW total supply (represents exchange rate growth)
            token_abi = [
                {"constant": True, "inputs": [], "name": "totalSupply", "outputs": [{"name": "", "type": "uint256"}], "type": "function"},
                {"constant": True, "inputs": [], "name": "decimals", "outputs": [{"name": "", "type": "uint8"}], "type": "function"}
            ]
            
            token_contract = self.w3.eth.contract(
                address=Web3.to_checksum_address(self.ankr_token),
                abi=token_abi
            )
            
            current_block = self.w3.eth.block_number
            current_supply = token_contract.functions.totalSupply().call()
            decimals = token_contract.functions.decimals().call()
            
            # Get supply from 24 hours ago
            blocks_per_day = 4500 * 24
            yesterday_block = max(1, current_block - blocks_per_day)
            
            yesterday_supply = token_contract.functions.totalSupply().call(
                block_identifier=yesterday_block
            )
            
            # Calculate growth rate
            if yesterday_supply > 0:
                growth_rate = (current_supply - yesterday_supply) / yesterday_supply
                daily_rate = growth_rate
                annualized_apy = daily_rate * 365 * 100
                
                current_supply_human = current_supply / (10 ** decimals)
                yesterday_supply_human = yesterday_supply / (10 ** decimals)
                
                print(f"📊 Exchange Rate Analysis:")
                print(f"   Current Supply: {current_supply_human:,.2f} ankrFLOW")
                print(f"   Yesterday Supply: {yesterday_supply_human:,.2f} ankrFLOW")
                print(f"   24h Growth: {growth_rate * 100:.6f}%")
                print(f"   Implied APY: {annualized_apy:.3f}%")
                
                if 0 <= annualized_apy <= 50:  # Reasonable range
                    return annualized_apy
            
        except Exception as e:
            print(f"❌ Exchange rate calculation failed: {e}")
        
        return None

    def store_apy_snapshot(self, snapshot: AnkrAPYSnapshot):
        """Store APY snapshot and detect changes"""
        
        with sqlite3.connect(self.db_path) as conn:
            # Get last APY for change detection
            cursor = conn.execute("""
                SELECT current_apy FROM ankr_apy_snapshots 
                ORDER BY timestamp DESC LIMIT 1
            """)
            last_record = cursor.fetchone()
            last_apy = last_record[0] if last_record else None
            
            # Store new snapshot
            conn.execute("""
                INSERT INTO ankr_apy_snapshots 
                (timestamp, block_number, current_apy, total_staked, apy_basis, 
                 exchange_rate, source, raw_data)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                int(snapshot.timestamp.timestamp()),
                snapshot.block_number,
                snapshot.current_apy,
                snapshot.total_staked,
                snapshot.apy_basis,
                snapshot.exchange_rate_flow_per_ankr,
                snapshot.source,
                json.dumps(snapshot.raw_data) if snapshot.raw_data else None
            ))
            
            # Detect significant changes
            if last_apy is not None:
                change = abs(snapshot.current_apy - last_apy)
                if change >= 0.1:  # 0.1% threshold
                    change_percent = ((snapshot.current_apy - last_apy) / last_apy) * 100
                    
                    conn.execute("""
                        INSERT INTO ankr_apy_changes 
                        (timestamp, previous_apy, new_apy, change_percent, change_reason)
                        VALUES (?, ?, ?, ?, ?)
                    """, (
                        int(snapshot.timestamp.timestamp()),
                        last_apy,
                        snapshot.current_apy,
                        change_percent,
                        f"APY changed from {last_apy:.3f}% to {snapshot.current_apy:.3f}%"
                    ))
                    
                    direction = "📈" if change_percent > 0 else "📉"
                    print(f"\n🚨 APY CHANGE DETECTED!")
                    print(f"   {direction} {last_apy:.3f}% → {snapshot.current_apy:.3f}%")
                    print(f"   Change: {change_percent:+.2f}%")
            
            conn.commit()

    async def start_monitoring(self, check_interval_minutes: int = 60):
        """Start real-time monitoring with working methods"""
        
        print(f"🔄 Starting Ankr APY monitoring (FIXED)")
        print(f"⏰ Check interval: {check_interval_minutes} minutes")
        print(f"🎯 Using working Ankr API + exchange rate analysis")
        print("=" * 80)
        
        while True:
            try:
                print(f"\n⏰ {datetime.now().strftime('%H:%M:%S')} - Checking Ankr APY...")
                
                # Method 1: Official API (primary)
                snapshot = await self.get_current_ankr_apy()
                
                if snapshot:
                    # Method 2: Add exchange rate analysis
                    exchange_rate_apy = await self.get_exchange_rate_growth()
                    if exchange_rate_apy:
                        snapshot.exchange_rate_flow_per_ankr = exchange_rate_apy
                        print(f"   Exchange rate implied APY: {exchange_rate_apy:.3f}%")
                    
                    # Store and analyze
                    self.store_apy_snapshot(snapshot)
                    
                    print(f"   ✅ Current APY: {snapshot.current_apy:.3f}% ({snapshot.apy_basis})")
                    print(f"   Total Staked: {snapshot.total_staked:,.0f} FLOW")
                
                else:
                    print(f"   ⚠️ No APY data retrieved")
                
            except Exception as e:
                print(f"   ❌ Error: {e}")
            
            # Wait for next check
            await asyncio.sleep(check_interval_minutes * 60)

    def generate_apy_report(self, days: int = 7):
        """Generate APY trend report"""
        
        with sqlite3.connect(self.db_path) as conn:
            # Get historical data
            df = pd.read_sql_query("""
                SELECT timestamp, current_apy, total_staked, apy_basis, exchange_rate, source
                FROM ankr_apy_snapshots 
                WHERE timestamp >= ?
                ORDER BY timestamp
            """, conn, params=[int((datetime.now() - timedelta(days=days)).timestamp())])
            
            if df.empty:
                print("No historical data available. Run --current first.")
                return
            
            # Convert timestamp
            df['datetime'] = pd.to_datetime(df['timestamp'], unit='s')
            
            print(f"\n" + "="*80)
            print(f"📊 ANKR FLOW STAKING APY ANALYSIS ({days} days)")
            print(f"="*80)
            
            latest = df.iloc[-1]
            
            print(f"\n📈 CURRENT STATUS:")
            print(f"   Current APY: {latest['current_apy']:.3f}%")
            print(f"   Total Staked: {latest['total_staked']:,.0f} FLOW")
            print(f"   APY Basis: {latest['apy_basis']}")
            print(f"   Last Updated: {latest['datetime'].strftime('%Y-%m-%d %H:%M:%S')}")
            
            if len(df) > 1:
                print(f"\n📊 HISTORICAL TRENDS:")
                avg_apy = df['current_apy'].mean()
                min_apy = df['current_apy'].min()
                max_apy = df['current_apy'].max()
                volatility = df['current_apy'].std()
                
                print(f"   Average APY: {avg_apy:.3f}%")
                print(f"   Range: {min_apy:.3f}% - {max_apy:.3f}%")
                print(f"   Volatility: {volatility:.3f}%")
                
                # Staking growth
                staking_growth = ((latest['total_staked'] - df['total_staked'].iloc[0]) / df['total_staked'].iloc[0]) * 100
                print(f"   Staking Growth: {staking_growth:+.2f}%")
            
            # Recent changes
            changes_df = pd.read_sql_query("""
                SELECT timestamp, previous_apy, new_apy, change_percent, change_reason
                FROM ankr_apy_changes 
                WHERE timestamp >= ?
                ORDER BY timestamp DESC
                LIMIT 5
            """, conn, params=[int((datetime.now() - timedelta(days=days)).timestamp())])
            
            if not changes_df.empty:
                print(f"\n🔄 RECENT APY CHANGES:")
                changes_df['datetime'] = pd.to_datetime(changes_df['timestamp'], unit='s')
                
                for _, change in changes_df.iterrows():
                    direction = "📈" if change['change_percent'] > 0 else "📉"
                    print(f"   {direction} {change['datetime'].strftime('%m-%d %H:%M')}: "
                          f"{change['previous_apy']:.3f}% → {change['new_apy']:.3f}% "
                          f"({change['change_percent']:+.2f}%)")
            
            print(f"\n💡 UPDATE FREQUENCY:")
            if len(df) > 1:
                time_diffs = df['datetime'].diff().dropna()
                avg_interval = time_diffs.mean().total_seconds() / 3600
                print(f"   Data points: {len(df)}")
                print(f"   Average update interval: {avg_interval:.1f} hours")
                
                # Predict next update based on APY basis
                if latest['apy_basis'] == 'WEEK':
                    print(f"   Expected update frequency: Weekly")
                else:
                    print(f"   Expected update frequency: Based on {latest['apy_basis']}")
            
            print("="*80)

async def main():
    """Main execution"""
    
    import sys
    
    logging.basicConfig(level=logging.INFO)
    
    tracker = FixedAnkrTracker()
    
    if len(sys.argv) > 1:
        command = sys.argv[1]
        
        if command == '--current':
            snapshot = await tracker.get_current_ankr_apy()
            if snapshot:
                # Also get exchange rate analysis
                exchange_apy = await tracker.get_exchange_rate_growth()
                if exchange_apy:
                    snapshot.exchange_rate_flow_per_ankr = exchange_apy
                
                tracker.store_apy_snapshot(snapshot)
                print(f"\n✅ Stored APY snapshot: {snapshot.current_apy:.3f}%")
            else:
                print("❌ Failed to get current APY")
        
        elif command == '--monitor':
            interval = int(sys.argv[2]) if len(sys.argv) > 2 else 60
            await tracker.start_monitoring(interval)
        
        elif command == '--report':
            days = int(sys.argv[2]) if len(sys.argv) > 2 else 7
            tracker.generate_apy_report(days)
        
        else:
            print("Unknown command")
    
    else:
        print("Fixed Ankr Dynamic APY Tracker")
        print("Usage:")
        print("  --current                 Get current APY (working method)")
        print("  --monitor [interval_min]  Start monitoring (default 60 min)")
        print("  --report [days]           Generate report (default 7 days)")

if __name__ == "__main__":
    asyncio.run(main())