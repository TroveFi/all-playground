"""
Delta Neutral APR Calculator
Comprehensive APR calculations for staking + perp short strategy
"""
import math
from typing import Dict, Any, List


def calculate_staking_yield_component(
    staked_amount: float,
    staking_apr: float,
    flow_price: float
) -> Dict[str, Any]:
    """
    Calculate the staking yield component
    """
    position_value = staked_amount * flow_price
    annual_yield = position_value * staking_apr
    
    return {
        'staked_amount': staked_amount,
        'position_value_usd': position_value,
        'staking_apr': staking_apr,
        'staking_apr_percentage': staking_apr * 100,
        'annual_yield_usd': annual_yield,
        'monthly_yield_usd': annual_yield / 12,
        'daily_yield_usd': annual_yield / 365
    }


def calculate_funding_cost_component(
    perp_size: float,
    perp_price: float,
    funding_rate_8h: float,
    periods_per_year: int = 1095  # 3 times per day * 365 days
) -> Dict[str, Any]:
    """
    Calculate funding rate costs/income
    
    Funding rates are typically quoted per 8 hours
    - Positive funding rate = longs pay shorts (you receive)
    - Negative funding rate = shorts pay longs (you pay)
    """
    position_value = perp_size * perp_price
    
    # Funding per period
    funding_per_period = position_value * funding_rate_8h
    
    # Annualized funding
    annual_funding = funding_per_period * periods_per_year
    funding_apr = funding_rate_8h * periods_per_year
    
    # For shorts, positive funding rate means you RECEIVE funding
    # Negative funding rate means you PAY funding
    
    return {
        'perp_size': perp_size,
        'position_value_usd': position_value,
        'funding_rate_8h': funding_rate_8h,
        'funding_rate_8h_percentage': funding_rate_8h * 100,
        'funding_apr': funding_apr,
        'funding_apr_percentage': funding_apr * 100,
        'annual_funding_usd': annual_funding,
        'monthly_funding_usd': annual_funding / 12,
        'daily_funding_usd': annual_funding / 365,
        'is_receiving_funding': funding_rate_8h > 0,  # Positive = shorts receive
        'funding_direction': 'RECEIVE' if funding_rate_8h > 0 else 'PAY'
    }


def calculate_trading_fees(
    position_size_usd: float,
    entry_fee_rate: float = 0.0005,  # 0.05% taker fee
    exit_fee_rate: float = 0.0005,
    rebalance_frequency_per_year: int = 12,  # Monthly rebalancing
    rebalance_fee_rate: float = 0.0005,
    spot_entry_fee: float = 0.003,  # 0.3% DEX fee
    spot_exit_fee: float = 0.003
) -> Dict[str, Any]:
    """
    Calculate all trading fees for delta neutral strategy
    """
    # Entry fees (spot + perp)
    spot_entry_cost = position_size_usd * spot_entry_fee
    perp_entry_cost = position_size_usd * entry_fee_rate
    total_entry_fees = spot_entry_cost + perp_entry_cost
    
    # Exit fees (spot + perp)
    spot_exit_cost = position_size_usd * spot_exit_fee
    perp_exit_cost = position_size_usd * exit_fee_rate
    total_exit_fees = spot_exit_cost + perp_exit_cost
    
    # Rebalancing fees (per rebalance)
    rebalance_cost_per_time = position_size_usd * rebalance_fee_rate * 2  # Buy & sell
    annual_rebalance_costs = rebalance_cost_per_time * rebalance_frequency_per_year
    
    # Total annual fees
    total_annual_fees = annual_rebalance_costs  # Entry/exit amortized over holding period
    
    # As percentage of position
    fee_apr = total_annual_fees / position_size_usd
    
    return {
        'spot_entry_fee': spot_entry_cost,
        'perp_entry_fee': perp_entry_cost,
        'total_entry_fees': total_entry_fees,
        'spot_exit_fee': spot_exit_cost,
        'perp_exit_fee': perp_exit_cost,
        'total_exit_fees': total_exit_fees,
        'rebalance_frequency_per_year': rebalance_frequency_per_year,
        'cost_per_rebalance': rebalance_cost_per_time,
        'annual_rebalance_costs': annual_rebalance_costs,
        'total_annual_fees': total_annual_fees,
        'fee_apr': fee_apr,
        'fee_apr_percentage': fee_apr * 100
    }


