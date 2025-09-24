'use client'

import { motion } from 'framer-motion'
import Image from 'next/image'
import { useState, useCallback } from 'react'
import { Button } from '@/components/ui/button'
import { ExternalLink, Play } from 'lucide-react'

export default function DemoPreview() {
  const [open, setOpen] = useState(false)

  const openVideo = useCallback(() => setOpen(true), [])
  const closeVideo = useCallback(() => setOpen(false), [])
  const onKeyDown = useCallback((e: React.KeyboardEvent) => {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault()
      openVideo()
    }
  }, [openVideo])

  return (
    <section className="py-20 px-6">
      <div className="max-w-5xl mx-auto">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          className="text-center mb-16"
        >
          <h2 className="text-4xl font-bold mb-4">App Preview</h2>
          <p className="text-xl text-white/70">Coming soon: Experience the lottery mechanics with testnet tokens</p>
        </motion.div>

        <motion.div
          initial={{ opacity: 0, y: 40 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          className="relative group"
        >
          <div className="glass-card rounded-2xl p-8 relative overflow-hidden">
            <div className="absolute inset-0 bg-gradient-to-br from-[var(--flow)]/5 to-[var(--aqua)]/5 opacity-0 group-hover:opacity-100 transition-opacity duration-300"></div>
            
            <div className="relative">
              <div
                className="relative rounded-xl overflow-hidden bg-black/20 border border-white/10 cursor-pointer"
                role="button"
                tabIndex={0}
                aria-label="Play demo video"
                onClick={openVideo}
                onKeyDown={onKeyDown}
              >
                {/* Coming Soon badge on dark area */}
                <motion.div
                  initial={{ opacity: 0, y: -6 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ delay: 0.2, duration: 0.35 }}
                  className="absolute top-3 left-3 z-20"
                >
                  <div className="flex items-center gap-2 rounded-full bg-black/60 backdrop-blur-md border border-white/15 px-3 py-1.5 shadow-lg">
                    <Image
                      src="/icons/coming_soon.png"
                      alt=""
                      width={18}
                      height={18}
                      className="w-4 h-4 object-contain"
                    />
                    <span className="text-xs text-white/90 font-semibold tracking-wide">Coming Soon</span>
                  </div>
                </motion.div>

                <Image
                  src="/demo/demo-shot.png"
                  alt="TroveFi Demo Screenshot"
                  width={1200}
                  height={675}
                  className="w-full h-auto"
                  priority
                />

                {/* Overlay with play button (ensure below badge) */}
                <div className="absolute inset-0 bg-black/40 z-10 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity duration-300">
                  <div className="w-20 h-20 rounded-full bg-white/20 backdrop-blur-sm border border-white/30 flex items-center justify-center group-hover:scale-110 transition-transform">
                    <Play className="w-8 h-8 text-white ml-1" />
                  </div>
                </div>

                {/* Demo glow effect */}
                <div className="absolute -inset-1 bg-gradient-to-r from-[var(--flow)] via-[var(--aqua)] to-[var(--purple)] rounded-xl opacity-20 group-hover:opacity-40 transition-opacity blur-xl -z-10"></div>
              </div>

              <div className="mt-8 text-center space-y-4">
                <p className="text-white/70">
                  Full primative simulation • Mock Flow tokens • Safe testnet environment
                </p>

                {/* Button WITHOUT the icon now */}
                <Button
                  disabled
                  size="lg"
                  className="bg-gradient-to-r from-[var(--flow)] to-[var(--aqua)] opacity-50 text-black font-semibold px-8 py-3 rounded-xl"
                >
                  Coming Soon: Interactive dApp
                  <span className="ml-2 text-xs opacity-80"></span>
                </Button>

                {/* Fallback links */}
                <div className="text-sm text-white/50">
                  <button
                    onClick={openVideo}
                    className="underline hover:text-white/80"
                  >
                    Watch demo inline
                  </button>
                  <span className="mx-2">•</span>
                  <a
                    href="/demo/demo.mp4"
                    target="_blank"
                    rel="noreferrer"
                    className="underline hover:text-white/80 inline-flex items-center gap-1"
                  >
                    Open video in new tab
                    <ExternalLink className="w-3 h-3" />
                  </a>
                </div>
              </div>
            </div>
          </div>
        </motion.div>

        {/* Steps */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          transition={{ delay: 0.4 }}
          className="mt-12 grid md:grid-cols-3 gap-6"
        >
          <div className="text-center">
            <div className="w-12 h-12 rounded-xl bg-[var(--flow)]/20 border border-[var(--flow)]/30 flex items-center justify-center mx-auto mb-4">
              <span className="text-[var(--flow)] font-bold">1</span>
            </div>
            <h4 className="font-semibold mb-2">Connect Flow Wallet</h4>
            <p className="text-sm text-white/60">Use testnet Flow for safe experimentation</p>
          </div>
          
          <div className="text-center">
            <div className="w-12 h-12 rounded-xl bg-[var(--aqua)]/20 border border-[var(--aqua)]/30 flex items-center justify-center mx-auto mb-4">
              <span className="text-[var(--aqua)] font-bold">2</span>
            </div>
            <h4 className="font-semibold mb-2">Deposit Mock Tokens</h4>
            <p className="text-sm text-white/60">Experience the full deposit and lottery flow</p>
          </div>
          
          <div className="text-center">
            <div className="w-12 h-12 rounded-xl bg-[var(--purple)]/20 border border-[var(--purple)]/30 flex items-center justify-center mx-auto mb-4">
              <span className="text-[var(--purple)] font-bold">3</span>
            </div>
            <h4 className="font-semibold mb-2">Watch AI Agent</h4>
            <p className="text-sm text-white/60">See real-time yield allocation and risk management</p>
          </div>
        </motion.div>
      </div>

      {/* Lightweight modal for the MP4 */}
      {open && (
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          className="fixed inset-0 z-[80] bg-black/70 backdrop-blur-sm flex items-center justify-center p-4"
          onClick={closeVideo}
        >
          <motion.div
            initial={{ scale: 0.96, opacity: 0 }}
            animate={{ scale: 1, opacity: 1 }}
            exit={{ scale: 0.96, opacity: 0 }}
            className="relative w-full max-w-4xl aspect-video bg-black rounded-2xl overflow-hidden border border-white/10"
            onClick={(e) => e.stopPropagation()}
          >
            <video
              src="/demo/demo.mp4"
              controls
              autoPlay
              className="w-full h-full"
            />
            <button
              onClick={closeVideo}
              aria-label="Close video"
              className="absolute top-2 right-2 px-3 py-1.5 rounded-md bg-white/10 hover:bg-white/20 text-white text-sm"
            >
              Close
            </button>
          </motion.div>
        </motion.div>
      )}
    </section>
  )
}
