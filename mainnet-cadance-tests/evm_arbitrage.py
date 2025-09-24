import asyncio
import json
from web3 import Web3
from decimal import Decimal
import logging
from typing import Dict, List, Tuple, Optional
import time
from dataclasses import dataclass

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

@dataclass
class ArbitrageOpportunity:
    token_a: str
    token_b: str
    dex_buy: str
    dex_sell: str
    buy_price: Decimal
    sell_price: Decimal
    profit_percentage: Decimal
    min_amount: Decimal

class FlowArbitrageScanner:
    def __init__(self, rpc_url: str, private_key: str = None):
        self.w3 = Web3(Web3.HTTPProvider(rpc_url))
        self.private_key = private_key
        
        # Contract addresses
        self.contracts = {
            'WFLOW': '0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e',
            'USDC': '0xF1815bd50389c46847f0Bda824eC8da914045D14',
            'USDT': '0x674843C06FF83502ddb4D37c2E09C01cdA38cbc8',
        }
        
        # DEX contracts
        self.dexs = {
            'StableKittyFactory': '0x4412140D52C1F5834469a061927811Abb6026dB7',
            'TwoKittyFactory': '0xf0E48dC92f66E246244dd9F33b02f57b0E69fBa9',
            'TriKittyFactory': '0xebd098c60b1089f362AC9cfAd9134CBD29408226',
            'PunchSwapRouter': '0xf45AFe28fd5519d5f8C1d4787a4D5f724C0eFa4d'
        }
        
        # ABIs (simplified for key functions)
        self.factory_abi = [
            {
                "inputs": [{"name": "_from", "type": "address"}, {"name": "_to", "type": "address"}, {"name": "i", "type": "uint256"}],
                "name": "find_pool_for_coins",
                "outputs": [{"name": "", "type": "address"}],
                "stateMutability": "view",
                "type": "function"
            },
            {
                "inputs": [{"name": "_pool", "type": "address"}],
                "name": "get_balances",
                "outputs": [{"name": "", "type": "uint256[]"}],
                "stateMutability": "view",
                "type": "function"
            }
        ]
        
        self.router_abi = [
            {
                "inputs": [{"name": "amountIn", "type": "uint256"}, {"name": "path", "type": "address[]"}],
                "name": "getAmountsOut",
                "outputs": [{"name": "amounts", "type": "uint256[]"}],
                "stateMutability": "view",
                "type": "function"
            }
        ]
        
        self.erc20_abi = [
            {
                "inputs": [],
                "name": "decimals",
                "outputs": [{"name": "", "type": "uint8"}],
                "stateMutability": "view",
                "type": "function"
            },
            {
                "inputs": [{"name": "account", "type": "address"}],
                "name": "balanceOf",
                "outputs": [{"name": "", "type": "uint256"}],
                "stateMutability": "view",
                "type": "function"
            }
        ]
        
        # Initialize contract instances
        self.init_contracts()
        
        # Token pairs to monitor
        self.pairs = [
            ('WFLOW', 'USDC'),
            ('WFLOW', 'USDT'),
            ('USDC', 'USDT'),
        ]
        
        # Minimum profit threshold (percentage)
        self.min_profit_threshold = Decimal('0.5')  # 0.5%
        
    def init_contracts(self):
        """Initialize contract instances"""
        self.contract_instances = {}
        
        # Initialize DEX factory contracts
        for name, address in self.dexs.items():
            if 'Factory' in name:
                self.contract_instances[name] = self.w3.eth.contract(
                    address=address, abi=self.factory_abi
                )
            elif 'Router' in name:
                self.contract_instances[name] = self.w3.eth.contract(
                    address=address, abi=self.router_abi
                )
        
        # Initialize token contracts
        for name, address in self.contracts.items():
            self.contract_instances[f'{name}_token'] = self.w3.eth.contract(
                address=address, abi=self.erc20_abi
            )
    
    def get_token_decimals(self, token_symbol: str) -> int:
        """Get token decimals"""
        try:
            contract = self.contract_instances[f'{token_symbol}_token']
            return contract.functions.decimals().call()
        except Exception as e:
            logger.error(f"Error getting decimals for {token_symbol}: {e}")
            return 18  # Default to 18 decimals
    
    def find_pools_for_pair(self, token_a: str, token_b: str) -> Dict[str, str]:
        """Find pools for a token pair across different DEXs"""
        pools = {}
        token_a_addr = self.contracts[token_a]
        token_b_addr = self.contracts[token_b]
        
        for dex_name, contract in self.contract_instances.items():
            if 'Factory' not in dex_name:
                continue
                
            try:
                pool_addr = contract.functions.find_pool_for_coins(
                    token_a_addr, token_b_addr, 0
                ).call()
                
                if pool_addr != '0x0000000000000000000000000000000000000000':
                    pools[dex_name] = pool_addr
                    logger.debug(f"Found pool on {dex_name}: {pool_addr}")
                    
            except Exception as e:
                logger.debug(f"No pool found on {dex_name} for {token_a}/{token_b}: {e}")
                
        return pools
    
    def check_pool_health(self, pool_address: str) -> Dict:
        """Check if a pool has sufficient liquidity and is active"""
        try:
            # Try each factory to get balances
            for dex_name, contract in self.contract_instances.items():
                if 'Factory' not in dex_name:
                    continue
                    
                try:
                    balances = contract.functions.get_balances(pool_address).call()
                    if len(balances) >= 2:
                        return {
                            'active': True,
                            'balances': balances,
                            'dex': dex_name,
                            'total_liquidity': sum(balances)
                        }
                except Exception:
                    continue
                    
            return {'active': False, 'reason': 'No balances found'}
            
        except Exception as e:
            return {'active': False, 'reason': str(e)}
    
    def get_pool_price(self, pool_address: str, token_a: str, token_b: str, amount: int = None) -> Optional[Decimal]:
        """Get price from a specific pool"""
        if amount is None:
            amount = 10 ** self.get_token_decimals(token_a)  # 1 token
            
        # First check if pool is healthy
        pool_health = self.check_pool_health(pool_address)
        if not pool_health.get('active', False):
            logger.debug(f"Pool {pool_address[:10]}... not active: {pool_health.get('reason', 'Unknown')}")
            return None
            
        try:
            balances = pool_health['balances']
            
            if len(balances) >= 2 and balances[0] > 0 and balances[1] > 0:
                # Simple price calculation for demonstration
                # For production, you'd want more sophisticated pricing based on the AMM curve
                decimals_a = self.get_token_decimals(token_a)
                decimals_b = self.get_token_decimals(token_b)
                
                # Normalize balances
                balance_a_normalized = Decimal(balances[0]) / Decimal(10 ** decimals_a)
                balance_b_normalized = Decimal(balances[1]) / Decimal(10 ** decimals_b)
                
                # Simple ratio price (for Curve-style pools)
                price = balance_b_normalized / balance_a_normalized
                
                logger.debug(f"Pool {pool_address[:10]}... price: {price:.6f}, liquidity: ${balance_a_normalized:.2f} + ${balance_b_normalized:.2f}")
                return price
                
        except Exception as e:
            logger.debug(f"Error calculating price from pool {pool_address}: {e}")
            
        return None
    
    def get_router_price(self, token_a: str, token_b: str, amount: int = None) -> Optional[Decimal]:
        """Get price from PunchSwap router"""
        if amount is None:
            amount = 10 ** self.get_token_decimals(token_a)
            
        try:
            router = self.contract_instances['PunchSwapRouter']
            path = [self.contracts[token_a], self.contracts[token_b]]
            
            # Try to get amounts out
            amounts_out = router.functions.getAmountsOut(amount, path).call()
            
            if len(amounts_out) >= 2 and amounts_out[1] > 0:
                input_amount = Decimal(amounts_out[0])
                output_amount = Decimal(amounts_out[1])
                
                # Adjust for decimals
                decimals_a = self.get_token_decimals(token_a)
                decimals_b = self.get_token_decimals(token_b)
                
                # Normalize to same decimal places
                input_normalized = input_amount / Decimal(10 ** decimals_a)
                output_normalized = output_amount / Decimal(10 ** decimals_b)
                
                if input_normalized > 0:
                    price = output_normalized / input_normalized
                    return price
                
        except Exception as e:
            logger.debug(f"No router liquidity for {token_a}/{token_b}: {str(e)[:50]}...")
            
        return None
    
    def scan_arbitrage_opportunities(self, test_amount: int = None) -> List[ArbitrageOpportunity]:
        """Scan for arbitrage opportunities across all pairs and DEXs"""
        opportunities = []
        
        for token_a, token_b in self.pairs:
            logger.info(f"Scanning {token_a}/{token_b} pair...")
            
            if test_amount is None:
                test_amount = 10 ** self.get_token_decimals(token_a)  # 1 token
            
            prices = {}
            
            # Get prices from factory pools
            pools = self.find_pools_for_pair(token_a, token_b)
            logger.info(f"  Found {len(pools)} pools: {list(pools.keys())}")
            
            for dex_name, pool_addr in pools.items():
                price = self.get_pool_price(pool_addr, token_a, token_b, test_amount)
                if price:
                    prices[dex_name] = price
                    logger.info(f"  {dex_name}: {price:.6f} {token_b} per {token_a}")
                else:
                    logger.debug(f"  {dex_name}: No price available")
            
            # Get price from router
            router_price = self.get_router_price(token_a, token_b, test_amount)
            if router_price:
                prices['PunchSwapRouter'] = router_price
                logger.info(f"  PunchSwapRouter: {router_price:.6f} {token_b} per {token_a}")
            else:
                logger.info(f"  PunchSwapRouter: No liquidity available")
            
            # Also try reverse direction for router
            router_price_reverse = self.get_router_price(token_b, token_a, test_amount)
            if router_price_reverse and router_price_reverse > 0:
                # Convert reverse price to forward price
                forward_price = Decimal(1) / router_price_reverse
                if 'PunchSwapRouter' not in prices:  # Only use if we don't have direct price
                    prices['PunchSwapRouter_Reverse'] = forward_price
                    logger.info(f"  PunchSwapRouter (reverse): {forward_price:.6f} {token_b} per {token_a}")
            
            logger.info(f"  Total price sources: {len(prices)}")
            
            # Find arbitrage opportunities
            if len(prices) >= 2:
                price_items = list(prices.items())
                
                for i in range(len(price_items)):
                    for j in range(i + 1, len(price_items)):
                        dex1_name, price1 = price_items[i]
                        dex2_name, price2 = price_items[j]
                        
                        # Skip if prices are too close (might be same underlying pool)
                        price_diff = abs(price1 - price2) / min(price1, price2) * 100
                        if price_diff < 0.1:  # Less than 0.1% difference
                            continue
                        
                        if price1 > price2:
                            # Buy on dex2, sell on dex1
                            profit_pct = ((price1 - price2) / price2) * 100
                            buy_dex, sell_dex = dex2_name, dex1_name
                            buy_price, sell_price = price2, price1
                        else:
                            # Buy on dex1, sell on dex2
                            profit_pct = ((price2 - price1) / price1) * 100
                            buy_dex, sell_dex = dex1_name, dex2_name
                            buy_price, sell_price = price1, price2
                        
                        if profit_pct >= self.min_profit_threshold:
                            opportunity = ArbitrageOpportunity(
                                token_a=token_a,
                                token_b=token_b,
                                dex_buy=buy_dex,
                                dex_sell=sell_dex,
                                buy_price=buy_price,
                                sell_price=sell_price,
                                profit_percentage=profit_pct,
                                min_amount=Decimal(test_amount) / Decimal(10 ** self.get_token_decimals(token_a))
                            )
                            opportunities.append(opportunity)
                            
                            logger.info(f"🔥 ARBITRAGE OPPORTUNITY FOUND!")
                            logger.info(f"   Pair: {token_a}/{token_b}")
                            logger.info(f"   Buy on {buy_dex} at {buy_price:.6f}")
                            logger.info(f"   Sell on {sell_dex} at {sell_price:.6f}")
                            logger.info(f"   Profit: {profit_pct:.2f}%")
                            logger.info(f"   Min amount: {opportunity.min_amount:.2f} {token_a}")
                        else:
                            logger.debug(f"  Price difference too small: {profit_pct:.3f}%")
            else:
                logger.info(f"  Not enough price sources ({len(prices)}) for arbitrage")
        
        return opportunities
    
    def estimate_gas_costs(self, opportunity: ArbitrageOpportunity) -> Dict:
        """Estimate gas costs for executing arbitrage"""
        try:
            gas_price = self.w3.eth.gas_price
            
            # Estimate gas for typical arbitrage transaction
            estimated_gas = 300000  # Conservative estimate
            
            gas_cost_wei = gas_price * estimated_gas
            gas_cost_flow = Decimal(gas_cost_wei) / Decimal(10**18)
            
            return {
                'gas_price': gas_price,
                'estimated_gas': estimated_gas,
                'gas_cost_flow': gas_cost_flow,
                'gas_cost_wei': gas_cost_wei
            }
            
        except Exception as e:
            logger.error(f"Error estimating gas costs: {e}")
            return {}
    
    def run_continuous_scan(self, interval: int = 30):
        """Run continuous arbitrage scanning"""
        logger.info(f"Starting continuous arbitrage scanning (interval: {interval}s)")
        logger.info(f"Monitoring pairs: {self.pairs}")
        logger.info(f"Minimum profit threshold: {self.min_profit_threshold}%")
        
        while True:
            try:
                logger.info("=" * 60)
                logger.info(f"Scanning at {time.strftime('%Y-%m-%d %H:%M:%S')}")
                
                opportunities = self.scan_arbitrage_opportunities()
                
                if opportunities:
                    logger.info(f"Found {len(opportunities)} arbitrage opportunities:")
                    
                    for i, opp in enumerate(opportunities, 1):
                        logger.info(f"\n--- Opportunity {i} ---")
                        logger.info(f"Pair: {opp.token_a}/{opp.token_b}")
                        logger.info(f"Buy: {opp.dex_buy} @ {opp.buy_price:.6f}")
                        logger.info(f"Sell: {opp.dex_sell} @ {opp.sell_price:.6f}")
                        logger.info(f"Profit: {opp.profit_percentage:.2f}%")
                        
                        # Estimate gas costs
                        gas_info = self.estimate_gas_costs(opp)
                        if gas_info:
                            logger.info(f"Est. Gas Cost: {gas_info['gas_cost_flow']:.4f} FLOW")
                else:
                    logger.info("No arbitrage opportunities found above threshold")
                
                logger.info(f"Next scan in {interval} seconds...")
                time.sleep(interval)
                
            except KeyboardInterrupt:
                logger.info("Stopping scanner...")
                break
            except Exception as e:
                logger.error(f"Error during scan: {e}")
                time.sleep(interval)

