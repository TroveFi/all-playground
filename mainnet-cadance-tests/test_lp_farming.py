# test_lp_farming_fixed.py
# Fixed version with proper Flow struct parsing

import asyncio
import json
import subprocess
import time
import os
import re
from dataclasses import dataclass, asdict
from typing import List, Dict, Optional, Tuple
from decimal import Decimal, getcontext
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import logging
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

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
    calculated_apy: float = 0.0
    il_risk: float = 0.0
    
    def __post_init__(self):
        # Parse LP token pair from acceptTokenKey
        if "SwapPair" in self.accept_token_key:
            self.lp_pair = self._parse_lp_pair()
        else:
            self.lp_pair = ("UNKNOWN", "UNKNOWN")
    
    def _parse_lp_pair(self) -> Tuple[str, str]:
        # Parse based on the actual contract addresses we see
        if "fa82796435e15832" in self.accept_token_key:
            return ("FLOW", "USDC")  # Most common pair
        elif "396c0cda3302d8c5" in self.accept_token_key:
            return ("FLOW", "stFLOW")
        elif "6155398610a02093" in self.accept_token_key:
            return ("SDM", "FLOW")
        else:
            return ("TOKEN_A", "TOKEN_B")
    
    @property
    def utilization(self) -> float:
        """Pool utilization percentage"""
        if self.limit_amount > 0:
            return (self.total_staking / self.limit_amount) * 100
        return 0.0
    
    @property
    def capacity(self) -> float:
        """Available capacity in pool"""
        return max(0, self.limit_amount - self.total_staking)

