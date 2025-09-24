'use client'

import React, { useState, useEffect } from 'react';
import { motion } from 'framer-motion';
import Image from 'next/image';
import { Clock, TrendingUp, TrendingDown, Wallet, DollarSign, ExternalLink, RefreshCw } from 'lucide-react';

// Your actual contract addresses
const CONTRACTS = {
  coreVault: '0xbD82c706e3632972A00E288a54Ea50c958b865b2',
  vaultExtension: '0xBaF543b07e01F0Ed02dFEa5dfbAd38167AC9be57',
  vault: '0xF670C5F28cFA8fd7Ed16AaE81aA9AF2b304F0b4B'
};

interface ActivityItem {
  id: string;
  type: 'deposit' | 'withdraw' | 'yield_claim' | 'native_deposit' | 'native_withdraw' | 'risk_update';
  userAddress: string;
  amount: string;
  asset?: string;
  timestamp: number;
  txHash: string;
  blockNumber: number;
  riskLevel?: string;
}

const RISK_LEVELS = ['LOW', 'MEDIUM', 'HIGH'];

const formatTimeAgo = (timestamp: number): string => {
  const now = Date.now();
  const diff = now - timestamp;
  const minutes = Math.floor(diff / (1000 * 60));
  const hours = Math.floor(diff / (1000 * 60 * 60));
  const days = Math.floor(diff / (1000 * 60 * 60 * 24));
  
  if (days > 0) return `${days}d ago`;
  if (hours > 0) return `${hours}h ago`;
  if (minutes > 0) return `${minutes}m ago`;
  return 'Just now';
};

const formatAddress = (address: string): string => {
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
};

const formatAmount = (amount: string): string => {
  const num = parseFloat(amount);
  if (num >= 10000) return `${(num / 1000).toFixed(1)}k`;
  if (num >= 1000) return `${(num / 1000).toFixed(2)}k`;
  if (num >= 1) return num.toFixed(2);
  return num.toFixed(6);
};

const getAssetSymbol = (asset?: string): string => {
  const assetMap: { [key: string]: string } = {
    '0x2aaBea2058b5aC2D339b163C6Ab6f2b6d53aabED': 'USDF',
    '0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e': 'WFLOW',
    '0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590': 'WETH',
    '0xF1815bd50389c46847f0Bda824eC8da914045D14': 'STGUSD',
    '0x674843C06FF83502ddb4D37c2E09C01cdA38cbc8': 'USDT',
    '0x7f27352D5F83Db87a5A3E00f4B07Cc2138D8ee52': 'USDC.e',
    '0x5598c0652B899EB40f169Dd5949BdBE0BF36ffDe': 'STFLOW',
    '0x1b97100eA1D7126C4d60027e231EA4CB25314bdb': 'ANKRFLOW',
    '0xA0197b2044D28b08Be34d98b23c9312158Ea9A18': 'CBBTC',
    'native': 'FLOW'
  };
  return asset ? (assetMap[asset] || 'Unknown') : 'FLOW';
};

const getActivityIcon = (type: ActivityItem['type']) => {
  switch (type) {
    case 'deposit':
    case 'native_deposit':
      return <TrendingUp className="w-4 h-4 text-[var(--flow)]" />;
    case 'withdraw':
    case 'native_withdraw':
      return <TrendingDown className="w-4 h-4 text-red-400" />;
    case 'yield_claim':
      return <DollarSign className="w-4 h-4 text-[var(--aqua)]" />;
    case 'risk_update':
      return <Wallet className="w-4 h-4 text-[var(--purple)]" />;
    default:
      return <Wallet className="w-4 h-4 text-white/60" />;
  }
};

const getActivityColor = (type: ActivityItem['type']) => {
  switch (type) {
    case 'deposit':
    case 'native_deposit':
      return 'border-[var(--flow)]/20 bg-[var(--flow)]/5';
    case 'withdraw':
    case 'native_withdraw':
      return 'border-red-400/20 bg-red-400/5';
    case 'yield_claim':
      return 'border-[var(--aqua)]/20 bg-[var(--aqua)]/5';
    case 'risk_update':
      return 'border-[var(--purple)]/20 bg-[var(--purple)]/5';
    default:
      return 'border-white/10 bg-white/5';
  }
};