def main():
    # Configuration
    RPC_URL = "https://mainnet.evm.nodes.onflow.org"  # Flow EVM RPC
    
    print("Initializing Flow EVM Arbitrage Scanner...")
    
    # Initialize scanner
    try:
        scanner = FlowArbitrageScanner(RPC_URL)
        print(f"✅ Connected to Flow EVM at {RPC_URL}")
        print(f"📊 Monitoring tokens: {list(scanner.contracts.keys())}")
        print(f"🏭 Monitoring DEXs: {list(scanner.dexs.keys())}")
        print(f"💰 Minimum profit threshold: {scanner.min_profit_threshold}%")
        
    except Exception as e:
        print(f"❌ Failed to initialize scanner: {e}")
        return
    
    # Run single scan
    print("\n🔍 Running single arbitrage scan...")
    print("=" * 50)
    
    try:
        opportunities = scanner.scan_arbitrage_opportunities()
        
        print("\n" + "=" * 50)
        if opportunities:
            print(f"🎯 Found {len(opportunities)} arbitrage opportunities:")
            for i, opp in enumerate(opportunities, 1):
                print(f"\n--- Opportunity {i} ---")
                print(f"Pair: {opp.token_a}/{opp.token_b}")
                print(f"Buy: {opp.dex_buy} @ {opp.buy_price:.6f}")
                print(f"Sell: {opp.dex_sell} @ {opp.sell_price:.6f}")
                print(f"Profit: {opp.profit_percentage:.2f}%")
                print(f"Min trade: {opp.min_amount:.2f} {opp.token_a}")
        else:
            print("❌ No arbitrage opportunities found above threshold")
            print("\n💡 Try:")
            print("   - Lowering minimum profit threshold")
            print("   - Checking if more pools are available")
            print("   - Running continuous monitoring for opportunities")
        
    except Exception as e:
        print(f"❌ Error during scan: {e}")
        import traceback
        traceback.print_exc()
    
    # Ask if user wants to run continuous monitoring
    print(f"\n{'='*50}")
    response = input("Run continuous monitoring? (y/N): ").strip().lower()
    if response in ['y', 'yes']:
        interval = input("Scan interval in seconds (default 30): ").strip()
        try:
            interval = int(interval) if interval else 30
            scanner.run_continuous_scan(interval=interval)
        except KeyboardInterrupt:
            print("\n👋 Scanner stopped by user")
        except ValueError:
            print("❌ Invalid interval, using 30 seconds")
            scanner.run_continuous_scan(interval=30)

if __name__ == "__main__":
    main()