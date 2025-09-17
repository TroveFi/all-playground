# flow_lp_agent.py
# Python-first architecture for optimal LP farming on Flow/IncrementFi

import asyncio
import json
import subprocess
import time
from dataclasses import dataclass, asdict
from typing import List, Dict, Optional, Tuple
from decimal import Decimal, getcontext
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import logging

# Set high precision for financial calculations
getcontext().prec = 28

@dataclass
class FarmPool:
    pid: int
    status: str
    accept_token_key: str
    total_staking: float
    limit_amount: float
    creator: str
    reward_tokens: List[str]
    reward_per_seed: Dict[str, float]
    
    def __post_init__(self):
        # Parse LP token pair from acceptTokenKey
        if "SwapPair" in self.accept_token_key:
            self.lp_pair = self._parse_lp_pair()
        else:
            self.lp_pair = ("UNKNOWN", "UNKNOWN")
    
    def _parse_lp_pair(self) -> Tuple[str, str]:
        # Would need to query the actual SwapPair contract to get token info
        # For now, placeholder logic
        return ("TOKEN_A", "TOKEN_B")
    
    @property
    def estimated_apr(self) -> float:
        """Calculate estimated APR based on reward per seed"""
        total_rps = sum(self.reward_per_seed.values())
        # Simplified APR calculation - would need token prices for accuracy
        return total_rps * 365 * 24 * 60 * 60  # Assuming per-second rewards
    
    @property
    def utilization(self) -> float:
        """Pool utilization percentage"""
        if self.limit_amount > 0:
            return (self.total_staking / self.limit_amount) * 100
        return 0.0

class FlowClient:
    """Handles all Flow blockchain interactions"""
    
    def __init__(self, network: str = "mainnet"):
        self.network = network
        self.logger = logging.getLogger(__name__)
    
    async def execute_script(self, script_path: str, args: List[str] = None) -> dict:
        """Execute Cadence script and return parsed result"""
        cmd = ["flow", "scripts", "execute", script_path, f"--network={self.network}"]
        if args:
            cmd.extend(args)
        
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)
            # Parse the Flow CLI output to extract JSON result
            output_lines = result.stdout.strip().split('\n')
            result_line = next(line for line in output_lines if line.startswith('Result:'))
            json_str = result_line[7:].strip()  # Remove 'Result: ' prefix
            return json.loads(json_str)
        except subprocess.CalledProcessError as e:
            self.logger.error(f"Script execution failed: {e.stderr}")
            raise
        except (json.JSONDecodeError, StopIteration) as e:
            self.logger.error(f"Failed to parse script result: {e}")
            raise
    
    async def send_transaction(self, tx_path: str, args: List[str] = None) -> str:
        """Send transaction and return transaction ID"""
        cmd = ["flow", "transactions", "send", tx_path, f"--network={self.network}"]
        if args:
            cmd.extend(args)
        
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)
            # Extract transaction ID from output
            for line in result.stdout.split('\n'):
                if 'Transaction ID' in line:
                    return line.split(':')[-1].strip()
            return "unknown"
        except subprocess.CalledProcessError as e:
            self.logger.error(f"Transaction failed: {e.stderr}")
            raise
    
    async def get_farm_pools(self) -> List[FarmPool]:
        """Fetch all available farming pools"""
        result = await self.execute_script("cadence/scripts/get-increment-pools.cdc")
        pools = []
        
        for pool_data in result:
            # Parse the complex struct format from Flow CLI
            pool = FarmPool(
                pid=pool_data['pid'],
                status=pool_data['status'],
                accept_token_key=pool_data['acceptTokenKey'],
                total_staking=float(pool_data['totalStaking']),
                limit_amount=float(pool_data['limitAmount']),
                creator=pool_data['creator'],
                reward_tokens=pool_data['rewardTokens'],
                reward_per_seed={k: float(v.split(':')[1].strip()) 
                               for k, v in pool_data['rewardInfo'].items()}
            )
            pools.append(pool)
        
        return pools
    
    async def get_user_positions(self, user_address: str) -> List[dict]:
        """Get user's current staking positions"""
        result = await self.execute_script(
            "cadence/scripts/get-user-lp-positions.cdc", 
            [user_address]
        )
        return result

