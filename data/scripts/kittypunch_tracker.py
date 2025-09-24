#!/usr/bin/env python3
"""
Fixed KittyPunch Tracker - Working Volume Analysis
Uses smaller event chunks and fixed DefiLlama parsing
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
class KittyPunchAPYSnapshot:
    """KittyPunch APY snapshot"""
    timestamp: datetime
    block_number: int
    pair_symbol: str
    pair_address: str
    trading_fee_apy: float
    farm_reward_apy: float
    total_apy: float
    tvl_usd: float
    volume_24h: float
    liquidity_tokens: float
    source: str
    raw_data: Dict = None

# Simplified Uniswap V2 ABI
UNISWAP_V2_ABI = [
    # Factory
    {"constant": True, "inputs": [{"name": "tokenA", "type": "address"}, {"name": "tokenB", "type": "address"}], "name": "getPair", "outputs": [{"name": "pair", "type": "address"}], "type": "function"},
    
    # Pair
    {"constant": True, "inputs": [], "name": "getReserves", "outputs": [{"name": "reserve0", "type": "uint112"}, {"name": "reserve1", "type": "uint112"}, {"name": "blockTimestampLast", "type": "uint32"}], "type": "function"},
    {"constant": True, "inputs": [], "name": "token0", "outputs": [{"name": "", "type": "address"}], "type": "function"},
    {"constant": True, "inputs": [], "name": "token1", "outputs": [{"name": "", "type": "address"}], "type": "function"},
    {"constant": True, "inputs": [], "name": "totalSupply", "outputs": [{"name": "", "type": "uint256"}], "type": "function"},
    
    # Events (for small chunks)
    {"anonymous": False, "inputs": [
        {"indexed": True, "name": "sender", "type": "address"},
        {"indexed": False, "name": "amount0In", "type": "uint256"},
        {"indexed": False, "name": "amount1In", "type": "uint256"},
        {"indexed": False, "name": "amount0Out", "type": "uint256"},
        {"indexed": False, "name": "amount1Out", "type": "uint256"},
        {"indexed": True, "name": "to", "type": "address"}
    ], "name": "Swap", "type": "event"},
]

class FixedKittyPunchTracker:
    """Fixed KittyPunch tracker with working methods"""
    
    def __init__(self, db_path: str = "fixed_kittypunch_apy.db"):
        self.db_path = db_path
        self.w3 = None
        self._init_web3()
        self._init_database()
        
        # PunchSwap addresses
        self.factory_v2 = "0x29372c22459a4e373851798bFd6808e71EA34A71"
        
        # Known token addresses
        self.tokens = {
            'WFLOW': '0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e',
            'ankrFLOW': '0x1b97100eA1D7126C4d60027e231EA4CB25314bdb'
        }
        
        # Flow price estimate (for USD calculations)
        self.flow_price_usd = 0.62

    def _init_web3(self):
        """Initialize Web3"""
        endpoint = "https://mainnet.evm.nodes.onflow.org"
        self.w3 = Web3(Web3.HTTPProvider(endpoint, request_kwargs={'timeout': 30}))
        if not self.w3.is_connected():
            raise Exception("Failed to connect to Flow EVM")
        logging.info(f"✅ Connected to Flow EVM")

    def _init_database(self):
        """Initialize database"""
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS kittypunch_apy_snapshots (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp INTEGER NOT NULL,
                    block_number INTEGER NOT NULL,
                    pair_symbol TEXT NOT NULL,
                    pair_address TEXT NOT NULL,
                    trading_fee_apy REAL NOT NULL,
                    farm_reward_apy REAL NOT NULL,
                    total_apy REAL NOT NULL,
                    tvl_usd REAL,
                    volume_24h REAL,
                    liquidity_tokens REAL,
                    source TEXT NOT NULL,
                    raw_data TEXT,
                    created_at INTEGER DEFAULT (strftime('%s','now'))
                )
            """)
            
            conn.execute("""
                CREATE TABLE IF NOT EXISTS kittypunch_volume_events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp INTEGER NOT NULL,
                    block_number INTEGER NOT NULL,
                    pair_address TEXT NOT NULL,
                    amount0 REAL NOT NULL,
                    amount1 REAL NOT NULL,
                    estimated_volume_usd REAL NOT NULL,
                    estimated_fees_usd REAL NOT NULL,
                    transaction_hash TEXT NOT NULL,
                    created_at INTEGER DEFAULT (strftime('%s','now'))
                )
            """)
            
            conn.commit()

    async def get_fixed_defillama_data(self) -> List[KittyPunchAPYSnapshot]:
        """Get DefiLlama data with fixed parsing"""
        
        snapshots = []
        current_time = datetime.now()
        current_block = self.w3.eth.block_number
        
        try:
            print("🔗 Trying DefiLlama API with fixed parsing...")
            
            async with aiohttp.ClientSession() as session:
                async with session.get("https://yields.llama.fi/pools", timeout=15) as response:
                    if response.status == 200:
                        data = await response.json()
                        
                        flow_pools_found = 0
                        
                        for pool in data.get('data', []):
                            try:
                                # Safe parsing with None checks
                                chain = str(pool.get('chain', '')).lower()
                                project = str(pool.get('project', '')).lower()
                                symbol = str(pool.get('symbol', 'Unknown'))
                                
                                # Look for Flow-related pools
                                if ('flow' in chain or 'punch' in project or 'kitty' in project):
                                    flow_pools_found += 1
                                    
                                    # Safe float conversion with fallbacks
                                    try:
                                        apy = float(pool.get('apy') or 0)
                                    except (ValueError, TypeError):
                                        apy = 0.0
                                    
                                    try:
                                        tvl = float(pool.get('tvlUsd') or 0)
                                    except (ValueError, TypeError):
                                        tvl = 0.0
                                    
                                    try:
                                        volume_7d = float(pool.get('volumeUsd7d') or 0)
                                        volume_24h = volume_7d / 7  # Rough daily estimate
                                    except (ValueError, TypeError):
                                        volume_24h = 0.0
                                    
                                    # Estimate APY breakdown
                                    if apy > 50:  # High APY suggests farm rewards
                                        farm_apy = apy * 0.7  # Assume 70% from farms
                                        trading_apy = apy * 0.3  # 30% from trading
                                    elif apy > 10:
                                        farm_apy = apy * 0.5  # Mixed
                                        trading_apy = apy * 0.5
                                    else:
                                        farm_apy = 0  # Low APY = just trading fees
                                        trading_apy = apy
                                    
                                    snapshots.append(KittyPunchAPYSnapshot(
                                        timestamp=current_time,
                                        block_number=current_block,
                                        pair_symbol=symbol,
                                        pair_address='defillama_unknown',
                                        trading_fee_apy=trading_apy,
                                        farm_reward_apy=farm_apy,
                                        total_apy=apy,
                                        tvl_usd=tvl,
                                        volume_24h=volume_24h,
                                        liquidity_tokens=tvl / (self.flow_price_usd * 2),  # Rough estimate
                                        source='defillama_api_fixed',
                                        raw_data={
                                            'chain': chain,
                                            'project': project,
                                            'original_apy': pool.get('apy'),
                                            'original_tvl': pool.get('tvlUsd')
                                        }
                                    ))
                                    
                                    print(f"   ✅ Found: {symbol} - {apy:.3f}% APY, ${tvl:,.0f} TVL")
                            
                            except Exception as e:
                                # Skip pools with parsing errors
                                continue
                        
                        print(f"   📊 Total Flow pools found: {flow_pools_found}")
                        
        except Exception as e:
            print(f"   ❌ DefiLlama API failed: {e}")
        
        return snapshots

    async def get_pair_address_safe(self, token0_symbol: str, token1_symbol: str) -> Optional[str]:
        """Safely get pair address"""
        
        try:
            factory_contract = self.w3.eth.contract(
                address=Web3.to_checksum_address(self.factory_v2),
                abi=UNISWAP_V2_ABI
            )
            
            token0_addr = Web3.to_checksum_address(self.tokens[token0_symbol])
            token1_addr = Web3.to_checksum_address(self.tokens[token1_symbol])
            
            pair_address = factory_contract.functions.getPair(token0_addr, token1_addr).call()
            
            if pair_address != '0x0000000000000000000000000000000000000000':
                return pair_address
        
        except Exception as e:
            print(f"   ❌ Failed to get pair for {token0_symbol}-{token1_symbol}: {e}")
        
        return None

    async def calculate_trading_apy_safe(self, pair_address: str) -> Tuple[float, Dict]:
        """Calculate trading APY with safe event querying"""
        
        try:
            pair_contract = self.w3.eth.contract(
                address=Web3.to_checksum_address(pair_address),
                abi=UNISWAP_V2_ABI
            )
            
            # Get basic pair info
            reserves = pair_contract.functions.getReserves().call()
            reserve0, reserve1 = reserves[0] / 1e18, reserves[1] / 1e18
            total_supply = pair_contract.functions.totalSupply().call() / 1e18
            
            print(f"      📊 Pair reserves: {reserve0:.2f} / {reserve1:.2f}")
            print(f"      📊 LP tokens: {total_supply:.2f}")
            
            # Try to get recent swaps with VERY small chunks to avoid 413 error
            current_block = self.w3.eth.block_number
            
            # Only check last 500 blocks (about 2 hours) to avoid size issues
            lookback_blocks = 500
            from_block = max(1, current_block - lookback_blocks)
            
            print(f"      🔍 Checking swaps in blocks {from_block:,} to {current_block:,}")
            
            try:
                swap_filter = pair_contract.events.Swap.create_filter(
                    from_block=from_block,
                    to_block=current_block
                )
                
                swaps = swap_filter.get_all_entries()
                print(f"      📡 Found {len(swaps)} swaps in last {lookback_blocks} blocks")
                
                if swaps:
                    # Calculate volume from swaps
                    total_volume_token0 = 0
                    total_volume_token1 = 0
                    
                    for swap in swaps:
                        vol0 = (swap['args']['amount0In'] + swap['args']['amount0Out']) / 1e18
                        vol1 = (swap['args']['amount1In'] + swap['args']['amount1Out']) / 1e18
                        
                        total_volume_token0 += vol0
                        total_volume_token1 += vol1
                    
                    # Estimate USD volume (rough)
                    estimated_volume_usd = (total_volume_token0 + total_volume_token1) * self.flow_price_usd
                    
                    # Scale to 24h (rough extrapolation)
                    blocks_per_day = 4500 * 24
                    volume_24h_usd = estimated_volume_usd * (blocks_per_day / lookback_blocks)
                    
                    # Calculate fees (0.25% to LPs)
                    fees_24h_usd = volume_24h_usd * 0.0025
                    
                    # Estimate TVL
                    tvl_usd = (reserve0 + reserve1) * self.flow_price_usd
                    
                    # Calculate APY
                    if tvl_usd > 0:
                        daily_fee_rate = fees_24h_usd / tvl_usd
                        annual_apy = daily_fee_rate * 365 * 100
                        
                        print(f"      💰 24h volume: ${volume_24h_usd:,.0f}")
                        print(f"      💰 24h fees: ${fees_24h_usd:,.2f}")
                        print(f"      💰 TVL: ${tvl_usd:,.0f}")
                        print(f"      📈 Trading APY: {annual_apy:.3f}%")
                        
                        return annual_apy, {
                            'volume_24h': volume_24h_usd,
                            'fees_24h': fees_24h_usd,
                            'tvl_usd': tvl_usd,
                            'swap_count': len(swaps),
                            'lookback_blocks': lookback_blocks
                        }
            
            except Exception as e:
                print(f"      ⚠️ Swap event query failed: {e}")
            
            # Fallback: estimate based on reserves
            tvl_usd = (reserve0 + reserve1) * self.flow_price_usd
            
            # Use conservative estimate: 0.1% daily volume of TVL
            estimated_volume_24h = tvl_usd * 0.001
            estimated_fees_24h = estimated_volume_24h * 0.0025
            estimated_apy = (estimated_fees_24h / tvl_usd) * 365 * 100 if tvl_usd > 0 else 0
            
            print(f"      📊 Fallback estimate: {estimated_apy:.3f}% APY")
            
            return estimated_apy, {
                'volume_24h': estimated_volume_24h,
                'fees_24h': estimated_fees_24h,
                'tvl_usd': tvl_usd,
                'method': 'estimated'
            }
        
        except Exception as e:
            print(f"      ❌ Trading APY calculation failed: {e}")
            return 0.0, {}

    async def get_current_apy_data(self) -> List[KittyPunchAPYSnapshot]:
        """Get current APY data with fixed methods"""
        
        print("🎯 Getting KittyPunch APY data (FIXED methods)...")
        snapshots = []
        
        # Method 1: Fixed DefiLlama parsing
        defillama_snapshots = await self.get_fixed_defillama_data()
        snapshots.extend(defillama_snapshots)
        
        # Method 2: Direct pair analysis (if DefiLlama fails)
        if not snapshots:
            print("\n🔍 DefiLlama had no data, trying direct pair analysis...")
            
            # Try WFLOW-ankrFLOW pair
            pair_address = await self.get_pair_address_safe('WFLOW', 'ankrFLOW')
            
            if pair_address:
                print(f"   📊 Analyzing WFLOW-ankrFLOW pair: {pair_address}")
                
                trading_apy, analysis_data = await self.calculate_trading_apy_safe(pair_address)
                
                # Create snapshot
                snapshots.append(KittyPunchAPYSnapshot(
                    timestamp=datetime.now(),
                    block_number=self.w3.eth.block_number,
                    pair_symbol="WFLOW-ankrFLOW",
                    pair_address=pair_address,
                    trading_fee_apy=trading_apy,
                    farm_reward_apy=0.0,  # No farm data available
                    total_apy=trading_apy,
                    tvl_usd=analysis_data.get('tvl_usd', 0),
                    volume_24h=analysis_data.get('volume_24h', 0),
                    liquidity_tokens=analysis_data.get('tvl_usd', 0) / (self.flow_price_usd * 2),
                    source='direct_pair_analysis',
                    raw_data=analysis_data
                ))
        
        return snapshots

    def store_apy_snapshots(self, snapshots: List[KittyPunchAPYSnapshot]):
        """Store APY snapshots"""
        
        with sqlite3.connect(self.db_path) as conn:
            for snapshot in snapshots:
                conn.execute("""
                    INSERT INTO kittypunch_apy_snapshots 
                    (timestamp, block_number, pair_symbol, pair_address, trading_fee_apy,
                     farm_reward_apy, total_apy, tvl_usd, volume_24h, liquidity_tokens, source, raw_data)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (
                    int(snapshot.timestamp.timestamp()),
                    snapshot.block_number,
                    snapshot.pair_symbol,
                    snapshot.pair_address,
                    snapshot.trading_fee_apy,
                    snapshot.farm_reward_apy,
                    snapshot.total_apy,
                    snapshot.tvl_usd,
                    snapshot.volume_24h,
                    snapshot.liquidity_tokens,
                    snapshot.source,
                    json.dumps(snapshot.raw_data) if snapshot.raw_data else None
                ))
            conn.commit()

    def generate_yield_report(self):
        """Generate yield report"""
        
        with sqlite3.connect(self.db_path) as conn:
            df = pd.read_sql_query("""
                SELECT timestamp, pair_symbol, trading_fee_apy, farm_reward_apy, 
                       total_apy, tvl_usd, volume_24h, source
                FROM kittypunch_apy_snapshots 
                WHERE timestamp >= ?
                ORDER BY timestamp DESC
            """, conn, params=[int((datetime.now() - timedelta(days=7)).timestamp())])
            
            if df.empty:
                print("No historical data available. Run --current first.")
                return
            
            print(f"\n" + "="*80)
            print(f"🎯 KITTYPUNCH APY ANALYSIS (FIXED)")
            print(f"="*80)
            
            # Current data
            latest_data = df.groupby('pair_symbol').first()
            
            print(f"\n📊 CURRENT YIELDS:")
            for pair, data in latest_data.iterrows():
                print(f"\n💰 {pair}:")
                print(f"   Trading Fee APY: {data['trading_fee_apy']:.3f}%")
                print(f"   Farm Reward APY: {data['farm_reward_apy']:.3f}%")
                print(f"   Total APY: {data['total_apy']:.3f}%")
                print(f"   TVL: ${data['tvl_usd']:,.0f}")
                print(f"   24h Volume: ${data['volume_24h']:,.0f}")
                print(f"   Data Source: {data['source']}")
            
            # Overall insights
            print(f"\n💡 YIELD INSIGHTS:")
            max_apy = latest_data['total_apy'].max()
            avg_apy = latest_data['total_apy'].mean()
            
            if max_apy > 100:
                print("   🚀 Very high APY detected - likely farm epoch active")
            elif max_apy > 20:
                print("   📈 Good yield opportunities available")
            else:
                print("   📊 Normal trading fee yields")
            
            print(f"   Best APY: {max_apy:.2f}%")
            print(f"   Average APY: {avg_apy:.2f}%")
            
            print("="*80)

async def main():
    """Main execution"""
    
    import sys
    
    logging.basicConfig(level=logging.INFO)
    
    tracker = FixedKittyPunchTracker()
    
    if len(sys.argv) > 1:
        command = sys.argv[1]
        
        if command == '--current':
            snapshots = await tracker.get_current_apy_data()
            
            if snapshots:
                print(f"\n✅ Retrieved {len(snapshots)} yield measurements:")
                for snapshot in snapshots:
                    print(f"   {snapshot.pair_symbol}: {snapshot.total_apy:.3f}% total APY")
                    print(f"      Trading: {snapshot.trading_fee_apy:.3f}%, Farm: {snapshot.farm_reward_apy:.3f}%")
                    print(f"      TVL: ${snapshot.tvl_usd:,.0f}, Source: {snapshot.source}")
                
                tracker.store_apy_snapshots(snapshots)
                print(f"\n💾 Stored snapshots to database")
            else:
                print("❌ No yield data retrieved")
        
        elif command == '--report':
            tracker.generate_yield_report()
        
        else:
            print("Unknown command")
    
    else:
        print("Fixed KittyPunch Dynamic APY Tracker")
        print("Usage:")
        print("  --current    Get current APY data (fixed methods)")
        print("  --report     Generate yield report")

if __name__ == "__main__":
    asyncio.run(main())