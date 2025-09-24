'use client'

import { motion } from 'framer-motion'
import Image from 'next/image'
import { useMemo } from 'react'
import { Button } from '@/components/ui/button'
import { ArrowUpRight, Lock } from 'lucide-react'

type Point = { x: number; y: number }

function Particle({
  src,
  size = 22,
  start,
  mid,
  end,
  duration = 4.5,
  delay = 0,
  repeatDelay = 1.2,
  rotate = 0,
  className = '',
}: {
  src: string
  size?: number
  start: Point
  mid: Point
  end: Point
  duration?: number
  delay?: number
  repeatDelay?: number
  rotate?: number
  className?: string
}) {
  return (
    <motion.img
      src={src}
      alt=""
      width={size}
      height={size}
      className={`absolute pointer-events-none ${className}`}
      style={{ filter: 'drop-shadow(0 0 6px rgba(0,255,255,0.35))' }}
      initial={{ left: `${start.x}%`, top: `${start.y}%`, opacity: 0, rotate }}
      animate={{
        left: [`${start.x}%`, `${mid.x}%`, `${end.x}%`],
        top: [`${start.y}%`, `${mid.y}%`, `${end.y}%`],
        opacity: [0, 1, 0.05],
        scale: [0.9, 1, 0.92],
      }}
      transition={{
        duration,
        times: [0, 0.55, 1],
        repeat: Infinity,
        delay,
        repeatDelay,
        ease: 'easeInOut',
      }}
    />
  )
}

