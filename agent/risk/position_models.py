"""
Position Data Models
Define data structures for different position types
"""
from dataclasses import dataclass
from typing import Optional

@dataclass
class StakingPosition:
    """Simple staking position"""
    staked_amount: float  # Amount of FLOW staked
    stflow_amount: float  # Amount of stFLOW received
    staking_apr: float  # Current staking APR (decimal, e.g., 0.15 for 15%)
    flow_price: float  # Current FLOW price in USD
    stflow_price: float  # Current stFLOW price in USD

@dataclass
class LoopingPosition:
    """Leveraged staking loop position"""
    initial_flow: float  # Initial FLOW deposited
    total_staked_flow: float  # Total FLOW staked across loops
    total_stflow: float  # Total stFLOW held as collateral
    total_borrowed_flow: float  # Total FLOW borrowed
    loop_count: int  # Number of loops executed
    
    # Market data
    flow_price: float  # Current FLOW price in USD
    stflow_price: float  # Current stFLOW price in USD
    staking_apr: float  # Staking APR (decimal)
    borrow_rate: float  # Borrow APR (decimal)
    
    # Protocol parameters
    collateral_factor: float  # Max LTV (decimal, e.g., 0.8 for 80%)
    liquidation_threshold: float  # Liquidation LTV (decimal, e.g., 0.85 for 85%)
    liquidation_penalty: float  # Liquidation penalty (decimal, e.g., 0.05 for 5%)
    
    # DEX liquidity (optional for slippage calculations)
    dex_liquidity_usd: Optional[float] = None

@dataclass
class DeltaNeutralPosition:
    """Delta neutral position: staking + short perp"""
    # Staking side
    staked_flow: float
    stflow_amount: float
    staking_apr: float
    
    # Perpetual short side
    perp_size: float  # Size of short position in FLOW
    perp_entry_price: float  # Entry price of short
    perp_current_price: float  # Current mark price
    perp_funding_rate: float  # Current funding rate (decimal, annualized)
    perp_leverage: float  # Leverage used on perp
    perp_margin: float  # Margin posted for perp
    perp_maintenance_margin_ratio: float  # Maintenance margin requirement
    
    # Market data
    flow_price: float  # Spot FLOW price
    stflow_price: float  # stFLOW price
    basis: float  # Perp price - Spot price
    
    # Liquidity
    perp_liquidity_usd: Optional[float] = None
    spot_liquidity_usd: Optional[float] = None

@dataclass
class MarketData:
    """General market data needed across calculations"""
    flow_price: float
    stflow_price: float
    flow_volatility: float  # Annualized volatility (decimal)
    stflow_flow_correlation: float  # Correlation coefficient
    risk_free_rate: float = 0.0  # Risk-free rate for calculations