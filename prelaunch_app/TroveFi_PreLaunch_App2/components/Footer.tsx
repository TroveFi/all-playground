'use client'

import Link from 'next/link'
import Image from 'next/image'
import { ExternalLink, Lock } from 'lucide-react'

export default function Footer() {
  return (
    <footer className="border-t border-white/10 py-16 px-6">
      <div className="max-w-6xl mx-auto">
        <div className="grid md:grid-cols-4 gap-8 mb-12">
          {/* Logo & Description */}
          <div className="md:col-span-2">
            <div className="flex items-center gap-3 mb-4">
              <Image
                src="/brand/logo_neon_zoom.png"
                alt="TroveFi"
                width={40}
                height={40}
                className="w-10 h-10"
                priority
              />
              <span className="text-xl font-semibold">TroveFi</span>
            </div>
            <p className="text-white/60 leading-relaxed max-w-md">
              AI-powered no-loss yield primative on Flow blockchain. 
              Deposit with the crowd, everyone keeps principal, winner takes the pooled yield.
            </p>
          </div>

          {/* Links */}
          <div>
            <h4 className="font-semibold mb-4 text-white/90">Product</h4>
            <div className="space-y-3">
              <Link 
                href="https://app.trovefi.xyz" 
                target="_blank"
                className="block text-white/60 hover:text-white transition-colors flex items-center gap-2 group"
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
                className="block text-white/60 hover:text-white transition-colors flex items-center gap-1 group"
              >
                Demo
                <ExternalLink className="w-3 h-3 group-hover:translate-x-0.5 group-hover:-translate-y-0.5 transition-transform" />
              </Link>
              <div className="flex items-center gap-2 text-white/40">
                <span>Docs</span>
                <span className="px-2 py-0.5 bg-white/10 rounded-full text-xs">soon</span>
              </div>
              <div className="flex items-center gap-2 text-white/40">
                <span>Whitepaper</span>
                <span className="px-2 py-0.5 bg-white/10 rounded-full text-xs">soon</span>
              </div>
            </div>
          </div>

          {/* Social */}
          <div>
            <h4 className="font-semibold mb-4 text-white/90">Connect</h4>
            <div className="space-y-3">
              <Link 
                href="https://x.com/TroveFi" 
                target="_blank"
                className="block text-white/60 hover:text-white transition-colors flex items-center gap-1 group"
              >
                X/Twitter
                <ExternalLink className="w-3 h-3 group-hover:translate-x-0.5 group-hover:-translate-y-0.5 transition-transform" />
              </Link>
              <div className="flex items-center gap-2 text-white/40">
                <span>Discord</span>
                <span className="px-2 py-0.5 bg-white/10 rounded-full text-xs">soon</span>
              </div>
              <Link 
                href="mailto:contact@trovefi.xyz"
                className="block text-white/60 hover:text-white transition-colors"
              >
                contact@trovefi.xyz
              </Link>
            </div>
          </div>
        </div>

        {/* Bottom */}
        <div className="pt-8 border-t border-white/10">
          <div className="flex flex-col md:flex-row justify-between items-center gap-4">
            <p className="text-sm text-white/50 text-center md:text-left">
              © 2025 TroveFi. Building in the Founders Forge Accelerator with Protocol Labs.
            </p>
            <p className="text-xs text-white/40 text-center md:text-right max-w-md">
              Prize is generated from yield; principal remains withdrawable. 
              Demo runs on testnet with mock tokens.
            </p>
          </div>
        </div>
      </div>
    </footer>
  )
}