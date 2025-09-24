'use client'

import { useEffect, useState } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Copy, Share, ExternalLink, Users, TrendingUp, Gift, ArrowLeft, Mail, Loader2, Check } from 'lucide-react'
import Link from 'next/link'
import Particles from '@/components/Particles'

interface ReferralData {
  email: string
  refCode: string
  referrals: number
  isNewUser: boolean
}

export default function ReferralPage() {
  const [email, setEmail] = useState('')
  const [friendEmail, setFriendEmail] = useState('')
  const [referralData, setReferralData] = useState<ReferralData | null>(null)
  const [isLoading, setIsLoading] = useState(false)
  const [copySuccess, setCopySuccess] = useState(false)
  const [inviteSuccess, setInviteSuccess] = useState(false)
  const [error, setError] = useState('')
  
  const origin = typeof window !== 'undefined' ? window.location.origin : ''

  // Check if we have cached referral data
  useEffect(() => {
    const cachedEmail = localStorage.getItem('trovefi:email')
    const cachedRefCode = localStorage.getItem('trovefi:refCode')
    
    if (cachedEmail && cachedRefCode) {
      setEmail(cachedEmail)
      // Auto-fetch their data
      handleGetReferralCode(cachedEmail, true)
    }
  }, [])

  const handleGetReferralCode = async (emailToUse?: string, silent = false) => {
    const targetEmail = emailToUse || email
    if (!targetEmail) return
    
    if (!silent) setIsLoading(true)
    setError('')

    try {
      // First try to get existing referral code
      const getResponse = await fetch(`/api/referrals/get-code?email=${encodeURIComponent(targetEmail)}`)
      
      if (getResponse.ok) {
        const data = await getResponse.json()
        setReferralData({
          email: targetEmail,
          refCode: data.refCode,
          referrals: data.referrals,
          isNewUser: false
        })
        
        // Cache the data
        localStorage.setItem('trovefi:email', targetEmail)
        localStorage.setItem('trovefi:refCode', data.refCode)
        
      } else if (getResponse.status === 404) {
        // User doesn't exist, sign them up
        const signupResponse = await fetch('/api/subscribe-newsletter', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            email: targetEmail,
            wantsClaimEmails: true // Default to yes for referral page users
          })
        })

        if (signupResponse.ok) {
          const signupData = await signupResponse.json()
          setReferralData({
            email: targetEmail,
            refCode: signupData.refCode,
            referrals: 0,
            isNewUser: true
          })
          
          // Cache the data
          localStorage.setItem('trovefi:email', targetEmail)
          localStorage.setItem('trovefi:refCode', signupData.refCode)
          
        } else {
          const errorData = await signupResponse.json()
          setError(errorData.error || 'Failed to create referral code')
        }
      } else {
        setError('Failed to retrieve referral code')
      }
    } catch (error) {
      console.error('Error getting referral code:', error)
      setError('Network error. Please try again.')
    } finally {
      if (!silent) setIsLoading(false)
    }
  }

  const invite = async () => {
    if (!referralData?.refCode || !friendEmail) return
    
    setIsLoading(true)
    try {
      const response = await fetch('/api/referrals/invite', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ refCode: referralData.refCode, friendEmail })
      })
      
      if (response.ok) {
        setFriendEmail('')
        setInviteSuccess(true)
        setTimeout(() => setInviteSuccess(false), 3000)
      }
    } catch (error) {
      console.error('Invite error:', error)
    } finally {
      setIsLoading(false)
    }
  }

  const copyReferralLink = async () => {
    if (!referralData?.refCode) return
    
    const link = `${origin}/?ref=${referralData.refCode}`
    await navigator.clipboard.writeText(link)
    setCopySuccess(true)
    setTimeout(() => setCopySuccess(false), 2000)
  }

  const shareToX = () => {
    if (!referralData?.refCode) return
    
    const link = `${origin}/?ref=${referralData.refCode}`
    const text = `I'm early to @TroveFi — no-loss yield primative on Flow. Join me: ${link}`
    window.open(`https://twitter.com/intent/tweet?text=${encodeURIComponent(text)}`, '_blank')
  }

  const refreshStats = async () => {
    if (!referralData?.email) return
    await handleGetReferralCode(referralData.email, true)
  }

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
        {/* Header */}
        <header className="px-6 py-6">
          <div className="max-w-7xl mx-auto flex items-center justify-between">
            <Link 
              href="/" 
              className="flex items-center gap-3 text-white/70 hover:text-white transition-colors group"
            >
              <ArrowLeft className="w-5 h-5 group-hover:-translate-x-1 transition-transform" />
              <span>Back to Home</span>
            </Link>
            
            <div className="flex items-center gap-3">
              <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-[var(--flow)] to-[var(--aqua)] flex items-center justify-center">
                <Users className="w-4 h-4 text-black" />
              </div>
              <span className="text-xl font-semibold">TroveFi Referrals</span>
            </div>
          </div>
        </header>

        {/* Main Content */}
        <div className="px-6 py-12">
          <div className="max-w-4xl mx-auto">
            {/* Hero Section */}
            <motion.div
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              className="text-center mb-16"
            >
              <h1 className="text-5xl font-bold mb-6">
                <span className="block text-white/40 text-2xl font-normal mb-2">Invite Friends</span>
                Earn Referral Rewards
              </h1>
              <p className="text-xl text-white/70 max-w-2xl mx-auto leading-relaxed">
                Share TroveFi with your network and earn rewards when they join the yield lottery. 
                Early referrers get priority access and bonus allocations.
              </p>
            </motion.div>

            <AnimatePresence mode="wait">
              {!referralData ? (
                // Email Entry Form
                <motion.div
                  key="email-entry"
                  initial={{ opacity: 0, y: 40 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0, y: -20 }}
                  className="glass-card rounded-3xl p-10 max-w-2xl mx-auto"
                >
                  <div className="text-center mb-8">
                    <div className="w-16 h-16 rounded-full bg-[var(--flow)]/20 border border-[var(--flow)]/40 flex items-center justify-center mx-auto mb-4">
                      <Mail className="w-8 h-8 text-[var(--flow)]" />
                    </div>
                    <h2 className="text-2xl font-semibold mb-2">Get Your Referral Code</h2>
                    <p className="text-white/70">
                      Enter your email to retrieve your existing referral code or create a new one
                    </p>
                  </div>

                  <div className="space-y-6">
                    <div>
                      <label htmlFor="email" className="block text-sm font-medium text-white/80 mb-2">
                        Email address
                      </label>
                      <Input
                        id="email"
                        type="email"
                        value={email}
                        onChange={(e) => setEmail(e.target.value)}
                        placeholder="you@email.com"
                        className="bg-white/5 border-white/20 text-white placeholder:text-white/40 focus:border-[var(--flow)] focus:ring-[var(--flow)] text-lg py-6"
                        onKeyPress={(e) => e.key === 'Enter' && handleGetReferralCode()}
                      />
                    </div>

                    {error && (
                      <div className="p-4 bg-red-500/10 border border-red-500/20 rounded-lg">
                        <p className="text-red-200 text-sm">{error}</p>
                      </div>
                    )}

                    <Button
                      onClick={() => handleGetReferralCode()}
                      disabled={!email || isLoading}
                      className="w-full bg-gradient-to-r from-[var(--flow)] to-[var(--aqua)] hover:from-[var(--flow)]/90 hover:to-[var(--aqua)]/90 text-black font-semibold py-4 rounded-xl transition-all duration-300 hover:scale-105"
                    >
                      {isLoading ? (
                        <>
                          <Loader2 className="w-5 h-5 mr-2 animate-spin" />
                          Getting Your Code...
                        </>
                      ) : (
                        <>
                          <Mail className="w-5 h-5 mr-2" />
                          Get My Referral Code
                        </>
                      )}
                    </Button>

                    <p className="text-sm text-white/60 text-center">
                      Don't have an account? We'll create one for you automatically with your referral code!
                    </p>
                  </div>
                </motion.div>
              ) : (
                // Referral Dashboard
                <motion.div
                  key="referral-dashboard"
                  initial={{ opacity: 0, y: 40 }}
                  animate={{ opacity: 1, y: 0 }}
                  className="space-y-8"
                >
                  {/* Welcome Message */}
                  {referralData.isNewUser && (
                    <motion.div
                      initial={{ opacity: 0, y: 20 }}
                      animate={{ opacity: 1, y: 0 }}
                      className="glass-card rounded-2xl p-6 border border-[var(--flow)]/30 bg-[var(--flow)]/5"
                    >
                      <div className="flex items-center gap-3">
                        <Check className="w-6 h-6 text-[var(--flow)]" />
                        <div>
                          <h3 className="font-semibold text-[var(--flow)]">Welcome to TroveFi!</h3>
                          <p className="text-white/70 text-sm">
                            You've been added to our waitlist and your referral code is ready to share.
                          </p>
                        </div>
                      </div>
                    </motion.div>
                  )}

                  {/* Stats Row */}
                  <div className="grid md:grid-cols-3 gap-6">
                    <div className="glass-card rounded-2xl p-6 text-center">
                      <div className="w-12 h-12 rounded-xl bg-[var(--flow)]/20 border border-[var(--flow)]/30 flex items-center justify-center mx-auto mb-4">
                        <Users className="w-6 h-6 text-[var(--flow)]" />
                      </div>
                      <div className="text-3xl font-bold text-[var(--flow)] mb-2">
                        {referralData.referrals}
                      </div>
                      <div className="text-sm text-white/60">Your Referrals</div>
                    </div>

                    <div className="glass-card rounded-2xl p-6 text-center">
                      <div className="w-12 h-12 rounded-xl bg-[var(--aqua)]/20 border border-[var(--aqua)]/30 flex items-center justify-center mx-auto mb-4">
                        <TrendingUp className="w-6 h-6 text-[var(--aqua)]" />
                      </div>
                      <div className="text-3xl font-bold text-[var(--aqua)] mb-2">5%</div>
                      <div className="text-sm text-white/60">Referral Bonus</div>
                    </div>

                    <div className="glass-card rounded-2xl p-6 text-center">
                      <div className="w-12 h-12 rounded-xl bg-[var(--purple)]/20 border border-[var(--purple)]/30 flex items-center justify-center mx-auto mb-4">
                        <Gift className="w-6 h-6 text-[var(--purple)]" />
                      </div>
                      <div className="text-3xl font-bold text-[var(--purple)] mb-2">∞</div>
                      <div className="text-sm text-white/60">Lifetime Rewards</div>
                    </div>
                  </div>

                  {/* Main Referral Card */}
                  <div className="glass-card rounded-3xl p-10">
                    <div className="space-y-8">
                      {/* User Info */}
                      <div className="flex items-center justify-between">
                        <div>
                          <h3 className="text-xl font-semibold mb-1">Your Referral Dashboard</h3>
                          <p className="text-white/70">{referralData.email}</p>
                        </div>
                        <Button
                          onClick={refreshStats}
                          variant="outline"
                          className="border-white/20 text-white hover:bg-white/5"
                        >
                          <TrendingUp className="w-4 h-4 mr-2" />
                          Refresh Stats
                        </Button>
                      </div>

                      {/* Referral Link Section */}
                      <div className="space-y-4">
                        <label className="block text-lg font-semibold text-white/90">
                          Your Referral Link
                        </label>
                        <div className="flex gap-2">
                          <Input
                            readOnly
                            value={`${origin}/?ref=${referralData.refCode}`}
                            className="bg-white/5 border-white/20 text-white font-mono text-sm"
                          />
                          <Button
                            onClick={copyReferralLink}
                            variant="outline"
                            className="border-white/20 text-white hover:bg-white/5 px-4"
                          >
                            {copySuccess ? (
                              <span className="text-[var(--flow)]">Copied!</span>
                            ) : (
                              <Copy className="w-4 h-4" />
                            )}
                          </Button>
                        </div>

                        <div className="flex gap-2">
                          <Button
                            onClick={shareToX}
                            className="flex-1 bg-blue-600 hover:bg-blue-700 text-white"
                          >
                            <Share className="w-4 h-4 mr-2" />
                            Share to X
                          </Button>
                          <Button
                            onClick={() => window.open('https://demo.trovefi.xyz', '_blank')}
                            variant="outline"
                            className="flex-1 border-white/20 text-white hover:bg-white/5"
                          >
                            <ExternalLink className="w-4 h-4 mr-2" />
                            Try Demo
                          </Button>
                        </div>
                      </div>

                      {/* Quick Invite Section */}
                      <div className="space-y-4 pt-6 border-t border-white/10">
                        <label className="block text-lg font-semibold text-white/90">
                          Quick Invite
                        </label>
                        <p className="text-sm text-white/60">
                          Send a direct invitation to a friend. We'll track when they join for your referral rewards.
                        </p>
                        
                        <div className="flex gap-2">
                          <Input
                            placeholder="friend@email.com"
                            value={friendEmail}
                            onChange={(e) => setFriendEmail(e.target.value)}
                            className="bg-white/5 border-white/20 text-white placeholder:text-white/40 focus:border-[var(--flow)] focus:ring-[var(--flow)]"
                          />
                          <Button 
                            onClick={invite}
                            disabled={!friendEmail || isLoading}
                            className="bg-gradient-to-r from-[var(--flow)] to-[var(--aqua)] hover:from-[var(--flow)]/90 hover:to-[var(--aqua)]/90 text-black font-semibold px-6"
                          >
                            {isLoading ? 'Sending...' : 'Send Invite'}
                          </Button>
                        </div>
                        
                        {inviteSuccess && (
                          <motion.div
                            initial={{ opacity: 0, y: 10 }}
                            animate={{ opacity: 1, y: 0 }}
                            className="text-sm text-[var(--flow)]"
                          >
                            ✅ Invitation recorded! They'll be attributed to your referrals when they join.
                          </motion.div>
                        )}
                      </div>

                      {/* Switch User */}
                      <div className="pt-6 border-t border-white/10">
                        <Button
                          onClick={() => {
                            setReferralData(null)
                            setEmail('')
                            localStorage.removeItem('trovefi:email')
                            localStorage.removeItem('trovefi:refCode')
                          }}
                          variant="ghost"
                          className="text-white/70 hover:text-white hover:bg-white/5"
                        >
                          Use Different Email
                        </Button>
                      </div>
                    </div>
                  </div>
                </motion.div>
              )}
            </AnimatePresence>

            {/* How It Works - Always Show */}
            <motion.div
              initial={{ opacity: 0, y: 40 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: referralData ? 0.3 : 0.6 }}
              className="glass-card rounded-2xl p-8 mt-12"
            >
              <h3 className="text-2xl font-semibold mb-6 text-center">How Referral Rewards Work</h3>
              
              <div className="grid md:grid-cols-3 gap-6">
                <div className="text-center">
                  <div className="w-12 h-12 rounded-xl bg-[var(--flow)]/20 border border-[var(--flow)]/30 flex items-center justify-center mx-auto mb-4">
                    <span className="text-[var(--flow)] font-bold">1</span>
                  </div>
                  <h4 className="font-semibold mb-2">Share Your Link</h4>
                  <p className="text-sm text-white/60">Send your unique referral link to friends and social media</p>
                </div>
                
                <div className="text-center">
                  <div className="w-12 h-12 rounded-xl bg-[var(--aqua)]/20 border border-[var(--aqua)]/30 flex items-center justify-center mx-auto mb-4">
                    <span className="text-[var(--aqua)] font-bold">2</span>
                  </div>
                  <h4 className="font-semibold mb-2">Friends Join & Deposit</h4>
                  <p className="text-sm text-white/60">When they sign up and make their first deposit, you both get rewards</p>
                </div>
                
                <div className="text-center">
                  <div className="w-12 h-12 rounded-xl bg-[var(--purple)]/20 border border-[var(--purple)]/30 flex items-center justify-center mx-auto mb-4">
                    <span className="text-[var(--purple)] font-bold">3</span>
                  </div>
                  <h4 className="font-semibold mb-2">Earn Ongoing Rewards</h4>
                  <p className="text-sm text-white/60">Get a percentage of their yield earnings forever</p>
                </div>
              </div>

              <div className="mt-8 p-6 bg-white/5 rounded-xl border border-white/10">
                <h4 className="font-semibold mb-3 text-[var(--flow)]">🎁 Referral Benefits</h4>
                <ul className="space-y-2 text-sm text-white/70">
                  <li><strong>•</strong> <strong>5% bonus</strong> on all referred user deposits</li>
                  <li><strong>•</strong> <strong>Priority access</strong> to new features and strategies</li>
                  <li><strong>•</strong> <strong>Exclusive rewards</strong> for top referrers</li>
                  <li><strong>•</strong> <strong>Lifetime earnings</strong> from your network</li>
                </ul>
              </div>
            </motion.div>
          </div>
        </div>
      </div>
    </main>
  )
}