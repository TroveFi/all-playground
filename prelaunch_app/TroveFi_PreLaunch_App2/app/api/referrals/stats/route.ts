import { NextRequest, NextResponse } from 'next/server'
import { getReferralStats } from '@/lib/googleSheets'

export async function GET(req: NextRequest) {
  try {
    const { searchParams } = new URL(req.url)
    const refCode = searchParams.get('code')
    
    if (!refCode) {
      return NextResponse.json({ error: 'Referral code is required' }, { status: 400 })
    }

    const stats = await getReferralStats(refCode)
    
    return NextResponse.json({
      refCode,
      referrals: stats.referrals,
      totalRewards: stats.totalRewards || 0,
      pendingRewards: stats.pendingRewards || 0
    })
  } catch (error) {
    console.error('Error fetching referral stats:', error)
    return NextResponse.json({ error: 'Failed to fetch stats' }, { status: 500 })
  }
}