class APYCalculator:
    """Calculate and compare APY across different strategies"""
    
    def __init__(self):
        self.token_prices = {}  # Cache token prices
        self.logger = logging.getLogger(__name__)
    
    async def update_token_prices(self):
        """Fetch current token prices from oracles or APIs"""
        # Placeholder - would integrate with price feeds
        self.token_prices = {
            "A.1654653399040a61.FlowToken": 0.50,  # FLOW
            "A.d6f80565193ad727.stFlowToken": 0.52,  # stFLOW
            "A.b19436aae4d94622.FiatToken": 1.00,   # USDC
            "A.c8c340cebd11f690.SdmToken": 0.01,    # SDM
        }
    
    def calculate_pool_apy(self, pool: FarmPool) -> float:
        """Calculate actual APY for a farming pool"""
        total_reward_value_per_day = 0.0
        
        for token_key, rps in pool.reward_per_seed.items():
            token_price = self.token_prices.get(token_key, 0.0)
            # Convert RPS to daily rewards (assuming RPS is per second)
            daily_reward_per_token = rps * 86400  # seconds in day
            total_reward_value_per_day += daily_reward_per_token * token_price
        
        if pool.total_staking == 0:
            return float('inf')  # Infinite APY for empty pools
        
        # Calculate APY: (daily_reward / total_staked) * 365 * 100
        daily_yield = total_reward_value_per_day / pool.total_staking
        apy = daily_yield * 365 * 100
        
        return apy
    
    def calculate_impermanent_loss_risk(self, pool: FarmPool) -> float:
        """Estimate impermanent loss risk (0-100 scale)"""
        # Placeholder logic - would analyze token volatility correlation
        if "stFlow" in pool.accept_token_key:
            return 20.0  # FLOW/stFLOW has lower IL risk
        elif "USDC" in pool.accept_token_key:
            return 30.0  # Stablecoin pairs have medium IL risk
        else:
            return 60.0  # Other pairs have higher IL risk
    
    def calculate_optimal_allocation(self, pools: List[FarmPool], 
                                   total_capital: float,
                                   risk_tolerance: str = "medium") -> Dict[int, float]:
        """Calculate optimal capital allocation across pools"""
        # Create DataFrame for analysis
        pool_data = []
        for pool in pools:
            apy = self.calculate_pool_apy(pool)
            il_risk = self.calculate_impermanent_loss_risk(pool)
            
            pool_data.append({
                'pid': pool.pid,
                'apy': apy,
                'il_risk': il_risk,
                'utilization': pool.utilization,
                'total_staking': pool.total_staking,
                'risk_adjusted_apy': apy * (1 - il_risk/100),
                'capacity': pool.limit_amount - pool.total_staking
            })
        
        df = pd.DataFrame(pool_data)
        
        # Filter out full pools and apply risk tolerance
        df = df[df['capacity'] > 100]  # Minimum capacity threshold
        
        if risk_tolerance == "low":
            df = df[df['il_risk'] <= 40]
        elif risk_tolerance == "medium":
            df = df[df['il_risk'] <= 60]
        # High risk tolerance includes all pools
        
        # Sort by risk-adjusted APY
        df = df.sort_values('risk_adjusted_apy', ascending=False)
        
        # Allocate capital using modified Kelly criterion
        allocation = {}
        remaining_capital = total_capital
        
        for _, row in df.head(5).iterrows():  # Top 5 opportunities
            if remaining_capital <= 0:
                break
            
            # Calculate allocation percentage based on risk-adjusted APY
            weight = min(0.3, row['risk_adjusted_apy'] / 100)  # Max 30% per pool
            allocation_amount = min(
                remaining_capital * weight,
                row['capacity'],
                remaining_capital * 0.4  # Max 40% of total capital per pool
            )
            
            if allocation_amount >= 10:  # Minimum position size
                allocation[row['pid']] = allocation_amount
                remaining_capital -= allocation_amount
        
        return allocation

