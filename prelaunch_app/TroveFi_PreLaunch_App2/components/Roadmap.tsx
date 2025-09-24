'use client'

import { motion } from 'framer-motion'
import { CheckCircle, Clock, ArrowRight } from 'lucide-react'
import { Badge } from '@/components/ui/badge'

export default function Roadmap() {
  const roadmapItems = [
    {
      status: 'complete',
      title: 'Testnet Demo',
      description: 'Interactive demo with mock tokens for testing the jackpot mechanism',
      timeline: 'Now'
    },
    {
      status: 'current',
      title: 'Email Notifications + Referral Priority',
      description: 'Automated notifications and early access for active referrers',
      timeline: 'Next'
    },
    {
      status: 'planned',
      title: 'Mainnet Strategies',
      description: 'Integration with KittyPunch, More.Markets, Ankr Staking, and other Flow yield protocols',
      timeline: 'Then'
    }
  ]

  return (
    <section className="py-20 px-6">
      <div className="max-w-4xl mx-auto">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          className="text-center mb-16"
        >
          <h2 className="text-4xl font-bold mb-4">Roadmap & Updates</h2>
          <p className="text-xl text-white/70">Building step by step towards mainnet launch</p>
        </motion.div>

        <div className="space-y-8">
          {roadmapItems.map((item, index) => (
            <motion.div
              key={index}
              initial={{ opacity: 0, x: -40 }}
              whileInView={{ opacity: 1, x: 0 }}
              viewport={{ once: true }}
              transition={{ delay: index * 0.2 }}
              className="glass-card rounded-2xl p-8 relative"
            >
              <div className="flex items-start gap-6">
                <div className="flex-shrink-0">
                  {item.status === 'complete' && (
                    <div className="w-10 h-10 rounded-full bg-[var(--flow)]/20 border border-[var(--flow)]/40 flex items-center justify-center">
                      <CheckCircle className="w-5 h-5 text-[var(--flow)]" />
                    </div>
                  )}
                  {item.status === 'current' && (
                    <div className="w-10 h-10 rounded-full bg-[var(--aqua)]/20 border border-[var(--aqua)]/40 flex items-center justify-center">
                      <ArrowRight className="w-5 h-5 text-[var(--aqua)]" />
                    </div>
                  )}
                  {item.status === 'planned' && (
                    <div className="w-10 h-10 rounded-full bg-white/10 border border-white/20 flex items-center justify-center">
                      <Clock className="w-5 h-5 text-white/60" />
                    </div>
                  )}
                </div>
                
                <div className="flex-grow">
                  <div className="flex items-center gap-4 mb-3">
                    <h3 className="text-xl font-semibold">{item.title}</h3>
                    <Badge variant={item.status === 'complete' ? 'success' : item.status === 'current' ? 'active' : 'default'}>
                      {item.timeline}
                    </Badge>
                  </div>
                  <p className="text-white/70 leading-relaxed">{item.description}</p>
                </div>
              </div>

              {index < roadmapItems.length - 1 && (
                <div className="absolute left-[2.125rem] top-20 w-0.5 h-8 bg-gradient-to-b from-white/20 to-transparent"></div>
              )}
            </motion.div>
          ))}
        </div>

        <motion.div
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          transition={{ delay: 0.6 }}
          className="text-center mt-12"
        >
          <Badge variant="default" className="inline-flex items-center gap-2">
            <Clock className="w-4 h-4" />
            Docs coming soon
          </Badge>
        </motion.div>
      </div>
    </section>
  )
}