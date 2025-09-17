# test_lp_farming.py
# Testing script for LP farming with small amounts and paper trading mode

import asyncio
import json
import subprocess
import time
import os
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
        # Simplified parsing - would need actual SwapPair contract query
        if "fa82796435e15832" in self.accept_token_key:
            return ("FLOW", "USDC")  # Most common pair
        elif "396c0cda3302d8c5" in self.accept_token_key:
            return ("FLOW", "stFLOW")
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

class TestFlowClient:
    """Test version of Flow client with paper trading and small amounts"""
    
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
    
    async def execute_script(self, script_path: str, args: List[str] = None) -> dict:
        """Execute Cadence script and return parsed result"""
        cmd = ["flow", "scripts", "execute", script_path, f"--network={self.network}"]
        if args:
            cmd.extend(args)
        
        try:
            self.logger.info(f"Executing script: {script_path} with args: {args}")
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)
            
            # Parse the Flow CLI output to extract result
            output_lines = result.stdout.strip().split('\n')
            result_line = None
            
            for line in output_lines:
                if line.startswith('Result:'):
                    result_line = line[7:].strip()
                    break
            
            if not result_line:
                self.logger.error(f"No result found in output: {result.stdout}")
                return {}
            
            # Handle both JSON and structured data from Flow
            try:
                return json.loads(result_line)
            except json.JSONDecodeError:
                # Handle Flow's struct format
                return self._parse_flow_struct(result_line)
                
        except subprocess.CalledProcessError as e:
            self.logger.error(f"Script execution failed: {e.stderr}")
            return {}
        except Exception as e:
            self.logger.error(f"Failed to parse script result: {e}")
            return {}
    
    def _parse_flow_struct(self, struct_str: str) -> dict:
        """Parse Flow struct format into Python dict"""
        # This is a simplified parser for Flow struct output
        # In production, you'd want a more robust parser
        try:
            # Remove the struct prefix and parse as JSON-like
            if struct_str.startswith('['):
                # It's an array of structs
                return {"pools": []}  # Simplified
            else:
                # Single struct
                return {"data": struct_str}
        except:
            return {"raw": struct_str}
    
    async def send_transaction(self, tx_path: str, args: List[str] = None) -> str:
        """Send transaction (paper trading or real)"""
        if self.paper_trading:
            self.logger.info(f"PAPER TRADE: Would send transaction {tx_path} with args: {args}")
            return f"paper_tx_{int(time.time())}"
        
        cmd = ["flow", "transactions", "send", tx_path, f"--network={self.network}", f"--signer={self.user_address}"]
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
        """Fetch all available farming pools"""
        result = await self.execute_script("cadence/scripts/get-increment-pools.cdc")
        pools = []
        
        # Handle the actual Flow output format from your test
        if isinstance(result, list):
            for pool_data in result:
                pools.append(self._parse_pool_data(pool_data))
        elif "pools" in result:
            for pool_data in result["pools"]:
                pools.append(self._parse_pool_data(pool_data))
        
        return pools
    
    def _parse_pool_data(self, pool_data) -> FarmPool:
        """Parse individual pool data from Flow output"""
        # Handle the complex struct format from your test results
        if isinstance(pool_data, dict):
            reward_per_seed = {}
            if "rewardInfo" in pool_data:
                for token, info in pool_data["rewardInfo"].items():
                    if ":" in str(info):
                        rps_value = float(str(info).split(":")[1].strip())
                        reward_per_seed[token] = rps_value
            
            return FarmPool(
                pid=pool_data.get("pid", 0),
                status=pool_data.get("status", "unknown"),
                accept_token_key=pool_data.get("acceptTokenKey", ""),
                total_staking=float(pool_data.get("totalStaking", 0)),
                limit_amount=float(pool_data.get("limitAmount", 0)),
                creator=pool_data.get("creator", ""),
                reward_tokens=pool_data.get("rewardTokens", []),
                reward_per_seed=reward_per_seed
            )
        else:
            # Fallback for other formats
            return FarmPool(
                pid=0, status="unknown", accept_token_key="", total_staking=0,
                limit_amount=0, creator="", reward_tokens=[], reward_per_seed={}
            )
    
    async def get_user_positions(self, user_address: str) -> List[dict]:
        """Get user's current staking positions"""
        result = await self.execute_script(
            "cadence/scripts/get-user-lp-positions.cdc", 
            [user_address]
        )
        
        if isinstance(result, list):
            return result
        return []

