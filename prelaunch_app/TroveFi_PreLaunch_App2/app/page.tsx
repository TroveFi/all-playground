'use client'

import { useEffect } from 'react'
import Header from '@/components/Header'
import Hero from '@/components/Hero'
import Explainer from '@/components/Explainer'
import BehavioralSection from '@/components/BehavioralSection'
import AgentPanel from '@/components/AgentPanel'
import UserActivity from '@/components/UserActivity'
import Roadmap from '@/components/Roadmap'
import Waitlist from '@/components/Waitlist'
import DemoPreview from '@/components/DemoPreview'
import Footer from '@/components/Footer'
import Particles from '@/components/Particles'

export default function Home() {

  useEffect(() => {
    // Capture referral from URL
    const urlParams = new URLSearchParams(window.location.search)
    const ref = urlParams.get('ref')
    if (ref) {
      localStorage.setItem('trovefi:referrer', ref)
    }
  }, [])

  return (
    <main className="min-h-screen bg-[var(--bg)] relative overflow-hidden">
      {/* Background Effects */}
      <div className="fixed inset-0 z-0">
        <Particles />
        <div className="orb orb-1" />
        <div className="orb orb-2" />
        <div className="orb orb-3" />
      </div>

      {/* Content */}
      <div className="relative z-10">
        <Header />
        <Hero />
        <Explainer />
        <BehavioralSection />
        <AgentPanel />
        <UserActivity />
        <Roadmap />
        <Waitlist />
        <DemoPreview />
        <Footer />
      </div>
    </main>
  )
}