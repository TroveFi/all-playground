#!/usr/bin/env python3
"""
CSV Exporter for APY tracking data
Converts SQLite data to CSV files for GitHub Actions
"""

import sqlite3
import pandas as pd
from datetime import datetime, timedelta
import os
import sys

def export_ankr_data(db_path: str, output_dir: str):
    """Export Ankr APY data to CSV"""
    
    if not os.path.exists(db_path):
        print(f"Database {db_path} not found, skipping Ankr export")
        return
    
    with sqlite3.connect(db_path) as conn:
        # Get latest snapshot
        latest_df = pd.read_sql_query("""
            SELECT timestamp, current_apy, total_staked, apy_basis, 
                   exchange_rate, source, block_number
            FROM ankr_apy_snapshots 
            ORDER BY timestamp DESC LIMIT 1
        """, conn)
        
        if not latest_df.empty:
            latest_df['datetime'] = pd.to_datetime(latest_df['timestamp'], unit='s')
            latest_df['date'] = latest_df['datetime'].dt.date
            latest_df['tracker'] = 'ankr_flow'
            
            output_path = os.path.join(output_dir, f"ankr_apy_{datetime.now().strftime('%Y%m%d')}.csv")
            latest_df.to_csv(output_path, index=False)
            print(f"Exported Ankr data to {output_path}")
            
            # Also append to master file
            master_path = os.path.join(output_dir, "ankr_apy_master.csv")
            if os.path.exists(master_path):
                latest_df.to_csv(master_path, mode='a', header=False, index=False)
            else:
                latest_df.to_csv(master_path, index=False)

def export_kittypunch_data(db_path: str, output_dir: str):
    """Export KittyPunch APY data to CSV"""
    
    if not os.path.exists(db_path):
        print(f"Database {db_path} not found, skipping KittyPunch export")
        return
    
    with sqlite3.connect(db_path) as conn:
        # Get latest snapshots for each pair
        latest_df = pd.read_sql_query("""
            SELECT timestamp, pair_symbol, trading_fee_apy, farm_reward_apy, 
                   total_apy, tvl_usd, volume_24h, source, block_number
            FROM kittypunch_apy_snapshots 
            WHERE timestamp >= (SELECT MAX(timestamp) - 3600 FROM kittypunch_apy_snapshots)
            ORDER BY timestamp DESC
        """, conn)
        
        if not latest_df.empty:
            latest_df['datetime'] = pd.to_datetime(latest_df['timestamp'], unit='s')
            latest_df['date'] = latest_df['datetime'].dt.date
            latest_df['tracker'] = 'kittypunch'
            
            output_path = os.path.join(output_dir, f"kittypunch_apy_{datetime.now().strftime('%Y%m%d')}.csv")
            latest_df.to_csv(output_path, index=False)
            print(f"Exported KittyPunch data to {output_path}")
            
            # Also append to master file
            master_path = os.path.join(output_dir, "kittypunch_apy_master.csv")
            if os.path.exists(master_path):
                latest_df.to_csv(master_path, mode='a', header=False, index=False)
            else:
                latest_df.to_csv(master_path, index=False)

def export_more_markets_data(db_path: str, output_dir: str):
    """Export More.Markets APY data to CSV"""
    
    if not os.path.exists(db_path):
        print(f"Database {db_path} not found, skipping More.Markets export")
        return
    
    with sqlite3.connect(db_path) as conn:
        # Get latest snapshots for each asset
        latest_df = pd.read_sql_query("""
            SELECT timestamp, asset_symbol, supply_apy, borrow_apy, 
                   utilization_rate, total_deposits, total_borrows, source, block_number
            FROM more_markets_apy_history 
            WHERE timestamp >= (SELECT MAX(timestamp) - 3600 FROM more_markets_apy_history)
            ORDER BY timestamp DESC
        """, conn)
        
        if not latest_df.empty:
            latest_df['datetime'] = pd.to_datetime(latest_df['timestamp'], unit='s')
            latest_df['date'] = latest_df['datetime'].dt.date
            latest_df['tracker'] = 'more_markets'
            
            output_path = os.path.join(output_dir, f"more_markets_apy_{datetime.now().strftime('%Y%m%d')}.csv")
            latest_df.to_csv(output_path, index=False)
            print(f"Exported More.Markets data to {output_path}")
            
            # Also append to master file
            master_path = os.path.join(output_dir, "more_markets_apy_master.csv")
            if os.path.exists(master_path):
                latest_df.to_csv(master_path, mode='a', header=False, index=False)
            else:
                latest_df.to_csv(master_path, index=False)

def create_daily_summary(output_dir: str):
    """Create a daily summary CSV with all trackers"""
    
    date_str = datetime.now().strftime('%Y%m%d')
    summary_data = []
    
    # Collect data from each tracker's daily file
    for tracker in ['ankr', 'kittypunch', 'more_markets']:
        daily_file = os.path.join(output_dir, f"{tracker}_apy_{date_str}.csv")
        
        if os.path.exists(daily_file):
            df = pd.read_csv(daily_file)
            
            if tracker == 'ankr':
                summary_data.append({
                    'date': date_str,
                    'tracker': 'Ankr Flow Staking',
                    'primary_apy': df['current_apy'].iloc[0] if not df.empty else 0,
                    'tvl_or_staked': df['total_staked'].iloc[0] if not df.empty else 0,
                    'asset': 'FLOW',
                    'apy_type': 'staking'
                })
            
            elif tracker == 'kittypunch':
                for _, row in df.iterrows():
                    summary_data.append({
                        'date': date_str,
                        'tracker': 'KittyPunch LP',
                        'primary_apy': row['total_apy'],
                        'tvl_or_staked': row['tvl_usd'],
                        'asset': row['pair_symbol'],
                        'apy_type': 'liquidity_provision'
                    })
            
            elif tracker == 'more_markets':
                for _, row in df.iterrows():
                    summary_data.append({
                        'date': date_str,
                        'tracker': 'More.Markets Lending',
                        'primary_apy': row['supply_apy'],
                        'tvl_or_staked': row['total_deposits'],
                        'asset': row['asset_symbol'],
                        'apy_type': 'lending'
                    })
    
    if summary_data:
        summary_df = pd.DataFrame(summary_data)
        summary_path = os.path.join(output_dir, f"daily_summary_{date_str}.csv")
        summary_df.to_csv(summary_path, index=False)
        print(f"Created daily summary: {summary_path}")
        
        # Also update master summary
        master_summary_path = os.path.join(output_dir, "master_summary.csv")
        if os.path.exists(master_summary_path):
            summary_df.to_csv(master_summary_path, mode='a', header=False, index=False)
        else:
            summary_df.to_csv(master_summary_path, index=False)

def main():
    """Main export function"""
    
    output_dir = "data"
    os.makedirs(output_dir, exist_ok=True)
    
    print(f"Starting CSV export at {datetime.now()}")
    
    # Export each tracker's data
    export_ankr_data("fixed_ankr_apy.db", output_dir)
    export_kittypunch_data("fixed_kittypunch_apy.db", output_dir)
    export_more_markets_data("more_markets_dynamic_apy.db", output_dir)
    
    # Create daily summary
    create_daily_summary(output_dir)
    
    print("CSV export completed")

if __name__ == "__main__":
    main()