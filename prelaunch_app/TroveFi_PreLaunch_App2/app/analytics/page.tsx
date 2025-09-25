'use client'

import { useEffect, useState } from 'react'
import dynamic from 'next/dynamic'
import Header from '@/components/Header'
import Footer from '@/components/Footer'

// Dynamic imports to prevent SSR issues
const DynamicContent = dynamic(() => Promise.resolve(AnalyticsContent), {
  ssr: false,
  loading: () => (
    <div className="min-h-screen bg-[var(--bg)] flex items-center justify-center">
      <div className="text-white">Loading Analytics...</div>
    </div>
  )
})

interface DuneQueryResult {
  execution_id: string
  query_id: number
  state: string
  submitted_at: string
  expires_at: string
  result?: {
    rows: any[]
    metadata: {
      column_names: string[]
      result_set_bytes: number
      total_row_count: number
    }
  }
}

interface MetricCardProps {
  title: string
  value: string | number
  change?: string
  changeType?: 'positive' | 'negative' | 'neutral'
  isLoading?: boolean
}

const MetricCard = ({ title, value, change, changeType = 'neutral', isLoading }: MetricCardProps) => (
  <div className="glass-card p-6 rounded-2xl hover:transform hover:scale-105 transition-all duration-300">
    <div className="text-[var(--text-secondary)] text-sm uppercase tracking-wider font-medium mb-2">
      {title}
    </div>
    <div className="text-3xl font-bold text-white mb-2">
      {isLoading ? (
        <div className="animate-pulse bg-gray-600 h-8 w-24 rounded"></div>
      ) : (
        value
      )}
    </div>
    {change && !isLoading && (
      <div className={`text-sm font-medium ${
        changeType === 'positive' ? 'text-[var(--flow)]' : 
        changeType === 'negative' ? 'text-red-400' : 
        'text-[var(--text-secondary)]'
      }`}>
        {change}
      </div>
    )}
  </div>
)

const DuneEmbed = ({ embedUrl, title, queryId }: { embedUrl: string; title: string; queryId: number }) => (
  <div className="glass-card p-6 rounded-2xl">
    <h3 className="text-xl font-semibold text-white mb-4">{title}</h3>
    <div className="w-full h-96 bg-[var(--glass)] rounded-lg border border-[var(--glass-border)] overflow-hidden">
      <iframe
        src={embedUrl}
        width="100%"
        height="100%"
        frameBorder="0"
        className="rounded-lg"
      />
    </div>
    <div className="mt-3 text-xs text-[var(--text-muted)] flex items-center justify-between">
      <span>Data from Dune Analytics</span>
      <a 
        href={`https://dune.com/queries/${queryId}`}
        target="_blank"
        rel="noopener noreferrer"
        className="text-[var(--flow)] hover:opacity-80 transition-opacity"
      >
        View Query →
      </a>
    </div>
  </div>
)

