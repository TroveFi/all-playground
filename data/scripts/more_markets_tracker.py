#!/usr/bin/env python3
"""
More.Markets Dynamic APY Tracker - Utilization-Based Real-Time
Tracks APY changes based on lending utilization in real-time
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
class MoreMarketsAPYSnapshot:
    """More.Markets APY snapshot"""
    timestamp: datetime
    block_number: int
    asset_symbol: str
    asset_address: str
    supply_apy: float
    borrow_apy: float
    utilization_rate: float
    total_deposits: float
    total_borrows: float
    liquidity_index: float
    source: str
    raw_data: Dict = None

# More.Markets/Aave ABI
MORE_MARKETS_ABI = [
    # Pool functions
    {"constant": True, "inputs": [{"name": "asset", "type": "address"}], "name": "getReserveData", "outputs": [
        {"name": "", "type": "tuple", "components": [
            {"name": "configuration", "type": "uint256"},
            {"name": "liquidityIndex", "type": "uint128"},
            {"name": "currentLiquidityRate", "type": "uint128"},
            {"name": "variableBorrowIndex", "type": "uint128"},
            {"name": "currentVariableBorrowRate", "type": "uint128"},
            {"name": "currentStableBorrowRate", "type": "uint128"},
            {"name": "lastUpdateTimestamp", "type": "uint40"},
            {"name": "id", "type": "uint16"},
            {"name": "aTokenAddress", "type": "address"},
            {"name": "stableDebtTokenAddress", "type": "address"},
            {"name": "variableDebtTokenAddress", "type": "address"},
            {"name": "interestRateStrategyAddress", "type": "address"},
            {"name": "accruedToTreasury", "type": "uint128"},
            {"name": "unbacked", "type": "uint128"},
            {"name": "isolationModeTotalDebt", "type": "uint128"}
        ]}
    ], "type": "function"},
    
    # Token functions for calculating utilization
    {"constant": True, "inputs": [], "name": "totalSupply", "outputs": [{"name": "", "type": "uint256"}], "type": "function"},
    {"constant": True, "inputs": [], "name": "decimals", "outputs": [{"name": "", "type": "uint8"}], "type": "function"},
    {"constant": True, "inputs": [], "name": "symbol", "outputs": [{"name": "", "type": "string"}], "type": "function"},
    
    # Events that trigger rate updates
    {"anonymous": False, "inputs": [
        {"indexed": True, "name": "reserve", "type": "address"},
        {"indexed": False, "name": "liquidityRate", "type": "uint256"},
        {"indexed": False, "name": "stableBorrowRate", "type": "uint256"},
        {"indexed": False, "name": "variableBorrowRate", "type": "uint256"},
        {"indexed": False, "name": "liquidityIndex", "type": "uint256"},
        {"indexed": False, "name": "variableBorrowIndex", "type": "uint256"}
    ], "name": "ReserveDataUpdated", "type": "event"},
    
    {"anonymous": False, "inputs": [
        {"indexed": True, "name": "reserve", "type": "address"},
        {"indexed": False, "name": "user", "type": "address"},
        {"indexed": True, "name": "onBehalfOf", "type": "address"},
        {"indexed": False, "name": "amount", "type": "uint256"},
        {"indexed": False, "name": "referralCode", "type": "uint16"}
    ], "name": "Supply", "type": "event"},
    
    {"anonymous": False, "inputs": [
        {"indexed": True, "name": "reserve", "type": "address"},
        {"indexed": True, "name": "user", "type": "address"},
        {"indexed": True, "name": "to", "type": "address"},
        {"indexed": False, "name": "amount", "type": "uint256"}
    ], "name": "Withdraw", "type": "event"},
]

class MoreMarketsDynamicTracker:
    """Dynamic More.Markets APY tracker"""
    
    def __init__(self, db_path: str = "more_markets_dynamic_apy.db"):
        self.db_path = db_path
        self.w3 = None
        self._init_web3()
        self._init_database()
        
        # More.Markets addresses
        self.pool_address = "0xbC92aaC2DBBF42215248B5688eB3D3d2b32F2c8d"
        
        # Assets to track
        self.assets = {
            'WFLOW': {
                'address': '0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e',
                'atoken': '0x02BF4bd075c1b7C8D85F54777eaAA3638135c059',
                'symbol': 'WFLOW'
            },
            'ankrFLOW': {
                'address': '0x1b97100eA1D7126C4d60027e231EA4CB25314bdb',
                'atoken': '0xD10cd10260e87eFdf36618621458eeAA996B8267',
                'symbol': 'ankrFLOW'
            }
        }
        
        self.subgraph_url = "https://graph.more.markets/subgraphs/name/more-markets/vaults-subgraph"

    def _init_web3(self):
        """Initialize Web3"""
        endpoint = "https://mainnet.evm.nodes.onflow.org"
        self.w3 = Web3(Web3.HTTPProvider(endpoint, request_kwargs={'timeout': 30}))
        if not self.w3.is_connected():
            raise Exception("Failed to connect to Flow EVM")
        logging.info(f"✅ Connected to Flow EVM")

    def _init_database(self):
        """Initialize database for tracking"""
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS more_markets_apy_history (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp INTEGER NOT NULL,
                    block_number INTEGER NOT NULL,
                    asset_symbol TEXT NOT NULL,
                    asset_address TEXT NOT NULL,
                    supply_apy REAL NOT NULL,
                    borrow_apy REAL NOT NULL,
                    utilization_rate REAL NOT NULL,
                    total_deposits REAL,
                    total_borrows REAL,
                    liquidity_index REAL,
                    source TEXT NOT NULL,
                    raw_data TEXT,
                    created_at INTEGER DEFAULT (strftime('%s','now'))
                )
            """)
            
            conn.execute("""
                CREATE TABLE IF NOT EXISTS more_markets_rate_events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp INTEGER NOT NULL,
                    block_number INTEGER NOT NULL,
                    transaction_hash TEXT NOT NULL,
                    event_type TEXT NOT NULL,
                    asset_address TEXT NOT NULL,
                    previous_apy REAL,
                    new_apy REAL,
                    trigger_amount REAL,
                    created_at INTEGER DEFAULT (strftime('%s','now'))
                )
            """)
            
            conn.commit()

    async def get_current_rates(self) -> List[MoreMarketsAPYSnapshot]:
        """Get current APY rates for all assets"""
        
        current_block = self.w3.eth.block_number
        current_time = datetime.now()
        snapshots = []
        
        # Try subgraph first
        try:
            async with aiohttp.ClientSession() as session:
                query = """
                {
                  reserves {
                    id
                    symbol
                    name
                    underlyingAsset
                    liquidityRate
                    variableBorrowRate
                    utilizationRate
                    totalATokenSupply
                    totalVariableDebt
                    liquidityIndex
                    lastUpdateTimestamp
                  }
                }
                """
                
                async with session.post(
                    self.subgraph_url,
                    json={'query': query},
                    timeout=10
                ) as response:
                    if response.status == 200:
                        data = await response.json()
                        
                        if 'data' in data and 'reserves' in data['data']:
                            for reserve in data['data']['reserves']:
                                symbol = reserve.get('symbol', '').upper()
                                
                                if symbol in ['WFLOW', 'ANKRFLOW']:
                                    supply_rate = float(reserve.get('liquidityRate', 0))
                                    borrow_rate = float(reserve.get('variableBorrowRate', 0))
                                    utilization = float(reserve.get('utilizationRate', 0))
                                    
                                    # Convert from ray to percentage
                                    supply_apy = (supply_rate / 1e27) * 100
                                    borrow_apy = (borrow_rate / 1e27) * 100
                                    utilization_pct = utilization * 100
                                    
                                    snapshots.append(MoreMarketsAPYSnapshot(
                                        timestamp=current_time,
                                        block_number=current_block,
                                        asset_symbol=symbol,
                                        asset_address=reserve.get('underlyingAsset', ''),
                                        supply_apy=supply_apy,
                                        borrow_apy=borrow_apy,
                                        utilization_rate=utilization_pct,
                                        total_deposits=float(reserve.get('totalATokenSupply', 0)) / 1e18,
                                        total_borrows=float(reserve.get('totalVariableDebt', 0)) / 1e18,
                                        liquidity_index=float(reserve.get('liquidityIndex', 0)) / 1e27,
                                        source='more_markets_subgraph',
                                        raw_data=reserve
                                    ))
                            
                            if snapshots:
                                return snapshots
        
        except Exception as e:
            logging.warning(f"Subgraph failed: {e}")
        
        # Fallback to direct contract calls
        try:
            pool_contract = self.w3.eth.contract(
                address=Web3.to_checksum_address(self.pool_address),
                abi=MORE_MARKETS_ABI
            )
            
            for asset_name, asset_config in self.assets.items():
                try:
                    asset_address = Web3.to_checksum_address(asset_config['address'])
                    reserve_data = pool_contract.functions.getReserveData(asset_address).call()
                    
                    # Extract data from tuple
                    liquidity_rate = reserve_data[2]
                    variable_borrow_rate = reserve_data[4]
                    liquidity_index = reserve_data[1]
                    
                    # Calculate APY from rates (ray format)
                    supply_apy = (liquidity_rate / 1e27) * 100
                    borrow_apy = (variable_borrow_rate / 1e27) * 100
                    
                    # Get aToken to calculate utilization
                    atoken_contract = self.w3.eth.contract(
                        address=Web3.to_checksum_address(asset_config['atoken']),
                        abi=MORE_MARKETS_ABI
                    )
                    
                    total_supply = atoken_contract.functions.totalSupply().call()
                    decimals = atoken_contract.functions.decimals().call()
                    
                    total_deposits = total_supply / (10 ** decimals)
                    
                    # Estimate utilization (simplified)
                    utilization_rate = min(50.0, max(0.0, supply_apy * 20))  # Rough estimate
                    
                    snapshots.append(MoreMarketsAPYSnapshot(
                        timestamp=current_time,
                        block_number=current_block,
                        asset_symbol=asset_name,
                        asset_address=asset_config['address'],
                        supply_apy=supply_apy,
                        borrow_apy=borrow_apy,
                        utilization_rate=utilization_rate,
                        total_deposits=total_deposits,
                        total_borrows=total_deposits * (utilization_rate / 100),
                        liquidity_index=liquidity_index / 1e27,
                        source='pool_contract_direct',
                        raw_data={
                            'liquidity_rate': liquidity_rate,
                            'variable_borrow_rate': variable_borrow_rate,
                            'liquidity_index': liquidity_index
                        }
                    ))
                
                except Exception as e:
                    logging.warning(f"Failed to get data for {asset_name}: {e}")
        
        except Exception as e:
            logging.error(f"Contract calls failed: {e}")
        
        return snapshots

    def store_apy_snapshots(self, snapshots: List[MoreMarketsAPYSnapshot]):
        """Store APY snapshots"""
        
        with sqlite3.connect(self.db_path) as conn:
            for snapshot in snapshots:
                conn.execute("""
                    INSERT INTO more_markets_apy_history 
                    (timestamp, block_number, asset_symbol, asset_address, supply_apy, borrow_apy,
                     utilization_rate, total_deposits, total_borrows, liquidity_index, source, raw_data)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (
                    int(snapshot.timestamp.timestamp()),
                    snapshot.block_number,
                    snapshot.asset_symbol,
                    snapshot.asset_address,
                    snapshot.supply_apy,
                    snapshot.borrow_apy,
                    snapshot.utilization_rate,
                    snapshot.total_deposits,
                    snapshot.total_borrows,
                    snapshot.liquidity_index,
                    snapshot.source,
                    json.dumps(snapshot.raw_data) if snapshot.raw_data else None
                ))
            conn.commit()

    async def monitor_rate_changes(self, asset_address: str, check_interval_seconds: int = 60):
        """Monitor for rate changes on a specific asset"""
        
        pool_contract = self.w3.eth.contract(
            address=Web3.to_checksum_address(self.pool_address),
            abi=MORE_MARKETS_ABI
        )
        
        print(f"🔄 Monitoring rate changes for {asset_address}")
        print(f"⏰ Check interval: {check_interval_seconds} seconds")
        
        last_supply_apy = None
        
        while True:
            try:
                current_snapshots = await self.get_current_rates()
                
                for snapshot in current_snapshots:
                    if snapshot.asset_address.lower() == asset_address.lower():
                        
                        if last_supply_apy is not None:
                            change = abs(snapshot.supply_apy - last_supply_apy)
                            
                            if change >= 0.01:  # 0.01% change threshold
                                direction = "📈" if snapshot.supply_apy > last_supply_apy else "📉"
                                print(f"\n🚨 RATE CHANGE DETECTED!")
                                print(f"   {direction} {snapshot.asset_symbol}: {last_supply_apy:.4f}% → {snapshot.supply_apy:.4f}%")
                                print(f"   Utilization: {snapshot.utilization_rate:.2f}%")
                                print(f"   Time: {snapshot.timestamp.strftime('%H:%M:%S')}")
                                
                                # Store the event
                                with sqlite3.connect(self.db_path) as conn:
                                    conn.execute("""
                                        INSERT INTO more_markets_rate_events
                                        (timestamp, block_number, transaction_hash, event_type, asset_address,
                                         previous_apy, new_apy, trigger_amount)
                                        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                                    """, (
                                        int(snapshot.timestamp.timestamp()),
                                        snapshot.block_number,
                                        'manual_check',
                                        'rate_change',
                                        asset_address,
                                        last_supply_apy,
                                        snapshot.supply_apy,
                                        change
                                    ))
                                    conn.commit()
                        
                        last_supply_apy = snapshot.supply_apy
                        self.store_apy_snapshots([snapshot])
                        break
            
            except Exception as e:
                print(f"❌ Monitoring error: {e}")
            
            await asyncio.sleep(check_interval_seconds)

    async def track_historical_utilization(self, days: int = 7):
        """Track historical utilization and rate changes"""
        
        print(f"📊 Tracking utilization history for {days} days...")
        
        current_block = self.w3.eth.block_number
        blocks_per_day = 4500 * 24
        from_block = max(1, current_block - (days * blocks_per_day))
        
        pool_contract = self.w3.eth.contract(
            address=Web3.to_checksum_address(self.pool_address),
            abi=MORE_MARKETS_ABI
        )
        
        # Get ReserveDataUpdated events
        try:
            event_filter = pool_contract.events.ReserveDataUpdated.create_filter(
                from_block=from_block,
                to_block=current_block
            )
            
            events = event_filter.get_all_entries()
            print(f"   📡 Found {len(events)} rate update events")
            
            for event in events[-50:]:  # Last 50 events
                block_info = self.w3.eth.get_block(event['blockNumber'])
                timestamp = datetime.fromtimestamp(block_info['timestamp'])
                
                asset_address = event['args']['reserve']
                liquidity_rate = event['args']['liquidityRate']
                
                # Find asset name
                asset_name = 'Unknown'
                for name, config in self.assets.items():
                    if config['address'].lower() == asset_address.lower():
                        asset_name = name
                        break
                
                supply_apy = (liquidity_rate / 1e27) * 100
                
                print(f"   📅 {timestamp.strftime('%m-%d %H:%M')} - {asset_name}: {supply_apy:.4f}% APY")
        
        except Exception as e:
            print(f"   ❌ Event tracking failed: {e}")

    def generate_utilization_report(self):
        """Generate utilization and APY report"""
        
        with sqlite3.connect(self.db_path) as conn:
            # Get recent data
            df = pd.read_sql_query("""
                SELECT timestamp, asset_symbol, supply_apy, borrow_apy, utilization_rate, 
                       total_deposits, total_borrows
                FROM more_markets_apy_history 
                WHERE timestamp >= ?
                ORDER BY timestamp DESC
            """, conn, params=[int((datetime.now() - timedelta(days=7)).timestamp())])
            
            if df.empty:
                print("No historical data available")
                return
            
            print(f"\n" + "="*80)
            print(f"📊 MORE.MARKETS UTILIZATION & APY ANALYSIS")
            print(f"="*80)
            
            # Convert timestamp
            df['datetime'] = pd.to_datetime(df['timestamp'], unit='s')
            
            # Analysis by asset
            for asset in df['asset_symbol'].unique():
                asset_df = df[df['asset_symbol'] == asset].sort_values('timestamp')
                
                if len(asset_df) > 0:
                    latest = asset_df.iloc[-1]
                    avg_supply_apy = asset_df['supply_apy'].mean()
                    avg_utilization = asset_df['utilization_rate'].mean()
                    
                    print(f"\n💰 {asset}:")
                    print(f"   Current Supply APY: {latest['supply_apy']:.4f}%")
                    print(f"   Current Borrow APY: {latest['borrow_apy']:.4f}%")
                    print(f"   Current Utilization: {latest['utilization_rate']:.2f}%")
                    print(f"   7-day Avg Supply APY: {avg_supply_apy:.4f}%")
                    print(f"   7-day Avg Utilization: {avg_utilization:.2f}%")
                    print(f"   Total Deposits: ${latest['total_deposits']:,.0f}")
                    
                    # Volatility
                    if len(asset_df) > 1:
                        volatility = asset_df['supply_apy'].std()
                        print(f"   APY Volatility: {volatility:.4f}%")
            
            # Rate change events
            events_df = pd.read_sql_query("""
                SELECT timestamp, asset_address, previous_apy, new_apy, trigger_amount
                FROM more_markets_rate_events 
                WHERE timestamp >= ?
                ORDER BY timestamp DESC
                LIMIT 10
            """, conn, params=[int((datetime.now() - timedelta(days=7)).timestamp())])
            
            if not events_df.empty:
                print(f"\n🔄 RECENT RATE CHANGES:")
                events_df['datetime'] = pd.to_datetime(events_df['timestamp'], unit='s')
                
                for _, event in events_df.iterrows():
                    direction = "📈" if event['new_apy'] > event['previous_apy'] else "📉"
                    print(f"   {direction} {event['datetime'].strftime('%m-%d %H:%M')}: "
                          f"{event['previous_apy']:.4f}% → {event['new_apy']:.4f}%")
            
            print(f"\n💡 UTILIZATION INSIGHTS:")
            current_avg_util = df.groupby('asset_symbol')['utilization_rate'].last().mean()
            
            if current_avg_util < 10:
                print("   📉 Low utilization - APY likely to be low")
            elif current_avg_util < 50:
                print("   📊 Moderate utilization - reasonable APY")
            else:
                print("   📈 High utilization - higher APY but supply risk")
            
            print("="*80)

async def main():
    """Main execution"""
    
    import sys
    
    logging.basicConfig(level=logging.INFO)
    
    tracker = MoreMarketsDynamicTracker()
    
    if len(sys.argv) > 1:
        command = sys.argv[1]
        
        if command == '--current':
            snapshots = await tracker.get_current_rates()
            for snapshot in snapshots:
                print(f"{snapshot.asset_symbol}: {snapshot.supply_apy:.4f}% supply APY, "
                      f"{snapshot.utilization_rate:.2f}% utilization")
            tracker.store_apy_snapshots(snapshots)
            
        elif command == '--monitor':
            asset = sys.argv[2] if len(sys.argv) > 2 else '0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e'
            interval = int(sys.argv[3]) if len(sys.argv) > 3 else 60
            await tracker.monitor_rate_changes(asset, interval)
            
        elif command == '--historical':
            days = int(sys.argv[2]) if len(sys.argv) > 2 else 7
            await tracker.track_historical_utilization(days)
            
        elif command == '--report':
            tracker.generate_utilization_report()
            
    else:
        print("More.Markets Dynamic APY Tracker")
        print("Usage:")
        print("  --current                    Get current APY rates")
        print("  --monitor [asset] [interval] Monitor rate changes (default WFLOW, 60s)")
        print("  --historical [days]          Track historical changes (default 7 days)")
        print("  --report                     Generate utilization report")

if __name__ == "__main__":
    asyncio.run(main())