import asyncio
import json
import subprocess
import os
import re
from dataclasses import dataclass
import logging
from dotenv import load_dotenv
from typing import Dict, List, Optional

# --- Basic Setup ---
load_dotenv()
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# --- Enhanced Data Structures ---
@dataclass
class EnhancedPoolInfo:
    pid: int
    pair: str
    accept_token_key: str
    total_staking: float
    limit_amount: float
    capacity: float
    utilization: float
    status: str
    reward_tokens: List[str]
    reward_rates: Dict[str, float]
    estimated_apy: float
    daily_rewards: float
    is_open_for_staking: bool
    pool_type: str  # 'LP' or 'STAKING'

@dataclass
class UserPosition:
    pid: int
    pair: str
    lp_amount: float
    accept_token_key: str
    claimable_rewards: Dict[str, float]

# --- Core Logic ---
class EnhancedFlowAgent:
    def __init__(self):
        self.network = "mainnet"
        self.signer = "mainnet-deployer"
        self.user_address = os.getenv("USER_ADDRESS")
        if not self.user_address:
            raise ValueError("USER_ADDRESS not found in .env file")
        
        # Token price mapping (would ideally fetch from oracle)
        self.token_prices = {
            "FlowToken": 0.94,  # Approximate FLOW price
            "stFlowToken": 1.0,  # Approximate stFlow price
            "LOPPY": 2.3,  # Approximate LOPPY price
            "MVP": 0.336,  # Approximate MVP price
        }

    def _parse_cli_output(self, output: str) -> list[dict]:
        """Enhanced parser for Flow CLI output with better error handling."""
        structs = []
        try:
            # Handle both array and single struct responses
            outer_pattern = re.compile(r'\w+\(([^)]*(?:\([^)]*\)[^)]*)*)\)')
            inner_pattern = re.compile(r'(\w+):\s*(".*?"|[\d.]+|(?:\{[^}]*\}|\[[^\]]*\]))')
            
            result_line = ""
            for line in output.strip().splitlines():
                if line.strip() and not line.startswith("Status"):
                    result_line = line
            
            if result_line.startswith("Result:"):
                result_line = result_line[len("Result:"):].strip()
            
            # Handle array responses
            if result_line.startswith("[") and result_line.endswith("]"):
                result_line = result_line[1:-1]  # Remove outer brackets
            
            for match in outer_pattern.finditer(result_line):
                struct_content = match.group(1)
                data = {}
                
                for field_match in inner_pattern.finditer(struct_content):
                    key, value = field_match.groups()
                    
                    if value.startswith('"') and value.endswith('"'):
                        data[key] = value[1:-1]
                    elif value.startswith('{') or value.startswith('['):
                        # Handle nested structures (rewards, etc.)
                        data[key] = value
                    else:
                        try:
                            data[key] = float(value)
                        except ValueError:
                            data[key] = value
                
                if data:
                    structs.append(data)
                    
        except Exception as e:
            logging.warning(f"Parser warning: {e}")
            
        return structs

    def _identify_pool_type(self, accept_token_key: str) -> tuple[str, str]:
        """Enhanced pool type identification."""
        pool_mappings = {
            # Original LP Pools 
            "A.396c0cda3302d8c5.SwapPair": ("FLOW-stFlow", "LP"),
            "A.fa82796435e15832.SwapPair": ("FLOW-USDC", "LP"),
            "A.6155398610a02093.SwapPair": ("SDM-FLOW", "LP"),
            # New active LP pools from Increment Fi
            "A.c353b9d685ec427d.SwapPair": ("FLOW-stFlow", "LP"),  # Pool #204
            "A.14bc0af67ad1c5ff.SwapPair": ("stFlow-LOPPY", "LP"),  # Pool #205
            "A.1c502071c9ab3d84.SwapPair": ("stFlow-MVP", "LP"),    # Pool #206
        }
        
        for address, (pair_name, pool_type) in pool_mappings.items():
            if address in accept_token_key:
                return pair_name, pool_type
        
        # Check for LP tokens by SwapPair pattern
        if "SwapPair" in accept_token_key:
            # Try to identify the pair from context
            if "d6f80565193ad727" in accept_token_key:  # stFlow contract
                if "LOPPY" in accept_token_key.upper():
                    return "stFlow-LOPPY", "LP"
                elif "MVP" in accept_token_key.upper():
                    return "stFlow-MVP", "LP"
                else:
                    return "stFlow-UNKNOWN", "LP"
            return "UNKNOWN-LP", "LP"
        
        # Check for single token staking pools
        if "stFlowToken" in accept_token_key or "d6f80565193ad727" in accept_token_key:
            return "stFlow-SINGLE", "STAKING"
        elif "FlowToken" in accept_token_key or "1654653399040a61" in accept_token_key:
            return "FLOW-SINGLE", "STAKING"
        elif "LOPPY" in accept_token_key.upper():
            return "LOPPY-SINGLE", "STAKING"
        elif "MVP" in accept_token_key.upper():
            return "MVP-SINGLE", "STAKING"
        
        return "UNKNOWN", "STAKING"

    def _calculate_apy(self, reward_rates: Dict[str, float], total_staking: float) -> float:
        """Calculate estimated APY based on reward rates and token prices."""
        if total_staking == 0:
            return 0.0
        
        annual_rewards_value = 0.0
        
        for token_key, rate_per_second in reward_rates.items():
            # Extract token name
            token_name = "FlowToken"
            for token in self.token_prices.keys():
                if token in token_key:
                    token_name = token
                    break
            
            # Calculate annual rewards in USD
            annual_rate = rate_per_second * 365 * 24 * 60 * 60
            token_price = self.token_prices.get(token_name, 1.0)
            annual_rewards_value += annual_rate * token_price
        
        # Estimate TVL in USD (assuming average token price of $1)
        tvl_usd = total_staking * 1.0  # Simplified
        
        if tvl_usd > 0:
            return (annual_rewards_value / tvl_usd) * 100
        return 0.0

    async def _run_command(self, cmd: list) -> str:
        """Execute command with better error handling."""
        try:
            process = await asyncio.create_subprocess_exec(
                *cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE
            )
            stdout, stderr = await process.communicate()
            
            if process.returncode != 0:
                error_msg = stderr.decode().strip()
                if "not open staking yet" in error_msg:
                    raise Exception("Pool is not open for staking yet")
                elif "pre-condition failed" in error_msg:
                    raise Exception("Transaction pre-condition failed - check pool status")
                else:
                    raise Exception(f"Command failed: {error_msg}")
                    
            return stdout.decode()
        except Exception as e:
            raise Exception(f"Command execution failed: {str(e)}")

    async def setup_staking_account(self):
        """Runs the one-time setup transaction for the staking contract."""
        logging.info("Running one-time setup for Staking contract...")
        cmd = [
            "flow", "transactions", "send",
            f"--network={self.network}",
            f"--signer={self.signer}",
            "cadence/transactions/setup_staking.cdc"
        ]
        output = await self._run_command(cmd)
        logging.info(f"Setup transaction submitted!\n{output}")

    async def debug_pools(self) -> List[dict]:
        """Get raw pool data for debugging."""
        logging.info("Fetching debug pool information...")
        
        cmd = [
            "flow", "scripts", "execute", 
            "cadence/scripts/debug_pools.cdc",
            f"--network={self.network}"
        ]
        
        output = await self._run_command(cmd)
        return self._parse_cli_output(output)

    async def get_enhanced_pools(self) -> List[EnhancedPoolInfo]:
        """Get comprehensive pool information including APYs and staking status."""
        logging.info("Fetching enhanced pool information...")
        
        # Use the safer specific pools scanner
        cmd = [
            "flow", "scripts", "execute", 
            "cadence/scripts/get_specific_pools.cdc",
            f"--network={self.network}"
        ]
        
        output = await self._run_command(cmd)
        pools_data = self._parse_cli_output(output)
        
        # Known active pools from Increment Fi website (trust the website)
        website_active_pools = {204, 205, 206, 20, 14}
        
        enhanced_pools = []
        
        for pool_data in pools_data:
            pid = int(pool_data.get('pid', 0))
            pair, pool_type = self._identify_pool_type(pool_data.get('acceptTokenKey', ''))
            
            # Parse reward information  
            reward_tokens = pool_data.get('rewardTokens', [])
            reward_rates = {}  # Simplified since reward rate parsing is complex
            
            # Calculate metrics
            total_staking = float(pool_data.get('totalStaking', 0))
            limit_amount = float(pool_data.get('limitAmount', 0))
            capacity = float(pool_data.get('capacity', 0))
            utilization = (total_staking / limit_amount * 100) if limit_amount > 0 else 0.0
            
            # Basic APY calculation
            estimated_apy = 0.0  # Simplified since we don't have accurate reward rates
            daily_rewards = 0.0
            has_rewards = pool_data.get('hasRewards', False)
            
            # Trust the website - mark pools as stakeable if:
            # 1. They're in the website's active list, OR
            # 2. They have status "2" (running) and capacity
            pool_status = pool_data.get('status', '0')
            is_website_active = pid in website_active_pools
            is_contract_running = pool_status == "2"
            has_capacity = capacity > 1.0
            
            is_open = is_website_active or (is_contract_running and has_capacity)
            
            enhanced_pool = EnhancedPoolInfo(
                pid=pid,
                pair=pair,
                accept_token_key=pool_data.get('acceptTokenKey', ''),
                total_staking=total_staking,
                limit_amount=limit_amount,
                capacity=capacity,
                utilization=utilization,
                status=pool_status,
                reward_tokens=reward_tokens,
                reward_rates=reward_rates,
                estimated_apy=estimated_apy,
                daily_rewards=daily_rewards,
                is_open_for_staking=is_open,
                pool_type=pool_type
            )
            
            enhanced_pools.append(enhanced_pool)
        
        # Sort by TVL descending
        enhanced_pools.sort(key=lambda p: p.total_staking, reverse=True)
        return enhanced_pools

    async def get_positions(self) -> List[UserPosition]:
        """Get user positions with claimable rewards."""
        logging.info(f"Fetching enhanced positions for {self.user_address}...")
        
        cmd = [
            "flow", "scripts", "execute", 
            "cadence/scripts/get_user_positions.cdc",
            self.user_address,
            f"--network={self.network}"
        ]
        
        output = await self._run_command(cmd)
        positions_data = self._parse_cli_output(output)
        
        positions = []
        for pos in positions_data:
            pair, _ = self._identify_pool_type(pos.get('acceptTokenKey', ''))
            
            position = UserPosition(
                pid=int(pos.get('pid', 0)),
                pair=pair,
                lp_amount=float(pos.get('stakingAmount', 0)),
                accept_token_key=pos.get('acceptTokenKey', ''),
                claimable_rewards={}  # Would need additional script to get this
            )
            positions.append(position)
            
        return positions

    async def stake_into_pool(self, pool_id: int, amount: float, pool_info: EnhancedPoolInfo):
        """Smart staking that chooses the right transaction based on pool type.""" 
        if not pool_info.is_open_for_staking:
            raise Exception(f"Pool {pool_id} is not open for staking")
        
        logging.info(f"Staking {amount} into {pool_info.pair} pool {pool_id}...")
        
        # Use the dynamic transaction for FLOW-based LP pools  
        if pool_info.pair == "FLOW-stFlow" and pool_info.pool_type == "LP":
            cmd = [
                "flow", "transactions", "send",
                f"--network={self.network}",
                f"--signer={self.signer}",
                "cadence/transactions/stake_pool_dynamic.cdc",
                str(pool_id),
                f"{amount:.8f}"
            ]
        else:
            # For other pools, user needs to have the tokens already
            logging.warning(f"Pool {pool_id} ({pool_info.pair}) requires you to already have the LP tokens")
            raise Exception(f"Staking into {pool_info.pair} pools is not yet supported - you need to create the LP tokens first")
        
        output = await self._run_command(cmd)
        logging.info(f"Staking transaction submitted!\n{output}")

    async def claim(self, pool_id: int):
        logging.info(f"Claiming rewards from pool {pool_id}...")
        cmd = [
            "flow", "transactions", "send",
            f"--network={self.network}",
            f"--signer={self.signer}",
            "cadence/transactions/claim_rewards.cdc",
            str(pool_id)
        ]
        output = await self._run_command(cmd)
        logging.info(f"Transaction submitted!\n{output}")

    async def find_optimal_pools(self, min_apy: float = 10.0, min_capacity: float = 100.0) -> List[EnhancedPoolInfo]:
        """Find optimal pools for yield farming based on APY and capacity."""
        all_pools = await self.get_enhanced_pools()
        
        optimal_pools = [
            pool for pool in all_pools 
            if pool.estimated_apy >= min_apy 
            and pool.capacity >= min_capacity 
            and pool.is_open_for_staking
        ]
        
        return optimal_pools