export default function Hero() {
  const scrollToWaitlist = () => {
    document.getElementById('waitlist')?.scrollIntoView({ behavior: 'smooth' })
  }

  // Fixed anchor points (% within the overlay box)
  // Apex is the visual center of the agent image.
  const anchors = useMemo(() => {
    const agent: Point = { x: 50, y: 62 }
    const leftChar: Point = { x: 32, y: 20 }
    const midChar: Point = { x: 50, y: 18 }
    const rightChar: Point = { x: 68, y: 20 }

    // Fixed midpoints define EXACT paths (no lateral randomness)
    const leftMid: Point = { x: 41, y: 30 }   // gentle arc from agent to left
    const midMid: Point = { x: 50, y: 32 }    // subtle vertical arc
    const rightMid: Point = { x: 59, y: 30 }  // gentle arc from agent to right

    return {
      agent,
      routes: [
        { name: 'left',   toChar: { start: agent, mid: leftMid, end: leftChar },   toAgent: { start: leftChar, mid: leftMid, end: agent } },
        { name: 'center', toChar: { start: agent, mid: midMid,  end: midChar },    toAgent: { start: midChar,  mid: midMid,  end: agent } },
        { name: 'right',  toChar: { start: agent, mid: rightMid,end: rightChar },  toAgent: { start: rightChar,mid: rightMid,end: agent } },
      ],
    }
  }, [])

  const particles = useMemo(() => {
    const { routes } = anchors
    const nodes: React.ReactNode[] = []

    routes.forEach((r, idx) => {
      // === Agent -> Character (steady but not spammy): FLOW COINS ===
      // Two coins per stream, staggered. Fixed path geometry.
      nodes.push(
        <Particle
          key={`coin1-${r.name}`}
          src="/icons/flow_coin.png"
          size={20}
          {...r.toChar}
          duration={4.4}
          delay={0.8 + idx * 0.6}
          repeatDelay={5.5}
          rotate={-10}
        />,
        <Particle
          key={`coin2-${r.name}`}
          src="/icons/flow_coin.png"
          size={20}
          {...r.toChar}
          duration={5.0}
          delay={2.0 + idx * 0.6}
          repeatDelay={6.5}
          rotate={10}
        />
      )

      // === Agent -> Character (occasional rewards) ===
      nodes.push(
        <Particle
          key={`band-${r.name}`}
          src="/icons/dollar_band.png"
          size={26}
          {...r.toChar}
          duration={5.4}
          delay={3.2 + idx * 0.7}
          repeatDelay={11}
          rotate={-8}
          className="z-10"
        />,
        <Particle
          key={`bag-${r.name}`}
          src="/icons/cash_bag.png"
          size={28}
          {...r.toChar}
          duration={5.8}
          delay={5.2 + idx * 0.7}
          repeatDelay={13}
          rotate={6}
          className="z-10"
        />
      )

      // === Character -> Agent (RARE tickets) ===
      nodes.push(
        <Particle
          key={`ticket-${r.name}`}
          src="/icons/lottery_ticket.png"
          size={24}
          {...r.toAgent}
          duration={4.8}
          delay={4.0 + idx * 1.2}
          repeatDelay={16} // rare
          rotate={-16}
          className="z-20"
        />
      )
    })

    return nodes
  }, [anchors])

  return (
    <section className="pt-32 pb-20 px-6">
      <div className="max-w-7xl mx-auto">
        <div className="grid lg:grid-cols-[1.2fr,0.8fr] gap-16 items-center">
          {/* Left Content */}
          <motion.div
            initial={{ opacity: 0, x: -50 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ duration: 0.8 }}
            className="space-y-10"
          >
            <div className="space-y-8">
              <motion.h1
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: 0.2 }}
                className="text-6xl lg:text-7xl font-bold leading-[0.9] tracking-tight"
              >
                <span className="block text-white/50 text-3xl font-normal mb-4">Coming Soon</span>
                <span className="block">Yield Protocol</span>
                <span className="block text-white/60">on Flow —</span>
                <span className="block bg-gradient-to-r from-[var(--flow)] via-[var(--aqua)] to-[var(--flow)] bg-clip-text text-transparent animate-pulse">
                  No Loss. Big Wins.
                </span>
              </motion.h1>
              
              <motion.p
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: 0.4 }}
                className="text-2xl text-white/90 leading-relaxed font-light max-w-2xl"
              >
                Deposit with the crowd → everyone keeps principal → winners take the pooled yield.
              </motion.p>
            </div>

            {/* Trust Bullets */}
            <motion.div
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.6 }}
              className="grid grid-cols-1 gap-4"
            >
              <div className="flex items-center gap-4 p-4 rounded-xl bg-white/5 border border-white/10 hover:border-[var(--flow)]/30 transition-colors">
                <Image
                  src="/icons/receive_payout.png"
                  alt=""
                  width={32}
                  height={32}
                  className="w-8 h-8 object-contain flex-shrink-0"
                />
                <span className="text-white/90 font-medium">Claim principal anytime</span>
              </div>
              <div className="flex items-center gap-4 p-4 rounded-xl bg-white/5 border border-white/10 hover:border-[var(--aqua)]/30 transition-colors">
                <Image
                  src="/icons/secure_vrf_dice.png"
                  alt=""
                  width={32}
                  height={32}
                  className="w-8 h-8 object-contain flex-shrink-0"
                />
                <span className="text-white/90 font-medium">Weekly VRF payouts on Flow</span>
              </div>
              <div className="flex items-center gap-4 p-4 rounded-xl bg-white/5 border border-white/10 hover:border-[var(--purple)]/30 transition-colors">
                <Image
                  src="/icons/ai_secure.png"
                  alt=""
                  width={32}
                  height={32}
                  className="w-8 h-8 object-contain flex-shrink-0"
                />
                <span className="text-white/90 font-medium">Agent-managed rebalancing & ML risk controls</span>
              </div>
            </motion.div>

            {/* CTAs */}
            <motion.div
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.8 }}
              className="flex flex-col sm:flex-row gap-6"
            >
              <Button 
                onClick={scrollToWaitlist}
                size="lg"
                className="bg-gradient-to-r from-[var(--flow)] to-[var(--aqua)] hover:from-[var(--flow)]/90 hover:to-[var(--aqua)]/90 text-black font-semibold px-8 py-3 rounded-xl transition-all duration-300 hover:scale-105 hover:shadow-lg hover:shadow-[var(--flow)]/25"
              >
                Join the Waitlist
              </Button>
              <Button 
                variant="ghost"
                size="lg"
                className="text-white hover:bg-white/10 px-8 py-3 rounded-xl border border-white/20 hover:border-white/40 transition-all group"
                onClick={() => window.open('https://app.trovefi.xyz', '_blank')}
              >
                <Lock className="w-4 h-4 mr-2" />
                Try the App
                <span className="ml-2 px-2 py-0.5 bg-amber-500/20 text-amber-300 rounded-full text-xs border border-amber-500/30">
                  closed beta
                </span>
              </Button>
              <Button
                variant="ghost"
                size="lg"
                className="text-white/70 hover:text-white hover:bg-white/5 px-8 py-3 rounded-xl group"
                onClick={() => window.open('https://x.com/TroveFi', '_blank')}
              >
                Follow @TroveFi
                <ArrowUpRight className="w-4 h-4 ml-2 group-hover:translate-x-0.5 group-hover:-translate-y-0.5 transition-transform" />
              </Button>
            </motion.div>

            {/* Accelerator Note */}
            <motion.p
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 1.0 }}
              className="text-sm text-white/50 italic"
            >
              Building in the Founders Forge Accelerator with Protocol Labs.
            </motion.p>
          </motion.div>

          {/* Right Content - Hero Card */}
          <motion.div
            initial={{ opacity: 0, x: 50 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ duration: 0.8, delay: 0.2 }}
            className="flex justify-center"
          >
            <div className="hero-card-tilt glass-card rounded-3xl p-10 w-full max-w-lg relative overflow-hidden">
              {/* Gradient overlay */}
              <div className="absolute inset-0 bg-gradient-to-br from-[var(--flow)]/5 via-transparent to-[var(--aqua)]/5 pointer-events-none" />

              {/* Fixed-path animated streams */}
              <div className="absolute inset-0 pointer-events-none z-20">
                <div className="relative w-full h-[260px] sm:h-[280px] md:h-[300px]">
                  {particles}
                </div>
              </div>
              
              <div className="space-y-6 relative z-10">
                {/* Characters Row */}
                <div className="flex justify-center gap-6">
                  <motion.div 
                    className="character-bounce"
                    animate={{ y: [0, -8, 0] }}
                    transition={{ duration: 3, repeat: Infinity, ease: "easeInOut" }}
                  >
                    <Image
                      src="/characters/char1.png"
                      alt="Character 1"
                      width={70}
                      height={70}
                      className="rounded-2xl hover:scale-110 transition-transform cursor-pointer shadow-lg"
                    />
                  </motion.div>
                  <motion.div 
                    className="character-bounce"
                    animate={{ y: [0, -8, 0] }}
                    transition={{ duration: 3, repeat: Infinity, ease: "easeInOut", delay: -1 }}
                  >
                    <Image
                      src="/characters/char2.png"
                      alt="Character 2"
                      width={70}
                      height={70}
                      className="rounded-2xl hover:scale-110 transition-transform cursor-pointer shadow-lg"
                    />
                  </motion.div>
                  <motion.div 
                    className="character-bounce"
                    animate={{ y: [0, -8, 0] }}
                    transition={{ duration: 3, repeat: Infinity, ease: "easeInOut", delay: -2 }}
                  >
                    <Image
                      src="/characters/char3.png"
                      alt="Character 3"
                      width={70}
                      height={70}
                      className="rounded-2xl hover:scale-110 transition-transform cursor-pointer shadow-lg"
                    />
                  </motion.div>
                </div>

                {/* Agent */}
                <div className="text-center space-y-4">
                  <motion.div
                    animate={{ y: [0, -4, 0] }}
                    transition={{ duration: 2, repeat: Infinity, ease: "easeInOut" }}
                    className="flex justify-center"
                  >
                    <Image
                      src="/characters/agent.png"
                      alt="AI Agent"
                      width={90}
                      height={90}
                      className="rounded-2xl filter drop-shadow-xl"
                    />
                  </motion.div>
                  
                  {/* Mini Agent HUD */}
                  <div className="glass-card rounded-xl p-5 space-y-4 border border-white/20">
                    <div className="flex items-center justify-between text-xs font-mono">
                      <span className="text-white/70">Agent Status</span>
                      <div className="flex items-center gap-1">
                        <div className="w-2 h-2 bg-[var(--flow)] rounded-full animate-pulse"></div>
                        <span className="text-[var(--flow)]">ACTIVE</span>
                      </div>
                    </div>
                    
                    <div className="space-y-3">
                      <div className="flex justify-between text-xs">
                        <span className="text-white/60">Risk Scan</span>
                        <span className="text-white/80">2.3%</span>
                      </div>
                      <div className="flex justify-between text-xs">
                        <span className="text-white/60">Yield Target</span>
                        <span className="text-[var(--aqua)]">8.7% APY</span>
                      </div>
                      <div className="flex justify-between text-xs">
                        <span className="text-white/60">Next Rebalance</span>
                        <span className="text-white/80">2.1h</span>
                      </div>
                    </div>
                    
                    {/* Mini Sparkline */}
                    <div className="flex items-center justify-between pt-2 border-t border-white/10">
                      <span className="text-xs text-white/60">Performance</span>
                      <div className="sparkline"></div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </motion.div>
        </div>
      </div>
    </section>
  )
}