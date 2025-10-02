"""
Simple Staking Position Calculations
For non-leveraged staking positions
"""
from typing import Dict, Any

def calculate_staking_returns(
    staked_amount: float,
    stflow_amount: float,
    staking_apr: float,
    flow_price: float,
    stflow_price: float,
    time_period_days: float = 365
) -> Dict[str, Any]:
    """
    Calculate returns for simple staking position
    """
    # Current value
    staked_value = staked_amount * flow_price
    stflow_value = stflow_amount * stflow_price
    
    # Expected yield
    time_factor = time_period_days / 365
    expected_yield_tokens = staked_amount * staking_apr * time_factor
    expected_yield_usd = expected_yield_tokens * flow_price
    
    # APY (compounding)
    compounds_per_year = 365  # Daily compounding
    apy = (1 + staking_apr / compounds_per_year) ** compounds_per_year - 1
    
    return {
        'staked_amount': staked_amount,
        'stflow_amount': stflow_amount,
        'staked_value_usd': staked_value,
        'stflow_value_usd': stflow_value,
        'staking_apr': staking_apr,
        'staking_apr_percentage': staking_apr * 100,
        'staking_apy': apy,
        'staking_apy_percentage': apy * 100,
        'expected_yield_tokens': expected_yield_tokens,
        'expected_yield_usd': expected_yield_usd,
        'time_period_days': time_period_days
    }

def calculate_staking_peg_risk(
    stflow_price: float,
    flow_price: float
) -> Dict[str, Any]:
    """
    Calculate peg risk for stFLOW/FLOW
    """
    ratio = stflow_price / flow_price if flow_price > 0 else 0
    depeg = (ratio - 1.0) * 100
    
    return {
        'stflow_price': stflow_price,
        'flow_price': flow_price,
        'ratio': ratio,
        'depeg_percentage': depeg,
        'is_depegged': abs(depeg) > 2,
        'risk_level': 'HIGH' if abs(depeg) > 5 else 'MEDIUM' if abs(depeg) > 2 else 'LOW'
    }

def calculate_unstaking_risk(
    staked_amount: float,
    flow_price: float,
    unstaking_period_days: int = 7,
    price_volatility: float = 0.5
) -> Dict[str, Any]:
    """
    Calculate risk during unstaking period
    """
    # Potential price movement during unstaking
    time_factor = (unstaking_period_days / 365) ** 0.5
    expected_volatility = price_volatility * time_factor
    
    # Value at risk (2 std dev)
    position_value = staked_amount * flow_price
    value_at_risk_2sd = position_value * expected_volatility * 2
    
    return {
        'staked_amount': staked_amount,
        'position_value_usd': position_value,
        'unstaking_period_days': unstaking_period_days,
        'expected_volatility': expected_volatility,
        'expected_volatility_percentage': expected_volatility * 100,
        'value_at_risk_2sd_usd': value_at_risk_2sd,
        'value_at_risk_percentage': (value_at_risk_2sd / position_value * 100) if position_value > 0 else 0,
        'risk_level': 'HIGH' if expected_volatility > 0.2 else 'MEDIUM' if expected_volatility > 0.1 else 'LOW'
    }

def calculate_opportunity_cost(
    staking_apr: float,
    alternative_yield: float,
    staked_amount: float,
    flow_price: float,
    time_period_days: float = 365
) -> Dict[str, Any]:
    """
    Calculate opportunity cost vs alternative investments
    """
    position_value = staked_amount * flow_price
    time_factor = time_period_days / 365
    
    # Yields
    staking_yield = position_value * staking_apr * time_factor
    alternative_yield_amount = position_value * alternative_yield * time_factor
    
    # Opportunity cost
    opportunity_cost = alternative_yield_amount - staking_yield
    
    return {
        'staking_apr': staking_apr,
        'staking_apr_percentage': staking_apr * 100,
        'alternative_apr': alternative_yield,
        'alternative_apr_percentage': alternative_yield * 100,
        'staking_yield_usd': staking_yield,
        'alternative_yield_usd': alternative_yield_amount,
        'opportunity_cost_usd': opportunity_cost,
        'is_optimal': opportunity_cost <= 0,
        'time_period_days': time_period_days
    }

def calculate_all_staking_metrics(
    staked_amount: float,
    stflow_amount: float,
    staking_apr: float,
    flow_price: float,
    stflow_price: float,
    price_volatility: float = 0.5,
    unstaking_period_days: int = 7,
    alternative_yield: float = 0.05
) -> Dict[str, Any]:
    """
    Calculate all metrics for simple staking position
    """
    returns = calculate_staking_returns(
        staked_amount, stflow_amount, staking_apr,
        flow_price, stflow_price
    )
    
    peg_risk = calculate_staking_peg_risk(stflow_price, flow_price)
    
    unstaking_risk = calculate_unstaking_risk(
        staked_amount, flow_price, unstaking_period_days, price_volatility
    )
    
    opp_cost = calculate_opportunity_cost(
        staking_apr, alternative_yield, staked_amount, flow_price
    )
    
    return {
        'returns_analysis': returns,
        'peg_risk': peg_risk,
        'unstaking_risk': unstaking_risk,
        'opportunity_cost_analysis': opp_cost,
        'overall_recommendation': 'HOLD' if opp_cost['is_optimal'] and not peg_risk['is_depegged'] else 'REVIEW'
    }