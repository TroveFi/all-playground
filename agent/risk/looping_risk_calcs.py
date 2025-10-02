"""
Looping Position Risk Calculations
Calculate risk metrics for leveraged staking loops
"""
import math
from scipy.stats import norm
from typing import Dict, Any

def calculate_looping_health_factor(
    total_stflow: float,
    stflow_price: float,
    total_borrowed_flow: float,
    flow_price: float,
    liquidation_threshold: float
) -> float:
    """
    Calculate health factor for looping position
    HF = (Collateral * Price * Liquidation Threshold) / (Borrowed * Price)
    HF < 1.0 means position can be liquidated
    """
    collateral_value = total_stflow * stflow_price * liquidation_threshold
    debt_value = total_borrowed_flow * flow_price
    
    if debt_value == 0:
        return float('inf')
    
    return collateral_value / debt_value

def calculate_liquidation_price(
    total_stflow: float,
    total_borrowed_flow: float,
    liquidation_threshold: float,
    flow_price: float
) -> float:
    """
    Calculate stFLOW/FLOW price ratio at which liquidation occurs
    Liquidation when: stFLOW_value * liq_threshold = borrowed_FLOW_value
    """
    if total_stflow == 0:
        return 0.0
    
    # Price ratio at liquidation
    liquidation_ratio = total_borrowed_flow / (total_stflow * liquidation_threshold)
    
    # Convert to stFLOW price in USD terms
    liquidation_stflow_price = liquidation_ratio * flow_price
    
    return liquidation_stflow_price

def calculate_lst_discount_risk(
    stflow_price: float,
    flow_price: float,
    expected_peg: float = 1.0
) -> Dict[str, float]:
    """
    Calculate LST (Liquid Staking Token) discount/premium
    """
    actual_ratio = stflow_price / flow_price if flow_price > 0 else 0
    discount = expected_peg - actual_ratio
    discount_pct = discount / expected_peg if expected_peg > 0 else 0
    
    return {
        'stflow_flow_ratio': actual_ratio,
        'expected_ratio': expected_peg,
        'discount': discount,
        'discount_percentage': discount_pct * 100,
        'is_depeg': abs(discount_pct) > 0.02  # 2% threshold for depeg warning
    }

def calculate_probability_of_default(
    current_health_factor: float,
    price_volatility: float,
    time_horizon_days: float = 30
) -> float:
    """
    Calculate probability of default using Gaussian model
    Assumes log-normal price distribution
    
    PD = Phi(-d) where d = ln(HF) / (volatility * sqrt(time))
    """
    if current_health_factor <= 0:
        return 1.0
    
    if current_health_factor >= 100:  # Extremely safe position
        return 0.0
    
    # Convert volatility to daily if annual, and scale by time horizon
    time_in_years = time_horizon_days / 365
    volatility_adjusted = price_volatility * math.sqrt(time_in_years)
    
    if volatility_adjusted == 0:
        return 0.0
    
    # Distance to default
    d = math.log(current_health_factor) / volatility_adjusted
    
    # Probability that HF drops below 1.0
    prob_default = norm.cdf(-d)
    
    return prob_default

def calculate_borrow_rate_risk(
    current_borrow_rate: float,
    staking_apr: float,
    leverage: float
) -> Dict[str, Any]:
    """
    Calculate borrow rate risk metrics
    """
    # Net APR after borrowing costs
    net_apr = staking_apr * leverage - current_borrow_rate * (leverage - 1)
    
    # Break-even borrow rate (where net APR = 0)
    if leverage > 1:
        breakeven_rate = staking_apr * leverage / (leverage - 1)
    else:
        breakeven_rate = float('inf')
    
    # Rate cushion
    rate_cushion = breakeven_rate - current_borrow_rate if breakeven_rate != float('inf') else float('inf')
    
    return {
        'net_apr': net_apr,
        'breakeven_borrow_rate': breakeven_rate,
        'rate_cushion': rate_cushion,
        'rate_cushion_percentage': (rate_cushion / current_borrow_rate * 100) if current_borrow_rate > 0 else float('inf'),
        'is_profitable': net_apr > 0
    }

