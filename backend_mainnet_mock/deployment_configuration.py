#!/usr/bin/env python3
"""
Production Deployment & Configuration System
Complete setup, configuration, and deployment management for Flow EVM Yield Strategy System
"""

import os
import sys
import json
import yaml
import sqlite3
import asyncio
import subprocess
from pathlib import Path
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any
import logging
import argparse
from dataclasses import dataclass, asdict
import hashlib
import secrets

@dataclass
class DatabaseConfig:
    """Database configuration"""
    type: str = "sqlite"
    path: str = "flow_yield_system.db"
    backup_enabled: bool = True
    backup_interval_hours: int = 6
    retention_days: int = 90

@dataclass
class APIConfig:
    """API server configuration"""
    host: str = "0.0.0.0"
    port: int = 8000
    workers: int = 4
    cors_origins: List[str] = None
    rate_limit: str = "100/minute"
    api_key_required: bool = True
    ssl_enabled: bool = False
    ssl_cert_path: str = ""
    ssl_key_path: str = ""

@dataclass
class FlowEVMConfig:
    """Flow EVM network configuration"""
    rpc_url: str = "https://mainnet.evm.nodes.onflow.org"
    chain_id: int = 747
    gas_price_multiplier: float = 1.2
    max_gas_price: int = 50_000_000_000  # 50 gwei
    confirmation_blocks: int = 2
    timeout_seconds: int = 30

@dataclass
class RiskConfig:
    """Risk management configuration"""
    max_portfolio_risk: float = 0.25
    var_confidence_level: float = 0.95
    stress_test_enabled: bool = True
    rebalance_threshold: float = 0.05
    emergency_stop_loss: float = 0.20
    max_protocol_allocation: float = 0.45

@dataclass
class MLConfig:
    """Machine learning configuration"""
    model_update_frequency: str = "daily"
    training_data_days: int = 365
    anomaly_detection_sensitivity: float = 0.1
    prediction_confidence_threshold: float = 0.7
    model_validation_enabled: bool = True
    auto_retrain_enabled: bool = True

@dataclass
class MonitoringConfig:
    """Monitoring and alerting configuration"""
    health_check_interval: int = 30  # seconds
    alert_email_enabled: bool = False
    alert_email_recipients: List[str] = None
    webhook_alerts_enabled: bool = False
    webhook_url: str = ""
    log_level: str = "INFO"
    metrics_retention_days: int = 30

@dataclass
class SystemConfig:
    """Complete system configuration"""
    environment: str = "production"
    version: str = "2.1.0"
    secret_key: str = ""
    database: DatabaseConfig = None
    api: APIConfig = None
    flow_evm: FlowEVMConfig = None
    risk: RiskConfig = None
    ml: MLConfig = None
    monitoring: MonitoringConfig = None

    def __post_init__(self):
        if self.database is None:
            self.database = DatabaseConfig()
        if self.api is None:
            self.api = APIConfig()
        if self.flow_evm is None:
            self.flow_evm = FlowEVMConfig()
        if self.risk is None:
            self.risk = RiskConfig()
        if self.ml is None:
            self.ml = MLConfig()
        if self.monitoring is None:
            self.monitoring = MonitoringConfig()
        if not self.secret_key:
            self.secret_key = secrets.token_urlsafe(32)

