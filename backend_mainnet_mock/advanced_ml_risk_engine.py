#!/usr/bin/env python3
"""
Advanced ML Risk Assessment Engine for Flow EVM Protocols
Uses real historical data and sophisticated models for production-grade risk analysis
"""

import pandas as pd
import numpy as np
from sklearn.ensemble import IsolationForest, RandomForestRegressor, GradientBoostingRegressor
from sklearn.preprocessing import StandardScaler, RobustScaler
from sklearn.decomposition import PCA
from sklearn.cluster import DBSCAN
from sklearn.metrics import classification_report, mean_squared_error
import joblib
import warnings
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple, Any
import logging
from dataclasses import dataclass, asdict
import sqlite3
import asyncio
import aiohttp
import json
from scipy import stats
import matplotlib.pyplot as plt
import seaborn as sns

warnings.filterwarnings('ignore')

@dataclass
class ProtocolRiskProfile:
    """Comprehensive risk profile for a protocol"""
    protocol_name: str
    overall_risk_score: float  # 0-1 scale
    smart_contract_risk: float
    liquidity_risk: float
    market_risk: float
    operational_risk: float
    regulatory_risk: float
    
    # Quantitative metrics
    value_at_risk_1d: float  # 1-day VaR at 95% confidence
    value_at_risk_7d: float  # 7-day VaR at 95% confidence
    expected_shortfall: float  # Expected loss beyond VaR
    max_drawdown_historical: float
    volatility_30d: float
    sharpe_ratio: float
    sortino_ratio: float
    beta_to_market: float
    
    # ML-derived metrics
    anomaly_score: float  # Isolation Forest score
    default_probability: float  # ML predicted default risk
    return_prediction: float  # ML predicted returns
    confidence_interval: Tuple[float, float]  # CI for predictions
    
    # Time-based analysis
    risk_trend: str  # "increasing", "stable", "decreasing"
    stress_test_results: Dict[str, float]
    
    # Metadata
    last_updated: datetime
    data_quality_score: float
    model_version: str

@dataclass
class HistoricalEvent:
    """Historical protocol event for learning"""
    protocol: str
    event_date: datetime
    event_type: str  # "exploit", "rug_pull", "depegging", "governance_attack"
    severity: float  # 0-1 scale
    financial_impact: float  # USD lost
    recovery_time_days: int
    root_cause: str
    warning_signals: List[str]