# --- Enhanced Interactive Menu ---
async def main():
    agent = EnhancedFlowAgent()
    
    while True:
        print("\n🚀 Enhanced Flow LP Farming Bot")
        print("0. (ONE-TIME) Setup Staking Account")
        print("1. View All Farming Pools (Enhanced)")
        print("2. View Optimal Yield Opportunities") 
        print("3. View My Positions")
        print("4. Smart Stake into Best Pool")
        print("5. Stake into Specific Pool")
        print("6. Claim All Rewards")
        print("7. Unstake & Withdraw")
        print("8. Debug Pools (Raw Data)")
        print("9. Check Known Active Pools")
        print("10. Check Pool Range 200-210")
        print("11. Exit")
        choice = input(">> ")

        try:
            if choice == "0":
                await agent.setup_staking_account()
            
            elif choice == "1":
                pools = await agent.get_enhanced_pools()
                print("\n--- All Available Pools (Sorted by Daily Rewards) ---")
                print(f"{'Pool ID':<8} {'Pair':<20} {'Type':<8} {'TVL':<15} {'Daily Rewards':<12} {'Status':<10} {'Open'}")
                print("-" * 85)
                
                for pool in pools[:20]:  # Show top 20
                    status_icon = "🟢" if pool.is_open_for_staking else "🔴"
                    print(f"{pool.pid:<8} {pool.pair:<20} {pool.pool_type:<8} {pool.total_staking:<15,.2f} {pool.daily_rewards:<12.6f} {pool.status:<10} {status_icon}")

            elif choice == "2":
                optimal_pools = await agent.find_optimal_pools(min_apy=0.0, min_capacity=0.0)
                print("\n--- Optimal Yield Opportunities ---")
                
                if not optimal_pools:
                    print("No optimal pools found with current criteria.")
                else:
                    print(f"{'Pool ID':<8} {'Pair':<20} {'Daily Rewards':<12} {'Capacity':<15} {'Utilization'}")
                    print("-" * 75)
                    
                    for pool in optimal_pools:
                        print(f"{pool.pid:<8} {pool.pair:<20} {pool.daily_rewards:<12.6f} {pool.capacity:<15,.2f} {pool.utilization:<.1f}%")

            elif choice == "3":
                positions = await agent.get_positions()
                if not positions:
                    print("\nNo active positions found.")
                else:
                    print("\n--- Your Active Positions ---")
                    
                    for pos in positions:
                        print(f"Pool {pos.pid} ({pos.pair}): {pos.lp_amount:.6f} tokens")
                        
            elif choice == "4":
                optimal_pools = await agent.find_optimal_pools(min_apy=0.0, min_capacity=0.0)
                if not optimal_pools:
                    print("No optimal pools available for staking.")
                    continue
                    
                best_pool = optimal_pools[0]
                print(f"\nBest pool found: {best_pool.pair} (Pool {best_pool.pid}) - Daily Rewards: {best_pool.daily_rewards:.6f}")
                
                amount = float(input("Enter amount to stake: "))
                await agent.stake_into_pool(best_pool.pid, amount, best_pool)

            elif choice == "5":
                pools = await agent.get_enhanced_pools()
                stakeable_pools = [p for p in pools if p.is_open_for_staking]
                
                if not stakeable_pools:
                    print("No pools available for staking.")
                    continue
                    
                print("\n--- Available Pools for Staking ---")
                for i, pool in enumerate(stakeable_pools[:10]):
                    print(f"  {i+1}. Pool {pool.pid} ({pool.pair}) - Daily Rewards: {pool.daily_rewards:.6f}")
                
                selection = int(input("Enter selection number: ")) - 1
                if 0 <= selection < len(stakeable_pools[:10]):
                    selected_pool = stakeable_pools[selection]
                    amount = float(input("Enter amount to stake: "))
                    await agent.stake_into_pool(selected_pool.pid, amount, selected_pool)

            elif choice == "6":
                positions = await agent.get_positions()
                if not positions:
                    print("No positions to claim from.")
                    continue
                    
                for pos in positions:
                    try:
                        await agent.claim(pos.pid)
                        print(f"✅ Claimed rewards from pool {pos.pid}")
                    except Exception as e:
                        print(f"❌ Failed to claim from pool {pos.pid}: {e}")

            elif choice == "8":
                debug_data = await agent.debug_pools()
                print("\n--- Debug Pool Data ---")
                print(f"{'PID':<4} {'Status':<6} {'TVL':<12} {'Rewards':<8} {'Accept Token Key'}")
                print("-" * 80)
                
                for pool in debug_data[:20]:  # Show top 20
                    rewards_str = "YES" if pool.get('hasRewards', False) else "NO"
                    token_key_short = pool.get('acceptTokenKey', '')[:50] + "..." if len(pool.get('acceptTokenKey', '')) > 50 else pool.get('acceptTokenKey', '')
                    print(f"{pool.get('pid', 0):<4} {pool.get('status', ''):<6} {pool.get('totalStaking', 0):<12.2f} {rewards_str:<8} {token_key_short}")

            elif choice == "9":
                # Check known active pools from Increment Fi website
                cmd = [
                    "flow", "scripts", "execute", 
                    "cadence/scripts/check_known_pools.cdc",
                    f"--network={agent.network}"
                ]
                output = await agent._run_command(cmd)
                known_pools = agent._parse_cli_output(output)
                
                print("\n--- Known Active Pools Check ---")
                print(f"{'PID':<4} {'Exists':<6} {'Status':<6} {'TVL':<12} {'Rewards':<8} {'Accept Token Key'}")
                print("-" * 80)
                
                for pool in known_pools:
                    exists_str = "YES" if pool.get('exists', False) else "NO"
                    rewards_str = "YES" if pool.get('hasRewards', False) else "NO"
                    token_key_short = pool.get('acceptTokenKey', '')[:40] + "..." if len(pool.get('acceptTokenKey', '')) > 40 else pool.get('acceptTokenKey', '')
                    print(f"{pool.get('pid', 0):<4} {exists_str:<6} {pool.get('status', ''):<6} {pool.get('totalStaking', 0):<12.2f} {rewards_str:<8} {token_key_short}")

            elif choice == "10":
                # Check pool range 200-210
                cmd = [
                    "flow", "scripts", "execute", 
                    "cadence/scripts/check_pool_range.cdc",
                    f"--network={agent.network}"
                ]
                output = await agent._run_command(cmd)
                range_pools = agent._parse_cli_output(output)
                
                print("\n--- Pool Range 200-210 Check ---")
                print(f"{'PID':<4} {'Exists':<6} {'Status':<6} {'TVL':<12} {'Rewards':<8} {'Count':<5} {'Accept Token Key'}")
                print("-" * 85)
                
                for pool in range_pools:
                    exists_str = "YES" if pool.get('exists', False) else "NO"
                    rewards_str = "YES" if pool.get('hasRewards', False) else "NO"
                    token_key_short = pool.get('acceptTokenKey', '')[:30] + "..." if len(pool.get('acceptTokenKey', '')) > 30 else pool.get('acceptTokenKey', '')
                    print(f"{pool.get('pid', 0):<4} {exists_str:<6} {pool.get('status', ''):<6} {pool.get('totalStaking', 0):<12.2f} {rewards_str:<8} {pool.get('rewardCount', 0):<5} {token_key_short}")

            elif choice == "11":
                break
                
            else:
                print("Invalid choice.")
                
        except Exception as e:
            logging.error(f"Operation failed: {e}")

if __name__ == "__main__":
    asyncio.run(main())