def calculate_gas_costs(
    entry_gas_usd: float = 5,
    exit_gas_usd: float = 5,
    rebalance_gas_usd: float = 10,
    rebalance_frequency_per_year: int = 12,
    position_size_usd: float = 10000,
    holding_period_days: float = 365
) -> Dict[str, Any]:
    """
    Calculate gas/transaction costs
    """
    # Entry/exit costs amortized over holding period
    entry_exit_gas = entry_gas_usd + exit_gas_usd
    entry_exit_annualized = entry_exit_gas * (365 / holding_period_days)
    
    # Rebalancing gas costs
    annual_rebalance_gas = rebalance_gas_usd * rebalance_frequency_per_year
    
    # Total annual gas
    total_annual_gas = entry_exit_annualized + annual_rebalance_gas
    
    # As percentage of position
    gas_cost_apr = total_annual_gas / position_size_usd
    
    return {
        'entry_gas_usd': entry_gas_usd,
        'exit_gas_usd': exit_gas_usd,
        'rebalance_gas_usd': rebalance_gas_usd,
        'rebalance_frequency': rebalance_frequency_per_year,
        'annual_rebalance_gas': annual_rebalance_gas,
        'entry_exit_annualized': entry_exit_annualized,
        'total_annual_gas': total_annual_gas,
        'gas_cost_apr': gas_cost_apr,
        'gas_cost_apr_percentage': gas_cost_apr * 100
    }


def calculate_slippage_costs(
    position_size_usd: float,
    spot_liquidity_usd: float,
    perp_liquidity_usd: float,
    rebalance_frequency_per_year: int = 12,
    entry_exit_multiplier: float = 1.0  # For entry/exit vs rebalancing
) -> Dict[str, Any]:
    """
    Estimate slippage costs for execution
    """
    # Spot slippage (AMM model: slippage ≈ size/liquidity for small trades)
    spot_size_ratio = position_size_usd / spot_liquidity_usd if spot_liquidity_usd > 0 else 0
    spot_slippage_rate = min(spot_size_ratio * 0.5, 0.05)  # Cap at 5%
    
    # Perp slippage (order book model: lower slippage)
    perp_size_ratio = position_size_usd / perp_liquidity_usd if perp_liquidity_usd > 0 else 0
    perp_slippage_rate = min(perp_size_ratio * 0.2, 0.02)  # Cap at 2%
    
    # Entry/exit slippage costs
    entry_spot_slippage = position_size_usd * spot_slippage_rate
    entry_perp_slippage = position_size_usd * perp_slippage_rate
    total_entry_slippage = entry_spot_slippage + entry_perp_slippage
    
    # Rebalancing slippage (typically smaller trades)
    avg_rebalance_size = position_size_usd * 0.1  # Assume 10% rebalance
    rebalance_slippage_per_time = (avg_rebalance_size * spot_slippage_rate + 
                                    avg_rebalance_size * perp_slippage_rate)
    annual_rebalance_slippage = rebalance_slippage_per_time * rebalance_frequency_per_year
    
    # Total annual slippage
    total_annual_slippage = annual_rebalance_slippage
    slippage_apr = total_annual_slippage / position_size_usd
    
    return {
        'spot_liquidity_usd': spot_liquidity_usd,
        'perp_liquidity_usd': perp_liquidity_usd,
        'spot_slippage_rate': spot_slippage_rate,
        'spot_slippage_percentage': spot_slippage_rate * 100,
        'perp_slippage_rate': perp_slippage_rate,
        'perp_slippage_percentage': perp_slippage_rate * 100,
        'entry_total_slippage': total_entry_slippage,
        'rebalance_frequency': rebalance_frequency_per_year,
        'annual_rebalance_slippage': annual_rebalance_slippage,
        'total_annual_slippage': total_annual_slippage,
        'slippage_apr': slippage_apr,
        'slippage_apr_percentage': slippage_apr * 100
    }