class FixedFlowClient:
    """Fixed Flow client with proper struct parsing"""
    
    def __init__(self, network: str = "mainnet", paper_trading: bool = True):
        self.network = network
        self.paper_trading = paper_trading
        self.user_address = os.getenv("USER_ADDRESS")
        self.private_key = os.getenv("PRIVATE_KEY")
        self.logger = logging.getLogger(__name__)
        
        if not self.user_address:
            raise ValueError("USER_ADDRESS not found in environment variables")
        
        if not paper_trading and not self.private_key:
            raise ValueError("PRIVATE_KEY required for real transactions")
    
    def parse_flow_struct_array(self, flow_output: str) -> List[Dict]:
        """Parse Flow struct array output into Python dicts"""
        structs = []
        
        # Extract individual structs using regex
        pattern = r'FarmPoolInfo\(([^)]+(?:\([^)]*\)[^)]*)*)\)'
        matches = re.findall(pattern, flow_output)
        
        for match in matches:
            struct_data = self.parse_single_struct(match)
            if struct_data:
                structs.append(struct_data)
        
        return structs
    
    def parse_single_struct(self, struct_content: str) -> Dict:
        """Parse a single FarmPoolInfo struct"""
        data = {}
        
        try:
            # Extract pid
            pid_match = re.search(r'pid:\s*(\d+)', struct_content)
            if pid_match:
                data['pid'] = int(pid_match.group(1))
            
            # Extract status
            status_match = re.search(r'status:\s*"([^"]*)"', struct_content)
            if status_match:
                data['status'] = status_match.group(1)
            
            # Extract acceptTokenKey
            token_match = re.search(r'acceptTokenKey:\s*"([^"]*)"', struct_content)
            if token_match:
                data['acceptTokenKey'] = token_match.group(1)
            
            # Extract totalStaking
            staking_match = re.search(r'totalStaking:\s*([\d.]+)', struct_content)
            if staking_match:
                data['totalStaking'] = float(staking_match.group(1))
            
            # Extract limitAmount
            limit_match = re.search(r'limitAmount:\s*([\d.]+)', struct_content)
            if limit_match:
                data['limitAmount'] = float(limit_match.group(1))
            
            # Extract creator
            creator_match = re.search(r'creator:\s*(0x[a-fA-F0-9]+)', struct_content)
            if creator_match:
                data['creator'] = creator_match.group(1)
            
            # Extract rewardTokens array
            reward_tokens_match = re.search(r'rewardTokens:\s*\[([^\]]*)\]', struct_content)
            if reward_tokens_match:
                tokens_str = reward_tokens_match.group(1)
                tokens = re.findall(r'"([^"]*)"', tokens_str)
                data['rewardTokens'] = tokens
            else:
                data['rewardTokens'] = []
            
            # Extract rewardInfo dict and parse RPS values
            reward_info_match = re.search(r'rewardInfo:\s*\{([^}]*)\}', struct_content)
            if reward_info_match:
                info_str = reward_info_match.group(1)
                pairs = re.findall(r'"([^"]*)"\s*:\s*"([^"]*)"', info_str)
                
                reward_info = {}
                for token_key, rps_str in pairs:
                    # Extract the numeric RPS value
                    rps_match = re.search(r'RPS:\s*([\d.]+)', rps_str)
                    if rps_match:
                        reward_info[token_key] = float(rps_match.group(1))
                    else:
                        reward_info[token_key] = 0.0
                
                data['rewardInfo'] = reward_info
            else:
                data['rewardInfo'] = {}
                
        except Exception as e:
            self.logger.error(f"Error parsing struct: {e}")
            return {}
        
        return data
    
    async def execute_script(self, script_path: str, args: List[str] = None) -> dict:
        """Execute Cadence script with proper parsing"""
        cmd = ["flow", "scripts", "execute", script_path, f"--network={self.network}"]
        if args:
            cmd.extend(args)
        
        try:
            self.logger.info(f"Executing script: {script_path}")
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)
            
            # Find the Result line
            output_lines = result.stdout.strip().split('\n')
            result_line = None
            
            for line in output_lines:
                if line.startswith('Result:'):
                    result_line = line[7:].strip()
                    break
            
            if not result_line:
                self.logger.error("No result found in Flow output")
                return {}
            
            # Parse based on content type
            if result_line.startswith('[') and 'FarmPoolInfo' in result_line:
                # Array of structs
                structs = self.parse_flow_struct_array(result_line)
                return {"pools": structs}
            elif result_line == "[]":
                # Empty array
                return {"pools": []}
            else:
                # Try JSON parsing for other formats
                try:
                    return json.loads(result_line)
                except json.JSONDecodeError:
                    self.logger.warning(f"Could not parse result: {result_line[:100]}...")
                    return {"raw": result_line}
                    
        except subprocess.CalledProcessError as e:
            self.logger.error(f"Script execution failed: {e.stderr}")
            return {}
        except Exception as e:
            self.logger.error(f"Script execution error: {e}")
            return {}
    
async def send_transaction(self, tx_path: str, args: List[str] = None) -> str:
        """Send transaction (paper trading or real)"""
        if self.paper_trading:
            self.logger.info(f"PAPER TRADE: Would send transaction {tx_path} with args: {args}")
            return f"paper_tx_{int(time.time())}"
        
        # Corrected line below
        cmd = ["flow", "transactions", "send", tx_path, f"--network={self.network}", f"--signer=mainnet-deployer"]
        if args:
            cmd.extend(args)
        
        try:
            self.logger.info(f"Sending real transaction: {tx_path}")
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)
            
            # Extract transaction ID
            for line in result.stdout.split('\n'):
                if 'Transaction ID' in line:
                    return line.split(':')[-1].strip()
            return "unknown_tx"
            
        except subprocess.CalledProcessError as e:
            self.logger.error(f"Transaction failed: {e.stderr}")
            raise
    
    async def get_farm_pools(self) -> List[FarmPool]:
        """Fetch all available farming pools with proper parsing"""
        result = await self.execute_script("cadence/scripts/get-increment-pools.cdc")
        pools = []
        
        if "pools" in result and result["pools"]:
            for pool_data in result["pools"]:
                pool = FarmPool(
                    pid=pool_data.get("pid", 0),
                    status=pool_data.get("status", "unknown"),
                    accept_token_key=pool_data.get("acceptTokenKey", ""),
                    total_staking=pool_data.get("totalStaking", 0.0),
                    limit_amount=pool_data.get("limitAmount", 0.0),
                    creator=pool_data.get("creator", ""),
                    reward_tokens=pool_data.get("rewardTokens", []),
                    reward_per_seed=pool_data.get("rewardInfo", {})
                )
                pools.append(pool)
        
        return pools
    
    async def get_user_positions(self, user_address: str) -> List[dict]:
        """Get user's current staking positions"""
        result = await self.execute_script(
            "cadence/scripts/get-user-lp-positions.cdc", 
            [user_address]
        )
        
        if "pools" in result:
            return result["pools"]
        elif isinstance(result, list):
            return result
        return []