class DatabaseManager:
    """Database setup and migration manager"""
    
    def __init__(self, config: DatabaseConfig):
        self.config = config
        self.db_path = config.path
        
    def initialize_database(self):
        """Initialize database with required tables"""
        
        logging.info("Initializing database schema...")
        
        with sqlite3.connect(self.db_path) as conn:
            # Protocol data table
            conn.execute("""
                CREATE TABLE IF NOT EXISTS protocol_data (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    protocol TEXT NOT NULL,
                    timestamp TEXT NOT NULL,
                    block_number INTEGER,
                    tvl_exact INTEGER,
                    tvl_usd REAL,
                    supply_apy REAL,
                    borrow_apy REAL,
                    utilization_rate REAL,
                    volume_24h REAL,
                    fees_24h REAL,
                    liquidity_exact INTEGER,
                    reserves_token0 INTEGER,
                    reserves_token1 INTEGER,
                    price_impact_1k REAL,
                    price_impact_10k REAL,
                    gas_used INTEGER,
                    data_json TEXT,
                    data_source TEXT,
                    confidence_score REAL,
                    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                    INDEX(protocol, timestamp),
                    INDEX(timestamp)
                )
            """)
            
            # Risk assessments table
            conn.execute("""
                CREATE TABLE IF NOT EXISTS risk_assessments (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    protocol TEXT NOT NULL,
                    timestamp TEXT NOT NULL,
                    overall_risk_score REAL,
                    smart_contract_risk REAL,
                    liquidity_risk REAL,
                    market_risk REAL,
                    operational_risk REAL,
                    regulatory_risk REAL,
                    value_at_risk_1d REAL,
                    value_at_risk_7d REAL,
                    max_drawdown REAL,
                    sharpe_ratio REAL,
                    default_probability REAL,
                    anomaly_score REAL,
                    stress_test_results TEXT,
                    model_version TEXT,
                    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                    INDEX(protocol, timestamp)
                )
            """)
            
            # Portfolio allocations table
            conn.execute("""
                CREATE TABLE IF NOT EXISTS portfolio_allocations (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    portfolio_id TEXT NOT NULL,
                    protocol TEXT NOT NULL,
                    allocation_usd REAL,
                    weight REAL,
                    target_weight REAL,
                    last_rebalance TEXT,
                    cumulative_yield REAL,
                    transaction_costs REAL,
                    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                    updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
                    INDEX(portfolio_id, protocol)
                )
            """)
            
            # Backtest results table
            conn.execute("""
                CREATE TABLE IF NOT EXISTS backtest_results (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    strategy_name TEXT NOT NULL,
                    start_date TEXT,
                    end_date TEXT,
                    initial_capital REAL,
                    final_value REAL,
                    total_return REAL,
                    annualized_return REAL,
                    volatility REAL,
                    sharpe_ratio REAL,
                    max_drawdown REAL,
                    win_rate REAL,
                    value_at_risk_95 REAL,
                    total_gas_costs REAL,
                    rebalancing_frequency INTEGER,
                    risk_adjusted_return REAL,
                    results_json TEXT,
                    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                    INDEX(strategy_name, created_at)
                )
            """)
            
            # System metrics table
            conn.execute("""
                CREATE TABLE IF NOT EXISTS system_metrics (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    metric_name TEXT NOT NULL,
                    metric_value REAL,
                    metric_unit TEXT,
                    timestamp TEXT NOT NULL,
                    tags TEXT,
                    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                    INDEX(metric_name, timestamp)
                )
            """)
            
            # API keys table
            conn.execute("""
                CREATE TABLE IF NOT EXISTS api_keys (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    key_hash TEXT UNIQUE NOT NULL,
                    key_name TEXT NOT NULL,
                    permissions TEXT,
                    rate_limit INTEGER,
                    last_used TEXT,
                    expires_at TEXT,
                    is_active BOOLEAN DEFAULT 1,
                    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                    INDEX(key_hash)
                )
            """)
            
            # System events/audit log
            conn.execute("""
                CREATE TABLE IF NOT EXISTS system_events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    event_type TEXT NOT NULL,
                    event_data TEXT,
                    user_id TEXT,
                    ip_address TEXT,
                    timestamp TEXT NOT NULL,
                    severity TEXT,
                    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                    INDEX(event_type, timestamp),
                    INDEX(timestamp)
                )
            """)
            
            conn.commit()
            
        logging.info("Database schema initialized successfully")

    def create_backup(self, backup_path: Optional[str] = None) -> str:
        """Create database backup"""
        
        if not backup_path:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            backup_path = f"backup_{timestamp}_{os.path.basename(self.db_path)}"
        
        logging.info(f"Creating database backup: {backup_path}")
        
        with sqlite3.connect(self.db_path) as source:
            with sqlite3.connect(backup_path) as backup:
                source.backup(backup)
        
        return backup_path

    def cleanup_old_data(self):
        """Clean up old data based on retention policy"""
        
        cutoff_date = datetime.now() - timedelta(days=self.config.retention_days)
        cutoff_str = cutoff_date.isoformat()
        
        with sqlite3.connect(self.db_path) as conn:
            # Clean old protocol data
            result = conn.execute(
                "DELETE FROM protocol_data WHERE timestamp < ?", 
                (cutoff_str,)
            )
            logging.info(f"Cleaned {result.rowcount} old protocol_data records")
            
            # Clean old system metrics
            result = conn.execute(
                "DELETE FROM system_metrics WHERE timestamp < ?", 
                (cutoff_str,)
            )
            logging.info(f"Cleaned {result.rowcount} old system_metrics records")
            
            conn.commit()

