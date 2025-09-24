'use client'

import Image from 'next/image'
import { motion } from 'framer-motion'
import { useState } from 'react'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { Bot, Activity, AlertTriangle, Zap } from 'lucide-react'

export default function AgentPanel() {
  const [activeTab, setActiveTab] = useState('scan')

  const tabs = [
    {
      id: 'scan',
      label: '5-Minute Loop',
      icon: Activity,
      color: 'var(--flow)',
      title: '5-Minute Risk Scan',
      bullets: [
        {
          text: 'Risk scan • Market volatility assessment',
          icon: '/icons/agent_scan.png',
          alt: 'Risk scan',
        },
        {
          text: 'Volatility • Price movement analysis across protocols',
          icon: '/icons/volatility.png',
          alt: 'Volatility analysis',
        },
        {
          text: 'Opportunity search • Yield optimization targets',
          icon: '/icons/opportunity_target.png',
          alt: 'Opportunity search',
        },
      ],
    },
    {
      id: 'allocate',
      label: '4-Hour Loop',
      icon: Bot,
      color: 'var(--aqua)',
      title: '4-Hour Strategic Allocation',
      bullets: [
        {
          text: 'Optimal allocation • Portfolio rebalancing decisions',
          icon: '/icons/portfolio.png',
          alt: 'Portfolio allocation',
        },
        {
          text: 'Smart execution • Gas-efficient transaction batching',
          icon: '/icons/gas_batch.png',
          alt: 'Gas-efficient batching',
        },
        {
          text: 'Learn & adapt • Performance feedback integration',
          icon: '/icons/learning_loop.png',
          alt: 'Learning loop',
        },
      ],
    },
    {
      id: 'emergency',
      label: 'Emergency',
      icon: AlertTriangle,
      color: 'var(--purple)',
      title: 'Emergency Risk Management',
      bullets: [
        {
          text: 'Auto-exit >80% risk • Immediate position unwinding',
          icon: '/icons/emergency_exit.png',
          alt: 'Emergency exit',
        },
        {
          text: 'Stress-mode throttling • Reduced allocation exposure',
          icon: '/icons/throttle.png',
          alt: 'Stress throttling',
        },
        {
          text: 'Yield re-route • Alternative strategy deployment',
          icon: '/icons/yield_reroute.png',
          alt: 'Yield reroute',
        },
      ],
    },
  ]

  return (
    <section className="py-32 px-6 relative">
      {/* Background gradient */}
      <div className="absolute inset-0 bg-gradient-to-b from-transparent via-[var(--purple)]/5 to-transparent"></div>
      
      <div className="max-w-6xl mx-auto">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          className="mb-20"
        >
          <div className="grid lg:grid-cols-[0.6fr,0.4fr] gap-16 items-center">
            <div>
              <h2 className="text-5xl font-bold leading-tight mb-6">
                <span className="block text-white/40 text-2xl font-normal mb-2">Autonomous AI</span>
                Agent Management
              </h2>
              <p className="text-xl text-white/70 leading-relaxed">
                Continuous risk monitoring, yield optimization, and emergency protocols running 24/7
              </p>
            </div>
            
            {/* Agent Status Card */}
            <motion.div
              initial={{ opacity: 0, x: 40 }}
              whileInView={{ opacity: 1, x: 0 }}
              viewport={{ once: true }}
              className="glass-card rounded-2xl p-6 border border-[var(--purple)]/20"
            >
              <div className="flex items-center gap-3 mb-4">
                <Image
                  src="/icons/agent_monitor.png"
                  alt=""
                  width={40}
                  height={40}
                  className="w-10 h-10 object-contain"
                  priority
                />
                <div>
                  <div className="font-semibold">Agent Status</div>
                  <div className="text-sm text-white/60">Monitoring</div>
                </div>
              </div>
              
              <div className="space-y-3">
                <div className="flex items-center justify-between">
                  <span className="text-sm text-white/70">Status</span>
                  <div className="flex items-center gap-2">
                    <div className="w-2 h-2 bg-[var(--flow)] rounded-full animate-pulse"></div>
                    <span className="text-[var(--flow)] text-sm font-mono">ACTIVE</span>
                  </div>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-sm text-white/70">Last Action</span>
                  <span className="text-sm font-mono">23s ago</span>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-sm text-white/70">Next Scan</span>
                  <span className="text-sm font-mono">4m 12s</span>
                </div>
              </div>
            </motion.div>
          </div>
        </motion.div>

        <motion.div
          initial={{ opacity: 0, y: 40 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          className="glass-card rounded-3xl p-10 border border-white/10"
        >
          <Tabs value={activeTab} onValueChange={setActiveTab} className="w-full">
            <TabsList className="grid w-full grid-cols-3 mb-10 bg-white/5 rounded-2xl p-2 min-h-14 items-stretch">
              {tabs.map((tab) => (
                <TabsTrigger
                  key={tab.id}
                  value={tab.id}
                  className="justify-center whitespace-nowrap text-sm ring-offset-background focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:pointer-events-none disabled:opacity-50 data-[state=active]:shadow-sm flex items-center gap-3 py-4 px-6 rounded-xl transition-all data-[state=active]:bg-white/10 data-[state=active]:text-white text-white/60 font-medium"
                >
                  <tab.icon className="w-5 h-5" />
                  <span className="font-mono">{tab.label}</span>
                </TabsTrigger>
              ))}
            </TabsList>

            {tabs.map((tab) => (
              <TabsContent key={tab.id} value={tab.id} className="mt-0">
                <motion.div
                  initial={{ opacity: 0, y: 20 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ duration: 0.3 }}
                  className="space-y-6"
                >
                  <div className="flex items-center gap-6 mb-8">
                    {/* Header icon */}
                    <Image
                      src="/icons/ml_secure.png"
                      alt=""
                      width={64}
                      height={64}
                      className="w-16 h-16 object-contain"
                    />
                    <div>
                      <h3 className="text-3xl font-bold mb-2">{tab.title}</h3>
                      <div className="flex items-center gap-2">
                        <Zap className="w-4 h-4" style={{ color: tab.color }} />
                        <span className="text-sm text-white/60 font-mono">Automated execution</span>
                      </div>
                    </div>
                  </div>

                  <div className="grid md:grid-cols-3 gap-6">
                    {tab.bullets.map((bullet, index) => (
                      <motion.div
                        key={index}
                        initial={{ opacity: 0, y: 8 }}
                        whileInView={{ opacity: 1, y: 0 }}
                        viewport={{ once: true }}
                        transition={{ delay: index * 0.06 }}
                        className="bg-white/5 rounded-xl p-6 border border-white/10 hover:border-white/20 transition-colors text-center"
                      >
                        {/* Icon ABOVE the text */}
                        <Image
                          src={bullet.icon}
                          alt={bullet.alt}
                          width={48}
                          height={48}
                          className="w-12 h-12 object-contain mx-auto mb-4"
                        />
                        <p className="font-mono text-sm text-white/90 leading-relaxed group-hover:text-white transition-colors">
                          {bullet.text}
                        </p>
                      </motion.div>
                    ))}
                  </div>

                  {/* Agent Status Indicator */}
                  <div className="flex items-center justify-between pt-8 border-t border-white/10">
                    <div className="flex items-center gap-4">
                      <div className="w-4 h-4 rounded-full bg-[var(--flow)] animate-pulse"></div>
                      <span className="font-mono text-white/80">System Status: GATHERING DATA</span>
                    </div>
                    <div className="flex items-center gap-8 font-mono text-sm text-white/60">
                      <span>Uptime: 99.9%</span>
                      <span>Response: &lt;100ms</span>
                    </div>
                  </div>
                </motion.div>
              </TabsContent>
            ))}
          </Tabs>
        </motion.div>
      </div>
    </section>
  )
}