class LPFarmingAgent:
    """Main agent orchestrating LP farming operations"""
    
    def __init__(self, 
                 user_address: str,
                 total_capital: float,
                 risk_tolerance: str = "medium",
                 rebalance_interval: int = 3600):  # 1 hour
        
        self.user_address = user_address
        self.total_capital = total_capital
        self.risk_tolerance = risk_tolerance
        self.rebalance_interval = rebalance_interval
        
        self.flow_client = FlowClient()
        self.apy_calculator = APYCalculator()
        self.current_positions = {}
        self.target_allocation = {}
        self.last_rebalance = datetime.now()
        
        self.logger = logging.getLogger(__name__)
        
        # Performance tracking
        self.performance_history = []
        self.total_rewards_claimed = 0.0
        
    async def initialize(self):
        """Initialize the agent"""
        self.logger.info("Initializing LP Farming Agent...")
        await self.apy_calculator.update_token_prices()
        await self.update_positions()
        self.logger.info("Agent initialized successfully")
    
    async def update_positions(self):
        """Update current positions from blockchain"""
        positions = await self.flow_client.get_user_positions(self.user_address)
        self.current_positions = {pos['pid']: pos for pos in positions}
        
    async def analyze_opportunities(self) -> List[FarmPool]:
        """Analyze current farming opportunities"""
        pools = await self.flow_client.get_farm_pools()
        
        # Filter active pools with reasonable TVL
        active_pools = [p for p in pools if p.status == "2" and p.total_staking > 10]
        
        # Calculate APY for each pool
        await self.apy_calculator.update_token_prices()
        
        # Sort by risk-adjusted APY
        for pool in active_pools:
            pool.calculated_apy = self.apy_calculator.calculate_pool_apy(pool)
            pool.il_risk = self.apy_calculator.calculate_impermanent_loss_risk(pool)
        
        active_pools.sort(key=lambda p: p.calculated_apy, reverse=True)
        
        return active_pools[:10]  # Top 10 opportunities
    
    async def calculate_rebalancing_needs(self) -> Dict[str, List[Tuple[int, float]]]:
        """Determine what rebalancing operations are needed"""
        opportunities = await self.analyze_opportunities()
        
        # Calculate optimal allocation
        self.target_allocation = self.apy_calculator.calculate_optimal_allocation(
            opportunities, 
            self.total_capital, 
            self.risk_tolerance
        )
        
        operations = {
            'enter': [],  # (pool_id, amount)
            'exit': [],   # (pool_id, amount)
            'rebalance': []  # (from_pool_id, to_pool_id, amount)
        }
        
        # Find positions to enter
        for pid, target_amount in self.target_allocation.items():
            current_amount = self.current_positions.get(pid, {}).get('stakingAmount', 0)
            
            if target_amount > current_amount + 10:  # 10 token threshold
                operations['enter'].append((pid, target_amount - current_amount))
        
        # Find positions to exit or reduce
        for pid, position in self.current_positions.items():
            current_amount = position['stakingAmount']
            target_amount = self.target_allocation.get(pid, 0)
            
            if target_amount < current_amount - 10:
                operations['exit'].append((pid, current_amount - target_amount))
        
        return operations
    
    async def execute_rebalancing(self, operations: Dict[str, List[Tuple[int, float]]]):
        """Execute the rebalancing operations"""
        self.logger.info(f"Executing rebalancing operations: {operations}")
        
        # First, exit positions that are no longer optimal
        for pid, amount in operations['exit']:
            await self._unstake_from_pool(pid, amount)
            await asyncio.sleep(5)  # Rate limiting
        
        # Then, enter new positions
        for pid, amount in operations['enter']:
            await self._stake_in_pool(pid, amount)
            await asyncio.sleep(5)  # Rate limiting
        
        self.last_rebalance = datetime.now()
        self.logger.info("Rebalancing completed")
    
    async def _stake_in_pool(self, pid: int, amount: float):
        """Stake tokens in a specific farm pool"""
        # This would need to:
        # 1. Get LP tokens (either already owned or create by adding liquidity)
        # 2. Stake LP tokens in the farm
        # For now, placeholder
        self.logger.info(f"Staking {amount} tokens in pool {pid}")
        
        # Would call appropriate Cadence transaction
        # tx_id = await self.flow_client.send_transaction(
        #     "cadence/transactions/stake-lp-in-farm.cdc",
        #     [str(pid), str(amount)]
        # )
    
    async def _unstake_from_pool(self, pid: int, amount: float):
        """Unstake tokens from a specific farm pool"""
        self.logger.info(f"Unstaking {amount} tokens from pool {pid}")
        
        # Would call appropriate Cadence transaction
        # tx_id = await self.flow_client.send_transaction(
        #     "cadence/transactions/unstake-from-farm.cdc", 
        #     [str(pid), str(amount)]
        # )
    
    async def claim_all_rewards(self):
        """Claim rewards from all active positions"""
        self.logger.info("Claiming rewards from all positions")
        
        for pid in self.current_positions.keys():
            # Would call reward claiming transaction
            # tx_id = await self.flow_client.send_transaction(
            #     "cadence/transactions/claim-farm-rewards.cdc",
            #     [str(pid)]
            # )
            pass
    
    async def run_agent_loop(self):
        """Main agent loop"""
        self.logger.info("Starting LP farming agent loop")
        
        while True:
            try:
                # Update current positions
                await self.update_positions()
                
                # Check if rebalancing is needed
                time_since_rebalance = datetime.now() - self.last_rebalance
                
                if time_since_rebalance.total_seconds() >= self.rebalance_interval:
                    operations = await self.calculate_rebalancing_needs()
                    
                    # Only rebalance if there are significant opportunities
                    total_operations = len(operations['enter']) + len(operations['exit'])
                    if total_operations > 0:
                        await self.execute_rebalancing(operations)
                
                # Claim rewards periodically (every 4 hours)
                if time_since_rebalance.total_seconds() >= 14400:  # 4 hours
                    await self.claim_all_rewards()
                
                # Log performance
                await self.log_performance()
                
                # Sleep until next cycle
                await asyncio.sleep(300)  # 5 minutes
                
            except Exception as e:
                self.logger.error(f"Error in agent loop: {e}")
                await asyncio.sleep(60)  # Wait 1 minute before retrying
    
    async def log_performance(self):
        """Log current performance metrics"""
        opportunities = await self.analyze_opportunities()
        
        total_staked = sum(pos['stakingAmount'] for pos in self.current_positions.values())
        weighted_apy = 0.0
        
        for pid, position in self.current_positions.items():
            pool = next((p for p in opportunities if p.pid == pid), None)
            if pool:
                weight = position['stakingAmount'] / total_staked if total_staked > 0 else 0
                weighted_apy += pool.calculated_apy * weight
        
        performance = {
            'timestamp': datetime.now().isoformat(),
            'total_staked': total_staked,
            'active_positions': len(self.current_positions),
            'weighted_apy': weighted_apy,
            'capital_utilization': (total_staked / self.total_capital) * 100
        }
        
        self.performance_history.append(performance)
        
        # Keep only last 24 hours of data
        cutoff = datetime.now() - timedelta(hours=24)
        self.performance_history = [
            p for p in self.performance_history 
            if datetime.fromisoformat(p['timestamp']) > cutoff
        ]
        
        self.logger.info(f"Performance: APY={weighted_apy:.2f}%, "
                        f"Utilization={performance['capital_utilization']:.1f}%, "
                        f"Positions={len(self.current_positions)}")
    
    def get_performance_report(self) -> Dict:
        """Generate performance report"""
        if not self.performance_history:
            return {"error": "No performance data available"}
        
        df = pd.DataFrame(self.performance_history)
        
        return {
            "current_apy": df['weighted_apy'].iloc[-1] if len(df) > 0 else 0,
            "average_apy_24h": df['weighted_apy'].mean(),
            "max_apy_24h": df['weighted_apy'].max(),
            "current_utilization": df['capital_utilization'].iloc[-1] if len(df) > 0 else 0,
            "active_positions": df['active_positions'].iloc[-1] if len(df) > 0 else 0,
            "total_data_points": len(df)
        }