class ConfigManager:
    """Configuration management"""
    
    @staticmethod
    def load_config(config_path: str = "config.yaml") -> SystemConfig:
        """Load configuration from file"""
        
        if os.path.exists(config_path):
            with open(config_path, 'r') as f:
                config_dict = yaml.safe_load(f)
            
            # Convert nested dicts to dataclasses
            if 'database' in config_dict:
                config_dict['database'] = DatabaseConfig(**config_dict['database'])
            if 'api' in config_dict:
                config_dict['api'] = APIConfig(**config_dict['api'])
            if 'flow_evm' in config_dict:
                config_dict['flow_evm'] = FlowEVMConfig(**config_dict['flow_evm'])
            if 'risk' in config_dict:
                config_dict['risk'] = RiskConfig(**config_dict['risk'])
            if 'ml' in config_dict:
                config_dict['ml'] = MLConfig(**config_dict['ml'])
            if 'monitoring' in config_dict:
                config_dict['monitoring'] = MonitoringConfig(**config_dict['monitoring'])
            
            return SystemConfig(**config_dict)
        else:
            # Create default config
            config = SystemConfig()
            ConfigManager.save_config(config, config_path)
            return config

    @staticmethod
    def save_config(config: SystemConfig, config_path: str = "config.yaml"):
        """Save configuration to file"""
        
        config_dict = asdict(config)
        
        with open(config_path, 'w') as f:
            yaml.dump(config_dict, f, default_flow_style=False, indent=2)

    @staticmethod
    def generate_env_file(config: SystemConfig, env_path: str = ".env"):
        """Generate environment file from config"""
        
        env_vars = [
            f"ENVIRONMENT={config.environment}",
            f"SECRET_KEY={config.secret_key}",
            f"DATABASE_PATH={config.database.path}",
            f"API_HOST={config.api.host}",
            f"API_PORT={config.api.port}",
            f"FLOW_EVM_RPC_URL={config.flow_evm.rpc_url}",
            f"FLOW_EVM_CHAIN_ID={config.flow_evm.chain_id}",
            f"LOG_LEVEL={config.monitoring.log_level}",
            f"MAX_PORTFOLIO_RISK={config.risk.max_portfolio_risk}",
            f"MODEL_UPDATE_FREQUENCY={config.ml.model_update_frequency}"
        ]
        
        with open(env_path, 'w') as f:
            f.write('\n'.join(env_vars))
            f.write('\n')