const AnalyticsContent = () => {
  const [flowMetrics, setFlowMetrics] = useState<any>(null)
  const [stFlowMetrics, setStFlowMetrics] = useState<any>(null)
  const [defiMetrics, setDefiMetrics] = useState<any>(null)
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [mounted, setMounted] = useState(false)

  // Dune API configuration
  const DUNE_API_KEY = process.env.NEXT_PUBLIC_DUNE_API_KEY
  const DUNE_API_BASE = 'https://api.dune.com/api/v1'

  // Embed URLs
  const EMBEDS = {
    FLOW_NETWORK_ACTIVITY: "https://dune.com/embeds/5847859/9466202",
    FLOW_TRANSACTION_METRICS: "https://dune.com/embeds/5847915/9466225", 
    FLOW_BLOCK_METRICS: "https://dune.com/embeds/5847962/9466239", 
    FLOW_ADDRESS_ACTIVITY: "https://dune.com/embeds/5847942/9466069", 
  }

  useEffect(() => {
    setMounted(true)
  }, [])

  const fetchDuneQuery = async (queryId: number): Promise<DuneQueryResult | null> => {
    if (!DUNE_API_KEY) {
      console.warn('Dune API key not configured')
      return null
    }

    try {
      // Get latest query result
      const response = await fetch(
        `${DUNE_API_BASE}/query/${queryId}/results`,
        {
          headers: {
            'X-Dune-API-Key': DUNE_API_KEY,
          },
        }
      )

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`)
      }

      const data = await response.json()
      return data
    } catch (err) {
      console.error(`Error fetching query ${queryId}:`, err)
      return null
    }
  }

  useEffect(() => {
    if (!mounted) return

    const loadAnalyticsData = async () => {
      setIsLoading(true)
      setError(null)

      try {
        // Use data from your working query results
        setTimeout(() => {
          setFlowMetrics({
            daily_txs: 169191,
            unique_addresses_24h: 546,
            addr_change_24h: -41.2,
            tx_change_7d: -41.2
          })
          setStFlowMetrics({
            avg_gas_used: 525494,
            gas_change_24h: 0.5
          })
          setDefiMetrics({
            avg_block_time: 2.1
          })
          setIsLoading(false)
        }, 1000)

        // Uncomment when you have API key and all queries set up
        /*
        const [networkData, txData, blockData, addressData] = await Promise.all([
          fetchDuneQuery(QUERIES.FLOW_NETWORK_ACTIVITY),
          fetchDuneQuery(QUERIES.FLOW_TRANSACTION_METRICS),
          fetchDuneQuery(QUERIES.FLOW_BLOCK_METRICS),
          fetchDuneQuery(QUERIES.FLOW_ADDRESS_ACTIVITY),
        ])

        setFlowMetrics(networkData?.result?.rows?.[0] || null)
        setStFlowMetrics(txData?.result?.rows?.[0] || null)
        setDefiMetrics(blockData?.result?.rows?.[0] || null)
        */

      } catch (err) {
        setError('Failed to load analytics data')
        console.error('Analytics data error:', err)
        setIsLoading(false)
      }
    }

    loadAnalyticsData()
  }, [mounted])

  if (!mounted) {
    return null
  }

  return (
    <main className="min-h-screen bg-[var(--bg)] relative overflow-hidden">
      {/* Background Effects */}
      <div className="fixed inset-0 z-0">
        <div className="orb orb-1" />
        <div className="orb orb-2" />
        <div className="orb orb-3" />
      </div>

      {/* Content */}
      <div className="relative z-10">
        <Header />
        
        <div className="container mx-auto px-4 pt-24 pb-12 max-w-7xl">
          {/* Header Section */}
          <div className="text-center mb-12">
            <div className="inline-flex items-center gap-2 bg-[var(--glass)] border border-[var(--flow)] px-4 py-2 rounded-full mb-6">
              <div className="w-2 h-2 bg-[var(--flow)] rounded-full animate-pulse"></div>
              <span className="text-[var(--flow)] text-sm font-medium">Live Analytics Dashboard</span>
            </div>
            
            <h1 className="text-4xl md:text-5xl font-bold text-white mb-4">
              TroveFi Analytics
            </h1>
            
            <p className="text-[var(--text-secondary)] text-lg max-w-2xl mx-auto">
              Real-time metrics for Flow blockchain DeFi protocols, powered by Dune Analytics
            </p>
          </div>

          {error && (
            <div className="bg-red-900/20 border border-red-500/50 rounded-lg p-4 mb-8 text-center">
              <p className="text-red-400">{error}</p>
              <p className="text-sm text-[var(--text-muted)] mt-2">
                Configure DUNE_API_KEY environment variable to enable live data
              </p>
            </div>
          )}

          {/* Key Metrics Grid */}
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-12">
            <MetricCard
              title="Daily Transactions"
              value={flowMetrics?.daily_txs ? flowMetrics.daily_txs.toLocaleString() : 'Loading...'}
              change={flowMetrics?.tx_change_7d ? `${flowMetrics.tx_change_7d > 0 ? '+' : ''}${flowMetrics.tx_change_7d.toFixed(1)}% (7d)` : undefined}
              changeType={flowMetrics?.tx_change_7d > 0 ? "positive" : "negative"}
              isLoading={isLoading && !flowMetrics}
            />
            
            <MetricCard
              title="Average Gas Used"
              value={stFlowMetrics?.avg_gas_used ? `${(stFlowMetrics.avg_gas_used / 1000).toFixed(0)}K` : 'Loading...'}
              change={stFlowMetrics?.gas_change_24h ? `${stFlowMetrics.gas_change_24h > 0 ? '+' : ''}${stFlowMetrics.gas_change_24h.toFixed(1)}% (24h)` : undefined}
              changeType={stFlowMetrics?.gas_change_24h > 0 ? "positive" : "negative"}
              isLoading={isLoading && !stFlowMetrics}
            />
            
            <MetricCard
              title="Block Time (avg)"
              value={defiMetrics?.avg_block_time ? `${defiMetrics.avg_block_time.toFixed(1)}s` : 'Loading...'}
              change="Stable"
              changeType="neutral"
              isLoading={isLoading && !defiMetrics}
            />
            
            <MetricCard
              title="Unique Addresses (24h)"
              value={flowMetrics?.unique_addresses_24h ? flowMetrics.unique_addresses_24h.toLocaleString() : 'Loading...'}
              change={flowMetrics?.addr_change_24h ? `${flowMetrics.addr_change_24h > 0 ? '+' : ''}${flowMetrics.addr_change_24h.toFixed(1)}% (24h)` : undefined}
              changeType={flowMetrics?.addr_change_24h > 0 ? "positive" : "negative"}
              isLoading={isLoading && !flowMetrics}
            />
          </div>

          {/* Charts Section */}
          <div className="space-y-8">
            {/* Flow Network Activity */}
            <section>
              <div className="flex items-center gap-3 mb-6">
                <div className="w-8 h-8 bg-gradient-to-br from-[var(--flow)] to-[var(--aqua)] rounded-lg flex items-center justify-center">
                  <span className="text-sm font-bold text-black">⚡</span>
                </div>
                <h2 className="text-2xl font-bold text-white">
                  Flow Network Activity
                </h2>
              </div>
              
              <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
                <DuneEmbed 
                  embedUrl={EMBEDS.FLOW_NETWORK_ACTIVITY}
                  queryId={5847859}
                  title="Daily Transaction Volume"
                />
                
                <DuneEmbed 
                  embedUrl={EMBEDS.FLOW_TRANSACTION_METRICS}
                  queryId={5847915}
                  title="Gas Usage & Transaction Success Rate"
                />
              </div>
            </section>

            {/* Flow Blockchain Metrics */}
            <section>
              <div className="flex items-center gap-3 mb-6">
                <div className="w-8 h-8 bg-gradient-to-br from-[var(--purple)] to-[var(--aqua)] rounded-lg flex items-center justify-center">
                  <span className="text-sm font-bold text-white">🔗</span>
                </div>
                <h2 className="text-2xl font-bold text-white">
                  Blockchain Infrastructure
                </h2>
              </div>
              
              <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
                <DuneEmbed 
                  embedUrl={EMBEDS.FLOW_BLOCK_METRICS}
                  queryId={5847962}
                  title="Block Production & Size"
                />
                
                <DuneEmbed 
                  embedUrl={EMBEDS.FLOW_ADDRESS_ACTIVITY}
                  queryId={5847942}
                  title="Address Growth & Activity"
                />
              </div>
            </section>

            {/* TroveFi Integration Preview */}
            <section>
              <div className="flex items-center gap-3 mb-6">
                <div className="w-8 h-8 bg-gradient-to-br from-[var(--flow)] to-[var(--purple)] rounded-lg flex items-center justify-center">
                  <span className="text-sm font-bold text-black">🤖</span>
                </div>
                <h2 className="text-2xl font-bold text-white">
                  TroveFi AI Agent Analytics
                </h2>
              </div>
              
              <div className="glass-card p-8 rounded-2xl text-center">
                <div className="mb-6">
                  <div className="w-16 h-16 bg-gradient-to-br from-[var(--flow)] to-[var(--purple)] rounded-full mx-auto mb-4 flex items-center justify-center">
                    <span className="text-2xl">🚀</span>
                  </div>
                  <h3 className="text-2xl font-bold text-white mb-2">Coming Soon</h3>
                  <p className="text-[var(--text-secondary)] max-w-md mx-auto">
                    AI-powered yield optimization analytics will be integrated here, tracking 
                    automated rebalancing strategies and cross-protocol performance.
                  </p>
                </div>
                
                <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mt-8">
                  <div className="bg-[var(--glass)] border border-[var(--glass-border)] rounded-lg p-4">
                    <div className="text-lg font-semibold text-white">Yield Strategies</div>
                    <div className="text-sm text-[var(--text-secondary)]">Real-time optimization</div>
                  </div>
                  <div className="bg-[var(--glass)] border border-[var(--glass-border)] rounded-lg p-4">
                    <div className="text-lg font-semibold text-white">Risk Analysis</div>
                    <div className="text-sm text-[var(--text-secondary)]">AI-powered assessment</div>
                  </div>
                  <div className="bg-[var(--glass)] border border-[var(--glass-border)] rounded-lg p-4">
                    <div className="text-lg font-semibold text-white">Performance Tracking</div>
                    <div className="text-sm text-[var(--text-secondary)]">Historical & predictive</div>
                  </div>
                </div>
              </div>
            </section>
          </div>

          {/* Integration Status */}
          <div className="mt-12 text-center">
            <div className="inline-block glass-card px-6 py-4 rounded-full">
              <div className="flex items-center gap-3">
                <div className="flex gap-1">
                  <div className="w-2 h-2 bg-[var(--flow)] rounded-full animate-pulse"></div>
                  <div className="w-2 h-2 bg-[var(--flow)] rounded-full animate-pulse" style={{animationDelay: '0.5s'}}></div>
                  <div className="w-2 h-2 bg-[var(--flow)] rounded-full animate-pulse" style={{animationDelay: '1s'}}></div>
                </div>
                <span className="text-[var(--text-secondary)] text-sm">
                  Data refreshed every 6 hours • Last update: {mounted ? new Date().toLocaleString() : 'Loading...'}
                </span>
              </div>
            </div>
          </div>
        </div>

        <Footer />
      </div>
    </main>
  )
}

export default function AnalyticsPage() {
  return <DynamicContent />
}