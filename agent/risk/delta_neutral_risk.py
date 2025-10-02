"""
Delta Neutral Position Risk Calculations
For staking + perp short strategy
"""
import math
from typing import Dict, Any

def calculate_delta_exposure(
    staked_flow: float,
    perp_short_size: float
) -> Dict[str, Any]:
    """
    Calculate net delta exposure
    Perfect hedge = staked amount == short size
    """
    net_delta = staked_flow - perp_short_size
    hedge_ratio = perp_short_size / staked_flow if staked_flow > 0 else 0
    
    return {
        'staked_flow': staked_flow,
        'perp_short_size': perp_short_size,
        'net_delta_exposure': net_delta,
        'hedge_ratio': hedge_ratio,
        'is_perfectly_hedged': abs(hedge_ratio - 1.0) < 0.01,  # Within 1%
        'hedge_drift_percentage': (1 - hedge_ratio) * 100
    }

def calculate_perp_liquidation_risk(
    perp_size: float,
    perp_entry_price: float,
    perp_current_price: float,
    perp_margin: float,
    perp_leverage: float,
    maintenance_margin_ratio: float
) -> Dict[str, Any]:
    """
    Calculate liquidation risk for perpetual short position
    """
    # PnL on short position (negative when price goes up)
    pnl = perp_size * (perp_entry_price - perp_current_price)
    pnl_percentage = (perp_entry_price - perp_current_price) / perp_entry_price if perp_entry_price > 0 else 0
    
    # Current margin ratio
    position_value = perp_size * perp_current_price
    current_equity = perp_margin + pnl
    current_margin_ratio = current_equity / position_value if position_value > 0 else 0
    
    # Liquidation price (for short: price where margin ratio = maintenance ratio)
    # maintenance_margin = position_value * maintenance_margin_ratio
    # equity = margin + size * (entry_price - liq_price)
    # liq_price = entry_price - (margin - position_value * maintenance_margin_ratio) / size
    
    liquidation_price = perp_entry_price + (perp_margin / perp_size) - (maintenance_margin_ratio * perp_current_price)
    
    # Distance to liquidation
    price_to_liquidation = liquidation_price - perp_current_price
    distance_to_liq_pct = price_to_liquidation / perp_current_price * 100 if perp_current_price > 0 else 0
    
    return {
        'perp_pnl': pnl,
        'perp_pnl_percentage': pnl_percentage * 100,
        'current_margin_ratio': current_margin_ratio,
        'maintenance_margin_ratio': maintenance_margin_ratio,
        'margin_cushion': current_margin_ratio - maintenance_margin_ratio,
        'liquidation_price': liquidation_price,
        'distance_to_liquidation_pct': distance_to_liq_pct,
        'risk_level': 'HIGH' if distance_to_liq_pct < 10 else 'MEDIUM' if distance_to_liq_pct < 20 else 'LOW'
    }

def calculate_basis_risk(
    perp_price: float,
    spot_price: float,
    funding_rate: float
) -> Dict[str, Any]:
    """
    Calculate basis risk (perp/spot price difference)
    """
    basis = perp_price - spot_price
    basis_percentage = (basis / spot_price * 100) if spot_price > 0 else 0
    
    # Annualized funding rate impact (funding typically paid 3x per day)
    funding_rate_annual = funding_rate * 365 * 3  # 3 funding periods per day
    
    return {
        'perp_price': perp_price,
        'spot_price': spot_price,
        'basis': basis,
        'basis_percentage': basis_percentage,
        'funding_rate_8h': funding_rate,
        'funding_rate_annual': funding_rate_annual,
        'funding_rate_annual_percentage': funding_rate_annual * 100,
        'is_contango': basis > 0,
        'basis_risk_level': 'HIGH' if abs(basis_percentage) > 5 else 'MEDIUM' if abs(basis_percentage) > 2 else 'LOW'
    }