class APIKeyManager:
    """API key management"""
    
    def __init__(self, db_path: str):
        self.db_path = db_path

    def generate_api_key(self, name: str, permissions: List[str] = None, 
                        expires_days: int = 365) -> str:
        """Generate new API key"""
        
        # Generate secure random key
        api_key = f"fys_{secrets.token_urlsafe(32)}"
        key_hash = hashlib.sha256(api_key.encode()).hexdigest()
        
        expires_at = datetime.now() + timedelta(days=expires_days)
        permissions_str = json.dumps(permissions) if permissions else json.dumps(["read", "write"])
        
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                INSERT INTO api_keys (key_hash, key_name, permissions, expires_at)
                VALUES (?, ?, ?, ?)
            """, (key_hash, name, permissions_str, expires_at.isoformat()))
            
            conn.commit()
        
        logging.info(f"Generated API key for: {name}")
        return api_key

    def validate_api_key(self, api_key: str) -> bool:
        """Validate API key"""
        
        key_hash = hashlib.sha256(api_key.encode()).hexdigest()
        
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.execute("""
                SELECT expires_at, is_active FROM api_keys 
                WHERE key_hash = ?
            """, (key_hash,))
            
            result = cursor.fetchone()
            
            if not result:
                return False
            
            expires_at_str, is_active = result
            
            if not is_active:
                return False
            
            expires_at = datetime.fromisoformat(expires_at_str)
            if datetime.now() > expires_at:
                return False
            
            # Update last used
            conn.execute("""
                UPDATE api_keys SET last_used = ? WHERE key_hash = ?
            """, (datetime.now().isoformat(), key_hash))
            
            conn.commit()
            
            return True

    def revoke_api_key(self, api_key: str) -> bool:
        """Revoke API key"""
        
        key_hash = hashlib.sha256(api_key.encode()).hexdigest()
        
        with sqlite3.connect(self.db_path) as conn:
            result = conn.execute("""
                UPDATE api_keys SET is_active = 0 WHERE key_hash = ?
            """, (key_hash,))
            
            conn.commit()
            
            return result.rowcount > 0

class DeploymentManager:
    """Deployment and system management"""
    
    def __init__(self, config: SystemConfig):
        self.config = config
        self.db_manager = DatabaseManager(config.database)

    def initialize_system(self):
        """Initialize complete system"""
        
        logging.info("Initializing Flow EVM Yield Strategy System...")
        
        # Create directories
        os.makedirs("models", exist_ok=True)
        os.makedirs("logs", exist_ok=True)
        os.makedirs("backups", exist_ok=True)
        os.makedirs("data", exist_ok=True)
        
        # Initialize database
        self.db_manager.initialize_database()
        
        # Generate configuration files
        ConfigManager.save_config(self.config)
        ConfigManager.generate_env_file(self.config)
        
        # Create systemd service file
        self._create_systemd_service()
        
        # Create nginx config
        self._create_nginx_config()
        
        # Setup log rotation
        self._setup_log_rotation()
        
        logging.info("System initialization completed successfully")

    def _create_systemd_service(self):
        """Create systemd service file"""
        
        service_content = f"""[Unit]
Description=Flow EVM Yield Strategy API Server
After=network.target

[Service]
Type=exec
User=flowuser
Group=flowuser
WorkingDirectory={os.getcwd()}
Environment=PATH={os.environ.get('PATH', '')}
ExecStart={sys.executable} -m uvicorn production_api_server:create_production_server --factory --host {self.config.api.host} --port {self.config.api.port} --workers {self.config.api.workers}
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
"""
        
        with open("flow-yield-strategy.service", 'w') as f:
            f.write(service_content)
        
        logging.info("Systemd service file created: flow-yield-strategy.service")

    def _create_nginx_config(self):
        """Create nginx reverse proxy config"""
        
        nginx_content = f"""server {{
    listen 80;
    server_name your-domain.com;  # Update with your domain
    
    # Redirect HTTP to HTTPS
    return 301 https://$server_name$request_uri;
}}

