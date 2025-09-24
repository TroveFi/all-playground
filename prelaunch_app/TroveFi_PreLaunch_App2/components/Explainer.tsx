'use client'

import Image from 'next/image'
import { motion } from 'framer-motion'
import { ArrowRight, TrendingUp, Users, Zap } from 'lucide-react'

export default function Explainer() {
  return (
    <section className="py-32 px-6 relative">
      <div className="max-w-7xl mx-auto">
        {/* Main Content - Asymmetric Layout inspired by SafeYields */}
        <div className="grid lg:grid-cols-[0.4fr,0.6fr] gap-20 items-center">
          {/* Left - Compact Info */}
          <motion.div
            initial={{ opacity: 0, x: -40 }}
            whileInView={{ opacity: 1, x: 0 }}
            viewport={{ once: true }}
            className="space-y-8"
          >
            <div>
              <motion.h2
                initial={{ opacity: 0, y: 20 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true }}
                className="text-5xl font-bold leading-tight mb-6"
              >
                <span className="block text-white/40 text-2xl font-normal mb-2">How it works</span>
                Pool. Yield. Win.
              </motion.h2>
              <p className="text-xl text-white/70 leading-relaxed">
                Everyone deposits → AI generates yield → VRF verifies jackpots → principal stays safe
              </p>
            </div>

            {/* Stats Row */}
            <div className="grid grid-cols-2 gap-6">
              <div className="space-y-2">
                <div className="text-3xl font-bold text-[var(--flow)]">100%</div>
                <div className="text-sm text-white/60">Principal Protected</div>
              </div>
              <div className="space-y-2">
                <div className="text-3xl font-bold text-[var(--aqua)]">8.7%</div>
                <div className="text-sm text-white/60">Target APY</div>
              </div>
            </div>
          </motion.div>

          {/* Right - Flow Diagram */}
          <motion.div
            initial={{ opacity: 0, x: 40 }}
            whileInView={{ opacity: 1, x: 0 }}
            viewport={{ once: true }}
            className="relative"
          >
            <div className="space-y-8">
              {/* Step 1 */}
              <motion.div
                initial={{ opacity: 0, y: 20 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true }}
                transition={{ delay: 0.2 }}
                className="flex items-center gap-6 group"
              >
                <Image
                  src="/icons/deposit.png"
                  alt=""
                  width={64}
                  height={64}
                  className="w-16 h-16 object-contain transition-transform group-hover:scale-110"
                  priority
                />
                <div className="flex-1">
                  <h3 className="text-xl font-semibold mb-2">Deposit Together</h3>
                  <p className="text-white/60">Users pool their tokens into the shared vault</p>
                </div>
              </motion.div>

              {/* Connector */}
              <div className="flex justify-center">
                <div className="w-0.5 h-12 bg-gradient-to-b from-[var(--flow)]/40 to-[var(--aqua)]/40"></div>
              </div>

              {/* Step 2 */}
              <motion.div
                initial={{ opacity: 0, y: 20 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true }}
                transition={{ delay: 0.4 }}
                className="flex items-center gap-6 group"
              >
                <Image
                  src="/icons/ai_yield.png"
                  alt=""
                  width={64}
                  height={64}
                  className="w-16 h-16 object-contain transition-transform group-hover:scale-110"
                />
                <div className="flex-1">
                  <h3 className="text-xl font-semibold mb-2">AI Generates Yield</h3>
                  <p className="text-white/60">Agent allocates across Flow protocols to maximize returns</p>
                </div>
              </motion.div>

              {/* Connector */}
              <div className="flex justify-center">
                <div className="w-0.5 h-12 bg-gradient-to-b from-[var(--aqua)]/40 to-[var(--purple)]/40"></div>
              </div>

              {/* Step 3 */}
              <motion.div
                initial={{ opacity: 0, y: 20 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true }}
                transition={{ delay: 0.6 }}
                className="flex items-center gap-6 group"
              >
                <Image
                  src="/icons/win_all.png"
                  alt=""
                  width={64}
                  height={64}
                  className="w-16 h-16 object-contain transition-transform group-hover:scale-110"
                />
                <div className="flex-1">
                  <h3 className="text-xl font-semibold mb-2">Chase The Yield Jackpot</h3>
                  <p className="text-white/60">Weekly VRF creates jackpots; everyone else withdraws principal</p>
                </div>
              </motion.div>
            </div>

            {/* Floating Elements */}
            <div className="absolute -top-4 -right-4 w-8 h-8 rounded-full bg-[var(--flow)]/20 animate-pulse"></div>
            <div className="absolute -bottom-4 -left-4 w-6 h-6 rounded-full bg-[var(--aqua)]/20 animate-pulse" style={{ animationDelay: '1s' }}></div>
          </motion.div>
        </div>

        {/* Bottom CTA Strip */}
        <motion.div
          initial={{ opacity: 0, y: 40 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          transition={{ delay: 0.8 }}
          className="mt-20 glass-card rounded-2xl p-8 text-center"
        >
          <div className="flex flex-col md:flex-row items-center justify-between gap-6">
            <div className="text-left">
              <h3 className="text-2xl font-semibold mb-2">Ready to try it?</h3>
              <p className="text-white/60">Experience the full flow with testnet tokens</p>
            </div>
            <div className="flex gap-4">
              <button
                disabled
                className="px-6 py-3 bg-gradient-to-r from-[var(--flow)] to-[var(--aqua)] text-black font-semibold rounded-xl hover:scale-105 transition-transform"
              >
                <span className="opacity-50">Try App</span>
              </button>
              <button
                onClick={() => document.getElementById('waitlist')?.scrollIntoView({ behavior: 'smooth' })}
                className="px-6 py-3 border border-white/20 text-white rounded-xl hover:bg-white/5 transition-colors"
              >
                Join Waitlist
              </button>
            </div>
          </div>
        </motion.div>
      </div>
    </section>
  )
}