const getActivityLabel = (activity: ActivityItem) => {
  switch (activity.type) {
    case 'deposit':
      return `Deposited ${formatAmount(activity.amount)} ${getAssetSymbol(activity.asset)}`;
    case 'native_deposit':
      return `Deposited ${formatAmount(activity.amount)} FLOW`;
    case 'withdraw':
      return `Withdrew ${formatAmount(activity.amount)} ${getAssetSymbol(activity.asset)}`;
    case 'native_withdraw':
      return `Withdrew ${formatAmount(activity.amount)} FLOW`;
    case 'yield_claim':
      return `Claimed ${formatAmount(activity.amount)} USDF Yield`;
    case 'risk_update':
      return `Risk Level → ${activity.riskLevel}`;
    default:
      return 'Activity';
  }
};

// Real activity fetching from Flow RPC
const fetchActivitiesFromFlow = async (): Promise<ActivityItem[]> => {
  try {
    // Using Flow testnet RPC endpoint
    const rpcUrl = 'https://testnet.evm.nodes.onflow.org';
    
    // Get latest block number
    const latestBlockResponse = await fetch(rpcUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jsonrpc: '2.0',
        method: 'eth_blockNumber',
        params: [],
        id: 1
      })
    });

    if (!latestBlockResponse.ok) {
      throw new Error('Failed to fetch latest block');
    }

    const latestBlockData = await latestBlockResponse.json();
    
    if (latestBlockData.error) {
      throw new Error(latestBlockData.error.message);
    }

    const latestBlock = parseInt(latestBlockData.result, 16);
    
    // TODO: Implement actual event log parsing here
    // For now, return empty array until real blockchain integration is added
    // This prevents showing fake data
    const activities: ActivityItem[] = [];

    return activities;

  } catch (error) {
    console.error('Error fetching activities:', error);
    throw error;
  }
};