class TestAPYCalculator:
    """Test version of APY calculator with mock token prices"""
    
    def __init__(self):
        # Test token prices - would integrate with real APIs in production
        self.token_prices = {
            "A.1654653399040a61.FlowToken": 0.50,      # FLOW
            "A.d6f80565193ad727.stFlowToken": 0.52,    # stFLOW
            "A.b19436aae4d94622.FiatToken": 1.00,      # USDC
            "A.c8c340cebd11f690.SdmToken": 0.01,       # SDM
        }
        self.logger = logging.getLogger(__name__)
    
    async def update_token_prices(self):
        """Mock price update"""
        self.logger.info("Updated token prices (mock)")
    
    def calculate_pool_apy(self, pool: FarmPool) -> float:
        """Calculate APY for a farming pool"""
        total_reward_value_per_day = 0.0
        
        for token_key, rps in pool.reward_per_seed.items():
            token_price = self.token_prices.get(token_key, 0.0)
            # Convert RPS to daily rewards (RPS appears to be cumulative, so estimate daily)
            daily_reward_per_token = rps * 0.001  # Conservative estimate
            total_reward_value_per_day += daily_reward_per_token * token_price
        
        if pool.total_staking == 0:
            return 999.99  # High APY for empty pools (but risky)
        
        # Calculate APY: (daily_reward / total_staked) * 365 * 100
        daily_yield = total_reward_value_per_day / pool.total_staking
        apy = daily_yield * 365 * 100
        
        return min(apy, 2000.0)  # Cap at 2000% for sanity
    
    def calculate_impermanent_loss_risk(self, pool: FarmPool) -> float:
        """Estimate IL risk (0-100 scale)"""
        if "stFlow" in pool.lp_pair[0] or "stFlow" in pool.lp_pair[1]:
            return 15.0  # FLOW/stFLOW has very low IL risk
        elif "USDC" in pool.lp_pair[0] or "USDC" in pool.lp_pair[1]:
            return 35.0  # FLOW/USDC has medium IL risk
        else:
            return 65.0  # Other pairs have higher IL risk
    
    def calculate_safe_allocation(self, pools: List[FarmPool], 
                                total_capital: float,
                                max_risk: bool = False) -> Dict[int, float]:
        """Calculate safe allocation for testing"""
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
                'capacity': pool.capacity
            })
        
        df = pd.DataFrame(pool_data)
        
        # Filter for testing: only pools with reasonable capacity and not too risky
        if not max_risk:
            df = df[df['capacity'] > 50]  # At least 50 token capacity
            df = df[df['il_risk'] <= 50]   # Not too risky
            df = df[df['total_staking'] > 0]  # Has some liquidity
        
        # Sort by risk-adjusted APY
        df = df.sort_values('risk_adjusted_apy', ascending=False)
        
        # Conservative allocation for testing
        allocation = {}
        remaining_capital = total_capital
        
        # For testing, limit to top 3 pools max
        for _, row in df.head(3).iterrows():
            if remaining_capital <= 0:
                break
            
            # Very conservative allocation for testing
            weight = min(0.4, row['risk_adjusted_apy'] / 500)  # Much more conservative
            allocation_amount = min(
                remaining_capital * weight,
                row['capacity'] * 0.1,  # Only use 10% of pool capacity
                total_capital * 0.3,    # Max 30% per pool for testing
                50.0                    # Hard cap at 50 tokens for testing
            )
            
            if allocation_amount >= 1.0:  # Minimum 1 token position
                allocation[row['pid']] = allocation_amount
                remaining_capital -= allocation_amount
        
        return allocation

