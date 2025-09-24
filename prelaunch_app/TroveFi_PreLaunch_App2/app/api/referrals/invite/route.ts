import { NextRequest, NextResponse } from 'next/server'
import { getReferralDataByEmail } from '@/lib/googleSheets'

export async function GET(req: NextRequest) {
  try {
    const { searchParams } = new URL(req.url)
    const email = searchParams.get('email')
    
    if (!email) {
      return NextResponse.json({ error: 'Email is required' }, { status: 400 })
    }

    // Check if email format is valid
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
    if (!emailRegex.test(email)) {
      return NextResponse.json({ error: 'Invalid email format' }, { status: 400 })
    }

    try {
      const referralData = await getReferralDataByEmail(email)
      
      return NextResponse.json({
        email: referralData.email,
        refCode: referralData.refCode,
        referrals: referralData.referrals,
        wantsClaimEmails: referralData.wantsClaimEmails
      })
    } catch (error) {
      if (error instanceof Error && error.message === 'EMAIL_NOT_FOUND') {
        return NextResponse.json({ error: 'Email not found' }, { status: 404 })
      }
      throw error
    }
  } catch (error) {
    console.error('Error fetching referral code:', error)
    return NextResponse.json({ error: 'Failed to fetch referral code' }, { status: 500 })
  }
}