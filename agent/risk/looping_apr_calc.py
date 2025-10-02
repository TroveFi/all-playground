"""
Looping APR Calculator
Calculate APR for leveraged staking loops
"""
from typing import Dict, Any

def calculate_looping_apr(
    staking_apr: float,
    borrow_rate: float,
    collateral_factor: float,
    loop_count: int = None,
    leverage: float = None
) -> Dict[str, Any]:
    """
    Calculate effective APR for looping strategy
    
    Formula: APR = y * L - r_b * (L - 1)
    where:
    - y = staking APR
    - L = leverage
    - r_b = borrow rate
    
    Can calculate using either loop_count or leverage
    """
    # Calculate leverage if not provided
    if leverage is None:
        if loop_count is None:
            raise ValueError("Must provide either loop_count or leverage")
        leverage = calculate_leverage_from_loops(collateral_factor, loop_count)
    
    # Calculate APR components
    staking_yield = staking_apr * leverage
    borrow_cost = borrow_rate * (leverage - 1)
    net_apr = staking_yield - borrow_cost
    
    # Calculate APR boost compared to simple staking
    apr_boost = net_apr - staking_apr
    boost_multiplier = net_apr / staking_apr if staking_apr > 0 else 0
    
    return {
        'net_apr': net_apr,
        'net_apr_percentage': net_apr * 100,
        'staking_yield': staking_yield,
        'borrow_cost': borrow_cost,
        'base_staking_apr': staking_apr,
        'leverage': leverage,
        'apr_boost': apr_boost,
        'boost_multiplier': boost_multiplier,
        'is_profitable': net_apr > 0
    }

def calculate_leverage_from_loops(collateral_factor: float, loop_count: int) -> float:
    """
    Calculate effective leverage from number of loops
    
    Leverage = 1 + c + c^2 + ... + c^n = (1 - c^(n+1)) / (1 - c)
    where c = collateral_factor, n = loop_count
    """
    if collateral_factor >= 1:
        return float('inf')
    
    if loop_count == 0:
        return 1.0
    
    leverage = (1 - collateral_factor ** (loop_count + 1)) / (1 - collateral_factor)
    return leverage

def calculate_marginal_apr_benefit(
    staking_apr: float,
    borrow_rate: float,
    collateral_factor: float,
    current_loop_count: int
) -> Dict[str, Any]:
    """
    Calculate marginal benefit of adding one more loop
    
    APR_(n+1) - APR_n > 0 when y * c > r_b
    """
    # Current APR
    current_leverage = calculate_leverage_from_loops(collateral_factor, current_loop_count)
    current_apr = staking_apr * current_leverage - borrow_rate * (current_leverage - 1)
    
    # APR after one more loop
    next_leverage = calculate_leverage_from_loops(collateral_factor, current_loop_count + 1)
    next_apr = staking_apr * next_leverage - borrow_rate * (next_leverage - 1)
    
    # Marginal benefit
    marginal_benefit = next_apr - current_apr
    
    # Condition for profitability: y * c > r_b
    loop_condition = staking_apr * collateral_factor
    is_profitable_to_loop = loop_condition > borrow_rate
    
    return {
        'current_loop_count': current_loop_count,
        'current_leverage': current_leverage,
        'current_apr': current_apr,
        'next_leverage': next_leverage,
        'next_apr': next_apr,
        'marginal_apr_benefit': marginal_benefit,
        'marginal_benefit_percentage': marginal_benefit * 100,
        'should_loop_more': is_profitable_to_loop and marginal_benefit > 0.001,  # 0.1% threshold
        'loop_profitability_condition': f"{staking_apr * collateral_factor:.4f} > {borrow_rate:.4f}",
        'condition_met': is_profitable_to_loop
    }

def calculate_optimal_leverage(
    staking_apr: float,
    borrow_rate: float,
    collateral_factor: float,
    max_loops: int = 20
) -> Dict[str, Any]:
    """
    Find optimal number of loops (maximize APR while staying profitable)
    """
    # Theoretical max leverage at infinite loops
    max_theoretical_leverage = 1 / (1 - collateral_factor)
    max_theoretical_apr = staking_apr * max_theoretical_leverage - borrow_rate * (max_theoretical_leverage - 1)
    
    # Check if looping is profitable at all
    if staking_apr * collateral_factor <= borrow_rate:
        return {
            'optimal_loops': 0,
            'optimal_leverage': 1.0,
            'optimal_apr': staking_apr,
            'max_theoretical_apr': staking_apr,
            'reason': 'Looping not profitable: y * c <= r_b'
        }
    
    # Find practical optimal loops (with diminishing returns)
    best_apr = staking_apr
    best_loops = 0
    best_leverage = 1.0
    
    aprs = []
    for loops in range(0, max_loops + 1):
        leverage = calculate_leverage_from_loops(collateral_factor, loops)
        apr = staking_apr * leverage - borrow_rate * (leverage - 1)
        aprs.append(apr)
        
        if apr > best_apr:
            best_apr = apr
            best_loops = loops
            best_leverage = leverage
    
    # Calculate marginal benefit of last loop
    if best_loops > 0:
        marginal_benefit = aprs[best_loops] - aprs[best_loops - 1]
    else:
        marginal_benefit = 0
    
    return {
        'optimal_loops': best_loops,
        'optimal_leverage': best_leverage,
        'optimal_apr': best_apr,
        'optimal_apr_percentage': best_apr * 100,
        'max_theoretical_leverage': max_theoretical_leverage,
        'max_theoretical_apr': max_theoretical_apr,
        'max_theoretical_apr_percentage': max_theoretical_apr * 100,
        'marginal_benefit_at_optimal': marginal_benefit,
        'apr_by_loop_count': {i: apr for i, apr in enumerate(aprs)}
    }

def calculate_breakeven_borrow_rate(
    staking_apr: float,
    leverage: float
) -> float:
    """
    Calculate the borrow rate at which APR becomes zero
    
    0 = y * L - r_b * (L - 1)
    r_b = y * L / (L - 1)
    """
    if leverage <= 1:
        return float('inf')
    
    breakeven = staking_apr * leverage / (leverage - 1)
    return breakeven

def calculate_apr_with_fees(
    base_apr: float,
    gas_cost_usd: float,
    loop_count: int,
    position_size_usd: float,
    time_period_days: float = 365
) -> Dict[str, Any]:
    """
    Calculate APR accounting for transaction fees
    """
    # Estimate total gas cost (entry + loops + potential exit)
    total_gas_cost = gas_cost_usd * (loop_count + 2)  # +2 for entry and exit
    
    # Annualized fee impact
    fee_impact_annualized = (total_gas_cost / position_size_usd) * (365 / time_period_days)
    
    # Net APR after fees
    net_apr = base_apr - fee_impact_annualized
    
    return {
        'base_apr': base_apr,
        'base_apr_percentage': base_apr * 100,
        'total_gas_cost_usd': total_gas_cost,
        'fee_impact_annualized': fee_impact_annualized,
        'fee_impact_percentage': fee_impact_annualized * 100,
        'net_apr_after_fees': net_apr,
        'net_apr_percentage': net_apr * 100,
        'position_size_usd': position_size_usd,
        'time_period_days': time_period_days
    }