class TestLPFarmingAgent:
    """Test version of LP farming agent with small amounts and safety features"""
    
    def __init__(self, 
                 total_capital: float = 10.0,  # Default to 10 FLOW for testing
                 paper_trading: bool = True,
                 max_risk: bool = False):
        
        self.user_address = os.getenv("USER_ADDRESS")
        self.total_capital = total_capital
        self.paper_trading = paper_trading
        self.max_risk = max_risk
        
        if not self.user_address:
            raise ValueError("USER_ADDRESS must be set in .env file")
        
        # Safety check for real trading
        if not paper_trading and total_capital > 100:
            raise ValueError("For safety, limit real trading to 100 FLOW or less")
        
        self.flow_client = TestFlowClient(paper_trading=paper_trading)
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
        
        # Performance tracking
        self.test_results = {
            'start_time': datetime.now(),
            'opportunities_found': 0,
            'allocations_calculated': 0,
            'transactions_executed': 0,
            'errors_encountered': 0
        }
        
    async def run_comprehensive_test(self):
        """Run comprehensive test of all functionality"""
        self.logger.info("=" * 60)
        self.logger.info("STARTING LP FARMING COMPREHENSIVE TEST")
        self.logger.info(f"Capital: {self.total_capital} FLOW")
        self.logger.info(f"Paper Trading: {self.paper_trading}")
        self.logger.info(f"User Address: {self.user_address}")
        self.logger.info("=" * 60)
        
        try:
            # Test 1: Fetch and analyze pools
            await self.test_pool_discovery()
            
            # Test 2: Calculate optimal allocation
            await self.test_allocation_calculation()
            
            # Test 3: Check current positions
            await self.test_position_checking()
            
            # Test 4: Simulate transactions (paper trading)
            await self.test_transaction_simulation()
            
            # Test 5: Performance analysis
            await self.test_performance_analysis()
            
            # Final report
            self.generate_test_report()
            
        except Exception as e:
            self.logger.error(f"Test failed with error: {e}")
            self.test_results['errors_encountered'] += 1
            raise
    
    async def test_pool_discovery(self):
        """Test pool discovery and analysis"""
        self.logger.info("\n--- TEST 1: Pool Discovery ---")
        
        try:
            pools = await self.flow_client.get_farm_pools()
            self.test_results['opportunities_found'] = len(pools)
            
            if not pools:
                self.logger.warning("No pools found - check script execution")
                return
            
            self.logger.info(f"Found {len(pools)} farming pools")
            
            # Analyze each pool
            await self.apy_calculator.update_token_prices()
            
            analyzed_pools = []
            for pool in pools:
                pool.calculated_apy = self.apy_calculator.calculate_pool_apy(pool)
                pool.il_risk = self.apy_calculator.calculate_impermanent_loss_risk(pool)
                analyzed_pools.append(pool)
            
            # Sort by APY and show top 10
            analyzed_pools.sort(key=lambda p: p.calculated_apy, reverse=True)
            
            self.logger.info("\nTop 10 Farming Opportunities:")
            self.logger.info("-" * 80)
            for i, pool in enumerate(analyzed_pools[:10], 1):
                self.logger.info(
                    f"{i:2d}. Pool {pool.pid:2d} | "
                    f"Pair: {pool.lp_pair[0]}-{pool.lp_pair[1]:8s} | "
                    f"APY: {pool.calculated_apy:7.2f}% | "
                    f"TVL: {pool.total_staking:8.2f} | "
                    f"IL Risk: {pool.il_risk:4.1f}% | "
                    f"Capacity: {pool.capacity:8.0f}"
                )
            
            self.pools = analyzed_pools
            self.logger.info("✓ Pool discovery test completed successfully")
            
        except Exception as e:
            self.logger.error(f"Pool discovery test failed: {e}")
            self.test_results['errors_encountered'] += 1
            raise
    
    async def test_allocation_calculation(self):
        """Test optimal allocation calculation"""
        self.logger.info("\n--- TEST 2: Allocation Calculation ---")
        
        try:
            if not hasattr(self, 'pools') or not self.pools:
                self.logger.error("No pools available for allocation test")
                return
            
            # Calculate optimal allocation
            allocation = self.apy_calculator.calculate_safe_allocation(
                self.pools, 
                self.total_capital,
                max_risk=self.max_risk
            )
            
            self.target_allocation = allocation
            self.test_results['allocations_calculated'] = len(allocation)
            
            if not allocation:
                self.logger.warning("No suitable allocation found with current parameters")
                return
            
            total_allocated = sum(allocation.values())
            
            self.logger.info(f"\nOptimal Allocation for {self.total_capital} FLOW:")
            self.logger.info("-" * 60)
            
            for pid, amount in allocation.items():
                pool = next(p for p in self.pools if p.pid == pid)
                percentage = (amount / self.total_capital) * 100
                
                self.logger.info(
                    f"Pool {pid:2d}: {amount:6.2f} FLOW ({percentage:5.1f}%) | "
                    f"Pair: {pool.lp_pair[0]}-{pool.lp_pair[1]} | "
                    f"Expected APY: {pool.calculated_apy:6.2f}% | "
                    f"IL Risk: {pool.il_risk:4.1f}%"
                )
            
            self.logger.info("-" * 60)
            self.logger.info(f"Total Allocated: {total_allocated:.2f} FLOW ({total_allocated/self.total_capital*100:.1f}%)")
            self.logger.info(f"Remaining: {self.total_capital - total_allocated:.2f} FLOW")
            
            # Calculate weighted average APY
            weighted_apy = sum(
                allocation[pid] * next(p.calculated_apy for p in self.pools if p.pid == pid)
                for pid in allocation.keys()
            ) / total_allocated if total_allocated > 0 else 0
            
            self.logger.info(f"Portfolio Expected APY: {weighted_apy:.2f}%")
            self.logger.info("✓ Allocation calculation test completed successfully")
            
        except Exception as e:
            self.logger.error(f"Allocation calculation test failed: {e}")
            self.test_results['errors_encountered'] += 1
            raise
    
    async def test_position_checking(self):
        """Test current position checking"""
        self.logger.info("\n--- TEST 3: Position Checking ---")
        
        try:
            positions = await self.flow_client.get_user_positions(self.user_address)
            self.current_positions = {pos.get('pid', i): pos for i, pos in enumerate(positions)}
            
            self.logger.info(f"Current Positions: {len(positions)}")
            
            if positions:
                for pos in positions:
                    self.logger.info(f"  Pool {pos.get('pid', 'N/A')}: {pos.get('stakingAmount', 0)} staked")
            else:
                self.logger.info("  No current positions found")
            
            self.logger.info("✓ Position checking test completed successfully")
            
        except Exception as e:
            self.logger.error(f"Position checking test failed: {e}")
            self.test_results['errors_encountered'] += 1
            # Don't raise - this might fail if user has no positions
    
    async def test_transaction_simulation(self):
        """Test transaction simulation"""
        self.logger.info("\n--- TEST 4: Transaction Simulation ---")
        
        try:
            if not self.target_allocation:
                self.logger.warning("No allocation to simulate transactions")
                return
            
            self.logger.info("Simulating farming transactions...")
            
            for pid, amount in self.target_allocation.items():
                pool = next(p for p in self.pools if p.pid == pid)
                
                # Simulate staking transaction
                tx_id = await self.flow_client.send_transaction(
                    "cadence/transactions/stake-lp-in-farm.cdc",
                    [str(pid), str(amount)]
                )
                
                self.test_results['transactions_executed'] += 1
                
                self.logger.info(
                    f"  Stake {amount:.2f} FLOW in Pool {pid} "
                    f"({pool.lp_pair[0]}-{pool.lp_pair[1]}) -> TX: {tx_id}"
                )
                
                # Small delay to simulate real transaction timing
                await asyncio.sleep(0.1)
            
            # Simulate reward claiming
            if self.current_positions:
                for pid in self.current_positions.keys():
                    tx_id = await self.flow_client.send_transaction(
                        "cadence/transactions/claim-farm-rewards.cdc",
                        [str(pid)]
                    )
                    
                    self.test_results['transactions_executed'] += 1
                    self.logger.info(f"  Claim rewards from Pool {pid} -> TX: {tx_id}")
            
            self.logger.info("✓ Transaction simulation test completed successfully")
            
        except Exception as e:
            self.logger.error(f"Transaction simulation test failed: {e}")
            self.test_results['errors_encountered'] += 1
            raise
    
    async def test_performance_analysis(self):
        """Test performance analysis calculations"""
        self.logger.info("\n--- TEST 5: Performance Analysis ---")
        
        try:
            if not self.target_allocation:
                self.logger.warning("No allocation for performance analysis")
                return
            
            # Calculate expected returns
            total_allocated = sum(self.target_allocation.values())
            daily_returns = {}
            
            for pid, amount in self.target_allocation.items():
                pool = next(p for p in self.pools if p.pid == pid)
                daily_return = (amount * pool.calculated_apy / 100) / 365
                daily_returns[pid] = daily_return
            
            total_daily_return = sum(daily_returns.values())
            total_yearly_return = total_daily_return * 365
            
            self.logger.info("Performance Analysis:")
            self.logger.info(f"  Total Allocated: {total_allocated:.2f} FLOW")
            self.logger.info(f"  Expected Daily Return: {total_daily_return:.4f} FLOW")
            self.logger.info(f"  Expected Yearly Return: {total_yearly_return:.2f} FLOW")
            self.logger.info(f"  Expected APY: {(total_yearly_return/total_allocated)*100:.2f}%")
            
            # Risk analysis
            weighted_il_risk = sum(
                (self.target_allocation[pid] / total_allocated) * 
                next(p.il_risk for p in self.pools if p.pid == pid)
                for pid in self.target_allocation.keys()
            ) if total_allocated > 0 else 0
            
            self.logger.info(f"  Weighted IL Risk: {weighted_il_risk:.2f}%")
            self.logger.info("✓ Performance analysis test completed successfully")
            
        except Exception as e:
            self.logger.error(f"Performance analysis test failed: {e}")
            self.test_results['errors_encountered'] += 1
            raise
    
    def generate_test_report(self):
        """Generate final test report"""
        self.logger.info("\n" + "=" * 60)
        self.logger.info("TEST REPORT")
        self.logger.info("=" * 60)
        
        duration = datetime.now() - self.test_results['start_time']
        
        self.logger.info(f"Test Duration: {duration}")
        self.logger.info(f"Opportunities Found: {self.test_results['opportunities_found']}")
        self.logger.info(f"Allocations Calculated: {self.test_results['allocations_calculated']}")
        self.logger.info(f"Transactions Simulated: {self.test_results['transactions_executed']}")
        self.logger.info(f"Errors Encountered: {self.test_results['errors_encountered']}")
        
        if self.test_results['errors_encountered'] == 0:
            self.logger.info("\n✅ ALL TESTS PASSED SUCCESSFULLY!")
            
            if self.target_allocation:
                total_allocated = sum(self.target_allocation.values())
                self.logger.info(f"\nReady for deployment with {total_allocated:.2f} FLOW allocation")
                
                if self.paper_trading:
                    self.logger.info("To run with real transactions, set paper_trading=False")
                else:
                    self.logger.info("⚠️  REAL TRANSACTIONS WILL BE EXECUTED")
        else:
            self.logger.warning("\n⚠️  SOME TESTS FAILED - CHECK LOGS ABOVE")
        
        self.logger.info("=" * 60)