export default function UserActivity() {
  const [activities, setActivities] = useState<ActivityItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [isLive, setIsLive] = useState(true);
  const [lastUpdate, setLastUpdate] = useState<Date | null>(null);

  const fetchActivities = async () => {
    try {
      setError(null);
      const newActivities = await fetchActivitiesFromFlow();
      setActivities(newActivities);
      setLastUpdate(new Date());
    } catch (err) {
      console.error('Error fetching activities:', err);
      setError(err instanceof Error ? err.message : 'Failed to fetch activities');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchActivities();
    
    // Refresh every 30 seconds
    const interval = setInterval(() => {
      if (isLive) {
        fetchActivities();
      }
    }, 30000);

    return () => clearInterval(interval);
  }, [isLive]);

  const handleRefresh = () => {
    setLoading(true);
    fetchActivities();
  };

  return (
    <section className="py-20 px-6 relative">
      {/* Background gradient */}
      <div className="absolute inset-0 bg-gradient-to-b from-transparent via-[var(--aqua)]/5 to-transparent"></div>
      
      <div className="max-w-6xl mx-auto">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          className="text-center mb-12"
        >
          <h2 className="text-4xl font-bold mb-4">
            <span className="block text-white/40 text-2xl font-normal mb-2">Live Activity</span>
            Recent User Interactions
          </h2>
          <p className="text-xl text-white/70">
            Real-time feed from your Flow testnet contracts
          </p>
        </motion.div>

        <motion.div
          initial={{ opacity: 0, y: 40 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          className="glass-card rounded-2xl p-8 border border-white/10"
        >
          {/* Header with live indicator */}
          <div className="flex items-center justify-between mb-8">
            <div className="flex items-center gap-4">
              <div className="w-12 h-12 rounded-xl bg-gradient-to-br from-[var(--flow)]/20 to-[var(--aqua)]/20 flex items-center justify-center border border-white/10">
                <Wallet className="w-6 h-6 text-[var(--flow)]" />
              </div>
              <div>
                <h3 className="text-2xl font-semibold">Activity Feed</h3>
                <div className="flex items-center gap-2 mt-1">
                  <div className={`w-2 h-2 rounded-full ${isLive && !loading ? 'bg-[var(--flow)] animate-pulse' : 'bg-white/30'}`}></div>
                  <span className="text-sm text-white/60 font-mono">
                    {loading ? 'LOADING' : isLive ? 'LIVE' : 'PAUSED'}
                  </span>
                  {lastUpdate && (
                    <>
                      <span className="text-white/30">•</span>
                      <span className="text-xs text-white/50">
                        Updated {lastUpdate.toLocaleTimeString()}
                      </span>
                    </>
                  )}
                </div>
              </div>
            </div>

            {/* Controls */}
            <div className="flex items-center gap-3">
              <button
                onClick={handleRefresh}
                disabled={loading}
                className="flex items-center gap-2 px-3 py-2 bg-white/5 hover:bg-white/10 border border-white/10 hover:border-white/20 rounded-lg transition-colors text-sm text-white/80"
              >
                <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
                Refresh
              </button>
              
              <button
                onClick={() => setIsLive(!isLive)}
                className={`px-3 py-2 rounded-lg text-sm font-medium transition-colors ${
                  isLive 
                    ? 'bg-[var(--flow)]/20 text-[var(--flow)] border border-[var(--flow)]/30' 
                    : 'bg-white/10 text-white/60 border border-white/20'
                }`}
              >
                {isLive ? 'Live' : 'Paused'}
              </button>
            </div>
          </div>

          {/* Error state */}
          {error && (
            <div className="mb-6 p-4 bg-red-500/10 border border-red-500/20 rounded-xl">
              <p className="text-red-200 text-sm">Error: {error}</p>
              <button 
                onClick={handleRefresh} 
                className="mt-2 text-xs text-red-300 underline hover:text-red-200"
              >
                Retry
              </button>
            </div>
          )}

          {/* Activity List */}
          <div className="space-y-3 max-h-96 overflow-y-auto custom-scrollbar">
            {loading ? (
              <div className="text-center py-12 text-white/50">
                <RefreshCw className="w-12 h-12 mx-auto mb-4 opacity-50 animate-spin" />
                <p>Loading transaction data from Flow testnet...</p>
              </div>
            ) : activities.length === 0 ? (
              <div className="text-center py-12 text-white/50">
                <Clock className="w-12 h-12 mx-auto mb-4 opacity-50" />
                <p>No recent activity found</p>
                <p className="text-xs text-white/40 mt-2">
                  Connect to Flow testnet and interact with the vault to see activity
                </p>
                <button 
                  onClick={handleRefresh} 
                  className="mt-3 text-sm text-white/70 underline hover:text-white/90"
                >
                  Check again
                </button>
              </div>
            ) : (
              activities.map((activity, index) => (
                <motion.div
                  key={activity.id}
                  initial={{ opacity: 0, x: -20 }}
                  animate={{ opacity: 1, x: 0 }}
                  transition={{ delay: index * 0.05 }}
                  className={`p-4 rounded-xl border ${getActivityColor(activity.type)} hover:border-white/20 transition-all group`}
                >
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-4 flex-1">
                      <div className="w-10 h-10 rounded-full bg-white/5 border border-white/10 flex items-center justify-center group-hover:border-white/20 transition-colors">
                        {getActivityIcon(activity.type)}
                      </div>
                      
                      <div className="flex-1">
                        <div className="flex items-center gap-3 mb-1">
                          <span className="font-medium text-white/90">
                            {getActivityLabel(activity)}
                          </span>
                          {activity.riskLevel && (
                            <span className="px-2 py-0.5 bg-white/10 text-xs rounded-full text-white/70">
                              {activity.riskLevel}
                            </span>
                          )}
                        </div>
                        <div className="flex items-center gap-3 text-sm text-white/60">
                          <span className="font-mono">{formatAddress(activity.userAddress)}</span>
                          <span>•</span>
                          <span>{formatTimeAgo(activity.timestamp)}</span>
                          <span>•</span>
                          <span>Block {activity.blockNumber.toLocaleString()}</span>
                        </div>
                      </div>
                    </div>

                    {/* Transaction hash - clickable */}
                    <button
                      onClick={() => window.open(`https://evm-testnet.flowscan.io/tx/${activity.txHash}`, '_blank')}
                      className="flex items-center gap-1 text-xs text-white/40 hover:text-white/80 font-mono transition-colors group"
                      title="View on Flowscan"
                    >
                      {activity.txHash.slice(0, 8)}...
                      <ExternalLink className="w-3 h-3 group-hover:translate-x-0.5 group-hover:-translate-y-0.5 transition-transform" />
                    </button>
                  </div>
                </motion.div>
              ))
            )}
          </div>

          {/* Footer */}
          <div className="flex items-center justify-between pt-6 border-t border-white/10 mt-6">
            <div className="flex items-center gap-4">
              <div className="text-sm text-white/60">
                Monitoring Flow testnet
              </div>
              <div className="text-xs text-white/40">
                Updates every 30s when live
              </div>
            </div>
            <button
              onClick={() => window.open(`https://evm-testnet.flowscan.io/address/${CONTRACTS.coreVault}`, '_blank')}
              className="text-sm text-white/60 hover:text-white/80 transition-colors underline flex items-center gap-1"
            >
              View Core Vault on Flowscan
              <ExternalLink className="w-3 h-3" />
            </button>
          </div>
        </motion.div>

        {/* Contract Info Cards */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          transition={{ delay: 0.3 }}
          className="grid md:grid-cols-3 gap-6 mt-8"
        >
          <div className="glass-card rounded-xl p-6 border border-white/10 text-center">
            <div className="text-lg font-bold text-[var(--flow)] mb-2">Core Vault</div>
            <div className="text-xs text-white/60 font-mono break-all mb-3">
              {CONTRACTS.coreVault}
            </div>
            <button
              onClick={() => window.open(`https://evm-testnet.flowscan.io/address/${CONTRACTS.coreVault}`, '_blank')}
              className="text-xs text-white/50 hover:text-white/80 underline"
            >
              View on Flowscan
            </button>
          </div>
          
          <div className="glass-card rounded-xl p-6 border border-white/10 text-center">
            <div className="text-lg font-bold text-[var(--aqua)] mb-2">Vault Extension</div>
            <div className="text-xs text-white/60 font-mono break-all mb-3">
              {CONTRACTS.vaultExtension}
            </div>
            <button
              onClick={() => window.open(`https://evm-testnet.flowscan.io/address/${CONTRACTS.vaultExtension}`, '_blank')}
              className="text-xs text-white/50 hover:text-white/80 underline"
            >
              View on Flowscan
            </button>
          </div>
          
          <div className="glass-card rounded-xl p-6 border border-white/10 text-center">
            <div className="text-lg font-bold text-[var(--purple)] mb-2">Legacy Vault</div>
            <div className="text-xs text-white/60 font-mono break-all mb-3">
              {CONTRACTS.vault}
            </div>
            <button
              onClick={() => window.open(`https://evm-testnet.flowscan.io/address/${CONTRACTS.vault}`, '_blank')}
              className="text-xs text-white/50 hover:text-white/80 underline"
            >
              View on Flowscan
            </button>
          </div>
        </motion.div>
      </div>

      <style jsx>{`
        .custom-scrollbar {
          scrollbar-width: thin;
          scrollbar-color: rgba(255, 255, 255, 0.2) rgba(255, 255, 255, 0.05);
        }
        
        .custom-scrollbar::-webkit-scrollbar {
          width: 6px;
        }
        
        .custom-scrollbar::-webkit-scrollbar-track {
          background: rgba(255, 255, 255, 0.05);
          border-radius: 3px;
        }
        
        .custom-scrollbar::-webkit-scrollbar-thumb {
          background: rgba(255, 255, 255, 0.2);
          border-radius: 3px;
        }
        
        .custom-scrollbar::-webkit-scrollbar-thumb:hover {
          background: rgba(255, 255, 255, 0.3);
        }
      `}</style>
    </section>
  );
}