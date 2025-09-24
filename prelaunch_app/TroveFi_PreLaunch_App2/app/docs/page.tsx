'use client'

import { useState, useEffect } from 'react'
import { motion } from 'framer-motion'
import { 
  BookOpen, 
  Code, 
  TrendingUp, 
  Shield, 
  Bot, 
  Database,
  BarChart3,
  Zap,
  ArrowLeft,
  ExternalLink,
  ChevronRight,
  Clock,
  DollarSign,
  Target,
  AlertTriangle,
  Sun,
  Moon,
  Brain,
  Activity,
  TrendingDown
} from 'lucide-react'
import Link from 'next/link'

export default function DocsPage() {
  const [activeSection, setActiveSection] = useState('overview')
  const [darkMode, setDarkMode] = useState(true)

  useEffect(() => {
    // Apply dark/light mode to document
    if (darkMode) {
      document.documentElement.classList.add('dark')
      document.documentElement.classList.remove('light')
    } else {
      document.documentElement.classList.add('light')
      document.documentElement.classList.remove('dark')
    }
  }, [darkMode])

  const sections = [
    {
      id: 'overview',
      title: 'Overview',
      icon: BookOpen,
    },
    {
      id: 'ai-strategy',
      title: 'AI-Driven Strategy',
      icon: Brain,
    },
    {
      id: 'risk-matrix',
      title: 'Risk Allocation Matrix',
      icon: Target,
    },
    {
      id: 'market-regimes',
      title: 'Market Regime Intelligence',
      icon: Activity,
    },
    {
      id: 'performance',
      title: 'Performance Metrics',
      icon: TrendingUp,
    },
    {
      id: 'risk-management',
      title: 'Risk Management',
      icon: Shield,
    },
    {
      id: 'ai-agent',
      title: 'AI Agent Architecture',
      icon: Bot,
    },
    {
      id: 'api',
      title: 'API Reference',
      icon: Code,
    }
  ]

  const riskAllocationMatrix = {
    'extreme_risk': { 'more_markets': 0.85, 'staking': 0.10, 'punchswap_v2': 0.05 },
    'high_risk': { 'more_markets': 0.65, 'staking': 0.25, 'punchswap_v2': 0.10 },
    'moderate_risk': { 'more_markets': 0.45, 'staking': 0.30, 'punchswap_v2': 0.25 },
    'low_risk': { 'more_markets': 0.25, 'staking': 0.35, 'punchswap_v2': 0.40 },
    'minimal_risk': { 'more_markets': 0.05, 'staking': 0.15, 'punchswap_v2': 0.80 }
  }

  const marketRegimes = [
    { name: 'Bull Market', description: 'Rising prices, high confidence', allocation: 'Even more aggressive (up to 65% high-risk protocols)' },
    { name: 'Bear Market', description: 'Falling prices, risk aversion', allocation: 'Defensive positioning (70%+ staking)' },
    { name: 'Crisis Mode', description: 'Market stress, liquidity concerns', allocation: 'Emergency allocation (90% staking)' },
    { name: 'Recovery', description: 'Post-crisis stabilization', allocation: 'Tactical positioning for growth opportunities' },
    { name: 'Sideways', description: 'Flat market, range-bound', allocation: 'Balanced risk with yield focus' },
    { name: 'High Volatility', description: 'Unpredictable price swings', allocation: 'Conservative with quick rebalancing' },
    { name: 'Low Volatility', description: 'Stable, predictable movements', allocation: 'Aggressive yield maximization' },
    { name: 'Black Swan', description: 'Unprecedented market events', allocation: 'Maximum safety protocols activated' }
  ]

  const performanceMetrics = [
    { label: 'Aggressive Default APY', value: '18.2%', period: 'Target with AI risk management' },
    { label: 'Historical Return', value: '12.24%', period: 'Conservative baseline (Jan 2024 - Aug 2025)' },
    { label: 'AI Risk Detection', value: '<100ms', period: 'Real-time threat assessment' },
    { label: 'Max Drawdown', value: '0.00%', period: 'Principal protection maintained' },
    { label: 'Rebalancing Speed', value: '2.3s', period: 'AI-triggered position changes' },
    { label: 'Sharpe Improvement', value: '+340%', period: 'vs traditional strategies' }
  ]

  const renderContent = () => {
    switch (activeSection) {
      case 'overview':
        return (
          <div className="space-y-8">
            <div>
              <h1 className="text-4xl font-bold mb-4 text-foreground">TroveFi Protocol Documentation</h1>
              <p className="text-xl text-muted-foreground leading-relaxed">
                AI-powered no-loss yield primative with aggressive-by-default strategy and machine learning risk management.
              </p>
            </div>

            <div className="bg-card border border-border rounded-lg p-6">
              <h2 className="text-2xl font-semibold mb-4 text-foreground">🚀 Aggressive-by-Default Philosophy</h2>
              <p className="text-muted-foreground mb-4">
                Unlike conservative DeFi strategies that limit upside potential, TroveFi leverages advanced AI risk detection 
                to maximize yield during favorable conditions while providing intelligent protection during risk events.
              </p>
              <div className="grid md:grid-cols-2 gap-4">
                <div className="p-4 bg-muted rounded-lg">
                  <h3 className="font-semibold mb-2 text-foreground">Traditional Approach</h3>
                  <p className="text-sm text-muted-foreground">
                    Conservative allocations sacrifice yield for perceived safety, often missing significant opportunities.
                  </p>
                </div>
                <div className="p-4 bg-primary/10 rounded-lg border border-primary/20">
                  <h3 className="font-semibold mb-2 text-foreground">TroveFi Approach</h3>
                  <p className="text-sm text-muted-foreground">
                    Aggressive positioning with AI-powered early warning systems for optimal risk-adjusted returns.
                  </p>
                </div>
              </div>
            </div>

            <div className="grid md:grid-cols-3 gap-6">
              <div className="border border-border rounded-lg p-6">
                <Brain className="w-8 h-8 mb-4 text-primary" />
                <h3 className="text-lg font-semibold mb-2 text-foreground">AI-First Strategy</h3>
                <p className="text-sm text-muted-foreground">
                  Machine learning models continuously assess risk and optimize allocations in real-time.
                </p>
              </div>
              
              <div className="border border-border rounded-lg p-6">
                <Target className="w-8 h-8 mb-4 text-primary" />
                <h3 className="text-lg font-semibold mb-2 text-foreground">Dynamic Allocation</h3>
                <p className="text-sm text-muted-foreground">
                  Five-tier risk matrix adapts to market conditions from aggressive to crisis mode.
                </p>
              </div>
              
              <div className="border border-border rounded-lg p-6">
                <TrendingUp className="w-8 h-8 mb-4 text-primary" />
                <h3 className="text-lg font-semibold mb-2 text-foreground">Yield Maximization</h3>
                <p className="text-sm text-muted-foreground">
                  Default 85% allocation to highest-yield protocols when AI detects favorable conditions.
                </p>
              </div>
            </div>
          </div>
        )

      case 'ai-strategy':
        return (
          <div className="space-y-8">
            <div>
              <h1 className="text-4xl font-bold mb-4 text-foreground">AI-Driven Strategy Architecture</h1>
              <p className="text-xl text-muted-foreground leading-relaxed">
                Our competitive advantage lies in sophisticated AI risk detection that enables aggressive positioning 
                with intelligent protection mechanisms.
              </p>
            </div>

            <div className="bg-card border border-border rounded-lg p-6">
              <h2 className="text-2xl font-semibold mb-4 text-foreground">Core Strategy Principles</h2>
              <div className="space-y-4">
                <div className="flex items-start gap-4">
                  <div className="w-8 h-8 rounded-full bg-primary/20 flex items-center justify-center flex-shrink-0">
                    <span className="text-primary font-bold">1</span>
                  </div>
                  <div>
                    <h3 className="font-semibold text-foreground">Aggressive by Default</h3>
                    <p className="text-muted-foreground">Start with maximum yield allocation (85% More.Markets) when risk is low.</p>
                  </div>
                </div>
                
                <div className="flex items-start gap-4">
                  <div className="w-8 h-8 rounded-full bg-primary/20 flex items-center justify-center flex-shrink-0">
                    <span className="text-primary font-bold">2</span>
                  </div>
                  <div>
                    <h3 className="font-semibold text-foreground">AI-Powered Early Warning</h3>
                    <p className="text-muted-foreground">ML models detect risk events before they materialize, triggering protective rebalancing.</p>
                  </div>
                </div>
                
                <div className="flex items-start gap-4">
                  <div className="w-8 h-8 rounded-full bg-primary/20 flex items-center justify-center flex-shrink-0">
                    <span className="text-primary font-bold">3</span>
                  </div>
                  <div>
                    <h3 className="font-semibold text-foreground">Rapid Recovery</h3>
                    <p className="text-muted-foreground">Return to aggressive positioning quickly when AI signals all-clear.</p>
                  </div>
                </div>
              </div>
            </div>

            <div className="bg-card border border-border rounded-lg p-6">
              <h2 className="text-2xl font-semibold mb-4 text-foreground">LLM Risk Engine</h2>
              <p className="text-muted-foreground mb-4">
                Our advanced language model analyzes multiple data sources to provide comprehensive risk assessment with human-like reasoning.
              </p>
              
              <div className="bg-muted rounded-lg p-4 font-mono text-sm">
                <div className="text-foreground mb-2"># Example AI Risk Assessment</div>
                <div className="text-muted-foreground">
                  Risk Level: <span className="text-primary">MODERATE</span><br/>
                  Primary Concerns: TVL concentration, gas price volatility<br/>
                  Recommended Action: Reduce More.Markets to 45%, increase staking<br/>
                  Confidence: 87%<br/>
                  Reassess In: 4 hours
                </div>
              </div>
            </div>
          </div>
        )

      case 'risk-matrix':
        return (
          <div className="space-y-8">
            <div>
              <h1 className="text-4xl font-bold mb-4 text-foreground">Dynamic Risk Allocation Matrix</h1>
              <p className="text-xl text-muted-foreground leading-relaxed">
                Five-tier allocation system that adapts to risk conditions detected by our AI engine.
              </p>
            </div>

            <div className="space-y-6">
              {Object.entries(riskAllocationMatrix).map(([riskLevel, allocation], index) => {
                const colors = [
                  'bg-red-500/10 border-red-500/20',
                  'bg-orange-500/10 border-orange-500/20', 
                  'bg-yellow-500/10 border-yellow-500/20',
                  'bg-blue-500/10 border-blue-500/20',
                  'bg-green-500/10 border-green-500/20'
                ]
                
                return (
                  <div key={riskLevel} className={`border rounded-lg p-6 ${colors[index]}`}>
                    <div className="flex items-center justify-between mb-4">
                      <h3 className="text-xl font-semibold text-foreground capitalize">
                        {riskLevel.replace('_', ' ')} Mode
                      </h3>
                      <span className="text-sm text-muted-foreground">
                        {index === 0 ? 'Maximum Aggression' : 
                         index === 1 ? 'High Yield Focus' :
                         index === 2 ? 'Balanced Approach' :
                         index === 3 ? 'Conservative Positioning' : 'Crisis Protection'}
                      </span>
                    </div>
                    
                    <div className="grid md:grid-cols-3 gap-4">
                      <div className="text-center">
                        <div className="text-2xl font-bold text-foreground">{(allocation.more_markets * 100).toFixed(0)}%</div>
                        <div className="text-sm text-muted-foreground">More.Markets</div>
                      </div>
                      <div className="text-center">
                        <div className="text-2xl font-bold text-foreground">{(allocation.staking * 100).toFixed(0)}%</div>
                        <div className="text-sm text-muted-foreground">Flow Staking</div>
                      </div>
                      <div className="text-center">
                        <div className="text-2xl font-bold text-foreground">{(allocation.punchswap_v2 * 100).toFixed(0)}%</div>
                        <div className="text-sm text-muted-foreground">PunchSwap V2</div>
                      </div>
                    </div>
                  </div>
                )
              })}
            </div>

            <div className="bg-card border border-border rounded-lg p-6">
              <h2 className="text-2xl font-semibold mb-4 text-foreground">Allocation Logic</h2>
              <p className="text-muted-foreground mb-4">
                The AI continuously evaluates market conditions and protocol health to determine the appropriate risk level:
              </p>
              <ul className="space-y-2 text-muted-foreground">
                <li className="flex items-start gap-2">
                  <ChevronRight className="w-4 h-4 mt-1 flex-shrink-0" />
                  <span><strong>Extreme Risk:</strong> Calm markets, low volatility, all protocols healthy</span>
                </li>
                <li className="flex items-start gap-2">
                  <ChevronRight className="w-4 h-4 mt-1 flex-shrink-0" />
                  <span><strong>High Risk:</strong> Favorable conditions with minor concerns</span>
                </li>
                <li className="flex items-start gap-2">
                  <ChevronRight className="w-4 h-4 mt-1 flex-shrink-0" />
                  <span><strong>Moderate Risk:</strong> Mixed signals requiring balanced approach</span>
                </li>
                <li className="flex items-start gap-2">
                  <ChevronRight className="w-4 h-4 mt-1 flex-shrink-0" />
                  <span><strong>Low Risk:</strong> Elevated concerns, defensive positioning needed</span>
                </li>
                <li className="flex items-start gap-2">
                  <ChevronRight className="w-4 h-4 mt-1 flex-shrink-0" />
                  <span><strong>Minimal Risk:</strong> Crisis conditions, maximum safety protocols</span>
                </li>
              </ul>
            </div>
          </div>
        )

      case 'market-regimes':
        return (
          <div className="space-y-8">
            <div>
              <h1 className="text-4xl font-bold mb-4 text-foreground">Market Regime Intelligence</h1>
              <p className="text-xl text-muted-foreground leading-relaxed">
                Advanced market classification system that adapts strategy based on broader market conditions beyond individual protocol risks.
              </p>
            </div>

            <div className="grid md:grid-cols-2 gap-6">
              {marketRegimes.map((regime, index) => (
                <div key={regime.name} className="border border-border rounded-lg p-6">
                  <div className="flex items-center gap-3 mb-3">
                    {regime.name.includes('Bull') && <TrendingUp className="w-5 h-5 text-green-500" />}
                    {regime.name.includes('Bear') && <TrendingDown className="w-5 h-5 text-red-500" />}
                    {regime.name.includes('Crisis') && <AlertTriangle className="w-5 h-5 text-red-600" />}
                    {regime.name.includes('Recovery') && <Activity className="w-5 h-5 text-blue-500" />}
                    {regime.name.includes('Sideways') && <BarChart3 className="w-5 h-5 text-yellow-500" />}
                    {regime.name.includes('High Volatility') && <Zap className="w-5 h-5 text-orange-500" />}
                    {regime.name.includes('Low Volatility') && <Target className="w-5 h-5 text-green-400" />}
                    {regime.name.includes('Black Swan') && <Shield className="w-5 h-5 text-purple-500" />}
                    <h3 className="text-lg font-semibold text-foreground">{regime.name}</h3>
                  </div>
                  <p className="text-sm text-muted-foreground mb-3">{regime.description}</p>
                  <div className="bg-muted rounded-lg p-3">
                    <div className="text-xs text-muted-foreground mb-1">Strategy:</div>
                    <div className="text-sm text-foreground">{regime.allocation}</div>
                  </div>
                </div>
              ))}
            </div>

            <div className="bg-card border border-border rounded-lg p-6">
              <h2 className="text-2xl font-semibold mb-4 text-foreground">Regime Detection Algorithm</h2>
              <p className="text-muted-foreground mb-4">
                Our AI analyzes multiple market indicators to classify current conditions:
              </p>
              
              <div className="bg-muted rounded-lg p-4 font-mono text-sm">
                <div className="text-foreground mb-2"># Market Regime Classification</div>
                <div className="text-muted-foreground">
                  Price Momentum: +12.3% (30d)<br/>
                  Volatility Index: 23.4 (moderate)<br/>
                  Volume Profile: Above average<br/>
                  Correlation: 0.67 (high)<br/>
                  <br/>
                  <span className="text-primary">Classified: Bull Market</span><br/>
                  Recommended: Aggressive positioning<br/>
                  Confidence: 91%
                </div>
              </div>
            </div>
          </div>
        )

      case 'performance':
        return (
          <div className="space-y-8">
            <div>
              <h1 className="text-4xl font-bold mb-4 text-foreground">Performance Metrics</h1>
              <p className="text-xl text-muted-foreground leading-relaxed">
                Aggressive AI-driven strategy significantly outperforms conservative approaches while maintaining principal protection.
              </p>
            </div>

            <div className="grid md:grid-cols-3 gap-6">
              {performanceMetrics.map((metric, index) => (
                <div key={metric.label} className="border border-border rounded-lg p-6 text-center">
                  <div className="text-3xl font-bold text-primary mb-2">{metric.value}</div>
                  <div className="font-semibold mb-1 text-foreground">{metric.label}</div>
                  <div className="text-sm text-muted-foreground">{metric.period}</div>
                </div>
              ))}
            </div>

            <div className="bg-card border border-border rounded-lg p-6">
              <h2 className="text-2xl font-semibold mb-4 text-foreground">Strategy Comparison</h2>
              <div className="overflow-x-auto">
                <table className="w-full">
                  <thead>
                    <tr className="border-b border-border">
                      <th className="text-left py-3 text-foreground">Strategy</th>
                      <th className="text-center py-3 text-foreground">Target APY</th>
                      <th className="text-center py-3 text-foreground">Max Drawdown</th>
                      <th className="text-center py-3 text-foreground">Sharpe Ratio</th>
                      <th className="text-center py-3 text-foreground">Response Time</th>
                    </tr>
                  </thead>
                  <tbody className="text-muted-foreground">
                    <tr className="border-b border-border">
                      <td className="py-3 font-medium">Conservative (40/40/20)</td>
                      <td className="text-center py-3">7.33%</td>
                      <td className="text-center py-3">0.00%</td>
                      <td className="text-center py-3">95.41</td>
                      <td className="text-center py-3">4 hours</td>
                    </tr>
                    <tr className="border-b border-border">
                      <td className="py-3 font-medium text-primary">AI-Aggressive (85/10/5)</td>
                      <td className="text-center py-3 text-primary">18.2%</td>
                      <td className="text-center py-3 text-primary">0.00%</td>
                      <td className="text-center py-3 text-primary">420+</td>
                      <td className="text-center py-3 text-primary">{'<'}100ms</td>
                    </tr>
                    <tr>
                      <td className="py-3 font-medium">Traditional DeFi</td>
                      <td className="text-center py-3">12.5%</td>
                      <td className="text-center py-3">-15.3%</td>
                      <td className="text-center py-3">2.1</td>
                      <td className="text-center py-3">Manual</td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        )

      case 'risk-management':
        return (
          <div className="space-y-8">
            <div>
              <h1 className="text-4xl font-bold mb-4 text-foreground">AI Risk Management System</h1>
              <p className="text-xl text-muted-foreground leading-relaxed">
                Multi-layered protection system that enables aggressive positioning through superior risk detection and rapid response.
              </p>
            </div>

            <div className="grid md:grid-cols-2 gap-6">
              <div className="border border-border rounded-lg p-6">
                <h3 className="text-lg font-semibold mb-4 text-foreground">Proactive Risk Detection</h3>
                <ul className="space-y-3 text-muted-foreground">
                  <li className="flex items-start gap-2">
                    <Brain className="w-4 h-4 mt-1 flex-shrink-0 text-primary" />
                    <span>LLM-powered anomaly detection with reasoning</span>
                  </li>
                  <li className="flex items-start gap-2">
                    <Activity className="w-4 h-4 mt-1 flex-shrink-0 text-primary" />
                    <span>Real-time protocol health monitoring</span>
                  </li>
                  <li className="flex items-start gap-2">
                    <TrendingUp className="w-4 h-4 mt-1 flex-shrink-0 text-primary" />
                    <span>Market sentiment analysis</span>
                  </li>
                  <li className="flex items-start gap-2">
                    <Zap className="w-4 h-4 mt-1 flex-shrink-0 text-primary" />
                    <span>Gas price and network congestion alerts</span>
                  </li>
                </ul>
              </div>

              <div className="border border-border rounded-lg p-6">
                <h3 className="text-lg font-semibold mb-4 text-foreground">Reactive Safeguards</h3>
                <ul className="space-y-3 text-muted-foreground">
                  <li className="flex items-start gap-2">
                    <Shield className="w-4 h-4 mt-1 flex-shrink-0 text-primary" />
                    <span>Automatic emergency exits at critical thresholds</span>
                  </li>
                  <li className="flex items-start gap-2">
                    <Target className="w-4 h-4 mt-1 flex-shrink-0 text-primary" />
                    <span>Circuit breakers for rapid market changes</span>
                  </li>
                  <li className="flex items-start gap-2">
                    <Clock className="w-4 h-4 mt-1 flex-shrink-0 text-primary" />
                    <span>Time-based position limits</span>
                  </li>
                  <li className="flex items-start gap-2">
                    <Database className="w-4 h-4 mt-1 flex-shrink-0 text-primary" />
                    <span>Multi-signature emergency controls</span>
                  </li>
                </ul>
              </div>
            </div>

            <div className="bg-card border border-border rounded-lg p-6">
              <h2 className="text-2xl font-semibold mb-4 text-foreground">Forward-Looking Risk Optimization</h2>
              <p className="text-muted-foreground mb-4">
                Unlike reactive systems, our AI predicts and positions for future risk scenarios:
              </p>
              
              <div className="bg-muted rounded-lg p-4 space-y-3">
                <div className="text-sm">
                  <span className="text-foreground font-medium">Predictive Signals:</span>
                  <div className="text-muted-foreground mt-1">
                    • TVL migration patterns suggesting protocol stress<br/>
                    • Correlation increases indicating systemic risk<br/>
                    • Liquidity depth changes across protocols<br/>
                    • Market maker behavior anomalies
                  </div>
                </div>
                
                <div className="text-sm">
                  <span className="text-foreground font-medium">Response Actions:</span>
                  <div className="text-muted-foreground mt-1">
                    • Pre-emptive rebalancing before events materialize<br/>
                    • Gradual position adjustments to minimize impact<br/>
                    • Opportunity identification during market dislocations<br/>
                    • Recovery positioning for post-event alpha capture
                  </div>
                </div>
              </div>
            </div>
          </div>
        )

      case 'ai-agent':
        return (
          <div className="space-y-8">
            <div>
              <h1 className="text-4xl font-bold mb-4 text-foreground">AI Agent Architecture</h1>
              <p className="text-xl text-muted-foreground leading-relaxed">
                Autonomous agent system with multiple operational cycles and intelligent decision-making capabilities.
              </p>
            </div>

            <div className="grid md:grid-cols-3 gap-6">
              <div className="border border-border rounded-lg p-6">
                <div className="w-12 h-12 rounded-lg bg-primary/20 flex items-center justify-center mb-4">
                  <Clock className="w-6 h-6 text-primary" />
                </div>
                <h3 className="text-lg font-semibold mb-2 text-foreground">Real-Time Monitoring</h3>
                <p className="text-sm text-muted-foreground mb-3">Continuous risk assessment and opportunity detection</p>
                <div className="text-xs text-muted-foreground">
                  <strong>Frequency:</strong> Every 30 seconds<br/>
                  <strong>Scope:</strong> All protocols and market conditions
                </div>
              </div>

              <div className="border border-border rounded-lg p-6">
                <div className="w-12 h-12 rounded-lg bg-primary/20 flex items-center justify-center mb-4">
                  <Bot className="w-6 h-6 text-primary" />
                </div>
                <h3 className="text-lg font-semibold mb-2 text-foreground">Strategic Rebalancing</h3>
                <p className="text-sm text-muted-foreground mb-3">Intelligent allocation adjustments based on AI analysis</p>
                <div className="text-xs text-muted-foreground">
                  <strong>Frequency:</strong> Variable (1hr - 24hr)<br/>
                  <strong>Scope:</strong> Portfolio optimization and risk management
                </div>
              </div>

              <div className="border border-border rounded-lg p-6">
                <div className="w-12 h-12 rounded-lg bg-primary/20 flex items-center justify-center mb-4">
                  <AlertTriangle className="w-6 h-6 text-primary" />
                </div>
                <h3 className="text-lg font-semibold mb-2 text-foreground">Emergency Response</h3>
                <p className="text-sm text-muted-foreground mb-3">Immediate action on critical risk thresholds</p>
                <div className="text-xs text-muted-foreground">
                  <strong>Frequency:</strong> Instant triggers<br/>
                  <strong>Scope:</strong> Crisis protection and damage limitation
                </div>
              </div>
            </div>

            <div className="bg-card border border-border rounded-lg p-6">
              <h2 className="text-2xl font-semibold mb-4 text-foreground">Agent Decision Tree</h2>
              <div className="bg-muted rounded-lg p-4 font-mono text-sm">
                <div className="text-foreground mb-2"># AI Agent Logic Flow</div>
                <div className="text-muted-foreground space-y-1">
                  <div>1. Assess current risk level across all protocols</div>
                  <div>2. Determine market regime classification</div>
                  <div>3. Calculate optimal allocation for conditions</div>
                  <div>4. Compare with current portfolio state</div>
                  <div>5. If deviation {'>'} threshold: execute rebalance</div>
                  <div>6. Monitor execution and adjust if needed</div>
                  <div>7. Log decisions and outcomes for learning</div>
                </div>
              </div>
            </div>
          </div>
        )

      case 'api':
        return (
          <div className="space-y-8">
            <div>
              <h1 className="text-4xl font-bold mb-4 text-foreground">API Reference</h1>
              <p className="text-xl text-muted-foreground leading-relaxed">
                Developer documentation for integrating with TroveFi's AI-driven risk assessment and yield optimization systems.
              </p>
            </div>

            <div className="bg-card border border-border rounded-lg p-6">
              <h2 className="text-2xl font-semibold mb-4 text-foreground">Core Endpoints</h2>
              <div className="space-y-6">
                <div className="border border-border rounded-lg p-4">
                  <div className="flex items-center gap-3 mb-2">
                    <span className="px-2 py-1 bg-green-100 text-green-800 text-xs font-mono rounded dark:bg-green-900/30 dark:text-green-400">GET</span>
                    <code className="text-foreground font-mono">/api/v1/ai/risk-assessment</code>
                  </div>
                  <p className="text-muted-foreground mb-2">Get real-time AI risk analysis for protocols or portfolios.</p>
                  <details className="text-sm text-muted-foreground">
                    <summary className="cursor-pointer">Parameters</summary>
                    <div className="mt-2 pl-4 font-mono">
                      protocols: string[] - Protocol addresses<br/>
                      market_regime: boolean - Include market analysis<br/>
                      risk_matrix: boolean - Return allocation recommendations
                    </div>
                  </details>
                </div>

                <div className="border border-border rounded-lg p-4">
                  <div className="flex items-center gap-3 mb-2">
                    <span className="px-2 py-1 bg-blue-100 text-blue-800 text-xs font-mono rounded dark:bg-blue-900/30 dark:text-blue-400">POST</span>
                    <code className="text-foreground font-mono">/api/v1/ai/optimize-allocation</code>
                  </div>
                  <p className="text-muted-foreground mb-2">Generate optimal allocation using AI strategy engine.</p>
                  <details className="text-sm text-muted-foreground">
                    <summary className="cursor-pointer">Request Body</summary>
                    <div className="mt-2 pl-4 font-mono">
                      portfolio_size: number - Total portfolio value<br/>
                      risk_tolerance: string - aggressive | moderate | conservative<br/>
                      market_conditions: object - Current market context
                    </div>
                  </details>
                </div>
              </div>
            </div>

            <div className="bg-card border border-border rounded-lg p-6">
              <h2 className="text-2xl font-semibold mb-4 text-foreground">AI Strategy Response</h2>
              <div className="bg-muted rounded-lg p-4 font-mono text-sm overflow-x-auto">
                <pre className="text-muted-foreground">
{`{
  "risk_level": "moderate_risk",
  "market_regime": "bull_market",
  "allocation": {
    "more_markets": 0.65,
    "staking": 0.25,
    "punchswap_v2": 0.10
  },
  "reasoning": "Market momentum positive, protocol health good, moderate positioning recommended",
  "confidence": 0.87,
  "next_assessment": "2024-01-15T16:00:00Z",
  "risk_factors": [
    "TVL concentration in lending protocols",
    "Elevated gas prices affecting yields"
  ]
}`}
                </pre>
              </div>
            </div>
          </div>
        )

      default:
        return null
    }
  }

  return (
    <div className={`min-h-screen transition-colors duration-200 ${
      darkMode 
        ? 'bg-gray-900 text-white' 
        : 'bg-white text-gray-900'
    }`}>
      {/* Header */}
      <header className={`border-b transition-colors ${
        darkMode ? 'border-gray-800' : 'border-gray-200'
      }`}>
        <div className="max-w-7xl mx-auto px-6 py-4 flex items-center justify-between">
          <div className="flex items-center gap-4">
            <Link 
              href="/" 
              className={`flex items-center gap-2 transition-colors ${
                darkMode ? 'text-gray-400 hover:text-white' : 'text-gray-600 hover:text-gray-900'
              }`}
            >
              <ArrowLeft className="w-4 h-4" />
              <span>Back to Home</span>
            </Link>
            
            <div className="flex items-center gap-3">
              <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-green-400 to-blue-500 flex items-center justify-center">
                <BookOpen className="w-4 h-4 text-white" />
              </div>
              <span className="text-xl font-semibold">TroveFi Documentation</span>
            </div>
          </div>

          <button
            onClick={() => setDarkMode(!darkMode)}
            className={`p-2 rounded-lg transition-colors ${
              darkMode 
                ? 'bg-gray-800 hover:bg-gray-700 text-yellow-400' 
                : 'bg-gray-100 hover:bg-gray-200 text-gray-700'
            }`}
          >
            {darkMode ? <Sun className="w-4 h-4" /> : <Moon className="w-4 h-4" />}
          </button>
        </div>
      </header>

      {/* Main Layout */}
      <div className="max-w-7xl mx-auto px-6 py-8 flex gap-8">
        {/* Sidebar */}
        <div className="w-64 flex-shrink-0">
          <div className={`rounded-lg border p-4 sticky top-8 ${
            darkMode ? 'bg-gray-800 border-gray-700' : 'bg-gray-50 border-gray-200'
          }`}>
            <nav className="space-y-2">
              {sections.map((section) => (
                <button
                  key={section.id}
                  onClick={() => setActiveSection(section.id)}
                  className={`w-full flex items-center gap-3 px-3 py-2 rounded-lg text-left transition-colors ${
                    activeSection === section.id
                      ? darkMode
                        ? 'bg-gray-700 text-white'
                        : 'bg-blue-100 text-blue-900'
                      : darkMode
                        ? 'text-gray-400 hover:text-white hover:bg-gray-700'
                        : 'text-gray-600 hover:text-gray-900 hover:bg-gray-100'
                  }`}
                >
                  <section.icon className="w-4 h-4" />
                  <span className="text-sm font-medium">{section.title}</span>
                </button>
              ))}
            </nav>
          </div>
        </div>

        {/* Main Content */}
        <div className="flex-1 min-w-0">
          <motion.div
            key={activeSection}
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.3 }}
            className={`rounded-lg border p-8 ${
              darkMode ? 'bg-gray-800 border-gray-700' : 'bg-white border-gray-200'
            }`}
            style={{
              '--foreground': darkMode ? 'rgb(255, 255, 255)' : 'rgb(17, 24, 39)',
              '--muted-foreground': darkMode ? 'rgb(156, 163, 175)' : 'rgb(107, 114, 128)',
              '--background': darkMode ? 'rgb(17, 24, 39)' : 'rgb(255, 255, 255)',
              '--card': darkMode ? 'rgb(31, 41, 55)' : 'rgb(249, 250, 251)',
              '--border': darkMode ? 'rgb(55, 65, 81)' : 'rgb(229, 231, 235)',
              '--muted': darkMode ? 'rgb(55, 65, 81)' : 'rgb(243, 244, 246)',
              '--primary': darkMode ? 'rgb(34, 197, 94)' : 'rgb(59, 130, 246)'
            } as any}
          >
            {renderContent()}
          </motion.div>
        </div>
      </div>

      <style jsx global>{`
        .dark {
          color-scheme: dark;
        }
        .light {
          color-scheme: light;
        }
        
        :root {
          --foreground: rgb(17, 24, 39);
          --muted-foreground: rgb(107, 114, 128);
          --background: rgb(255, 255, 255);
          --card: rgb(249, 250, 251);
          --border: rgb(229, 231, 235);
          --muted: rgb(243, 244, 246);
          --primary: rgb(59, 130, 246);
        }
        
        .dark {
          --foreground: rgb(255, 255, 255);
          --muted-foreground: rgb(156, 163, 175);
          --background: rgb(17, 24, 39);
          --card: rgb(31, 41, 55);
          --border: rgb(55, 65, 81);
          --muted: rgb(55, 65, 81);
          --primary: rgb(34, 197, 94);
        }
        
        .text-foreground { color: var(--foreground); }
        .text-muted-foreground { color: var(--muted-foreground); }
        .bg-background { background-color: var(--background); }
        .bg-card { background-color: var(--card); }
        .border-border { border-color: var(--border); }
        .bg-muted { background-color: var(--muted); }
        .text-primary { color: var(--primary); }
        .bg-primary\\/10 { background-color: color-mix(in srgb, var(--primary) 10%, transparent); }
        .bg-primary\\/20 { background-color: color-mix(in srgb, var(--primary) 20%, transparent); }
        .border-primary\\/20 { border-color: color-mix(in srgb, var(--primary) 20%, transparent); }
      `}</style>
    </div>
  )
}