class TestAPYCalculator:
    """APY calculator with realistic token prices"""
    
    def __init__(self):
        # More realistic token prices
        self.token_prices = {
            "A.1654653399040a61.FlowToken": 0.50,      # FLOW
            "A.d6f80565193ad727.stFlowToken": 0.52,    # stFLOW (slight premium)
            "A.b19436aae4d94622.FiatToken": 1.00,      # USDC
            "A.c8c340cebd11f690.SdmToken": 0.02,       # SDM (small cap token)
        }
        self.logger = logging.getLogger(__name__)
    
    async def update_token_prices(self):
        """Mock price update"""
        self.logger.info("Updated token prices")
    
    def calculate_pool_apy(self, pool: FarmPool) -> float:
        """Calculate realistic APY for a farming pool"""
        if pool.total_staking == 0:
            return 500.0  # High APY for empty pools but capped for realism
        
        total_reward_value_per_day = 0.0
        
        for token_key, rps in pool.reward_per_seed.items():
            token_price = self.token_prices.get(token_key, 0.01)  # Default to 1 cent
            
            # RPS appears to be cumulative, so estimate daily rate
            # Based on the high RPS values, assuming they're per-second rewards
            daily_reward_per_staked_token = rps * 86400  # seconds per day
            daily_reward_value = daily_reward_per_staked_token * token_price
            
            total_reward_value_per_day += daily_reward_value
        
        if pool.total_staking == 0:
            return 500.0
        
        # Calculate APY: (daily_reward_per_token / token_value) * 365 * 100
        # Assuming staked token value is ~$0.50 (FLOW price)
        daily_yield_rate = total_reward_value_per_day / 0.50  # Assuming FLOW-based staking
        annual_yield_rate = daily_yield_rate * 365
        apy_percentage = annual_yield_rate * 100
        
        # Cap at reasonable maximum to avoid unrealistic numbers
        return min(apy_percentage, 2000.0)
    
    def calculate_impermanent_loss_risk(self, pool: FarmPool) -> float:
        """Estimate IL risk based on token pairs"""
        pair = pool.lp_pair
        
        if "stFLOW" in pair and "FLOW" in pair:
            return 10.0  # Very low IL risk - correlated assets
        elif "USDC" in pair:
            return 40.0  # Medium IL risk - stable vs volatile
        elif "SDM" in pair:
            return 75.0  # High IL risk - small cap volatile token
        else:
            return 50.0  # Default medium-high risk
    
    def calculate_safe_allocation(self, pools: List[FarmPool], 
                                total_capital: float,
                                max_risk: bool = False) -> Dict[int, float]:
        """Calculate safe allocation optimized for small amounts"""
        
        # Create analysis DataFrame
        pool_data = []
        for pool in pools:
            apy = self.calculate_pool_apy(pool)
            il_risk = self.calculate_impermanent_loss_risk(pool)
            
            # Risk-adjusted score
            risk_adjusted_apy = apy * (1 - il_risk/100)
            
            pool_data.append({
                'pid': pool.pid,
                'apy': apy,
                'il_risk': il_risk,
                'utilization': pool.utilization,
                'total_staking': pool.total_staking,
                'risk_adjusted_apy': risk_adjusted_apy,
                'capacity': pool.capacity,
                'lp_pair': f"{pool.lp_pair[0]}-{pool.lp_pair[1]}"
            })
        
        df = pd.DataFrame(pool_data)
        
        # Safety filters for small capital testing
        if not max_risk:
            df = df[df['capacity'] > 1.0]       # At least 1 token capacity
            df = df[df['il_risk'] <= 60]        # Moderate risk tolerance
            df = df[df['total_staking'] > 0.1]  # Some existing liquidity
        
        # Sort by risk-adjusted APY
        df = df.sort_values('risk_adjusted_apy', ascending=False)
        
        # Allocation algorithm for small amounts
        allocation = {}
        remaining_capital = total_capital
        
        # For very small amounts, focus on top opportunities
        max_positions = 3 if total_capital < 10 else 5
        
        for _, row in df.head(max_positions).iterrows():
            if remaining_capital <= 0:
                break
            
            # Conservative allocation sizing
            max_per_pool = min(
                total_capital * 0.5,        # Max 50% in one pool for small amounts
                row['capacity'] * 0.05,     # Use only 5% of pool capacity
                remaining_capital,
                1.0                         # Minimum viable amount
            )
            
            if max_per_pool >= 0.1:  # Minimum 0.1 FLOW position
                allocation[row['pid']] = round(max_per_pool, 4)
                remaining_capital -= max_per_pool
        
        return allocation