# Example usage
async def main():
    # Initialize agent
    agent = LPFarmingAgent(
        user_address="0x79f5b5b0f95a160b",
        total_capital=1000.0,
        risk_tolerance="medium",
        rebalance_interval=3600
    )
    
    await agent.initialize()
    
    # Get current opportunities
    opportunities = await agent.analyze_opportunities()
    
    print("Top LP Farming Opportunities:")
    print("-" * 50)
    for i, pool in enumerate(opportunities[:5], 1):
        print(f"{i}. Pool {pool.pid}")
        print(f"   Tokens: {pool.lp_pair}")
        print(f"   APY: {pool.calculated_apy:.2f}%")
        print(f"   TVL: {pool.total_staking:.2f}")
        print(f"   IL Risk: {pool.il_risk:.1f}%")
        print()
    
    # Calculate optimal allocation
    allocation = agent.apy_calculator.calculate_optimal_allocation(
        opportunities, 1000.0, "medium"
    )
    
    print("Optimal Allocation:")
    print("-" * 30)
    for pid, amount in allocation.items():
        pool = next(p for p in opportunities if p.pid == pid)
        print(f"Pool {pid}: {amount:.2f} FLOW ({amount/1000*100:.1f}%)")
        print(f"  Expected APY: {pool.calculated_apy:.2f}%")
    
    # Run agent (uncomment to start automated operation)
    # await agent.run_agent_loop()

if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    asyncio.run(main())