server {{
    listen 443 ssl http2;
    server_name your-domain.com;  # Update with your domain
    
    # SSL Configuration
    ssl_certificate /path/to/ssl/cert.pem;  # Update path
    ssl_certificate_key /path/to/ssl/key.pem;  # Update path
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    
    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
    
    # Proxy to FastAPI
    location / {{
        limit_req zone=api burst=20 nodelay;
        
        proxy_pass http://127.0.0.1:{self.config.api.port};
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }}
    
    # Static files (if any)
    location /static/ {{
        alias /path/to/static/files/;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }}
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self'" always;
}}
"""
        
        with open("nginx-flow-yield-strategy.conf", 'w') as f:
            f.write(nginx_content)
        
        logging.info("Nginx config created: nginx-flow-yield-strategy.conf")

    def _setup_log_rotation(self):
        """Setup log rotation"""
        
        logrotate_content = f"""{os.getcwd()}/logs/*.log {{
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 0644 flowuser flowuser
    postrotate
        systemctl reload flow-yield-strategy
    endscript
}}
"""
        
        with open("flow-yield-strategy.logrotate", 'w') as f:
            f.write(logrotate_content)
        
        logging.info("Log rotation config created: flow-yield-strategy.logrotate")

    def create_docker_setup(self):
        """Create Docker deployment files"""
        
        # Dockerfile
        dockerfile_content = """FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \\
    gcc \\
    && rm -rf /var/lib/apt/lists/*

# Copy requirements
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Create non-root user
RUN useradd -m -u 1000 flowuser && chown -R flowuser:flowuser /app
USER flowuser

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 \\
    CMD curl -f http://localhost:8000/health || exit 1

# Start command
CMD ["python", "-m", "uvicorn", "production_api_server:create_production_server", "--factory", "--host", "0.0.0.0", "--port", "8000"]
"""
        
        with open("Dockerfile", 'w') as f:
            f.write(dockerfile_content)
        
        # Docker Compose
        compose_content = f"""version: '3.8'

services:
  flow-yield-api:
    build: .
    ports:
      - "{self.config.api.port}:8000"
    volumes:
      - ./data:/app/data
      - ./logs:/app/logs
      - ./models:/app/models
      - ./backups:/app/backups
    environment:
      - ENVIRONMENT={self.config.environment}
      - DATABASE_PATH={self.config.database.path}
      - FLOW_EVM_RPC_URL={self.config.flow_evm.rpc_url}
      - LOG_LEVEL={self.config.monitoring.log_level}
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx-flow-yield-strategy.conf:/etc/nginx/conf.d/default.conf
      - ./ssl:/etc/nginx/ssl  # SSL certificates
    depends_on:
      - flow-yield-api
    restart: unless-stopped

  redis:
    image: redis:alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    restart: unless-stopped

volumes:
  redis_data:
"""
        
        with open("docker-compose.yml", 'w') as f:
            f.write(compose_content)
        
        # Requirements file
        requirements = """fastapi==0.104.1
uvicorn[standard]==0.24.0
pydantic==2.5.0
pandas==2.1.4
numpy==1.25.2
scikit-learn==1.3.2
aiohttp==3.9.1
web3==6.13.0
PyYAML==6.0.1
python-dotenv==1.0.0
asyncio==3.4.3
sqlite3
joblib==1.3.2
scipy==1.11.4
matplotlib==3.8.2
seaborn==0.13.0
"""
        
        with open("requirements.txt", 'w') as f:
            f.write(requirements)
        
        logging.info("Docker deployment files created")

    def run_system_checks(self) -> Dict[str, bool]:
        """Run comprehensive system checks"""
        
        checks = {}
        
        # Database connectivity
        try:
            with sqlite3.connect(self.config.database.path) as conn:
                conn.execute("SELECT 1")
            checks['database'] = True
        except Exception as e:
            logging.error(f"Database check failed: {e}")
            checks['database'] = False
        
        # Flow EVM connectivity
        try:
            import aiohttp
            async def test_rpc():
                async with aiohttp.ClientSession() as session:
                    payload = {
                        "jsonrpc": "2.0",
                        "method": "eth_blockNumber",
                        "params": [],
                        "id": 1
                    }
                    async with session.post(self.config.flow_evm.rpc_url, json=payload) as resp:
                        return resp.status == 200
            
            checks['flow_evm_rpc'] = asyncio.run(test_rpc())
        except Exception as e:
            logging.error(f"Flow EVM RPC check failed: {e}")
            checks['flow_evm_rpc'] = False
        
        # File permissions
        try:
            test_file = "test_permissions.tmp"
            with open(test_file, 'w') as f:
                f.write("test")
            os.remove(test_file)
            checks['file_permissions'] = True
        except Exception as e:
            logging.error(f"File permissions check failed: {e}")
            checks['file_permissions'] = False
        
        # Memory and disk space
        import shutil
        disk_usage = shutil.disk_usage(".")
        free_gb = disk_usage.free / (1024**3)
        checks['disk_space'] = free_gb > 1.0  # At least 1GB free
        
        return checks

class CLIAdmin:
    """Command line administration interface"""
    
    def __init__(self):
        self.config = ConfigManager.load_config()
        self.deployment_manager = DeploymentManager(self.config)
        self.api_key_manager = APIKeyManager(self.config.database.path)

    def main(self):
        """Main CLI interface"""
        
        parser = argparse.ArgumentParser(description="Flow EVM Yield Strategy System Administration")
        subparsers = parser.add_subparsers(dest='command', help='Available commands')
        
        # Initialize command
        init_parser = subparsers.add_parser('init', help='Initialize system')
        init_parser.add_argument('--environment', choices=['development', 'staging', 'production'], 
                               default='production', help='Environment type')
        
        # API key management
        key_parser = subparsers.add_parser('apikey', help='API key management')
        key_subparsers = key_parser.add_subparsers(dest='key_action')
        
        generate_parser = key_subparsers.add_parser('generate', help='Generate new API key')
        generate_parser.add_argument('name', help='API key name')
        generate_parser.add_argument('--expires-days', type=int, default=365, help='Expiration days')
        
        revoke_parser = key_subparsers.add_parser('revoke', help='Revoke API key')
        revoke_parser.add_argument('api_key', help='API key to revoke')
        
        # Database management
        db_parser = subparsers.add_parser('database', help='Database management')
        db_subparsers = db_parser.add_subparsers(dest='db_action')
        
        db_subparsers.add_parser('backup', help='Create database backup')
        db_subparsers.add_parser('cleanup', help='Clean old data')
        db_subparsers.add_parser('status', help='Database status')
        
        # System management
        system_parser = subparsers.add_parser('system', help='System management')
        system_subparsers = system_parser.add_subparsers(dest='system_action')
        
        system_subparsers.add_parser('status', help='System status')
        system_subparsers.add_parser('start', help='Start system services')
        system_subparsers.add_parser('stop', help='Stop system services')
        system_subparsers.add_parser('restart', help='Restart system services')
        system_subparsers.add_parser('logs', help='View system logs')
        
        # Deploy command
        deploy_parser = subparsers.add_parser('deploy', help='Deployment management')
        deploy_subparsers = deploy_parser.add_subparsers(dest='deploy_action')
        
        deploy_subparsers.add_parser('docker', help='Create Docker deployment files')
        deploy_subparsers.add_parser('systemd', help='Install systemd service')
        deploy_subparsers.add_parser('nginx', help='Setup nginx configuration')
        
        args = parser.parse_args()
        
        if not args.command:
            parser.print_help()
            return
        
        # Setup logging
        logging.basicConfig(
            level=getattr(logging, self.config.monitoring.log_level),
            format='%(asctime)s - %(levelname)s - %(message)s'
        )
        
        # Route commands
        if args.command == 'init':
            self._handle_init(args)
        elif args.command == 'apikey':
            self._handle_apikey(args)
        elif args.command == 'database':
            self._handle_database(args)
        elif args.command == 'system':
            self._handle_system(args)
        elif args.command == 'deploy':
            self._handle_deploy(args)

    def _handle_init(self, args):
        """Handle system initialization"""
        
        print("🚀 Initializing Flow EVM Yield Strategy System")
        print(f"Environment: {args.environment}")
        
        self.config.environment = args.environment
        ConfigManager.save_config(self.config)
        
        self.deployment_manager.initialize_system()
        
        # Generate initial API key
        api_key = self.api_key_manager.generate_api_key("admin", ["read", "write", "admin"])
        
        print(f"\n✅ System initialized successfully!")
        print(f"📝 Configuration saved to: config.yaml")
        print(f"🔑 Admin API key: {api_key}")
        print(f"⚠️  Save this API key securely - it won't be shown again!")
        
        # Run system checks
        print(f"\n🔍 Running system checks...")
        checks = self.deployment_manager.run_system_checks()
        
        for check, passed in checks.items():
            status = "✅" if passed else "❌"
            print(f"{status} {check}")

    def _handle_apikey(self, args):
        """Handle API key management"""
        
        if args.key_action == 'generate':
            api_key = self.api_key_manager.generate_api_key(args.name, expires_days=args.expires_days)
            print(f"Generated API key: {api_key}")
            print(f"Name: {args.name}")
            print(f"Expires: {args.expires_days} days")
            
        elif args.key_action == 'revoke':
            success = self.api_key_manager.revoke_api_key(args.api_key)
            if success:
                print("✅ API key revoked successfully")
            else:
                print("❌ API key not found or already revoked")

    def _handle_database(self, args):
        """Handle database management"""
        
        if args.db_action == 'backup':
            backup_path = self.deployment_manager.db_manager.create_backup()
            print(f"✅ Database backup created: {backup_path}")
            
        elif args.db_action == 'cleanup':
            self.deployment_manager.db_manager.cleanup_old_data()
            print("✅ Old data cleaned up")
            
        elif args.db_action == 'status':
            db_path = self.config.database.path
            if os.path.exists(db_path):
                size_mb = os.path.getsize(db_path) / (1024 * 1024)
                print(f"📊 Database Status:")
                print(f"   Path: {db_path}")
                print(f"   Size: {size_mb:.2f} MB")
                print(f"   Backup enabled: {self.config.database.backup_enabled}")
                print(f"   Retention: {self.config.database.retention_days} days")
            else:
                print("❌ Database not found")

    def _handle_system(self, args):
        """Handle system management"""
        
        if args.system_action == 'status':
            checks = self.deployment_manager.run_system_checks()
            print("🔍 System Status:")
            
            for check, passed in checks.items():
                status = "✅ PASS" if passed else "❌ FAIL"
                print(f"   {check}: {status}")
                
        elif args.system_action in ['start', 'stop', 'restart']:
            service_name = "flow-yield-strategy"
            cmd = f"systemctl {args.system_action} {service_name}"
            
            try:
                result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
                if result.returncode == 0:
                    print(f"✅ Service {args.system_action}ed successfully")
                else:
                    print(f"❌ Service {args.system_action} failed: {result.stderr}")
            except Exception as e:
                print(f"❌ Error: {e}")
                
        elif args.system_action == 'logs':
            cmd = "journalctl -u flow-yield-strategy -f"
            try:
                subprocess.run(cmd, shell=True)
            except KeyboardInterrupt:
                print("\nLog viewing stopped")

    def _handle_deploy(self, args):
        """Handle deployment management"""
        
        if args.deploy_action == 'docker':
            self.deployment_manager.create_docker_setup()
            print("✅ Docker deployment files created")
            print("   Run: docker-compose up -d")
            
        elif args.deploy_action == 'systemd':
            service_file = "flow-yield-strategy.service"
            target_path = f"/etc/systemd/system/{service_file}"
            
            try:
                subprocess.run(f"sudo cp {service_file} {target_path}", shell=True, check=True)
                subprocess.run("sudo systemctl daemon-reload", shell=True, check=True)
                subprocess.run("sudo systemctl enable flow-yield-strategy", shell=True, check=True)
                print("✅ Systemd service installed and enabled")
            except subprocess.CalledProcessError as e:
                print(f"❌ Systemd installation failed: {e}")
                
        elif args.deploy_action == 'nginx':
            config_file = "nginx-flow-yield-strategy.conf"
            target_path = f"/etc/nginx/sites-available/flow-yield-strategy"
            
            print(f"📝 Nginx configuration created: {config_file}")
            print(f"Manual steps required:")
            print(f"1. sudo cp {config_file} {target_path}")
            print(f"2. sudo ln -s {target_path} /etc/nginx/sites-enabled/")
            print(f"3. Update SSL certificate paths in the config")
            print(f"4. sudo nginx -t")
            print(f"5. sudo systemctl reload nginx")

if __name__ == "__main__":
    cli = CLIAdmin()
    cli.main()