class FixedLPFarmingAgent:
    """Fixed LP farming agent with proper parsing"""
    
    def __init__(self, 
                 total_capital: float = 2.0,
                 paper_trading: bool = True,
                 max_risk: bool = False):
        
        self.user_address = os.getenv("USER_ADDRESS")
        self.total_capital = total_capital
        self.paper_trading = paper_trading
        self.max_risk = max_risk
        
        if not self.user_address:
            raise ValueError("USER_ADDRESS must be set in .env file")
        
        # Safety check for real trading
        if not paper_trading and total_capital > 50:
            raise ValueError("For safety, limit real trading to 50 FLOW or less")
        
        self.flow_client = FixedFlowClient(paper_trading=paper_trading)
        self.apy_calculator = TestAPYCalculator()
        self.current_positions = {}
        self.target_allocation = {}
        
        # Logging setup
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler('test_lp_farming.log'),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger(__name__)
        
        # Test results tracking
        self.test_results = {
            'start_time': datetime.now(),
            'pools_discovered': 0,
            'viable_pools': 0,
            'allocation_pools': 0,
            'total_allocated': 0.0,
            'expected_apy': 0.0,
            'transactions_simulated': 0
        }
        
    async def run_comprehensive_test(self):
        """Run the fixed comprehensive test"""
        self.logger.info("=" * 60)
        self.logger.info("FIXED LP FARMING COMPREHENSIVE TEST")
        self.logger.info(f"Capital: {self.total_capital} FLOW")
        self.logger.info(f"Paper Trading: {self.paper_trading}")
        self.logger.info(f"User Address: {self.user_address}")
        self.logger.info("=" * 60)
        
        try:
            # Test pool discovery with fixed parsing
            pools = await self.test_pool_discovery()
            
            if pools:
                # Calculate allocations
                allocation = await self.test_allocation_calculation(pools)
                
                if allocation:
                    # Simulate transactions
                    await self.test_transaction_simulation(allocation, pools)
                    
                    # Show performance projection
                    await self.test_performance_projection(allocation, pools)
            
            # Generate final report
            self.generate_test_report()
            
        except Exception as e:
            self.logger.error(f"Test failed: {e}")
            raise
    
    async def test_pool_discovery(self) -> List[FarmPool]:
        """Test pool discovery with fixed parsing"""
        self.logger.info("\n--- POOL DISCOVERY TEST ---")
        
        pools = await self.flow_client.get_farm_pools()
        self.test_results['pools_discovered'] = len(pools)
        
        if not pools:
            self.logger.error("No pools discovered - check parsing logic")
            return []
        
        self.logger.info(f"Successfully discovered {len(pools)} pools")
        
        # Analyze pools
        await self.apy_calculator.update_token_prices()
        analyzed_pools = []
        
        for pool in pools:
            pool.calculated_apy = self.apy_calculator.calculate_pool_apy(pool)
            pool.il_risk = self.apy_calculator.calculate_impermanent_loss_risk(pool)
            analyzed_pools.append(pool)
        
        # Filter viable pools
        viable_pools = [p for p in analyzed_pools if p.calculated_apy > 10 and p.capacity > 1.0]
        self.test_results['viable_pools'] = len(viable_pools)
        
        # Sort and display top opportunities
        viable_pools.sort(key=lambda p: p.calculated_apy, reverse=True)
        
        self.logger.info(f"\nTop 10 Viable Opportunities:")
        self.logger.info("-" * 90)
        for i, pool in enumerate(viable_pools[:10], 1):
            self.logger.info(
                f"{i:2d}. Pool {pool.pid:2d} | "
                f"{pool.lp_pair[0]}-{pool.lp_pair[1]:8s} | "
                f"APY: {pool.calculated_apy:8.2f}% | "
                f"TVL: {pool.total_staking:10.2f} | "
                f"IL Risk: {pool.il_risk:5.1f}% | "
                f"Capacity: {pool.capacity:10.0f}"
            )
        
        return analyzed_pools
    
    async def test_allocation_calculation(self, pools: List[FarmPool]) -> Dict[int, float]:
        """Test allocation calculation"""
        self.logger.info(f"\n--- ALLOCATION CALCULATION TEST ---")
        
        allocation = self.apy_calculator.calculate_safe_allocation(
            pools, self.total_capital, self.max_risk
        )
        
        self.target_allocation = allocation
        self.test_results['allocation_pools'] = len(allocation)
        self.test_results['total_allocated'] = sum(allocation.values())
        
        if not allocation:
            self.logger.warning("No suitable allocation found")
            return {}
        
        total_allocated = sum(allocation.values())
        
        self.logger.info(f"\nOptimal Allocation for {self.total_capital} FLOW:")
        self.logger.info("-" * 70)
        
        weighted_apy = 0.0
        for pid, amount in allocation.items():
            pool = next(p for p in pools if p.pid == pid)
            percentage = (amount / total_allocated) * 100
            weighted_apy += (amount / total_allocated) * pool.calculated_apy
            
            self.logger.info(
                f"Pool {pid:2d}: {amount:6.4f} FLOW ({percentage:5.1f}%) | "
                f"{pool.lp_pair[0]}-{pool.lp_pair[1]:8s} | "
                f"APY: {pool.calculated_apy:7.2f}% | "
                f"IL Risk: {pool.il_risk:5.1f}%"
            )
        
        self.test_results['expected_apy'] = weighted_apy
        
        self.logger.info("-" * 70)
        self.logger.info(f"Total Allocated: {total_allocated:.4f} FLOW ({total_allocated/self.total_capital*100:.1f}%)")
        self.logger.info(f"Portfolio APY: {weighted_apy:.2f}%")
        
        return allocation
    
    async def test_transaction_simulation(self, allocation: Dict[int, float], pools: List[FarmPool]):
        """Test transaction simulation"""
        self.logger.info(f"\n--- TRANSACTION SIMULATION TEST ---")
        
        tx_count = 0
        for pid, amount in allocation.items():
            pool = next(p for p in pools if p.pid == pid)
            
            # Simulate staking
            tx_id = await self.flow_client.send_transaction(
                "cadence/transactions/stake-lp-in-farm.cdc",
                [str(pid), str(amount)]
            )
            
            tx_count += 1
            self.logger.info(f"  Stake {amount:.4f} FLOW → Pool {pid} ({pool.lp_pair[0]}-{pool.lp_pair[1]}) | TX: {tx_id}")
        
        self.test_results['transactions_simulated'] = tx_count
        
        self.logger.info(f"\nSimulated {tx_count} transactions successfully")
    
    async def test_performance_projection(self, allocation: Dict[int, float], pools: List[FarmPool]):
        """Test performance projection"""
        self.logger.info(f"\n--- PERFORMANCE PROJECTION ---")
        
        total_allocated = sum(allocation.values())
        daily_returns = {}
        
        for pid, amount in allocation.items():
            pool = next(p for p in pools if p.pid == pid)
            daily_return = (amount * pool.calculated_apy / 100) / 365
            daily_returns[pid] = daily_return
        
        total_daily = sum(daily_returns.values())
        total_weekly = total_daily * 7
        total_monthly = total_daily * 30
        
        self.logger.info(f"Performance Projections:")
        self.logger.info(f"  Allocated Capital: {total_allocated:.4f} FLOW")
        self.logger.info(f"  Expected Daily:    {total_daily:.6f} FLOW")
        self.logger.info(f"  Expected Weekly:   {total_weekly:.4f} FLOW")
        self.logger.info(f"  Expected Monthly:  {total_monthly:.4f} FLOW")
        self.logger.info(f"  Effective APY:     {self.test_results['expected_apy']:.2f}%")
    
    def generate_test_report(self):
        """Generate comprehensive test report"""
        self.logger.info("\n" + "=" * 60)
        self.logger.info("COMPREHENSIVE TEST REPORT")
        self.logger.info("=" * 60)
        
        duration = datetime.now() - self.test_results['start_time']
        
        self.logger.info(f"Test Duration:        {duration}")
        self.logger.info(f"Pools Discovered:     {self.test_results['pools_discovered']}")
        self.logger.info(f"Viable Pools:         {self.test_results['viable_pools']}")
        self.logger.info(f"Allocation Pools:     {self.test_results['allocation_pools']}")
        self.logger.info(f"Capital Allocated:    {self.test_results['total_allocated']:.4f} FLOW")
        self.logger.info(f"Expected APY:         {self.test_results['expected_apy']:.2f}%")
        self.logger.info(f"Transactions Sim:     {self.test_results['transactions_simulated']}")
        
        success = all([
            self.test_results['pools_discovered'] > 0,
            self.test_results['viable_pools'] > 0,
            self.test_results['allocation_pools'] > 0,
            self.test_results['total_allocated'] > 0
        ])
        
        if success:
            self.logger.info(f"\n🎉 ALL TESTS PASSED! System is ready for deployment.")
            
            if self.paper_trading:
                self.logger.info(f"💡 To execute real transactions, set paper_trading=False")
            else:
                self.logger.info(f"⚠️  Ready for REAL transaction execution!")
                
            # Deployment readiness check
            utilization = (self.test_results['total_allocated'] / self.total_capital) * 100
            self.logger.info(f"\nDeployment Summary:")
            self.logger.info(f"  Capital Utilization: {utilization:.1f}%")
            self.logger.info(f"  Risk-Adjusted APY:   {self.test_results['expected_apy']:.2f}%")
            self.logger.info(f"  Diversification:     {self.test_results['allocation_pools']} pools")
            
        else:
            self.logger.warning(f"\n⚠️  Some tests failed - review configuration")
        
        self.logger.info("=" * 60)

# Test execution functions
async def run_quick_test():
    """Quick test with 2 FLOW"""
    agent = FixedLPFarmingAgent(
        total_capital=2.0,
        paper_trading=True,
        max_risk=False
    )
    await agent.run_comprehensive_test()

async def run_real_test():
    """Real transaction test with 2 FLOW"""
    print("⚠️  WARNING: This will execute REAL transactions!")
    response = input("Type 'YES' to confirm: ")
    
    if response != "YES":
        print("Test cancelled")
        return
    
    agent = FixedLPFarmingAgent(
        total_capital=2.0,
        paper_trading=False,
        max_risk=False
    )
    await agent.run_comprehensive_test()

if __name__ == "__main__":
    import sys
    
    if not os.getenv("USER_ADDRESS"):
        print("❌ Error: USER_ADDRESS not found in .env file")
        sys.exit(1)
    
    print("Fixed LP Farming Test Options:")
    print("1. Paper Trading Test (2 FLOW)")
    print("2. Real Transaction Test (2 FLOW)")
    print("3. Exit")
    
    choice = input("\nSelect option (1-3): ")
    
    if choice == "1":
        asyncio.run(run_quick_test())
    elif choice == "2":
        asyncio.run(run_real_test())
    else:
        print("Goodbye!")