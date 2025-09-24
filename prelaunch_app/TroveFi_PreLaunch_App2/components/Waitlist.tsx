'use client'

import Image from 'next/image'
import { useState } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Check, Copy, Share, Loader2, ExternalLink } from 'lucide-react'
import { useAccount } from 'wagmi'

interface WaitlistResponse {
  success: boolean
  refCode: string
  referrals: number
  message?: string
  error?: string
}

export default function Waitlist() {
  const [email, setEmail] = useState('')
  const [isSubmitting, setIsSubmitting] = useState(false)
  const [response, setResponse] = useState<WaitlistResponse | null>(null)
  const [copySuccess, setCopySuccess] = useState(false)
  const [wantsEmails, setWantsEmails] = useState(true)
  const { address } = useAccount()

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!email || isSubmitting) return
    setIsSubmitting(true)
    try {
      const referrer = localStorage.getItem('trovefi:referrer')
      const requestBody = {
        email,
        walletAddress: address,
        ref: referrer,
        wantsClaimEmails: wantsEmails
      }
      const res = await fetch('/api/subscribe-newsletter', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(requestBody)
      })
      const data = await res.json()
      if (data.success) {
        localStorage.setItem('trovefi:refCode', data.refCode)
        localStorage.setItem('trovefi:email', email)
        setResponse(data)
      } else {
        setResponse({ success: false, error: data.error, refCode: '', referrals: 0 })
      }
    } catch {
      setResponse({ success: false, error: 'Network error. Please try again.', refCode: '', referrals: 0 })
    } finally {
      setIsSubmitting(false)
    }
  }

  const copyReferralLink = async () => {
    if (!response?.refCode) return
    const link = `${window.location.origin}/?ref=${response.refCode}`
    await navigator.clipboard.writeText(link)
    setCopySuccess(true)
    setTimeout(() => setCopySuccess(false), 2000)
  }

  const shareToX = () => {
    if (!response?.refCode) return
    const link = `${window.location.origin}/?ref=${response.refCode}`
    const text = `I'm early to @TroveFi — no-loss yield primative on Flow. Join me: ${link}`
    window.open(`https://twitter.com/intent/tweet?text=${encodeURIComponent(text)}`, '_blank')
  }

  return (
    <section id="waitlist" className="py-20 px-6">
      <div className="max-w-2xl mx-auto">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          className="text-center mb-12"
        >
          {/* Waitlist badge */}
          <div className="mb-5 flex justify-center">
            <div className="inline-flex items-center gap-2 rounded-full bg-black/55 backdrop-blur-md border border-white/15 px-3.5 py-2">
              <Image
                src="/icons/waitlist.png"
                alt=""
                width={36}
                height={36}
                className="w-8 h-8 md:w-9 md:h-9 object-contain"
              />
              <span className="text-sm md:text-base text-white/85 font-semibold tracking-wide">Waitlist</span>
            </div>
          </div>

          <h2 className="text-4xl font-bold mb-4">Join the Waitlist</h2>

          {/* Subtitle with BIG icon and NO square behind it */}
          <p className="text-xl text-white/70 flex items-center justify-center gap-3">
            <Image
              src="/icons/referral_rewards.png"
              alt=""
              width={48}
              height={48}
              className="w-12 h-12 md:w-14 md:h-14 object-contain"
            />
            <span>Get early access and earn referral rewards</span>
          </p>
        </motion.div>

        <motion.div
          initial={{ opacity: 0, y: 40 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          className="glass-card rounded-2xl p-8"
        >
          <AnimatePresence mode="wait">
            {!response?.success ? (
              <motion.form
                key="form"
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                onSubmit={handleSubmit}
                className="space-y-6"
              >
                <div className="space-y-4">
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
                      className="bg-white/5 border-white/20 text-white placeholder:text-white/40 focus:border-[var(--flow)] focus:ring-[var(--flow)]"
                      required
                    />
                  </div>

                  <div className="flex items-center gap-3">
                    <input
                      type="checkbox"
                      id="notifications"
                      checked={wantsEmails}
                      onChange={(e) => setWantsEmails(e.target.checked)}
                      className="w-4 h-4 rounded border-white/20 bg-white/5 text-[var(--flow)] focus:ring-[var(--flow)]"
                    />
                    <label htmlFor="notifications" className="text-sm text-white/70">
                      Email me when I can claim deposits & yield
                    </label>
                  </div>
                </div>

                {response?.error && (
                  <div className="p-4 bg-red-500/10 border border-red-500/20 rounded-lg">
                    <p className="text-red-200 text-sm">{response.error}</p>
                  </div>
                )}

                <Button
                  type="submit"
                  disabled={isSubmitting || !email}
                  className="w-full bg-gradient-to-r from-[var(--flow)] to-[var(--aqua)] hover:from-[var(--flow)]/90 hover:to-[var(--aqua)]/90 text-black font-semibold py-3 rounded-xl transition-all duration-300 hover:scale-105"
                >
                  {isSubmitting ? (
                    <>
                      <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                      Joining...
                    </>
                  ) : (
                    'Notify Me'
                  )}
                </Button>
              </motion.form>
            ) : (
              <motion.div
                key="success"
                initial={{ opacity: 0, scale: 0.95 }}
                animate={{ opacity: 1, scale: 1 }}
                className="text-center space-y-6"
              >
                <div className="flex items-center justify-center mb-6">
                  <div className="w-16 h-16 rounded-full bg-[var(--flow)]/20 border border-[var(--flow)]/40 flex items-center justify-center">
                    <Check className="w-8 h-8 text-[var(--flow)]" />
                  </div>
                </div>

                <div>
                  <h3 className="text-2xl font-semibold mb-2">You're in!</h3>
                  <p className="text-white/70">Successfully subscribed to TroveFi updates</p>
                </div>

                <div className="space-y-4">
                  <div>
                    <label className="block text-sm font-medium text-white/80 mb-2">
                      Your referral link
                    </label>
                    <div className="flex gap-2">
                      <Input
                        readOnly
                        value={`${window.location.origin}/?ref=${response.refCode}`}
                        className="bg-white/5 border-white/20 text-white font-mono text-sm"
                      />
                      <Button
                        onClick={copyReferralLink}
                        variant="outline"
                        className="border-white/20 text-white hover:bg-white/5 px-4"
                      >
                        {copySuccess ? (
                          <Check className="w-4 h-4 text-[var(--flow)]" />
                        ) : (
                          <Copy className="w-4 h-4" />
                        )}
                      </Button>
                    </div>
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

                  {/* Referrals with a larger icon (no wrapper) */}
                  <div className="text-center">
                    <p className="text-sm text-white/60 flex items-center justify-center gap-3">
                      <Image
                        src="/icons/referral_rewards.png"
                        alt=""
                        width={34}
                        height={34}
                        className="w-8 h-8 md:w-9 md:h-9 object-contain"
                      />
                      <span>
                        Referrals: <span className="font-semibold text-[var(--flow)]">{response.referrals}</span>
                      </span>
                    </p>
                  </div>

                  {/* Link to Full Referral Dashboard */}
                  <div className="pt-4 border-t border-white/10">
                    <Button
                      onClick={() => (window.location.href = '/referrals')}
                      variant="outline"
                      className="w-full border-white/20 text-white hover:bg-white/5"
                    >
                      Manage Your Referrals
                    </Button>
                  </div>
                </div>
              </motion.div>
            )}
          </AnimatePresence>
        </motion.div>
      </div>
    </section>
  )
}