def calculate_slippage_risk(
    position_size_usd: float,
    liquidity_usd: float,
    slippage_model: str = 'linear'
) -> Dict[str, float]:
    """
    Estimate slippage for unwinding position
    """
    if liquidity_usd == 0:
        return {'estimated_slippage': float('inf'), 'is_high_risk': True}
    
    # Position size as percentage of liquidity
    size_ratio = position_size_usd / liquidity_usd
    
    if slippage_model == 'linear':
        # Simple linear model: 1% slippage per 10% of liquidity
        estimated_slippage = size_ratio * 0.1
    elif slippage_model == 'square_root':
        # Square root model (more realistic for AMMs)
        estimated_slippage = 2 * (math.sqrt(1 + size_ratio) - 1)
    else:
        estimated_slippage = size_ratio * 0.1
    
    return {
        'position_to_liquidity_ratio': size_ratio,
        'estimated_slippage_percentage': estimated_slippage * 100,
        'is_high_risk': size_ratio > 0.1  # >10% of liquidity
    }

def calculate_parameter_sensitivity(
    base_health_factor: float,
    stflow_price_change_pct: float = 0.05
) -> Dict[str, float]:
    """
    Calculate sensitivity to parameter changes
    Shows how much HF changes with 5% price movement
    """
    # For a looping position, approximate sensitivity
    # HF changes roughly linearly with collateral price for small changes
    
    hf_change = base_health_factor * stflow_price_change_pct
    
    return {
        'base_health_factor': base_health_factor,
        'price_change_pct': stflow_price_change_pct * 100,
        'hf_change': hf_change,
        'hf_after_change': base_health_factor + hf_change,
        'sensitivity': hf_change / stflow_price_change_pct  # Delta HF per 1% price change
    }

def calculate_all_looping_risks(
    total_stflow: float,
    stflow_price: float,
    total_borrowed_flow: float,
    flow_price: float,
    liquidation_threshold: float,
    staking_apr: float,
    borrow_rate: float,
    price_volatility: float,
    initial_flow: float,
    dex_liquidity_usd: float = None,
    time_horizon_days: float = 30
) -> Dict[str, Any]:
    """
    Calculate all risk metrics for a looping position
    """
    # Calculate effective leverage
    collateral_value = total_stflow * stflow_price
    debt_value = total_borrowed_flow * flow_price
    initial_value = initial_flow * flow_price
    leverage = collateral_value / initial_value if initial_value > 0 else 1.0
    
    # Health Factor
    hf = calculate_looping_health_factor(
        total_stflow, stflow_price, total_borrowed_flow, flow_price, liquidation_threshold
    )
    
    # Liquidation Price
    liq_price = calculate_liquidation_price(
        total_stflow, total_borrowed_flow, liquidation_threshold, flow_price
    )
    
    # LST Discount
    lst_risk = calculate_lst_discount_risk(stflow_price, flow_price)
    
    # Probability of Default
    pd = calculate_probability_of_default(hf, price_volatility, time_horizon_days)
    
    # Borrow Rate Risk
    borrow_risk = calculate_borrow_rate_risk(borrow_rate, staking_apr, leverage)
    
    # Slippage Risk
    if dex_liquidity_usd:
        slippage_risk = calculate_slippage_risk(collateral_value, dex_liquidity_usd)
    else:
        slippage_risk = {'warning': 'No liquidity data provided'}
    
    # Parameter Sensitivity
    sensitivity = calculate_parameter_sensitivity(hf)
    
    return {
        'position_summary': {
            'collateral_value_usd': collateral_value,
            'debt_value_usd': debt_value,
            'net_value_usd': collateral_value - debt_value,
            'leverage': leverage,
            'ltv': debt_value / collateral_value if collateral_value > 0 else 0
        },
        'health_factor': hf,
        'liquidation_stflow_price': liq_price,
        'liquidation_price_distance_pct': ((stflow_price - liq_price) / stflow_price * 100) if stflow_price > 0 else 0,
        'lst_discount_risk': lst_risk,
        'probability_of_default': {
            'probability': pd,
            'probability_percentage': pd * 100,
            'time_horizon_days': time_horizon_days,
            'risk_level': 'HIGH' if pd > 0.1 else 'MEDIUM' if pd > 0.01 else 'LOW'
        },
        'borrow_rate_risk': borrow_risk,
        'slippage_risk': slippage_risk,
        'parameter_sensitivity': sensitivity,
        'overall_risk_level': 'HIGH' if hf < 1.2 or pd > 0.1 else 'MEDIUM' if hf < 1.5 or pd > 0.01 else 'LOW'
    }