def calculate_peg_risk(
    stflow_price: float,
    flow_price: float,
    expected_ratio: float = 1.0
) -> Dict[str, Any]:
    """
    Calculate stFLOW/FLOW peg risk
    """
    actual_ratio = stflow_price / flow_price if flow_price > 0 else 0
    depeg_percentage = (actual_ratio - expected_ratio) / expected_ratio * 100 if expected_ratio > 0 else 0
    
    return {
        'stflow_price': stflow_price,
        'flow_price': flow_price,
        'stflow_flow_ratio': actual_ratio,
        'expected_ratio': expected_ratio,
        'depeg_percentage': depeg_percentage,
        'is_depegged': abs(depeg_percentage) > 2,  # 2% threshold
        'peg_risk_level': 'HIGH' if abs(depeg_percentage) > 5 else 'MEDIUM' if abs(depeg_percentage) > 2 else 'LOW'
    }

def calculate_hedge_rebalance_need(
    staked_flow: float,
    perp_short_size: float,
    rebalance_threshold: float = 0.05
) -> Dict[str, Any]:
    """
    Determine if hedge needs rebalancing
    """
    delta_calc = calculate_delta_exposure(staked_flow, perp_short_size)
    hedge_drift = abs(delta_calc['hedge_ratio'] - 1.0)
    
    needs_rebalance = hedge_drift > rebalance_threshold
    
    if needs_rebalance:
        # Calculate required adjustment
        target_short_size = staked_flow
        adjustment_needed = target_short_size - perp_short_size
    else:
        adjustment_needed = 0
    
    return {
        'current_hedge_ratio': delta_calc['hedge_ratio'],
        'hedge_drift': hedge_drift,
        'hedge_drift_percentage': hedge_drift * 100,
        'rebalance_threshold': rebalance_threshold,
        'needs_rebalance': needs_rebalance,
        'adjustment_needed_flow': adjustment_needed,
        'target_short_size': staked_flow
    }

def calculate_execution_liquidity_risk(
    position_size_usd: float,
    spot_liquidity_usd: float,
    perp_liquidity_usd: float
) -> Dict[str, Any]:
    """
    Calculate DEX/execution liquidity risk
    """
    spot_ratio = position_size_usd / spot_liquidity_usd if spot_liquidity_usd > 0 else float('inf')
    perp_ratio = position_size_usd / perp_liquidity_usd if perp_liquidity_usd > 0 else float('inf')
    
    # Estimate slippage (simplified model)
    spot_slippage = min(spot_ratio * 0.1, 0.5) * 100  # Cap at 50%
    perp_slippage = min(perp_ratio * 0.05, 0.3) * 100  # Perps typically more liquid
    
    return {
        'position_size_usd': position_size_usd,
        'spot_liquidity_usd': spot_liquidity_usd,
        'perp_liquidity_usd': perp_liquidity_usd,
        'spot_position_to_liquidity': spot_ratio,
        'perp_position_to_liquidity': perp_ratio,
        'estimated_spot_slippage_pct': spot_slippage,
        'estimated_perp_slippage_pct': perp_slippage,
        'total_estimated_slippage_pct': spot_slippage + perp_slippage,
        'liquidity_risk_level': 'HIGH' if max(spot_ratio, perp_ratio) > 0.2 else 'MEDIUM' if max(spot_ratio, perp_ratio) > 0.1 else 'LOW'
    }

