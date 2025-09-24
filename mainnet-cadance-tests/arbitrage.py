import asyncio
import json
import requests
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
    liquidity_a: Decimal
    liquidity_b: Decimal
    # Safety metrics
    min_liquidity_usd: Decimal
    max_trade_size_usd: Decimal
    liquidity_ratio: Decimal  # smaller_pool / larger_pool
    price_ratio: Decimal     # higher_price / lower_price
    risk_level: str         # LOW, MEDIUM, HIGH, CRITICAL
    warnings: List[str]

class FlowCadenceArbitrageScanner:
    def __init__(self, flow_rpc_url: str = "https://rest-mainnet.onflow.org"):
        # Use the Access API endpoint that matches your flow.json setup
        self.flow_rpc_url = "https://rest-mainnet.onflow.org"
        # Alternative endpoints to try:
        # self.flow_rpc_url = "https://access-mainnet-beta.onflow.org" 
        # self.flow_rpc_url = "https://mainnet.onflow.org"
        
        # Contract addresses on Flow Mainnet
        self.contracts = {
            'SwapFactory': '0xb063c16cac85dbd1',
            'SwapRouter': '0xa6850776a94e6551',
            'SwapConfig': '0xb78ef7afa52ff906',
        }
        
        # Token identifiers (Flow Cadence style)
        self.tokens = {
            'FLOW': 'A.1654653399040a61.FlowToken',
            'FUSD': 'A.3c5959b568896393.FUSD', 
            'USDC': 'A.b19436aae4d94622.FiatToken',
            'stFLOW': 'A.d6f80565193ad727.stFlowToken',
            'BLT': 'A.0f9df91c9121c460.BloctoToken',
        }
        
        # Token pairs to monitor
        self.pairs = [
            ('FLOW', 'USDC'),
            ('FLOW', 'FUSD'), 
            ('FLOW', 'stFLOW'),
            ('USDC', 'FUSD'),
            ('stFLOW', 'FUSD'),
        ]
        
        # Minimum profit threshold (percentage)  
        self.min_profit_threshold = Decimal('0.3')  # 0.3%
        
    def execute_cadence_script(self, script_code: str) -> Optional[Dict]:
        """Execute a Cadence script on Flow"""
        # Try multiple RPC endpoints
        endpoints = [
            "https://rest-mainnet.onflow.org",
            "https://mainnet.onflow.org", 
            "https://access-mainnet-beta.onflow.org"
        ]
        
        for endpoint in endpoints:
            try:
                import base64
                import json
                
                # Encode script as base64
                script_encoded = base64.b64encode(script_code.encode('utf-8')).decode('utf-8')
                
                payload = {
                    "script": script_encoded,
                    "arguments": []
                }
                
                response = requests.post(
                    f"{endpoint}/v1/scripts", 
                    json=payload,
                    headers={'Content-Type': 'application/json'},
                    timeout=30
                )
                
                if response.status_code == 200:
                    result = response.json()
                    
                    # The result might be base64 encoded, try to decode it
                    if isinstance(result, str):
                        try:
                            decoded_result = base64.b64decode(result).decode('utf-8')
                            result = json.loads(decoded_result)
                        except:
                            # If decoding fails, return as is
                            pass
                    
                    logger.debug(f"Script executed successfully on {endpoint}: {result}")
                    self.flow_rpc_url = endpoint  # Use working endpoint for future calls
                    return result
                else:
                    logger.debug(f"Endpoint {endpoint} failed: {response.status_code} - {response.text}")
                    continue
                    
            except Exception as e:
                logger.debug(f"Endpoint {endpoint} error: {e}")
                continue
                
        logger.error("All RPC endpoints failed")
        return None
    
    def test_connection(self) -> bool:
        """Test connection to Flow and verify contracts are accessible"""
        logger.info("Testing connection to Flow Mainnet...")
        
        # Very simple test script first
        simple_script = """
        access(all) fun main(): Int {
            return 42
        }
        """
        
        result = self.execute_cadence_script(simple_script)
        if not result:
            logger.error("Failed basic script execution test")
            return False
        
        logger.info("Basic script execution successful")
        
        # Test if we can access the account at all
        account_test_script = f"""
        access(all) fun main(): Bool {{
            let account = getAccount({self.contracts['SwapFactory']})
            return account.address == {self.contracts['SwapFactory']}
        }}
        """
        
        result = self.execute_cadence_script(account_test_script)
        if result and isinstance(result, dict) and result.get('value'):
            logger.info("Account exists at SwapFactory address")
        else:
            logger.error(f"Account test result: {result}")
            logger.error("Account does not exist at SwapFactory address")
            return False
        
        # Try different import formats
        import_tests = [
            f"import SwapFactory from {self.contracts['SwapFactory']}",
            f"import SwapFactory from 0x{self.contracts['SwapFactory'][2:]}",  # Remove 0x prefix
        ]
        
        for i, import_statement in enumerate(import_tests):
            logger.info(f"Testing import format {i+1}: {import_statement}")
            
            script = f"""
            {import_statement}
            
            access(all) fun main(): Int {{
                return SwapFactory.getAllPairsLength()
            }}
            """
            
            result = self.execute_cadence_script(script)
            logger.debug(f"Import test {i+1} result: {result}")
            
            if result and isinstance(result, dict) and 'value' in result:
                pair_count = result['value']
                logger.info(f"SUCCESS! Found {pair_count} pairs in SwapFactory using import format {i+1}")
                return True
            else:
                logger.debug(f"Import format {i+1} failed")
        
        logger.error("All import formats failed - SwapFactory contract may not exist or be accessible")
        return False
    
    def get_all_pairs(self) -> List[Dict]:
        """Get all trading pairs from Increment Finance in batches"""
        # First get the total count
        count_script = f"""
        import SwapFactory from {self.contracts['SwapFactory']}
        
        access(all) fun main(): Int {{
            return SwapFactory.getAllPairsLength()
        }}
        """
        
        result = self.execute_cadence_script(count_script)
        if not result or 'value' not in result:
            logger.error("Failed to get pair count")
            return []
        
        # Handle different response formats
        total_pairs = result['value']
        if isinstance(total_pairs, str):
            try:
                total_pairs = int(total_pairs)
            except ValueError:
                logger.error(f"Could not convert pair count to integer: {total_pairs}")
                return []
        
        logger.info(f"Found {total_pairs} total pairs, fetching in batches...")
        
        all_pairs = []
        batch_size = 20  # Fetch pairs in smaller batches
        
        for start in range(0, total_pairs, batch_size):
            end = min(start + batch_size - 1, total_pairs - 1)
            logger.info(f"Fetching pairs {start} to {end}...")
            
            batch_script = f"""
            import SwapFactory from {self.contracts['SwapFactory']}
            
            access(all) fun main(): [AnyStruct] {{
                return SwapFactory.getSlicedPairInfos(from: UInt64({start}), to: UInt64({end}))
            }}
            """
            
            result = self.execute_cadence_script(batch_script)
            if result and 'value' in result:
                batch_pairs = result['value']
                all_pairs.extend(batch_pairs)
                logger.info(f"Retrieved {len(batch_pairs)} pairs in this batch")
            else:
                logger.warning(f"Failed to fetch batch {start}-{end}")
                # Continue with other batches even if one fails
            
            # Small delay between batches to be nice to the RPC
            time.sleep(0.5)
        
        logger.info(f"Total pairs retrieved: {len(all_pairs)}")
        return all_pairs
    
    def get_pair_info(self, token0_key: str, token1_key: str, is_stable: bool = False) -> Optional[Dict]:
        """Get specific pair information"""
        # For now, focus on volatile pairs only
        script = f"""
        import SwapFactory from {self.contracts['SwapFactory']}
        
        access(all) fun main(): AnyStruct? {{
            return SwapFactory.getPairInfo(token0Key: "{token0_key}", token1Key: "{token1_key}")
        }}
        """
        
        result = self.execute_cadence_script(script)
        if result and 'value' in result:
            return result['value']
        return None
    
    def get_amounts_out(self, amount_in: str, token_path: List[str]) -> Optional[List[str]]:
        """Get output amounts for a swap path using SwapRouter"""
        # Convert token symbols to full identifiers
        full_path = [self.tokens[token] for token in token_path if token in self.tokens]
        
        if len(full_path) != len(token_path):
            logger.warning(f"Could not resolve all tokens in path: {token_path}")
            return None
        
        path_array = ', '.join([f'"{token}"' for token in full_path])
        
        script = f"""
        import SwapRouter from {self.contracts['SwapRouter']}
        
        access(all) fun main(): [UFix64] {{
            let path: [String] = [{path_array}]
            return SwapRouter.getAmountsOut(amountIn: {amount_in}, tokenKeyPath: path)
        }}
        """
        
        result = self.execute_cadence_script(script)
        if result and 'value' in result:
            return [amount['value'] for amount in result['value']]
        return None
    
    def calculate_price_from_reserves(self, reserve0: Decimal, reserve1: Decimal, is_stable: bool = False) -> Decimal:
        """Calculate price from pool reserves"""
        if reserve0 == 0 or reserve1 == 0:
            return Decimal('0')
        
        if is_stable:
            # For stable pairs, use 1:1 pricing with slight curve adjustment
            # This is simplified - actual stable curve is more complex
            return Decimal('1.0')
        else:
            # For volatile pairs, simple ratio
            return reserve1 / reserve0
    
    def assess_risk_level(self, opportunity_data: Dict) -> Tuple[str, List[str]]:
        """Assess risk level and generate warnings for an arbitrage opportunity"""
        warnings = []
        risk_factors = 0
        
        profit_pct = opportunity_data['profit_percentage']
        min_liquidity = opportunity_data['min_liquidity_usd']
        max_trade_size = opportunity_data['max_trade_size_usd']
        liquidity_ratio = opportunity_data['liquidity_ratio']
        price_ratio = opportunity_data['price_ratio']
        
        # Check profit percentage (too good to be true)
        if profit_pct > 50:
            warnings.append("CRITICAL: >50% profit suggests broken oracle or worthless token")
            risk_factors += 4
        elif profit_pct > 10:
            warnings.append("HIGH: >10% profit is unusually high - verify token legitimacy")
            risk_factors += 2
        elif profit_pct > 5:
            warnings.append("MEDIUM: >5% profit requires extra caution")
            risk_factors += 1
        
        # Check liquidity levels
        if min_liquidity < 100:
            warnings.append("CRITICAL: Liquidity <$100 - likely not tradeable")
            risk_factors += 4
        elif min_liquidity < 1000:
            warnings.append("HIGH: Liquidity <$1K - high slippage risk")
            risk_factors += 2
        elif min_liquidity < 10000:
            warnings.append("MEDIUM: Liquidity <$10K - moderate slippage risk")
            risk_factors += 1
        
        # Check max tradeable amount
        if max_trade_size < 50:
            warnings.append("CRITICAL: Max trade <$50 - not economically viable")
            risk_factors += 3
        elif max_trade_size < 500:
            warnings.append("HIGH: Max trade <$500 - limited profit potential")
            risk_factors += 2
        
        # Check liquidity imbalance
        if liquidity_ratio < 0.1:
            warnings.append("HIGH: 10x+ liquidity imbalance between pools")
            risk_factors += 2
        elif liquidity_ratio < 0.3:
            warnings.append("MEDIUM: 3x+ liquidity imbalance between pools")
            risk_factors += 1
        
        # Check price ratio (extreme price differences)
        if price_ratio > 10:
            warnings.append("CRITICAL: 10x+ price difference suggests broken market")
            risk_factors += 4
        elif price_ratio > 3:
            warnings.append("HIGH: 3x+ price difference needs investigation")
            risk_factors += 2
        elif price_ratio > 1.5:
            warnings.append("MEDIUM: 1.5x+ price difference - verify quickly")
            risk_factors += 1
        
        # Determine overall risk level
        if risk_factors >= 8:
            risk_level = "CRITICAL"
        elif risk_factors >= 4:
            risk_level = "HIGH"
        elif risk_factors >= 2:
            risk_level = "MEDIUM"
        else:
            risk_level = "LOW"
        
        return risk_level, warnings
    
    def estimate_liquidity_usd(self, reserve_a: Decimal, reserve_b: Decimal, token_a: str, token_b: str) -> Decimal:
        """Estimate USD liquidity using rough token prices"""
        # Rough USD prices for estimation (should be updated with real price feeds)
        token_prices = {
            'FLOW': Decimal('0.40'),  # Approximate FLOW price
            'USDC': Decimal('1.00'),
            'FUSD': Decimal('0.15'),  # FUSD has been depegged
            'USDT': Decimal('1.00'),
            'stFLOW': Decimal('0.42'), # Slightly higher than FLOW
            'BLT': Decimal('0.01'),   # Rough estimate
        }
        
        price_a = token_prices.get(token_a, Decimal('0.01'))  # Default to very low price if unknown
        price_b = token_prices.get(token_b, Decimal('0.01'))
        
        usd_value_a = reserve_a * price_a
        usd_value_b = reserve_b * price_b
        
        return min(usd_value_a, usd_value_b)  # Return the smaller side (constraining factor)
    
    def calculate_max_trade_size(self, reserve_a: Decimal, reserve_b: Decimal, token_a: str, token_b: str, slippage_limit: float = 0.05) -> Decimal:
        """Calculate maximum trade size before hitting slippage limit"""
        # For constant product AMM: new_price / old_price = (old_reserve + delta) / old_reserve
        # Solve for delta when price_change = slippage_limit
        
        try:
            # Use smaller reserve as the limiting factor
            limiting_reserve = min(reserve_a, reserve_b)
            
            # Conservative estimate: max trade = 5% of smaller reserve
            max_trade_tokens = limiting_reserve * Decimal(str(slippage_limit))
            
            # Convert to USD
            token_prices = {
                'FLOW': Decimal('0.40'), 'USDC': Decimal('1.00'), 'FUSD': Decimal('0.15'),
                'USDT': Decimal('1.00'), 'stFLOW': Decimal('0.42'), 'BLT': Decimal('0.01'),
            }
            
            price = token_prices.get(token_a, Decimal('0.01'))
            max_trade_usd = max_trade_tokens * price
            
            return max_trade_usd
            
        except Exception:
            return Decimal('0')
    
    def parse_pair_info(self, pair_info) -> Optional[Dict]:
        """Parse pair info array into structured data"""
        try:
            # Handle the nested structure: {'value': [...], 'type': 'Array'}
            if isinstance(pair_info, dict) and 'value' in pair_info:
                pair_array = pair_info['value']
            else:
                pair_array = pair_info
            
            if not pair_array or len(pair_array) < 8:
                return None
            
            # Extract values from the nested structure
            def extract_value(item):
                if isinstance(item, dict) and 'value' in item:
                    return item['value']
                return item
            
            return {
                'token0_key': extract_value(pair_array[0]),
                'token1_key': extract_value(pair_array[1]), 
                'token0_reserve': Decimal(str(extract_value(pair_array[2]))),
                'token1_reserve': Decimal(str(extract_value(pair_array[3]))),
                'pair_address': extract_value(pair_array[4]),
                'lp_token_supply': Decimal(str(extract_value(pair_array[5]))),
                'swap_fee_bps': int(extract_value(pair_array[6])),
                'is_stableswap': extract_value(pair_array[7]),
                'stable_curve_p': Decimal(str(extract_value(pair_array[8]))) if len(pair_array) > 8 else Decimal('1.0')
            }
        except (KeyError, IndexError, ValueError, TypeError) as e:
            logger.error(f"Error parsing pair info: {e}")
            logger.debug(f"Pair data: {pair_info}")
            return None
    
    def find_symbol_from_key(self, token_key: str) -> str:
        """Find token symbol from Cadence identifier"""
        for symbol, key in self.tokens.items():
            if key == token_key:
                return symbol
        return token_key.split('.')[-1]  # Return contract name if not found
    
    def scan_arbitrage_opportunities(self) -> List[ArbitrageOpportunity]:
        """Scan for arbitrage opportunities"""
        logger.info("Fetching all pairs from Increment Finance...")
        
        all_pairs = self.get_all_pairs()
        if not all_pairs:
            logger.warning("No pairs found")
            return []
        
        logger.info(f"Found {len(all_pairs)} total pairs")
        
        # Debug: Show first few pairs to understand the data structure
        logger.info("Sample pair data structure:")
        for i, pair_data in enumerate(all_pairs[:3]):
            logger.info(f"Pair {i}: {pair_data}")
            parsed = self.parse_pair_info(pair_data)
            if parsed:
                logger.info(f"  Parsed: {parsed['token0_key']} / {parsed['token1_key']}")
                logger.info(f"  Reserves: {parsed['token0_reserve']} / {parsed['token1_reserve']}")
                logger.info(f"  Is stable: {parsed['is_stableswap']}")
            else:
                logger.warning(f"  Failed to parse pair {i}")
        
        # Group pairs by token combination
        pair_groups = {}
        parsed_count = 0
        
        for pair_data in all_pairs:
            pair_info = self.parse_pair_info(pair_data)
            if not pair_info:
                continue
            
            parsed_count += 1
            token0_symbol = self.find_symbol_from_key(pair_info['token0_key'])
            token1_symbol = self.find_symbol_from_key(pair_info['token1_key'])
            
            # Create a normalized key (alphabetical order)
            if token0_symbol < token1_symbol:
                key = f"{token0_symbol}/{token1_symbol}"
                token_a, token_b = token0_symbol, token1_symbol
                reserve_a, reserve_b = pair_info['token0_reserve'], pair_info['token1_reserve']
            else:
                key = f"{token1_symbol}/{token0_symbol}"
                token_a, token_b = token1_symbol, token0_symbol
                reserve_a, reserve_b = pair_info['token1_reserve'], pair_info['token0_reserve']
            
            if key not in pair_groups:
                pair_groups[key] = []
            
            # Calculate price (token_b per token_a)
            price = self.calculate_price_from_reserves(
                reserve_a, reserve_b, pair_info['is_stableswap']
            )
            
            pair_type = "Stable" if pair_info['is_stableswap'] else "Volatile"
            
            pair_groups[key].append({
                'type': pair_type,
                'price': price,
                'reserve_a': reserve_a,
                'reserve_b': reserve_b,
                'fee_bps': pair_info['swap_fee_bps'],
                'pair_address': pair_info['pair_address'],
                'token_a': token_a,
                'token_b': token_b
            })
        
        logger.info(f"Successfully parsed {parsed_count} out of {len(all_pairs)} pairs")
        logger.info(f"Found {len(pair_groups)} unique token pairs:")
        for key, pairs in pair_groups.items():
            if len(pairs) > 1:
                logger.info(f"  {key}: {len(pairs)} pools ({[p['type'] for p in pairs]})")
        
        # Find arbitrage opportunities
        opportunities = []
        
        for pair_key, pairs in pair_groups.items():
            if len(pairs) < 2:
                continue  # Need at least 2 pools for arbitrage
            
            logger.info(f"Checking arbitrage for {pair_key} ({len(pairs)} pools)")
            
            for i in range(len(pairs)):
                for j in range(i + 1, len(pairs)):
                    pool1, pool2 = pairs[i], pairs[j]
                    
                    if pool1['price'] == 0 or pool2['price'] == 0:
                        logger.debug(f"Skipping zero price: {pool1['price']}, {pool2['price']}")
                        continue
                    
                    # Calculate basic metrics
                    if pool1['price'] > pool2['price']:
                        buy_pool, sell_pool = pool2, pool1
                        profit_pct = ((pool1['price'] - pool2['price']) / pool2['price']) * 100
                    else:
                        buy_pool, sell_pool = pool1, pool2
                        profit_pct = ((pool2['price'] - pool1['price']) / pool1['price']) * 100
                    
                    # Calculate safety metrics
                    min_liquidity_usd = min(
                        self.estimate_liquidity_usd(buy_pool['reserve_a'], buy_pool['reserve_b'], buy_pool['token_a'], buy_pool['token_b']),
                        self.estimate_liquidity_usd(sell_pool['reserve_a'], sell_pool['reserve_b'], sell_pool['token_a'], sell_pool['token_b'])
                    )
                    
                    max_trade_size_usd = min(
                        self.calculate_max_trade_size(buy_pool['reserve_a'], buy_pool['reserve_b'], buy_pool['token_a'], buy_pool['token_b']),
                        self.calculate_max_trade_size(sell_pool['reserve_a'], sell_pool['reserve_b'], sell_pool['token_a'], sell_pool['token_b'])
                    )
                    
                    liquidity_ratio = min_liquidity_usd / max(
                        self.estimate_liquidity_usd(buy_pool['reserve_a'], buy_pool['reserve_b'], buy_pool['token_a'], buy_pool['token_b']),
                        self.estimate_liquidity_usd(sell_pool['reserve_a'], sell_pool['reserve_b'], sell_pool['token_a'], sell_pool['token_b'])
                    ) if max(
                        self.estimate_liquidity_usd(buy_pool['reserve_a'], buy_pool['reserve_b'], buy_pool['token_a'], buy_pool['token_b']),
                        self.estimate_liquidity_usd(sell_pool['reserve_a'], sell_pool['reserve_b'], sell_pool['token_a'], sell_pool['token_b'])
                    ) > 0 else Decimal('0')
                    
                    price_ratio = max(buy_pool['price'], sell_pool['price']) / min(buy_pool['price'], sell_pool['price']) if min(buy_pool['price'], sell_pool['price']) > 0 else Decimal('999')
                    
                    # Account for fees
                    total_fee_cost = Decimal(buy_pool['fee_bps'] + sell_pool['fee_bps']) / Decimal('10000') * Decimal('100')
                    net_profit_pct = profit_pct - total_fee_cost
                    
                    # Create opportunity data for risk assessment
                    opportunity_data = {
                        'profit_percentage': net_profit_pct,
                        'min_liquidity_usd': min_liquidity_usd,
                        'max_trade_size_usd': max_trade_size_usd,
                        'liquidity_ratio': liquidity_ratio,
                        'price_ratio': price_ratio
                    }
                    
                    # Assess risk level
                    risk_level, warnings = self.assess_risk_level(opportunity_data)
                    
                    logger.info(f"Price difference in {pair_key}: {buy_pool['price']:.6f} vs {sell_pool['price']:.6f} = {profit_pct:.3f}%")
                    logger.info(f"Net profit after {total_fee_cost:.3f}% fees: {net_profit_pct:.3f}%")
                    logger.info(f"Liquidity: ${min_liquidity_usd:.2f}, Max trade: ${max_trade_size_usd:.2f}")
                    logger.info(f"Risk level: {risk_level}")
                    
                    if net_profit_pct >= self.min_profit_threshold:
                        opportunity = ArbitrageOpportunity(
                            token_a=buy_pool['token_a'],
                            token_b=buy_pool['token_b'],
                            dex_buy=f"{buy_pool['type']} Pool",
                            dex_sell=f"{sell_pool['type']} Pool",
                            buy_price=buy_pool['price'],
                            sell_price=sell_pool['price'],
                            profit_percentage=net_profit_pct,
                            liquidity_a=buy_pool['reserve_a'],
                            liquidity_b=buy_pool['reserve_b'],
                            min_liquidity_usd=min_liquidity_usd,
                            max_trade_size_usd=max_trade_size_usd,
                            liquidity_ratio=liquidity_ratio,
                            price_ratio=price_ratio,
                            risk_level=risk_level,
                            warnings=warnings
                        )
                        opportunities.append(opportunity)
                        
                        logger.info(f"🔥 ARBITRAGE OPPORTUNITY FOUND!")
                        logger.info(f"   Pair: {opportunity.token_a}/{opportunity.token_b}")
                        logger.info(f"   Buy on {opportunity.dex_buy} at {opportunity.buy_price:.6f}")
                        logger.info(f"   Sell on {opportunity.dex_sell} at {opportunity.sell_price:.6f}")
                        logger.info(f"   Net profit: {opportunity.profit_percentage:.2f}%")
                        logger.info(f"   Risk: {opportunity.risk_level}")
                        logger.info(f"   Max trade: ${opportunity.max_trade_size_usd:.2f}")
                        
                        if warnings:
                            logger.warning("   ⚠️  WARNINGS:")
                            for warning in warnings:
                                logger.warning(f"      - {warning}")
                    else:
                        logger.debug(f"Opportunity below threshold: {net_profit_pct:.3f}% < {self.min_profit_threshold}%")
        
        return opportunities
    
    def get_price_via_router(self, token_a: str, token_b: str, amount: str = "1.0") -> Optional[Decimal]:
        """Get price via SwapRouter for comparison"""
        amounts_out = self.get_amounts_out(amount, [token_a, token_b])
        if amounts_out and len(amounts_out) >= 2:
            input_amount = Decimal(amounts_out[0])
            output_amount = Decimal(amounts_out[1])
            if input_amount > 0:
                return output_amount / input_amount
        return None
    
    def run_continuous_scan(self, interval: int = 60):
        """Run continuous arbitrage scanning"""
        logger.info(f"Starting continuous arbitrage scanning on Flow Cadence")
        logger.info(f"Monitoring Increment Finance (interval: {interval}s)")
        logger.info(f"Minimum profit threshold: {self.min_profit_threshold}%")
        logger.info(f"Token pairs: {self.pairs}")
        
        while True:
            try:
                logger.info("=" * 80)
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
                        logger.info(f"Available Liquidity: {opp.liquidity_a:.2f} {opp.token_a}")
                        
                        # Get router price for comparison
                        router_price = self.get_price_via_router(opp.token_a, opp.token_b)
                        if router_price:
                            logger.info(f"Router price: {router_price:.6f} (for reference)")
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
    print("🌊 Flow Cadence Arbitrage Scanner - Increment Finance")
    print("=" * 60)
    
    # Initialize scanner  
    try:
        scanner = FlowCadenceArbitrageScanner()
        print("✅ Connected to Flow Mainnet")
        print(f"📊 Monitoring tokens: {list(scanner.tokens.keys())}")
        print(f"🏭 Monitoring DEX: Increment Finance (Volatile + Stable pairs)")
        print(f"💰 Minimum profit threshold: {scanner.min_profit_threshold}%")
        
    except Exception as e:
        print(f"❌ Failed to initialize scanner: {e}")
        return
    
    # Test connection first
    print("\n🔗 Testing connection to Increment Finance...")
    if not scanner.test_connection():
        print("❌ Connection test failed. Please check:")
        print("   - Flow Mainnet RPC is accessible")
        print("   - Contract addresses are correct") 
        print("   - Network connectivity")
        return
    
    # Run single scan
    print("\n🔍 Running single arbitrage scan...")
    print("=" * 60)
    
    try:
        opportunities = scanner.scan_arbitrage_opportunities()
        
        print("\n" + "=" * 60)
        if opportunities:
            print(f"🎯 Found {len(opportunities)} arbitrage opportunities:")
            for i, opp in enumerate(opportunities, 1):
                print(f"\n--- Opportunity {i} ---")
                print(f"Pair: {opp.token_a}/{opp.token_b}")
                print(f"Buy: {opp.dex_buy} @ {opp.buy_price:.6f}")
                print(f"Sell: {opp.dex_sell} @ {opp.sell_price:.6f}")
                print(f"Net Profit: {opp.profit_percentage:.2f}%")
                print(f"Liquidity: {opp.liquidity_a:.2f} {opp.token_a}")
        else:
            print("❌ No arbitrage opportunities found above threshold")
            print("\n💡 This could mean:")
            print("   - Markets are efficient (good for users, bad for arbitrageurs)")
            print("   - Try lowering the profit threshold")
            print("   - Run continuous monitoring to catch opportunities")
        
    except Exception as e:
        print(f"❌ Error during scan: {e}")
        import traceback
        traceback.print_exc()
    
    # Ask if user wants continuous monitoring
    print(f"\n{'='*60}")
    response = input("Run continuous monitoring? (y/N): ").strip().lower()
    if response in ['y', 'yes']:
        interval = input("Scan interval in seconds (default 60): ").strip()
        try:
            interval = int(interval) if interval else 60
            scanner.run_continuous_scan(interval=interval)
        except KeyboardInterrupt:
            print("\n👋 Scanner stopped by user")
        except ValueError:
            print("❌ Invalid interval, using 60 seconds")
            scanner.run_continuous_scan(interval=60)

if __name__ == "__main__":
    main()