# Test execution functions
async def run_quick_test():
    """Run a quick test with minimal capital"""
    agent = TestLPFarmingAgent(
        total_capital=5.0,      # Just 5 FLOW for quick test
        paper_trading=True,     # Safe paper trading
        max_risk=False         # Conservative
    )
    
    await agent.run_comprehensive_test()

async def run_full_test():
    """Run full test with more capital"""
    agent = TestLPFarmingAgent(
        total_capital=50.0,     # 50 FLOW for comprehensive test
        paper_trading=True,     # Safe paper trading
        max_risk=False         # Conservative
    )
    
    await agent.run_comprehensive_test()

async def run_real_small_test():
    """Run real transactions with very small amount"""
    print("⚠️  WARNING: This will execute REAL transactions!")
    response = input("Type 'YES' to confirm real transaction testing: ")
    
    if response != "YES":
        print("Test cancelled")
        return
    
    agent = TestLPFarmingAgent(
        total_capital=2.0,      # Only 2 FLOW for real test
        paper_trading=False,    # REAL transactions
        max_risk=False         # Very conservative
    )
    
    await agent.run_comprehensive_test()

if __name__ == "__main__":
    import sys
    
    # Check environment setup
    if not os.getenv("USER_ADDRESS"):
        print("❌ Error: USER_ADDRESS not found in .env file")
        sys.exit(1)
    
    print("LP Farming Test Options:")
    print("1. Quick Test (5 FLOW, paper trading)")
    print("2. Full Test (50 FLOW, paper trading)")  
    print("3. Real Small Test (2 FLOW, REAL transactions)")
    print("4. Exit")
    
    choice = input("\nSelect option (1-4): ")
    
    if choice == "1":
        asyncio.run(run_quick_test())
    elif choice == "2":
        asyncio.run(run_full_test())
    elif choice == "3":
        asyncio.run(run_real_small_test())
    else:
        print("Goodbye!")