def calculate_delta_neutral_apr(
    staking_apr: float,
    funding_rate_annual: float,
    perp_trading_fees: float = 0.0005,
    gas_costs_annual_usd: float = 0,
    position_size_usd: float = 1
) -> Dict[str, Any]:
    """
    Calculate net APR for delta neutral strategy
    APR = Staking APR - Funding Rate - Fees
    """
    # Net APR components
    staking_yield = staking_apr
    funding_cost = funding_rate_annual  # Negative if you receive funding
    
    # Annualized trading fees (assuming periodic rebalancing)
    estimated_trades_per_year = 12  # Monthly rebalancing
    trading_fees_annual = perp_trading_fees * estimated_trades_per_year
    
    # Gas costs as percentage of position
    gas_cost_percentage = gas_costs_annual_usd / position_size_usd if position_size_usd > 0 else 0
    
    # Total costs
    total_costs = abs(funding_cost) + trading_fees_annual + gas_cost_percentage
    
    # Net APR
    net_apr = staking_yield - total_costs
    
    return {
        'staking_apr': staking_apr,
        'staking_apr_percentage': staking_apr * 100,
        'funding_rate_annual': funding_rate_annual,
        'funding_rate_annual_percentage': funding_rate_annual * 100,
        'trading_fees_annual': trading_fees_annual,
        'trading_fees_percentage': trading_fees_annual * 100,
        'gas_costs_annual_percentage': gas_cost_percentage * 100,
        'total_costs': total_costs,
        'total_costs_percentage': total_costs * 100,
        'net_apr': net_apr,
        'net_apr_percentage': net_apr * 100,
        'is_profitable': net_apr > 0
    }

def calculate_all_delta_neutral_risks(
    staked_flow: float,
    stflow_price: float,
    staking_apr: float,
    perp_size: float,
    perp_entry_price: float,
    perp_current_price: float,
    perp_margin: float,
    perp_leverage: float,
    perp_maintenance_margin_ratio: float,
    perp_funding_rate: float,
    flow_price: float,
    spot_liquidity_usd: float = None,
    perp_liquidity_usd: float = None
) -> Dict[str, Any]:
    """
    Calculate all risk metrics for delta neutral position
    """
    # Delta exposure
    delta = calculate_delta_exposure(staked_flow, perp_size)
    
    # Perp liquidation risk
    perp_liq = calculate_perp_liquidation_risk(
        perp_size, perp_entry_price, perp_current_price,
        perp_margin, perp_leverage, perp_maintenance_margin_ratio
    )
    
    # Basis risk
    basis = calculate_basis_risk(perp_current_price, flow_price, perp_funding_rate)
    
    # Peg risk
    peg = calculate_peg_risk(stflow_price, flow_price)
    
    # Rebalance need
    rebalance = calculate_hedge_rebalance_need(staked_flow, perp_size)
    
    # Liquidity risk
    position_value = staked_flow * flow_price
    if spot_liquidity_usd and perp_liquidity_usd:
        liquidity = calculate_execution_liquidity_risk(
            position_value, spot_liquidity_usd, perp_liquidity_usd
        )
    else:
        liquidity = {'warning': 'No liquidity data provided'}
    
    # APR calculation
    apr = calculate_delta_neutral_apr(
        staking_apr, basis['funding_rate_annual'],
        position_size_usd=position_value
    )
    
    # Overall risk assessment
    risk_factors = []
    if not delta['is_perfectly_hedged']:
        risk_factors.append('Hedge drift detected')
    if perp_liq['risk_level'] in ['HIGH', 'MEDIUM']:
        risk_factors.append('Perp liquidation risk')
    if basis['basis_risk_level'] == 'HIGH':
        risk_factors.append('High basis risk')
    if peg['is_depegged']:
        risk_factors.append('stFLOW depeg detected')
    
    overall_risk = 'HIGH' if len(risk_factors) >= 2 else 'MEDIUM' if len(risk_factors) == 1 else 'LOW'
    
    return {
        'position_summary': {
            'staked_flow': staked_flow,
            'perp_short_size': perp_size,
            'position_value_usd': position_value,
            'perp_margin_usd': perp_margin
        },
        'delta_exposure': delta,
        'perp_liquidation_risk': perp_liq,
        'basis_risk': basis,
        'peg_risk': peg,
        'rebalance_analysis': rebalance,
        'liquidity_risk': liquidity,
        'apr_analysis': apr,
        'overall_risk_level': overall_risk,
        'risk_factors': risk_factors
    }