def calculate_basis_cost(
    basis: float,
    perp_size: float,
    perp_price: float,
    expected_holding_days: float = 365,
    basis_decay_rate: float = 0.1  # Assume basis decays 10% per month
) -> Dict[str, Any]:
    """
    Calculate cost of basis (perp-spot difference) if holding to close
    
    If perp is trading at premium (basis > 0), you'll lose that premium when closing
    If perp is trading at discount (basis < 0), you'll gain when closing
    """
    position_value = perp_size * perp_price
    
    # Current basis in dollars
    basis_dollars = perp_size * basis
    
    # Expected basis at close (assuming it decays)
    months_held = expected_holding_days / 30
    decay_factor = (1 - basis_decay_rate) ** months_held
    expected_basis_at_close = basis * decay_factor
    
    # Realized basis cost (what you'll actually pay/receive)
    realized_basis_cost = perp_size * expected_basis_at_close
    
    # Annualized
    time_factor = 365 / expected_holding_days
    annualized_basis_cost = realized_basis_cost * time_factor
    basis_cost_apr = annualized_basis_cost / position_value
    
    return {
        'current_basis': basis,
        'current_basis_percentage': (basis / perp_price * 100) if perp_price > 0 else 0,
        'basis_in_dollars': basis_dollars,
        'expected_basis_at_close': expected_basis_at_close,
        'realized_basis_cost': realized_basis_cost,
        'annualized_basis_cost': annualized_basis_cost,
        'basis_cost_apr': basis_cost_apr,
        'basis_cost_apr_percentage': basis_cost_apr * 100,
        'is_cost': basis > 0  # Positive basis = cost for shorts
    }


def calculate_impermanent_gain_loss(
    initial_stflow_price: float,
    current_stflow_price: float,
    initial_flow_price: float,
    current_flow_price: float,
    staked_amount: float
) -> Dict[str, Any]:
    """
    Calculate IL-like effects from stFLOW/FLOW ratio changes
    Not true IL, but similar concept for delta neutral
    """
    # Initial ratio
    initial_ratio = initial_stflow_price / initial_flow_price if initial_flow_price > 0 else 1
    
    # Current ratio
    current_ratio = current_stflow_price / current_flow_price if current_flow_price > 0 else 1
    
    # Ratio change
    ratio_change = current_ratio - initial_ratio
    ratio_change_pct = ratio_change / initial_ratio if initial_ratio > 0 else 0
    
    # Impact on position value
    value_impact = staked_amount * current_stflow_price * ratio_change_pct
    
    return {
        'initial_stflow_flow_ratio': initial_ratio,
        'current_stflow_flow_ratio': current_ratio,
        'ratio_change': ratio_change,
        'ratio_change_percentage': ratio_change_pct * 100,
        'value_impact_usd': value_impact,
        'description': 'Gain from stFLOW appreciation' if ratio_change > 0 else 'Loss from stFLOW depreciation'
    }


