'use client'

import { useState, useEffect } from 'react'
import Link from 'next/link'
import Image from 'next/image'
import { motion } from 'framer-motion'
import { ExternalLink, Lock } from 'lucide-react'

export default function Header() {
  const [timeToLaunch, setTimeToLaunch] = useState<string>('')
  const [poolSize, setPoolSize] = useState<string>('$00,101')
  const [subscribers, setSubscribers] = useState<number>(101)

  useEffect(() => {
    const launchDate = new Date(process.env.NEXT_PUBLIC_LAUNCH_DATE || '2025-10-01T17:00:00Z')
    
    const updateCountdown = () => {
      const now = new Date()
      const diff = launchDate.getTime() - now.getTime()
      
      if (diff > 0) {
        const days = Math.floor(diff / (1000 * 60 * 60 * 24))
        const hours = Math.floor((diff % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60))
        setTimeToLaunch(`${days}d ${hours}h`)
      } else {
        setTimeToLaunch('Live!')
      }
    }

    updateCountdown()
    const interval = setInterval(updateCountdown, 1000 * 60) // Update every minute
    
    // Simulate pool size changes
    const poolInterval = setInterval(() => {
      const base = 47293
      const variance = Math.floor(Math.random() * 1000) - 500
      const newSize = base + variance
      setPoolSize(`$${newSize.toLocaleString()}`)
    }, 8000)
    
    // Simulate subscriber changes
    const subInterval = setInterval(() => {
      setSubscribers(prev => prev + Math.floor(Math.random() * 3))
    }, 12000)

    return () => {
      clearInterval(interval)
      clearInterval(poolInterval)
      clearInterval(subInterval)
    }
  }, [])

  return (
    <motion.header
      initial={{ y: -100, opacity: 0 }}
      animate={{ y: 0, opacity: 1 }}
      className="fixed top-0 left-0 right-0 z-50 glass-card border-b border-white/10"
    >
      {/* Stats Ticker */}
      <div className="bg-gradient-to-r from-[var(--flow)]/10 to-[var(--aqua)]/10 py-1 overflow-hidden">
        <div className="ticker-scroll whitespace-nowrap text-xs font-mono text-white/80">
          <span className="mx-8">Next draw ETA: {timeToLaunch}</span>
          <span className="mx-8">•</span>
          <span className="mx-8">Pool size: {poolSize}</span>
          <span className="mx-8">•</span>
          <span className="mx-8">Subscribers: {subscribers.toLocaleString()}</span>
          <span className="mx-8">•</span>
          <span className="mx-8">Next draw ETA: {timeToLaunch}</span>
          <span className="mx-8">•</span>
          <span className="mx-8">Pool size: {poolSize}</span>
        </div>
      </div>

      {/* Main Header */}
      <div className="px-6 py-4">
        <div className="max-w-7xl mx-auto flex items-center justify-between">
          {/* Logo */}
          <Link href="/" className="flex items-center gap-3 group">
            <Image
              src="/brand/logo_neon_zoom.png"
              alt="TroveFi"
              width={40}
              height={40}
              className="w-10 h-10 transition-transform group-hover:scale-110"
              priority
            />
            <span className="text-xl font-semibold bg-gradient-to-r from-white to-white/80 bg-clip-text text-transparent">
              TroveFi
            </span>
          </Link>

          {/* Navigation */}
          <nav className="hidden md:flex items-center gap-8">
            <Link 
              href="https://app.trovefi.xyz" 
              target="_blank"
              className="text-sm text-white/70 hover:text-white transition-colors flex items-center gap-2 group"
            >
              <Lock className="w-3 h-3" />
              App
              <span className="px-2 py-0.5 bg-amber-500/20 text-amber-300 rounded-full text-xs border border-amber-500/30">
                closed beta
              </span>
              <ExternalLink className="w-3 h-3 group-hover:translate-x-0.5 group-hover:-translate-y-0.5 transition-transform" />
            </Link>
            <Link 
              href="https://demo.trovefi.xyz" 
              target="_blank"
              className="text-sm text-white/70 hover:text-white transition-colors flex items-center gap-1 group"
            >
              Demo
              <ExternalLink className="w-3 h-3 group-hover:translate-x-0.5 group-hover:-translate-y-0.5 transition-transform" />
            </Link>
            <Link 
              href="https://x.com/TroveFi" 
              target="_blank"
              className="text-sm text-white/70 hover:text-white transition-colors flex items-center gap-1 group"
            >
              X/Twitter
              <ExternalLink className="w-3 h-3 group-hover:translate-x-0.5 group-hover:-translate-y-0.5 transition-transform" />
            </Link>
            <div className="text-sm text-white/40 flex items-center gap-2">
              Docs
              <span className="px-2 py-0.5 bg-white/10 rounded-full text-xs">soon</span>
            </div>
          </nav>

          {/* Mobile menu button */}
          <button className="md:hidden w-6 h-6 flex flex-col justify-center gap-1">
            <div className="w-full h-0.5 bg-white/70"></div>
            <div className="w-full h-0.5 bg-white/70"></div>
            <div className="w-full h-0.5 bg-white/70"></div>
          </button>
        </div>
      </div>
    </motion.header>
  )
}