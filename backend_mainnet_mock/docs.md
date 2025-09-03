# Flow EVM Yield Strategy System - Production Documentation

## Table of Contents
- [System Overview](#system-overview)
- [Architecture](#architecture)
- [Installation & Setup](#installation--setup)
- [Configuration](#configuration)
- [API Reference](#api-reference)
- [CLI Administration](#cli-administration)
- [Monitoring & Maintenance](#monitoring--maintenance)
- [Security](#security)
- [Troubleshooting](#troubleshooting)
- [Production Deployment](#production-deployment)

## System Overview

The Flow EVM Yield Strategy System is a production-grade platform for optimizing yield farming strategies across Flow EVM protocols. It provides:

### Core Features
- **Real-time Protocol Data**: Live on-chain data from Flow EVM protocols
- **ML Risk Assessment**: Advanced machine learning models for risk analysis
- **Portfolio Optimization**: Modern portfolio theory-based allocation
- **Historical Backtesting**: Comprehensive strategy validation
- **Production API**: RESTful API with investor-grade accuracy
- **Risk Management**: Automated monitoring and alerting
- **Multi-Protocol Support**: More.Markets, PunchSwap, iZiSwap, Flow Staking

### Key Capabilities
- **Investor-Grade Accuracy**: All calculations use exact on-chain data
- **Real-time Risk Assessment**: ML models detect anomalies and predict defaults
- **Comprehensive Backtesting**: Historical validation with exact market conditions
- **Production Ready**: Full deployment automation and monitoring
- **Scalable Architecture**: Designed for institutional-grade workloads

## Architecture

### System Components

```
┌─────────────────────────────────────────────────────────────────┐
│                    Flow EVM Yield Strategy System              │
├─────────────────────────────────────────────────────────────────┤
│  Production API Server (FastAPI)                               │
│  ├── Portfolio Optimization Endpoints                          │
│  ├── Risk Assessment Endpoints                                 │
│  ├── Backtesting Endpoints                                     │
│  ├── Market Data Endpoints                                     │
│  └── Monitoring & Admin Endpoints                              │
├─────────────────────────────────────────────────────────────────┤
│  Core Engine Components                                         │
│  ├── Production Flow Yield Agent                               │
│  ├── Real-time Data Service                                    │
│  ├── Advanced ML Risk Engine                                   │
│  ├── Production Backtester                                     │
│  └── Report Generator                                           │
├─────────────────────────────────────────────────────────────────┤
│  Data Layer                                                     │
│  ├── SQLite Database (Protocol Data, Risk Assessments)         │
│  ├── ML Model Storage (Trained Models, Feature Data)           │
│  ├── Configuration Management (YAML/ENV)                       │
│  └── Logging & Metrics (Structured Logs, Performance Data)     │
├─────────────────────────────────────────────────────────────────┤
│  External Integrations                                          │
│  ├── Flow EVM RPC (On-chain Data)                              │
│  ├── DeFiLlama API (Historical Yield Data)                     │
│  ├── CoinGecko API (Token Prices)                              │
│  └── Protocol APIs (More.Markets, PunchSwap, etc.)             │
└─────────────────────────────────────────────────────────────────┘
```

### Data Flow

1. **Real-time Data Collection**: Continuous polling of Flow EVM protocols
2. **Risk Assessment**: ML models analyze protocol safety and market conditions
3. **Portfolio Optimization**: Modern portfolio theory calculates optimal allocations
4. **Backtesting Validation**: Historical simulation validates strategy performance
5. **Report Generation**: Investor-grade reports with exact calculations
6. **Monitoring & Alerts**: Continuous system health and risk monitoring

## Installation & Setup

### Prerequisites

- **Python 3.11+**: Core runtime environment
- **Node.js 18+**: For additional tooling (optional)
- **SQLite**: Database (included with Python)
- **Git**: Version control
- **Linux/Ubuntu 22.04+**: Recommended OS (production)

### System Requirements

#### Minimum Requirements
- **CPU**: 2 cores
- **RAM**: 4 GB
- **Storage**: 20 GB SSD
- **Network**: Stable internet connection

#### Recommended (Production)
- **CPU**: 4+ cores
- **RAM**: 8+ GB
- **Storage**: 100+ GB SSD
- **Network**: High-bandwidth, low-latency connection
- **Load Balancer**: For high availability

### Quick Start

#### 1. Clone Repository
```bash
git clone https://github.com/your-org/flow-evm-yield-strategy.git
cd flow-evm-yield-strategy
```

#### 2. Setup Python Environment
```bash
# Create virtual environment
python3.11 -m venv venv
source venv/bin/activate  # Linux/Mac
# venv\Scripts\activate  # Windows

# Install dependencies
pip install -r requirements.txt
```

#### 3. Initialize System
```bash
# Initialize with CLI admin tool
python deployment_configuration.py init --environment production

# This will:
# - Create database schema
# - Generate configuration files
# - Create initial API key
# - Run system checks
```

#### 4. Start System
```bash
# Development mode
python -m uvicorn production_api_server:create_production_server --factory --reload

# Production mode
python production_api_server.py
```

#### 5. Verify Installation
```bash
# Check system health
curl http://localhost:8000/health

# Expected response:
{
  "status": "healthy",
  "timestamp": "2024-01-15T10:30:00Z",
  "version": "2.1.0",
  "components": {
    "yield_agent": true,
    "data_service": true,
    "risk_engine": true,
    "backtester": true
  }
}
```

## Configuration

### Configuration Files

#### config.yaml (Main Configuration)
```yaml
environment: production
version: "2.1.0"
secret_key: "your-secure-secret-key"

database:
  type: sqlite
  path: "flow_yield_system.db"
  backup_enabled: true
  backup_interval_hours: 6
  retention_days: 90

api:
  host: "0.0.0.0"
  port: 8000
  workers: 4
  cors_origins: ["https://yourdomain.com"]
  rate_limit: "100/minute"
  api_key_required: true
  ssl_enabled: false

flow_evm:
  rpc_url: "https://mainnet.evm.nodes.onflow.org"
  chain_id: 747
  gas_price_multiplier: 1.2
  max_gas_price: 50000000000
  confirmation_blocks: 2
  timeout_seconds: 30

risk:
  max_portfolio_risk: 0.25
  var_confidence_level: 0.95
  stress_test_enabled: true
  rebalance_threshold: 0.05
  emergency_stop_loss: 0.20
  max_protocol_allocation: 0.45

ml:
  model_update_frequency: "daily"
  training_data_days: 365
  anomaly_detection_sensitivity: 0.1
  prediction_confidence_threshold: 0.7
  model_validation_enabled: true
  auto_retrain_enabled: true

monitoring:
  health_check_interval: 30
  alert_email_enabled: false
  log_level: "INFO"
  metrics_retention_days: 30
```

#### .env (Environment Variables)
```env
ENVIRONMENT=production
SECRET_KEY=your-secure-secret-key
DATABASE_PATH=flow_yield_system.db
API_HOST=0.0.0.0
API_PORT=8000
FLOW_EVM_RPC_URL=https://mainnet.evm.nodes.onflow.org
FLOW_EVM_CHAIN_ID=747
LOG_LEVEL=INFO
MAX_PORTFOLIO_RISK=0.25
MODEL_UPDATE_FREQUENCY=daily
```

### Configuration Management

#### Update Configuration
```bash
# Edit config.yaml manually or use CLI
python deployment_configuration.py system status

# Restart system after changes
python deployment_configuration.py system restart
```

#### Environment-Specific Configs
```bash
# Development
python deployment_configuration.py init --environment development

# Staging
python deployment_configuration.py init --environment staging

# Production
python deployment_configuration.py init --environment production
```

## API Reference

### Authentication

All API endpoints require authentication via API key:

```bash
# Include API key in header
curl -H "Authorization: Bearer fys_your-api-key-here" \
     http://localhost:8000/api/v1/market-data
```

### Core Endpoints

#### Portfolio Optimization
```http
POST /api/v1/optimize-portfolio
Content-Type: application/json

{
  "portfolio_size": 500000,
  "risk_tolerance": 0.4,
  "target_apy": 12.0,
  "max_protocols": 5,
  "rebalancing_frequency": "monthly"
}
```

**Response:**
```json
{
  "strategy_name": "Optimized Flow EVM Portfolio",
  "portfolio_size": 500000,
  "allocations": {
    "more_markets": 0.30,
    "staking": 0.25,
    "punchswap_v2": 0.30,
    "iziswap": 0.15
  },
  "expected_apy": 11.8,
  "risk_score": 0.32,
  "sharpe_ratio": 1.75,
  "confidence_score": 0.87
}
```

#### Risk Assessment
```http
POST /api/v1/risk-assessment
Content-Type: application/json

{
  "protocols": ["more_markets", "punchswap_v2"],
  "allocation_weights": {
    "more_markets": 0.6,
    "punchswap_v2": 0.4
  },
  "time_horizon": 365
}
```

#### Historical Backtesting
```http
POST /api/v1/backtest
Content-Type: application/json

{
  "strategy_name": "Conservative Yield",
  "allocations": {
    "more_markets": 0.5,
    "staking": 0.3,
    "punchswap_v2": 0.2
  },
  "start_date": "2023-01-01",
  "end_date": "2024-01-01",
  "initial_capital": 100000,
  "rebalancing_frequency": "monthly"
}
```

#### Market Data
```http
GET /api/v1/market-data
```

**Response:**
```json
[
  {
    "protocol": "more_markets",
    "tvl_usd": 18450000,
    "apy": 4.75,
    "volume_24h": 2100000,
    "risk_score": 0.22,
    "last_updated": "2024-01-15T10:30:00Z"
  }
]
```

### Complete API Documentation

Access interactive API documentation at:
- **Swagger UI**: `http://localhost:8000/docs`
- **ReDoc**: `http://localhost:8000/redoc`

## CLI Administration

### Available Commands

#### System Initialization
```bash
# Initialize new system
python deployment_configuration.py init --environment production

# Initialize with custom settings
python deployment_configuration.py init --environment staging
```

#### API Key Management
```bash
# Generate new API key
python deployment_configuration.py apikey generate "investor-client" --expires-days 365

# Revoke API key
python deployment_configuration.py apikey revoke "fys_api_key_here"
```

#### Database Management
```bash
# Create backup
python deployment_configuration.py database backup

# Clean old data
python deployment_configuration.py database cleanup

# Check database status
python deployment_configuration.py database status
```

#### System Management
```bash
# Check system status
python deployment_configuration.py system status

# Start/stop/restart services
python deployment_configuration.py system start
python deployment_configuration.py system stop
python deployment_configuration.py system restart

# View real-time logs
python deployment_configuration.py system logs
```

#### Deployment Management
```bash
# Create Docker files
python deployment_configuration.py deploy docker

# Install systemd service
python deployment_configuration.py deploy systemd

# Setup nginx configuration
python deployment_configuration.py deploy nginx
```

## Monitoring & Maintenance

### Health Monitoring

#### System Health Endpoint
```bash
curl http://localhost:8000/health
```

#### Detailed System Status
```bash
curl -H "Authorization: Bearer your-api-key" \
     http://localhost:8000/api/v1/status
```

### Performance Metrics

#### Key Metrics Monitored
- **API Response Time**: Average endpoint latency
- **Data Freshness**: Time since last protocol data update
- **Model Accuracy**: ML model performance metrics
- **Database Performance**: Query execution times
- **Memory Usage**: System resource utilization
- **Error Rates**: Failed requests and system errors

#### Metrics Endpoint
```bash
curl -H "Authorization: Bearer your-api-key" \
     http://localhost:8000/api/v1/monitoring/metrics
```

### Automated Alerts

#### Alert Conditions
- Daily portfolio loss > 5%
- Protocol APY drop > 25%
- System errors > 10/hour
- Database connection failures
- High memory usage (>90%)
- Disk space low (<10%)

#### Alert Configuration
```yaml
monitoring:
  alert_email_enabled: true
  alert_email_recipients:
    - "admin@yourcompany.com"
    - "devops@yourcompany.com"
  webhook_alerts_enabled: true
  webhook_url: "https://your-alerting-system.com/webhook"
```

### Maintenance Tasks

#### Daily Maintenance
```bash
# Run automated daily maintenance
crontab -e

# Add daily maintenance job
0 2 * * * /path/to/venv/bin/python /path/to/deployment_configuration.py database cleanup
0 3 * * * /path/to/venv/bin/python /path/to/deployment_configuration.py database backup
```

#### Weekly Maintenance
- Review system performance metrics
- Check ML model accuracy
- Validate configuration settings
- Review security logs
- Update risk parameters if needed

#### Monthly Maintenance
- Full system health assessment
- Review and rotate API keys
- Update protocol configurations
- Analyze yield strategy performance
- Plan system capacity upgrades

## Security

### Security Features

#### API Security
- **API Key Authentication**: Required for all endpoints
- **Rate Limiting**: Prevents API abuse (100 requests/minute default)
- **CORS Protection**: Configurable allowed origins
- **Input Validation**: Pydantic models validate all inputs
- **SQL Injection Protection**: Parameterized queries only

#### Data Security
- **Database Encryption**: Option for encrypted database
- **Secure Configuration**: Sensitive data in environment variables
- **Access Logging**: All API access logged and monitored
- **Data Retention**: Automated cleanup of old data

#### Network Security
- **HTTPS Support**: SSL/TLS encryption for production
- **Firewall Configuration**: Restrict access to necessary ports only
- **Reverse Proxy**: Nginx proxy for additional security layer

### Security Best Practices

#### API Key Management
```bash
# Generate secure API keys with limited permissions
python deployment_configuration.py apikey generate "read-only-client" --expires-days 90

# Regularly rotate API keys
python deployment_configuration.py apikey revoke "old-api-key"
python deployment_configuration.py apikey generate "new-client" --expires-days 365
```

#### SSL/HTTPS Setup
```bash
# Generate SSL certificates (Let's Encrypt recommended)
sudo certbot certonly --nginx -d yourdomain.com

# Update nginx configuration with SSL paths
# Edit nginx-flow-yield-strategy.conf
ssl_certificate /etc/letsencrypt/live/yourdomain.com/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/yourdomain.com/privkey.pem;
```

#### Firewall Configuration
```bash
# UFW firewall setup
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw deny 8000/tcp  # Block direct API access
sudo ufw enable
```

## Troubleshooting

### Common Issues

#### Database Connection Errors
```bash
# Check database file permissions
ls -la flow_yield_system.db

# Reinitialize database if corrupted
python deployment_configuration.py init --environment production
```

#### Flow EVM RPC Issues
```bash
# Test RPC connectivity
curl -X POST https://mainnet.evm.nodes.onflow.org \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# Update RPC URL in config if needed
# Edit config.yaml -> flow_evm -> rpc_url
```

#### High Memory Usage
```bash
# Check system resources
htop
df -h

# Restart system to clear memory
python deployment_configuration.py system restart
```

#### API Performance Issues
```bash
# Check API response times
curl -w "@curl-format.txt" -H "Authorization: Bearer your-api-key" \
     http://localhost:8000/api/v1/market-data

# Enable API caching if needed
# Edit config.yaml -> api -> enable_caching: true
```

### Debug Mode

#### Enable Debug Logging
```bash
# Edit config.yaml
monitoring:
  log_level: "DEBUG"

# Restart system
python deployment_configuration.py system restart

# View debug logs
python deployment_configuration.py system logs
```

#### Test Individual Components
```bash
# Test data fetching
python real_time_data_system.py

# Test ML risk engine
python advanced_ml_risk_engine.py

# Test backtesting system
python production_backtesting_system.py
```

### Support

#### Getting Help
1. **Check Logs**: Review system logs for error details
2. **Run Diagnostics**: Use `system status` command
3. **Check Documentation**: Review this documentation
4. **Community Support**: Join our Discord/Telegram
5. **Enterprise Support**: Contact support@yourcompany.com

## Production Deployment

### Docker Deployment

#### Build and Deploy
```bash
# Create Docker deployment files
python deployment_configuration.py deploy docker

# Build and start services
docker-compose up -d

# Check service status
docker-compose ps
docker-compose logs flow-yield-api
```

#### Docker Configuration
```yaml
# docker-compose.yml
version: '3.8'
services:
  flow-yield-api:
    build: .
    ports:
      - "8000:8000"
    volumes:
      - ./data:/app/data
      - ./logs:/app/logs
    environment:
      - ENVIRONMENT=production
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
```

### Systemd Service Deployment

#### Install Service
```bash
# Create and install systemd service
python deployment_configuration.py deploy systemd

# Start service
sudo systemctl start flow-yield-strategy
sudo systemctl enable flow-yield-strategy

# Check service status
sudo systemctl status flow-yield-strategy
```

#### Service Management
```bash
# View service logs
sudo journalctl -u flow-yield-strategy -f

# Restart service
sudo systemctl restart flow-yield-strategy

# Stop service
sudo systemctl stop flow-yield-strategy
```

### Nginx Reverse Proxy

#### Setup Nginx
```bash
# Create nginx configuration
python deployment_configuration.py deploy nginx

# Install configuration
sudo cp nginx-flow-yield-strategy.conf /etc/nginx/sites-available/flow-yield-strategy
sudo ln -s /etc/nginx/sites-available/flow-yield-strategy /etc/nginx/sites-enabled/

# Test configuration
sudo nginx -t

# Reload nginx
sudo systemctl reload nginx
```

### High Availability Setup

#### Load Balancer Configuration
```nginx
upstream flow_yield_backend {
    server 10.0.1.10:8000 weight=1 max_fails=3 fail_timeout=30s;
    server 10.0.1.11:8000 weight=1 max_fails=3 fail_timeout=30s;
    server 10.0.1.12:8000 weight=1 max_fails=3 fail_timeout=30s;
}

server {
    listen 443 ssl http2;
    server_name api.yourdomain.com;
    
    location / {
        proxy_pass http://flow_yield_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Health check
        proxy_next_upstream error timeout http_500 http_502 http_503;
    }
}
```

### Database Replication

#### Master-Slave Setup
```bash
# For production, consider PostgreSQL with replication
# SQLite is suitable for single-instance deployments

# Setup PostgreSQL master-slave replication
# (Configuration details depend on your infrastructure)
```

### Monitoring in Production

#### Prometheus & Grafana
```yaml
# Add to docker-compose.yml
  prometheus:
    image: prom/prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml

  grafana:
    image: grafana/grafana
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
```

#### Custom Metrics
```python
# Add to production_api_server.py
from prometheus_client import Counter, Histogram, generate_latest

REQUEST_COUNT = Counter('requests_total', 'Total requests', ['method', 'endpoint'])
REQUEST_LATENCY = Histogram('request_duration_seconds', 'Request latency')
```

### Backup Strategy

#### Automated Backups
```bash
# Daily database backups
0 2 * * * /path/to/backup-script.sh

# Weekly full system backups
0 3 * * 0 /path/to/full-backup-script.sh

# Monthly archive backups
0 4 1 * * /path/to/archive-script.sh
```

### Scaling Considerations

#### Horizontal Scaling
- **API Layer**: Multiple FastAPI instances behind load balancer
- **Database**: Read replicas for query scaling
- **Caching**: Redis for API response caching
- **Background Tasks**: Celery for async processing

#### Performance Optimization
- **Database Indexing**: Optimize query performance
- **API Caching**: Cache expensive calculations
- **Connection Pooling**: Efficient database connections
- **Async Processing**: Non-blocking I/O operations

---

## Conclusion

This Flow EVM Yield Strategy System provides a complete, production-ready platform for institutional-grade yield optimization. The system combines real-time data analysis, advanced ML risk assessment, and comprehensive backtesting to deliver investor-grade accuracy and reliability.

### Key Benefits
- **Production Ready**: Complete deployment automation and monitoring
- **Investor Grade**: Exact calculations using real on-chain data
- **Scalable**: Designed for institutional workloads
- **Secure**: Enterprise-grade security features
- **Maintainable**: Comprehensive documentation and CLI tools

### Next Steps
1. **Deploy**: Follow the installation guide for your environment
2. **Configure**: Customize settings for your specific needs
3. **Monitor**: Set up monitoring and alerting
4. **Scale**: Implement high availability as needed
5. **Optimize**: Continuously improve based on usage patterns

For additional support, feature requests, or enterprise licensing, please contact our team.

---

**Version**: 2.1.0  
**Last Updated**: January 2024  
**License**: Enterprise License