def calculate_net_delta_neutral_apr(
    staked_amount: float,
    staking_apr: float,
    flow_price: float,
    perp_size: float,
    perp_price: float,
    funding_rate_8h: float,
    spot_liquidity_usd: float = None,
    perp_liquidity_usd: float = None,
    rebalance_frequency_per_year: int = 12,
    holding_period_days: float = 365,
    basis: float = 0,
    entry_gas_usd: float = 5,
    exit_gas_usd: float = 5,
    rebalance_gas_usd: float = 10
) -> Dict[str, Any]:
    """
    Calculate comprehensive net APR for delta neutral strategy
    
    Net APR = Staking Yield + Funding Received - Trading Fees - Gas Costs - Slippage - Basis Cost
    """
    position_value = staked_amount * flow_price
    
    # 1. Staking yield (positive)
    staking_yield = calculate_staking_yield_component(staked_amount, staking_apr, flow_price)
    
    # 2. Funding rate (can be positive or negative)
    funding = calculate_funding_cost_component(perp_size, perp_price, funding_rate_8h)
    
    # 3. Trading fees (negative)
    trading_fees = calculate_trading_fees(
        position_value, 
        rebalance_frequency_per_year=rebalance_frequency_per_year
    )
    
    # 4. Gas costs (negative)
    gas_costs = calculate_gas_costs(
        entry_gas_usd, exit_gas_usd, rebalance_gas_usd,
        rebalance_frequency_per_year, position_value, holding_period_days
    )
    
    # 5. Slippage (negative)
    if spot_liquidity_usd and perp_liquidity_usd:
        slippage = calculate_slippage_costs(
            position_value, spot_liquidity_usd, perp_liquidity_usd,
            rebalance_frequency_per_year
        )
    else:
        slippage = {
            'slippage_apr': 0,
            'slippage_apr_percentage': 0,
            'warning': 'No liquidity data provided'
        }
    
    # 6. Basis cost (can be positive or negative)
    basis_cost = calculate_basis_cost(basis, perp_size, perp_price, holding_period_days)
    
    # Calculate net APR
    net_apr = (
        staking_yield['staking_apr'] +  # Positive
        funding['funding_apr'] -  # Positive if receiving, negative if paying
        trading_fees['fee_apr'] -  # Always negative
        gas_costs['gas_cost_apr'] -  # Always negative
        slippage['slippage_apr'] -  # Always negative
        abs(basis_cost['basis_cost_apr'])  # Cost regardless of sign
    )
    
    # Breakdown
    total_income = staking_yield['staking_apr'] + max(0, funding['funding_apr'])
    total_costs = (
        trading_fees['fee_apr'] + 
        gas_costs['gas_cost_apr'] + 
        slippage['slippage_apr'] + 
        abs(basis_cost['basis_cost_apr']) +
        abs(min(0, funding['funding_apr']))  # Add funding if it's a cost
    )
    
    # Expected annual returns in USD
    annual_return_usd = net_apr * position_value
    monthly_return_usd = annual_return_usd / 12
    daily_return_usd = annual_return_usd / 365
    
    return {
        'position_summary': {
            'staked_amount': staked_amount,
            'perp_size': perp_size,
            'position_value_usd': position_value,
            'is_perfectly_hedged': abs(staked_amount - perp_size) < (staked_amount * 0.02)
        },
        'income_components': {
            'staking_apr': staking_yield['staking_apr'],
            'staking_apr_percentage': staking_yield['staking_apr_percentage'],
            'funding_apr': funding['funding_apr'],
            'funding_apr_percentage': funding['funding_apr_percentage'],
            'funding_direction': funding['funding_direction'],
            'total_income_apr': total_income,
            'total_income_apr_percentage': total_income * 100
        },
        'cost_components': {
            'trading_fees_apr': trading_fees['fee_apr'],
            'trading_fees_apr_percentage': trading_fees['fee_apr_percentage'],
            'gas_costs_apr': gas_costs['gas_cost_apr'],
            'gas_costs_apr_percentage': gas_costs['gas_cost_apr_percentage'],
            'slippage_apr': slippage['slippage_apr'],
            'slippage_apr_percentage': slippage['slippage_apr_percentage'],
            'basis_cost_apr': abs(basis_cost['basis_cost_apr']),
            'basis_cost_apr_percentage': abs(basis_cost['basis_cost_apr_percentage']),
            'total_costs_apr': total_costs,
            'total_costs_apr_percentage': total_costs * 100
        },
        'net_results': {
            'net_apr': net_apr,
            'net_apr_percentage': net_apr * 100,
            'annual_return_usd': annual_return_usd,
            'monthly_return_usd': monthly_return_usd,
            'daily_return_usd': daily_return_usd,
            'is_profitable': net_apr > 0,
            'profit_margin': (net_apr / total_income * 100) if total_income > 0 else 0
        },
        'detailed_breakdown': {
            'staking_yield': staking_yield,
            'funding': funding,
            'trading_fees': trading_fees,
            'gas_costs': gas_costs,
            'slippage': slippage,
            'basis_cost': basis_cost
        },
        'sensitivity_analysis': {
            'breakeven_funding_rate_8h': _calculate_breakeven_funding(
                staking_apr, trading_fees['fee_apr'], 
                gas_costs['gas_cost_apr'], slippage['slippage_apr']
            ),
            'cost_breakdown_percentage': {
                'trading_fees': (trading_fees['fee_apr'] / total_costs * 100) if total_costs > 0 else 0,
                'gas': (gas_costs['gas_cost_apr'] / total_costs * 100) if total_costs > 0 else 0,
                'slippage': (slippage['slippage_apr'] / total_costs * 100) if total_costs > 0 else 0,
                'basis': (abs(basis_cost['basis_cost_apr']) / total_costs * 100) if total_costs > 0 else 0
            }
        }
    }


