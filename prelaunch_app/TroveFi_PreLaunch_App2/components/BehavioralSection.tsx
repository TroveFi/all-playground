'use client'

import { motion } from 'framer-motion'
import Image from 'next/image'

export default function BehavioralSection() {
  return (
    <section className="py-32 px-6 relative overflow-hidden">
      {/* Background Elements */}
      <div className="absolute inset-0 opacity-30">
        <div className="absolute top-20 left-10 w-32 h-32 rounded-full bg-gradient-to-br from-red-500/20 to-red-600/10 blur-3xl"></div>
        <div className="absolute bottom-20 right-10 w-40 h-40 rounded-full bg-gradient-to-br from-[var(--flow)]/20 to-[var(--aqua)]/10 blur-3xl"></div>
      </div>

      <div className="max-w-7xl mx-auto relative">
        {/* Header */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          className="text-center mb-20"
        >
          <h2 className="text-5xl font-bold mb-6">
            <span className="block text-white/40 text-2xl font-normal mb-2">The psychology</span>
            Same Safety, Different Thrill
          </h2>
          <p className="text-xl text-white/70 max-w-3xl mx-auto leading-relaxed">
            Your principal is 100% protected in both cases. The difference? One offers guaranteed pennies, 
            the other offers the possibility of thousands.
          </p>
        </motion.div>

        {/* Comparison */}
        <div className="grid lg:grid-cols-[0.45fr,0.1fr,0.45fr] gap-8 items-stretch">
          {/* Traditional Savings */}
          <motion.div
            initial={{ opacity: 0, x: -40 }}
            whileInView={{ opacity: 1, x: 0 }}
            viewport={{ once: true }}
            className="relative group"
          >
            <div className="glass-card rounded-3xl p-10 h-full relative overflow-hidden border border-red-500/20 hover:border-red-500/40 transition-colors">
              {/* Subtle red glow */}
              <div className="absolute inset-0 bg-gradient-to-br from-red-500/5 to-red-600/5 opacity-0 group-hover:opacity-100 transition-opacity"></div>
              
              <div className="relative space-y-8">
                <div className="flex items-center gap-4">
                  {/* Replaced icon with image (no surrounding box) */}
                  <Image
                    src="/icons/traditional_savings.png"
                    alt="Traditional savings"
                    width={56}
                    height={56}
                    className="w-14 h-14 object-contain"
                    priority
                  />
                  <div>
                    <h3 className="text-2xl font-bold text-red-100">Traditional Savings</h3>
                    <p className="text-red-200/60">The "safe" choice</p>
                  </div>
                </div>

                <div className="space-y-6">
                  <div className="p-6 bg-red-500/5 rounded-2xl border border-red-500/10">
                    <div className="text-4xl font-bold text-red-200 mb-2">$30</div>
                    <div className="text-red-200/70">Annual return on $1,000</div>
                  </div>

                  <div className="space-y-4">
                    <div className="flex justify-between items-center py-3 border-b border-red-500/10">
                      <span className="text-white/70">Excitement level</span>
                      <span className="text-red-300">Minimal</span>
                    </div>
                    <div className="flex justify-between items-center py-3 border-b border-red-500/10">
                      <span className="text-white/70">Upside potential</span>
                      <span className="text-red-300">Capped</span>
                    </div>
                    <div className="flex justify-between items-center py-3">
                      <span className="text-white/70">Principal risk</span>
                      <span className="text-green-400">Protected</span>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </motion.div>

          {/* VS Divider */}
          <div className="flex items-center justify-center">
            <motion.div
              initial={{ opacity: 0, scale: 0.8 }}
              whileInView={{ opacity: 1, scale: 1 }}
              viewport={{ once: true }}
              transition={{ delay: 0.3 }}
              className="w-16 h-16 rounded-full bg-white/10 border border-white/20 flex items-center justify-center backdrop-blur-sm"
            >
              <span className="text-white/60 font-bold text-lg">VS</span>
            </motion.div>
          </div>

          {/* TroveFi Lottery */}
          <motion.div
            initial={{ opacity: 0, x: 40 }}
            whileInView={{ opacity: 1, x: 0 }}
            viewport={{ once: true }}
            className="relative group"
          >
            <div className="glass-card rounded-3xl p-10 h-full relative overflow-hidden border border-[var(--flow)]/20 hover:border-[var(--flow)]/40 transition-colors">
              {/* Flow glow */}
              <div className="absolute inset-0 bg-gradient-to-br from-[var(--flow)]/5 to-[var(--aqua)]/5 opacity-0 group-hover:opacity-100 transition-opacity"></div>
              
              <div className="relative space-y-8">
                <div className="flex items-center gap-4">
                  {/* Replaced icon with image (no surrounding box) */}
                  <Image
                    src="/icons/trovefi_lottery.png"
                    alt="TroveFi Lottery"
                    width={56}
                    height={56}
                    className="w-14 h-14 object-contain"
                    priority
                  />
                  <div>
                    <h3 className="text-2xl font-bold bg-gradient-to-r from-[var(--flow)] to-[var(--aqua)] bg-clip-text text-transparent">
                      TroveFi Lottery
                    </h3>
                    <p className="text-white/60">The exciting choice</p>
                  </div>
                </div>

                <div className="space-y-6">
                  <div className="p-6 bg-gradient-to-br from-[var(--flow)]/10 to-[var(--aqua)]/10 rounded-2xl border border-[var(--flow)]/20">
                    <div className="text-4xl font-bold text-[var(--flow)] mb-2">$1,000+</div>
                    <div className="text-white/70">Potential weekly win</div>
                  </div>

                  <div className="space-y-4">
                    <div className="flex justify-between items-center py-3 border-b border-white/10">
                      <span className="text-white/70">Excitement level</span>
                      <span className="text-[var(--flow)]">High</span>
                    </div>
                    <div className="flex justify-between items-center py-3 border-b border-white/10">
                      <span className="text-white/70">Upside potential</span>
                      <span className="text-[var(--aqua)]">Unlimited</span>
                    </div>
                    <div className="flex justify-between items-center py-3">
                      <span className="text-white/70">Principal risk</span>
                      <span className="text-green-400">Protected</span>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </motion.div>
        </div>

        {/* Bottom Insight */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          transition={{ delay: 0.6 }}
          className="text-center mt-16"
        >
          <div className="inline-flex items-center gap-3 px-6 py-3 bg-white/5 rounded-full border border-white/10">
            <div className="w-2 h-2 bg-[var(--flow)] rounded-full animate-pulse"></div>
            <p className="text-lg text-white/80 font-medium">
              Same principal protection, completely different emotional experience
            </p>
          </div>
        </motion.div>
      </div>
    </section>
  )
}