class AdvancedRiskEngine:
    """Production ML risk engine with multiple sophisticated models"""
    
    def __init__(self, model_dir: str = "models"):
        self.model_dir = model_dir
        self.models = {}
        self.scalers = {}
        self.feature_importance = {}
        self.is_trained = False
        
        # Initialize models
        self._init_models()
        
    def _init_models(self):
        """Initialize ML models for different risk aspects"""
        
        # Anomaly detection for protocol behavior
        self.models['anomaly_detector'] = IsolationForest(
            contamination=0.1,
            random_state=42,
            n_estimators=200,
            max_features=0.8
        )
        
        # Default probability prediction
        self.models['default_predictor'] = GradientBoostingRegressor(
            n_estimators=200,
            learning_rate=0.1,
            max_depth=6,
            random_state=42
        )
        
        # Return prediction
        self.models['return_predictor'] = RandomForestRegressor(
            n_estimators=150,
            max_depth=10,
            random_state=42,
            n_jobs=-1
        )
        
        # Volatility prediction
        self.models['volatility_predictor'] = GradientBoostingRegressor(
            n_estimators=100,
            learning_rate=0.15,
            random_state=42
        )
        
        # Scalers for different feature types
        self.scalers['robust'] = RobustScaler()
        self.scalers['standard'] = StandardScaler()
        
        logging.info("Advanced ML models initialized")

    async def load_real_historical_data(self) -> pd.DataFrame:
        """Load real historical DeFi protocol data from multiple sources"""
        
        # Combine data from multiple sources
        all_data = []
        
        # 1. Load from DeFiLlama historical API
        defillama_data = await self._fetch_defillama_historical()
        all_data.append(defillama_data)
        
        # 2. Load from local database (stored real-time data)
        local_data = await self._load_local_historical_data()
        all_data.append(local_data)
        
        # 3. Load known exploit/incident data
        incident_data = await self._load_incident_data()
        
        # Combine and clean data
        combined_data = pd.concat([df for df in all_data if not df.empty], ignore_index=True)
        
        # Add incident flags
        combined_data = self._add_incident_flags(combined_data, incident_data)
        
        # Feature engineering
        combined_data = self._engineer_risk_features(combined_data)
        
        return combined_data

    async def _fetch_defillama_historical(self) -> pd.DataFrame:
        """Fetch real historical data from DeFiLlama"""
        try:
            async with aiohttp.ClientSession() as session:
                # Get pool list
                pools_url = "https://yields.llama.fi/pools"
                async with session.get(pools_url) as response:
                    if response.status == 200:
                        pools_data = await response.json()
                        
                        # Filter for Flow and similar chains
                        relevant_pools = [
                            pool for pool in pools_data.get('data', [])
                            if pool.get('chain', '').lower() in ['flow', 'ethereum', 'polygon']
                            and pool.get('tvlUsd', 0) > 100000  # Min $100k TVL
                        ]
                        
                        # Convert to DataFrame
                        df = pd.DataFrame(relevant_pools)
                        
                        # Get historical data for each pool
                        historical_data = []
                        for pool in relevant_pools[:50]:  # Limit for testing
                            pool_id = pool.get('pool')
                            if pool_id:
                                hist_data = await self._fetch_pool_history(session, pool_id)
                                if not hist_data.empty:
                                    historical_data.append(hist_data)
                        
                        if historical_data:
                            return pd.concat(historical_data, ignore_index=True)
                        
                return df if 'df' in locals() else pd.DataFrame()
                
        except Exception as e:
            logging.error(f"Error fetching DeFiLlama data: {e}")
            return pd.DataFrame()

    async def _fetch_pool_history(self, session: aiohttp.ClientSession, pool_id: str) -> pd.DataFrame:
        """Fetch historical data for a specific pool"""
        try:
            # DeFiLlama historical chart endpoint
            url = f"https://yields.llama.fi/chart/{pool_id}"
            async with session.get(url) as response:
                if response.status == 200:
                    data = await response.json()
                    
                    if 'data' in data and data['data']:
                        df = pd.DataFrame(data['data'])
                        df['pool_id'] = pool_id
                        df['timestamp'] = pd.to_datetime(df['timestamp'], unit='s')
                        return df
                        
        except Exception as e:
            logging.error(f"Error fetching pool {pool_id} history: {e}")
            
        return pd.DataFrame()

    async def _load_local_historical_data(self) -> pd.DataFrame:
        """Load historical data from local database"""
        try:
            # Connect to local SQLite database
            conn = sqlite3.connect("flow_data.db")
            
            query = """
                SELECT 
                    protocol,
                    timestamp,
                    tvl_usd,
                    supply_apy,
                    utilization_rate,
                    data_json
                FROM protocol_data
                WHERE timestamp > datetime('now', '-365 days')
                ORDER BY protocol, timestamp
            """
            
            df = pd.read_sql_query(query, conn)
            conn.close()
            
            if not df.empty:
                df['timestamp'] = pd.to_datetime(df['timestamp'])
                
                # Parse JSON data
                for idx, row in df.iterrows():
                    try:
                        json_data = json.loads(row['data_json'])
                        for key, value in json_data.items():
                            df.loc[idx, key] = value
                    except:
                        pass
                        
            return df
            
        except Exception as e:
            logging.error(f"Error loading local data: {e}")
            return pd.DataFrame()

    async def _load_incident_data(self) -> List[HistoricalEvent]:
        """Load known DeFi incident data for training"""
        
        # Real historical incidents (subset for demonstration)
        incidents = [
            HistoricalEvent(
                protocol="PolyNetwork",
                event_date=datetime(2021, 8, 10),
                event_type="exploit",
                severity=0.95,
                financial_impact=610_000_000,
                recovery_time_days=30,
                root_cause="smart_contract_bug",
                warning_signals=["unusual_transaction_patterns", "high_value_movements"]
            ),
            HistoricalEvent(
                protocol="Ronin",
                event_date=datetime(2022, 3, 23),
                event_type="governance_attack",
                severity=0.98,
                financial_impact=625_000_000,
                recovery_time_days=180,
                root_cause="private_key_compromise",
                warning_signals=["validator_concentration", "poor_security_practices"]
            ),
            HistoricalEvent(
                protocol="TerraLuna",
                event_date=datetime(2022, 5, 8),
                event_type="depegging",
                severity=0.99,
                financial_impact=60_000_000_000,
                recovery_time_days=999,  # Still not recovered
                root_cause="algorithmic_stablecoin_design",
                warning_signals=["high_mint_rate", "reserves_depletion", "bank_run_risk"]
            ),
            HistoricalEvent(
                protocol="FTX",
                event_date=datetime(2022, 11, 11),
                event_type="rug_pull",
                severity=1.0,
                financial_impact=8_000_000_000,
                recovery_time_days=999,
                root_cause="misappropriation_of_funds",
                warning_signals=["liquidity_issues", "poor_transparency", "regulatory_scrutiny"]
            )
        ]
        
        return incidents

    def _add_incident_flags(self, df: pd.DataFrame, incidents: List[HistoricalEvent]) -> pd.DataFrame:
        """Add incident flags to historical data"""
        
        # Add incident columns
        df['has_incident'] = False
        df['incident_severity'] = 0.0
        df['days_to_incident'] = 999
        df['incident_type'] = 'none'
        
        for incident in incidents:
            # Find protocols matching incident
            protocol_mask = df['protocol'].str.contains(incident.protocol, case=False, na=False)
            
            # Add incident window (30 days before incident)
            incident_window_start = incident.event_date - timedelta(days=30)
            incident_window_end = incident.event_date + timedelta(days=1)
            
            time_mask = (df['timestamp'] >= incident_window_start) & (df['timestamp'] <= incident_window_end)
            
            combined_mask = protocol_mask & time_mask
            
            df.loc[combined_mask, 'has_incident'] = True
            df.loc[combined_mask, 'incident_severity'] = incident.severity
            df.loc[combined_mask, 'incident_type'] = incident.event_type
            
            # Calculate days to incident
            for idx in df[protocol_mask].index:
                days_diff = (incident.event_date - df.loc[idx, 'timestamp']).days
                if 0 <= days_diff <= 30:  # Within warning window
                    df.loc[idx, 'days_to_incident'] = days_diff
        
        return df

    def _engineer_risk_features(self, df: pd.DataFrame) -> pd.DataFrame:
        """Engineer comprehensive risk features from raw data"""
        
        if df.empty:
            return df
        
        # Sort by protocol and timestamp
        df = df.sort_values(['protocol', 'timestamp'])
        
        # Basic features
        for protocol in df['protocol'].unique():
            protocol_mask = df['protocol'] == protocol
            protocol_data = df[protocol_mask].copy()
            
            if len(protocol_data) < 2:
                continue
                
            # Price and TVL based features
            if 'tvl_usd' in df.columns:
                df.loc[protocol_mask, 'tvl_change_1d'] = protocol_data['tvl_usd'].pct_change()
                df.loc[protocol_mask, 'tvl_change_7d'] = protocol_data['tvl_usd'].pct_change(periods=7)
                df.loc[protocol_mask, 'tvl_volatility_7d'] = protocol_data['tvl_usd'].rolling(7).std()
                df.loc[protocol_mask, 'tvl_trend'] = protocol_data['tvl_usd'].rolling(7).apply(lambda x: np.polyfit(range(len(x)), x, 1)[0])
            
            # APY based features
            if 'supply_apy' in df.columns:
                df.loc[protocol_mask, 'apy_change_1d'] = protocol_data['supply_apy'].pct_change()
                df.loc[protocol_mask, 'apy_volatility_7d'] = protocol_data['supply_apy'].rolling(7).std()
                df.loc[protocol_mask, 'apy_zscore'] = stats.zscore(protocol_data['supply_apy'])
            
            # Volume and activity features
            if 'volume_24h' in df.columns:
                df.loc[protocol_mask, 'volume_to_tvl'] = protocol_data['volume_24h'] / (protocol_data['tvl_usd'] + 1e-8)
                df.loc[protocol_mask, 'volume_trend'] = protocol_data['volume_24h'].rolling(7).apply(lambda x: np.polyfit(range(len(x)), x, 1)[0])
        
        # Cross-protocol features
        df['protocol_age_days'] = (df['timestamp'] - df.groupby('protocol')['timestamp'].transform('min')).dt.days
        df['market_dominance'] = df['tvl_usd'] / (df.groupby('timestamp')['tvl_usd'].transform('sum') + 1e-8)
        
        # Risk signal features
        df['extreme_apy'] = (df['supply_apy'] > 100) | (df['supply_apy'] < 0)  # Suspicious APYs
        df['rapid_tvl_growth'] = df['tvl_change_1d'] > 0.5  # >50% daily growth
        df['tvl_drain'] = df['tvl_change_1d'] < -0.3  # >30% daily loss
        df['low_liquidity'] = df['volume_to_tvl'] < 0.01  # <1% daily turnover
        
        # Technical indicators
        if 'tvl_usd' in df.columns:
            df['tvl_rsi'] = df.groupby('protocol')['tvl_usd'].transform(lambda x: self._calculate_rsi(x))
            df['tvl_macd'] = df.groupby('protocol')['tvl_usd'].transform(lambda x: self._calculate_macd(x))
        
        # Fill NaN values
        df = df.fillna(0)
        
        return df

    def _calculate_rsi(self, prices: pd.Series, window: int = 14) -> pd.Series:
        """Calculate Relative Strength Index"""
        delta = prices.diff()
        gain = (delta.where(delta > 0, 0)).rolling(window=window).mean()
        loss = (-delta.where(delta < 0, 0)).rolling(window=window).mean()
        rs = gain / loss
        rsi = 100 - (100 / (1 + rs))
        return rsi.fillna(50)

    def _calculate_macd(self, prices: pd.Series, fast: int = 12, slow: int = 26) -> pd.Series:
        """Calculate MACD indicator"""
        ema_fast = prices.ewm(span=fast).mean()
        ema_slow = prices.ewm(span=slow).mean()
        macd = ema_fast - ema_slow
        return macd.fillna(0)

    async def train_models(self, data: pd.DataFrame):
        """Train all ML models on historical data"""
        
        if data.empty:
            logging.error("No data available for training")
            return
        
        # Prepare features
        feature_columns = [
            'tvl_usd', 'supply_apy', 'utilization_rate', 'tvl_change_1d', 'tvl_change_7d',
            'tvl_volatility_7d', 'apy_change_1d', 'apy_volatility_7d', 'apy_zscore',
            'volume_to_tvl', 'protocol_age_days', 'market_dominance', 'tvl_rsi', 'tvl_macd',
            'extreme_apy', 'rapid_tvl_growth', 'tvl_drain', 'low_liquidity'
        ]
        
        # Filter available features
        available_features = [col for col in feature_columns if col in data.columns]
        X = data[available_features].fillna(0)
        
        # Scale features
        X_scaled = self.scalers['robust'].fit_transform(X)
        
        # Train anomaly detection
        logging.info("Training anomaly detection model...")
        self.models['anomaly_detector'].fit(X_scaled)
        
        # Train default prediction (using incident flags)
        if 'has_incident' in data.columns:
            y_default = data['has_incident'].astype(int)
            logging.info("Training default prediction model...")
            self.models['default_predictor'].fit(X_scaled, y_default)
        
        # Train return prediction
        if 'supply_apy' in data.columns:
            y_returns = data['supply_apy']
            logging.info("Training return prediction model...")
            self.models['return_predictor'].fit(X_scaled, y_returns)
        
        # Train volatility prediction
        if 'apy_volatility_7d' in data.columns:
            y_volatility = data['apy_volatility_7d'].fillna(0)
            logging.info("Training volatility prediction model...")
            self.models['volatility_predictor'].fit(X_scaled, y_volatility)
        
        # Store feature names
        self.feature_names = available_features
        
        # Calculate feature importance
        self._calculate_feature_importance()
        
        self.is_trained = True
        logging.info("All models trained successfully")

    def _calculate_feature_importance(self):
        """Calculate and store feature importance for each model"""
        
        for model_name, model in self.models.items():
            if hasattr(model, 'feature_importances_'):
                importance = model.feature_importances_
                self.feature_importance[model_name] = dict(zip(self.feature_names, importance))

    def assess_protocol_risk(self, protocol_data: Dict) -> ProtocolRiskProfile:
        """Comprehensive risk assessment using all models"""
        
        if not self.is_trained:
            logging.warning("Models not trained - using conservative estimates")
            return self._generate_fallback_risk_profile(protocol_data)
        
        # Prepare features
        features = self._prepare_features_for_prediction(protocol_data)
        X = np.array([features])
        X_scaled = self.scalers['robust'].transform(X)
        
        # Get predictions from all models
        anomaly_score = self.models['anomaly_detector'].decision_function(X_scaled)[0]
        anomaly_score_normalized = max(0, min(1, (0.5 - anomaly_score) / 2))
        
        try:
            default_prob = self.models['default_predictor'].predict(X_scaled)[0]
            default_prob = max(0, min(1, default_prob))
        except:
            default_prob = anomaly_score_normalized
        
        try:
            predicted_return = self.models['return_predictor'].predict(X_scaled)[0]
        except:
            predicted_return = protocol_data.get('apy', 5.0)
        
        try:
            predicted_volatility = self.models['volatility_predictor'].predict(X_scaled)[0]
        except:
            predicted_volatility = 0.15
        
        # Calculate risk components
        smart_contract_risk = self._assess_smart_contract_risk(protocol_data)
        liquidity_risk = self._assess_liquidity_risk(protocol_data)
        market_risk = self._assess_market_risk(protocol_data, predicted_volatility)
        operational_risk = default_prob
        regulatory_risk = 0.1  # Base regulatory risk
        
        # Overall risk score (weighted combination)
        overall_risk = (
            smart_contract_risk * 0.25 +
            liquidity_risk * 0.20 +
            market_risk * 0.20 +
            operational_risk * 0.25 +
            regulatory_risk * 0.10
        )
        
        # Calculate quantitative risk metrics
        risk_metrics = self._calculate_quantitative_risk_metrics(
            predicted_return, predicted_volatility, protocol_data
        )
        
        # Stress testing
        stress_results = self._perform_stress_tests(protocol_data, predicted_return, predicted_volatility)
        
        # Risk trend analysis
        risk_trend = self._analyze_risk_trend(protocol_data)
        
        return ProtocolRiskProfile(
            protocol_name=protocol_data.get('protocol', 'Unknown'),
            overall_risk_score=overall_risk,
            smart_contract_risk=smart_contract_risk,
            liquidity_risk=liquidity_risk,
            market_risk=market_risk,
            operational_risk=operational_risk,
            regulatory_risk=regulatory_risk,
            
            value_at_risk_1d=risk_metrics['var_1d'],
            value_at_risk_7d=risk_metrics['var_7d'],
            expected_shortfall=risk_metrics['expected_shortfall'],
            max_drawdown_historical=risk_metrics['max_drawdown'],
            volatility_30d=predicted_volatility,
            sharpe_ratio=risk_metrics['sharpe_ratio'],
            sortino_ratio=risk_metrics['sortino_ratio'],
            beta_to_market=risk_metrics['beta'],
            
            anomaly_score=anomaly_score_normalized,
            default_probability=default_prob,
            return_prediction=predicted_return,
            confidence_interval=(predicted_return * 0.8, predicted_return * 1.2),
            
            risk_trend=risk_trend,
            stress_test_results=stress_results,
            
            last_updated=datetime.now(),
            data_quality_score=self._assess_data_quality(protocol_data),
            model_version="v2.1.0"
        )

    def _prepare_features_for_prediction(self, protocol_data: Dict) -> List[float]:
        """Prepare features for ML prediction"""
        
        features = []
        for feature_name in self.feature_names:
            if feature_name in protocol_data:
                features.append(float(protocol_data[feature_name]))
            else:
                # Use default values for missing features
                defaults = {
                    'tvl_usd': 1000000,
                    'supply_apy': 5.0,
                    'utilization_rate': 0.7,
                    'tvl_change_1d': 0.0,
                    'tvl_change_7d': 0.0,
                    'tvl_volatility_7d': 0.1,
                    'apy_change_1d': 0.0,
                    'apy_volatility_7d': 1.0,
                    'apy_zscore': 0.0,
                    'volume_to_tvl': 0.1,
                    'protocol_age_days': 365,
                    'market_dominance': 0.01,
                    'tvl_rsi': 50,
                    'tvl_macd': 0,
                    'extreme_apy': 0,
                    'rapid_tvl_growth': 0,
                    'tvl_drain': 0,
                    'low_liquidity': 0
                }
                features.append(defaults.get(feature_name, 0.0))
        
        return features

    def _assess_smart_contract_risk(self, data: Dict) -> float:
        """Assess smart contract specific risks"""
        
        # Base risk factors
        base_risk = 0.2
        
        # Protocol age factor
        age_days = data.get('protocol_age_days', 0)
        if age_days < 30:
            age_risk = 0.4
        elif age_days < 180:
            age_risk = 0.3
        elif age_days < 365:
            age_risk = 0.2
        else:
            age_risk = 0.1
        
        # TVL size factor (larger TVL = more battle-tested)
        tvl = data.get('tvl_usd', 0)
        if tvl > 100_000_000:
            tvl_risk = 0.1
        elif tvl > 10_000_000:
            tvl_risk = 0.2
        elif tvl > 1_000_000:
            tvl_risk = 0.3
        else:
            tvl_risk = 0.4
        
        return min(0.9, base_risk + age_risk + tvl_risk) / 2

    def _assess_liquidity_risk(self, data: Dict) -> float:
        """Assess liquidity risks"""
        
        volume_to_tvl = data.get('volume_to_tvl', 0)
        
        if volume_to_tvl < 0.01:  # <1% daily turnover
            return 0.7
        elif volume_to_tvl < 0.05:  # <5% daily turnover
            return 0.4
        elif volume_to_tvl < 0.2:  # <20% daily turnover
            return 0.2
        else:
            return 0.1

    def _assess_market_risk(self, data: Dict, volatility: float) -> float:
        """Assess market-related risks"""
        
        # Base market risk from volatility
        vol_risk = min(0.5, volatility / 0.5)  # Normalize to 50% vol
        
        # Correlation risk (would use real market correlation)
        correlation_risk = 0.3  # Assume moderate correlation
        
        return (vol_risk + correlation_risk) / 2

    def _calculate_quantitative_risk_metrics(self, expected_return: float, 
                                           volatility: float, data: Dict) -> Dict:
        """Calculate comprehensive quantitative risk metrics"""
        
        # Convert to daily metrics
        daily_return = expected_return / 365 / 100
        daily_vol = volatility / np.sqrt(365)
        
        # Value at Risk (parametric)
        confidence_level = 0.05  # 95% confidence
        var_1d = -stats.norm.ppf(confidence_level) * daily_vol
        var_7d = var_1d * np.sqrt(7)
        
        # Expected Shortfall (CVaR)
        expected_shortfall = daily_vol * stats.norm.pdf(stats.norm.ppf(confidence_level)) / confidence_level
        
        # Simulate returns for more complex metrics
        returns = np.random.normal(daily_return, daily_vol, 252)  # 1 year of daily returns
        
        # Maximum Drawdown
        cumulative = np.cumprod(1 + returns)
        running_max = np.maximum.accumulate(cumulative)
        drawdown = (cumulative - running_max) / running_max
        max_drawdown = abs(np.min(drawdown)) * 100
        
        # Sharpe Ratio
        risk_free_rate = 0.02 / 365  # 2% annual risk-free rate
        excess_returns = returns - risk_free_rate
        sharpe_ratio = np.mean(excess_returns) / np.std(excess_returns) * np.sqrt(252) if np.std(excess_returns) > 0 else 0
        
        # Sortino Ratio (downside deviation)
        downside_returns = returns[returns < 0]
        downside_deviation = np.std(downside_returns) if len(downside_returns) > 0 else np.std(returns)
        sortino_ratio = np.mean(excess_returns) / downside_deviation * np.sqrt(252) if downside_deviation > 0 else 0
        
        # Beta (would use real market data)
        beta = 1.0  # Assume market beta for now
        
        return {
            'var_1d': var_1d * 100,
            'var_7d': var_7d * 100,
            'expected_shortfall': expected_shortfall * 100,
            'max_drawdown': max_drawdown,
            'sharpe_ratio': sharpe_ratio,
            'sortino_ratio': sortino_ratio,
            'beta': beta
        }

    def _perform_stress_tests(self, data: Dict, expected_return: float, volatility: float) -> Dict:
        """Perform various stress test scenarios"""
        
        stress_scenarios = {
            'market_crash_20': self._stress_test_market_crash(data, -0.20),
            'market_crash_50': self._stress_test_market_crash(data, -0.50),
            'liquidity_crisis': self._stress_test_liquidity_crisis(data),
            'high_volatility': self._stress_test_high_volatility(data, volatility * 3),
            'protocol_exploit': self._stress_test_protocol_exploit(data),
            'regulatory_shock': self._stress_test_regulatory_shock(data)
        }
        
        return stress_scenarios

    def _stress_test_market_crash(self, data: Dict, crash_magnitude: float) -> float:
        """Stress test for market crash scenario"""
        tvl = data.get('tvl_usd', 1000000)
        # Assume TVL drops proportionally to market
        stressed_tvl = tvl * (1 + crash_magnitude)
        loss_percentage = abs(stressed_tvl - tvl) / tvl * 100
        return min(100, loss_percentage)

    def _stress_test_liquidity_crisis(self, data: Dict) -> float:
        """Stress test for liquidity crisis"""
        volume_to_tvl = data.get('volume_to_tvl', 0.1)
        # If volume drops to 10% of normal
        stressed_liquidity = volume_to_tvl * 0.1
        if stressed_liquidity < 0.01:
            return 80.0  # High impact
        elif stressed_liquidity < 0.05:
            return 40.0  # Medium impact
        else:
            return 10.0  # Low impact

    def _stress_test_high_volatility(self, data: Dict, stressed_volatility: float) -> float:
        """Stress test for high volatility scenario"""
        # Higher volatility increases slippage and IL risk
        return min(100, stressed_volatility * 50)  # Convert to percentage impact

    def _stress_test_protocol_exploit(self, data: Dict) -> float:
        """Stress test for protocol exploit scenario"""
        tvl = data.get('tvl_usd', 1000000)
        smart_contract_risk = self._assess_smart_contract_risk(data)
        
        # Potential loss in exploit scenario
        potential_loss = tvl * smart_contract_risk
        loss_percentage = potential_loss / tvl * 100
        return loss_percentage

    def _stress_test_regulatory_shock(self, data: Dict) -> float:
        """Stress test for regulatory shock"""
        # Assume 30% impact on DeFi protocols
        return 30.0

    def _analyze_risk_trend(self, data: Dict) -> str:
        """Analyze risk trend direction"""
        
        # Simple trend analysis based on available data
        tvl_change_7d = data.get('tvl_change_7d', 0)
        apy_volatility = data.get('apy_volatility_7d', 0)
        
        if tvl_change_7d < -0.1 or apy_volatility > 5:
            return "increasing"
        elif tvl_change_7d > 0.1 and apy_volatility < 2:
            return "decreasing"
        else:
            return "stable"

    def _assess_data_quality(self, data: Dict) -> float:
        """Assess quality of input data"""
        
        required_fields = ['tvl_usd', 'supply_apy', 'volume_24h']
        available_fields = sum(1 for field in required_fields if field in data and data[field] is not None)
        
        base_quality = available_fields / len(required_fields)
        
        # Penalize for extreme values
        apy = data.get('supply_apy', 5)
        if apy > 1000 or apy < 0:
            base_quality *= 0.7
        
        tvl = data.get('tvl_usd', 0)
        if tvl <= 0:
            base_quality *= 0.5
        
        return max(0.1, base_quality)

    def _generate_fallback_risk_profile(self, data: Dict) -> ProtocolRiskProfile:
        """Generate conservative fallback risk profile when models unavailable"""
        
        return ProtocolRiskProfile(
            protocol_name=data.get('protocol', 'Unknown'),
            overall_risk_score=0.5,  # Medium risk
            smart_contract_risk=0.4,
            liquidity_risk=0.3,
            market_risk=0.4,
            operational_risk=0.3,
            regulatory_risk=0.2,
            
            value_at_risk_1d=5.0,
            value_at_risk_7d=15.0,
            expected_shortfall=7.5,
            max_drawdown_historical=25.0,
            volatility_30d=0.2,
            sharpe_ratio=1.0,
            sortino_ratio=1.2,
            beta_to_market=1.0,
            
            anomaly_score=0.5,
            default_probability=0.1,
            return_prediction=data.get('apy', 5.0),
            confidence_interval=(3.0, 7.0),
            
            risk_trend="stable",
            stress_test_results={
                'market_crash_20': 20.0,
                'market_crash_50': 50.0,
                'liquidity_crisis': 30.0,
                'high_volatility': 40.0,
                'protocol_exploit': 60.0,
                'regulatory_shock': 30.0
            },
            
            last_updated=datetime.now(),
            data_quality_score=0.7,
            model_version="fallback"
        )

    def save_models(self):
        """Save trained models to disk"""
        import os
        os.makedirs(self.model_dir, exist_ok=True)
        
        # Save models
        for name, model in self.models.items():
            joblib.dump(model, f"{self.model_dir}/{name}.joblib")
        
        # Save scalers
        for name, scaler in self.scalers.items():
            joblib.dump(scaler, f"{self.model_dir}/scaler_{name}.joblib")
        
        # Save metadata
        metadata = {
            'feature_names': self.feature_names,
            'feature_importance': self.feature_importance,
            'model_version': '2.1.0',
            'trained_at': datetime.now().isoformat()
        }
        
        with open(f"{self.model_dir}/metadata.json", 'w') as f:
            json.dump(metadata, f, indent=2)
        
        logging.info(f"Models saved to {self.model_dir}")

    def load_models(self):
        """Load trained models from disk"""
        try:
            # Load models
            for name in self.models.keys():
                model_path = f"{self.model_dir}/{name}.joblib"
                if os.path.exists(model_path):
                    self.models[name] = joblib.load(model_path)
            
            # Load scalers
            for name in self.scalers.keys():
                scaler_path = f"{self.model_dir}/scaler_{name}.joblib"
                if os.path.exists(scaler_path):
                    self.scalers[name] = joblib.load(scaler_path)
            
            # Load metadata
            metadata_path = f"{self.model_dir}/metadata.json"
            if os.path.exists(metadata_path):
                with open(metadata_path, 'r') as f:
                    metadata = json.load(f)
                    self.feature_names = metadata.get('feature_names', [])
                    self.feature_importance = metadata.get('feature_importance', {})
            
            self.is_trained = True
            logging.info(f"Models loaded from {self.model_dir}")
            
        except Exception as e:
            logging.error(f"Error loading models: {e}")
            self.is_trained = False