def _calculate_breakeven_funding(
    staking_apr: float,
    trading_fee_apr: float,
    gas_apr: float,
    slippage_apr: float
) -> Dict[str, float]:
    """
    Calculate the funding rate at which strategy becomes unprofitable
    """
    # Net income needed to cover costs
    costs = trading_fee_apr + gas_apr + slippage_apr
    breakeven_funding_apr = costs - staking_apr
    
    # Convert to 8h rate
    breakeven_funding_8h = breakeven_funding_apr / 1095  # 3 per day * 365 days
    
    return {
        'breakeven_funding_apr': breakeven_funding_apr,
        'breakeven_funding_apr_percentage': breakeven_funding_apr * 100,
        'breakeven_funding_8h': breakeven_funding_8h,
        'breakeven_funding_8h_percentage': breakeven_funding_8h * 100,
        'description': 'Funding rate at which net APR = 0'
    }


def compare_delta_neutral_scenarios(
    staked_amount: float,
    staking_apr: float,
    flow_price: float,
    funding_rates_8h: List[float],
    spot_liquidity_usd: float = None,
    perp_liquidity_usd: float = None
) -> Dict[str, Any]:
    """
    Compare net APR across different funding rate scenarios
    """
    scenarios = {}
    
    for i, funding_rate in enumerate(funding_rates_8h):
        scenario_name = f"funding_{funding_rate*10000:.0f}_bps"  # basis points
        
        result = calculate_net_delta_neutral_apr(
            staked_amount=staked_amount,
            staking_apr=staking_apr,
            flow_price=flow_price,
            perp_size=staked_amount,  # Assume perfect hedge
            perp_price=flow_price,
            funding_rate_8h=funding_rate,
            spot_liquidity_usd=spot_liquidity_usd,
            perp_liquidity_usd=perp_liquidity_usd
        )
        
        scenarios[scenario_name] = {
            'funding_rate_8h': funding_rate,
            'funding_rate_8h_percentage': funding_rate * 100,
            'net_apr': result['net_results']['net_apr'],
            'net_apr_percentage': result['net_results']['net_apr_percentage'],
            'is_profitable': result['net_results']['is_profitable']
        }
    
    return {
        'scenarios': scenarios,
        'best_scenario': max(scenarios.items(), key=lambda x: x[1]['net_apr']),
        'worst_scenario': min(scenarios.items(), key=lambda x: x[1]['net_apr'])
    }


# Example usage
if __name__ == '__main__':
    # Example calculation
    result = calculate_net_delta_neutral_apr(
        staked_amount=10000,  # 10k FLOW staked
        staking_apr=0.15,  # 15% staking APR
        flow_price=0.75,  # $0.75 per FLOW
        perp_size=10000,  # 10k FLOW short
        perp_price=0.75,
        funding_rate_8h=0.0001,  # 0.01% per 8h (positive = shorts receive)
        spot_liquidity_usd=3000000,  # $3M DEX liquidity
        perp_liquidity_usd=10000000,  # $10M perp liquidity
        rebalance_frequency_per_year=12,  # Monthly
        basis=0.005  # $0.005 basis
    )
    
    import json
    print(json.dumps(result, indent=2))