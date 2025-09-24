import { type NextRequest, NextResponse } from "next/server"
import { addEmailToSheet } from "@/lib/googleSheets"

export async function POST(request: NextRequest) {
  try {
    const body = await request.json()
    const { email, walletAddress, ref, wantsClaimEmails = true } = body

    console.log("Received subscription request for:", email, "with referrer:", ref)

    if (!email) {
      return NextResponse.json({ error: "Email is required" }, { status: 400 })
    }

    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
    if (!emailRegex.test(email)) {
      return NextResponse.json({ error: "Invalid email format" }, { status: 400 })
    }

    // Google Sheets: add subscriber with referral tracking
    let refCode = ""
    let referrals = 0
    try {
      const res = await addEmailToSheet(
        email, 
        walletAddress, 
        ref, // referrer code from URL parameter
        wantsClaimEmails // preference for claim notifications
      )
      refCode = res.refCode
      referrals = res.referrals
      console.log("Successfully processed subscription for:", email, "refCode:", refCode, "referred by:", ref)
    } catch (error) {
      console.error("Error processing subscription:", error)
      if (error instanceof Error && error.message === "EMAIL_ALREADY_SUBSCRIBED") {
        return NextResponse.json(
          { error: "You're already subscribed! Check your inbox for our newsletters." },
          { status: 409 },
        )
      }
      throw error
    }

    return NextResponse.json({
      success: true,
      message: "Successfully subscribed to newsletter!",
      refCode, // user's new referral code
      referrals, // number of people they've referred (should be 0 for new users)
    })
  } catch (error) {
    console.error("Error in newsletter subscribe:", error)
    return NextResponse.json({ error: "Failed to subscribe. Please try again." }, { status: 500 })
  }
}