# Example usage and testing
async def main():
    """Test the advanced ML risk engine"""
    
    logging.basicConfig(level=logging.INFO)
    
    print("Initializing Advanced ML Risk Engine...")
    risk_engine = AdvancedRiskEngine()
    
    # Load and prepare training data
    print("Loading historical data for training...")
    historical_data = await risk_engine.load_real_historical_data()
    
    if not historical_data.empty:
        print(f"Loaded {len(historical_data)} historical records")
        print(f"Protocols: {historical_data['protocol'].nunique()}")
        print(f"Date range: {historical_data['timestamp'].min()} to {historical_data['timestamp'].max()}")
        
        # Train models
        print("Training ML models...")
        await risk_engine.train_models(historical_data)
        
        # Save models
        risk_engine.save_models()
        
        # Test risk assessment
        test_protocol_data = {
            'protocol': 'test_protocol',
            'tvl_usd': 5_000_000,
            'supply_apy': 12.5,
            'utilization_rate': 0.75,
            'volume_24h': 500_000,
            'protocol_age_days': 180,
            'apy_volatility_7d': 2.1
        }
        
        print("\nTesting risk assessment...")
        risk_profile = risk_engine.assess_protocol_risk(test_protocol_data)
        
        print(f"\nRisk Assessment Results:")
        print(f"Protocol: {risk_profile.protocol_name}")
        print(f"Overall Risk Score: {risk_profile.overall_risk_score:.3f}")
        print(f"Smart Contract Risk: {risk_profile.smart_contract_risk:.3f}")
        print(f"Liquidity Risk: {risk_profile.liquidity_risk:.3f}")
        print(f"Market Risk: {risk_profile.market_risk:.3f}")
        print(f"1-Day VaR: {risk_profile.value_at_risk_1d:.2f}%")
        print(f"7-Day VaR: {risk_profile.value_at_risk_7d:.2f}%")
        print(f"Max Drawdown: {risk_profile.max_drawdown_historical:.2f}%")
        print(f"Sharpe Ratio: {risk_profile.sharpe_ratio:.2f}")
        print(f"Default Probability: {risk_profile.default_probability:.3f}")
        print(f"Return Prediction: {risk_profile.return_prediction:.2f}%")
        print(f"Risk Trend: {risk_profile.risk_trend}")
        
        print(f"\nStress Test Results:")
        for scenario, impact in risk_profile.stress_test_results.items():
            print(f"  {scenario}: {impact:.1f}% impact")
        
        print(f"\nData Quality Score: {risk_profile.data_quality_score:.2f}")
        print(f"Model Version: {risk_profile.model_version}")
        
    else:
        print("No historical data available - using fallback models")
        
        # Test with fallback
        test_protocol_data = {
            'protocol': 'fallback_test',
            'apy': 8.5
        }
        
        risk_profile = risk_engine.assess_protocol_risk(test_protocol_data)
        print(f"Fallback Risk Score: {risk_profile.overall_risk_score:.3f}")

if __name__ == "__main__":
    asyncio.run(main())