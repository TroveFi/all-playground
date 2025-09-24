// lib/googleSheets.ts
import { google } from "googleapis"
import { JWT } from "google-auth-library"

const SCOPES = ["https://www.googleapis.com/auth/spreadsheets"]
const SHEET_RANGE = process.env.SHEETS_TAB_WAITLIST || "Waitlist!A:H"
// Updated columns: [timestamp, email, wallet, referrerCode, refCode, referrals, wantsClaimEmails, status]

function getAuth() {
  const clientEmail = process.env.GOOGLE_SERVICE_ACCOUNT_EMAIL
  const privateKey = (process.env.GOOGLE_PRIVATE_KEY || "").replace(/\\n/g, "\n")
  
  if (!clientEmail) {
    throw new Error("Missing GOOGLE_SERVICE_ACCOUNT_EMAIL environment variable")
  }
  
  if (!privateKey) {
    throw new Error("Missing GOOGLE_PRIVATE_KEY environment variable")
  }

  return new JWT({
    email: clientEmail,
    key: privateKey,
    scopes: SCOPES,
  })
}

async function getSheets() {
  const auth = getAuth()
  const sheets = google.sheets({ version: "v4", auth })
  
  // Check for spreadsheet ID with better error message
  const spreadsheetId = process.env.GOOGLE_SHEETS_SPREADSHEET_ID || process.env.GOOGLE_SHEET_ID
  
  if (!spreadsheetId) {
    console.error("Environment variables check:")
    console.error("GOOGLE_SHEETS_SPREADSHEET_ID:", process.env.GOOGLE_SHEETS_SPREADSHEET_ID)
    console.error("GOOGLE_SHEET_ID:", process.env.GOOGLE_SHEET_ID)
    console.error("Available env vars starting with GOOGLE:", Object.keys(process.env).filter(key => key.startsWith('GOOGLE')))
    throw new Error("Missing Google Sheets spreadsheet ID. Please set GOOGLE_SHEETS_SPREADSHEET_ID or GOOGLE_SHEET_ID in your environment variables")
  }
  
  return { sheets, spreadsheetId }
}

function shortCode(s: string) {
  const base = Buffer.from(s.toLowerCase())
    .toString("base64")
    .replace(/[^a-z0-9]/gi, "")
    .slice(0, 8)
  const rnd = Math.random().toString(36).slice(2, 6)
  return (base + rnd).slice(0, 10)
}

export async function addEmailToSheet(
  email: string,
  walletAddress?: string,
  referrerCode?: string,
  wantsClaimEmails?: boolean
): Promise<{ refCode: string; referrals: number }> {
  const { sheets, spreadsheetId } = await getSheets()
  const now = new Date().toISOString()

  console.log("Using spreadsheet ID:", spreadsheetId)
  console.log("Using sheet range:", SHEET_RANGE)

  // Read existing to dedupe + find existing refCode
  const read = await sheets.spreadsheets.values.get({
    spreadsheetId,
    range: SHEET_RANGE,
  })
  const rows = read.data.values || []
  const header = rows[0] || []
  const data = rows.slice(1)

  console.log("Sheet headers:", header)
  console.log("Data rows count:", data.length)

  const idxEmail = header.indexOf("email")
  const idxRefCode = header.indexOf("refCode")
  const idxReferrals = header.indexOf("referrals")
  const idxReferrerCode = header.indexOf("referrerCode")

  console.log("Column indices:", { idxEmail, idxRefCode, idxReferrals, idxReferrerCode })

  // Try to find existing
  let existingRefCode = ""
  let existingReferrals = 0
  for (const r of data) {
    if (r[idxEmail] && r[idxEmail].toLowerCase() === email.toLowerCase()) {
      existingRefCode = (r[idxRefCode] as string) || ""
      existingReferrals = Number.parseInt((r[idxReferrals] as string) || "0", 10)
      if (existingRefCode) {
        throw new Error("EMAIL_ALREADY_SUBSCRIBED")
      }
      break
    }
  }

  const refCode = existingRefCode || shortCode(email)
  
  // If someone referred this user, increment their referral count
  if (referrerCode) {
    await incrementReferrerCount(referrerCode)
  }

  const values = [
    [
      now,
      email.toLowerCase(),
      walletAddress || "",
      referrerCode || "",
      refCode,
      existingReferrals || 0,
      wantsClaimEmails ? "Yes" : "No", // Convert boolean to string
      "joined", // status
    ],
  ]

  console.log("Adding row:", values[0])

  await sheets.spreadsheets.values.append({
    spreadsheetId,
    range: SHEET_RANGE,
    valueInputOption: "RAW",
    requestBody: { values },
  })

  return { refCode, referrals: existingReferrals }
}

// Helper function to increment referrer's count
async function incrementReferrerCount(referrerCode: string) {
  const { sheets, spreadsheetId } = await getSheets()
  
  // Read the waitlist to find the referrer
  const read = await sheets.spreadsheets.values.get({
    spreadsheetId,
    range: SHEET_RANGE,
  })
  const rows = read.data.values || []
  const header = rows[0] || []
  const data = rows.slice(1)

  const idxRefCode = header.indexOf("refCode")
  const idxReferrals = header.indexOf("referrals")

  // Find the referrer and update their count
  for (let i = 0; i < data.length; i++) {
    const row = data[i]
    if (((row[idxRefCode] as string) || "") === referrerCode) {
      const currentReferrals = Number.parseInt((row[idxReferrals] as string) || "0", 10)
      const newReferrals = currentReferrals + 1
      
      // Update the specific cell
      const rowNumber = i + 2 // +1 for header, +1 for 0-based index
      const cellAddress = `${String.fromCharCode(65 + idxReferrals)}${rowNumber}` // Convert to A1 notation
      
      console.log(`Incrementing referrals for ${referrerCode}: ${currentReferrals} -> ${newReferrals} at ${cellAddress}`)
      
      await sheets.spreadsheets.values.update({
        spreadsheetId,
        range: `${process.env.SHEETS_TAB_WAITLIST?.split('!')[0] || 'Waitlist'}!${cellAddress}`,
        valueInputOption: "RAW",
        requestBody: {
          values: [[newReferrals]]
        }
      })
      break
    }
  }
}

export async function recordReferralInvite(fromRefCode: string, friendEmail: string) {
  const { sheets, spreadsheetId } = await getSheets()
  const range = process.env.SHEETS_TAB_REFERRALS || "Referrals!A:D"
  const now = new Date().toISOString()
  const values = [[now, fromRefCode, friendEmail.toLowerCase(), "invited"]]
  
  await sheets.spreadsheets.values.append({
    spreadsheetId,
    range,
    valueInputOption: "RAW",
    requestBody: { values },
  })
}

export async function getReferralStats(refCode: string): Promise<{
  referrals: number;
  totalRewards?: number;
  pendingRewards?: number;
}> {
  const { sheets, spreadsheetId } = await getSheets()
  const range = process.env.SHEETS_TAB_WAITLIST || "Waitlist!A:H"
  const read = await sheets.spreadsheets.values.get({ spreadsheetId, range })
  const rows = read.data.values || []
  const header = rows[0] || []
  const data = rows.slice(1)

  const idxRefCode = header.indexOf("refCode")
  const idxReferrals = header.indexOf("referrals")

  let referrals = 0
  for (const r of data) {
    if (((r[idxRefCode] as string) || "") === refCode) {
      referrals = Number.parseInt((r[idxReferrals] as string) || "0", 10) || 0
      break
    }
  }
  
  return { 
    referrals,
    totalRewards: 0, // Placeholder for future reward tracking
    pendingRewards: 0 // Placeholder for future reward tracking
  }
}

// Optional: Get all emails for newsletter purposes
export async function getAllEmails(): Promise<Array<{
  email: string;
  wantsClaimEmails: boolean;
  referralCode: string;
}>> {
  const { sheets, spreadsheetId } = await getSheets()
  const range = process.env.SHEETS_TAB_WAITLIST || "Waitlist!A:H"
  const read = await sheets.spreadsheets.values.get({ spreadsheetId, range })
  const rows = read.data.values || []
  const header = rows[0] || []
  const data = rows.slice(1)

  const idxEmail = header.indexOf("email")
  const idxRefCode = header.indexOf("refCode")
  const idxWantsEmails = header.indexOf("wantsClaimEmails")

  return data.map(row => ({
    email: (row[idxEmail] as string) || "",
    wantsClaimEmails: ((row[idxWantsEmails] as string) || "").toLowerCase() === "yes",
    referralCode: (row[idxRefCode] as string) || ""
  })).filter(item => item.email) // Filter out empty emails
}

// Count how many people a specific referrer has referred
export async function countReferralsByReferrer(referrerCode: string): Promise<number> {
  const { sheets, spreadsheetId } = await getSheets()
  const range = process.env.SHEETS_TAB_WAITLIST || "Waitlist!A:H"
  const read = await sheets.spreadsheets.values.get({ spreadsheetId, range })
  const rows = read.data.values || []
  const header = rows[0] || []
  const data = rows.slice(1)

  const idxReferrerCode = header.indexOf("referrerCode")
  
  let count = 0
  for (const r of data) {
    if (((r[idxReferrerCode] as string) || "") === referrerCode) {
      count++
    }
  }
  
  return count
}

// Get referral data by email address
export async function getReferralDataByEmail(email: string): Promise<{
  email: string;
  refCode: string;
  referrals: number;
  wantsClaimEmails: boolean;
}> {
  const { sheets, spreadsheetId } = await getSheets()
  const range = process.env.SHEETS_TAB_WAITLIST || "Waitlist!A:H"
  const read = await sheets.spreadsheets.values.get({ spreadsheetId, range })
  const rows = read.data.values || []
  const header = rows[0] || []
  const data = rows.slice(1)

  const idxEmail = header.indexOf("email")
  const idxRefCode = header.indexOf("refCode")
  const idxReferrals = header.indexOf("referrals")
  const idxWantsEmails = header.indexOf("wantsClaimEmails")

  // Find the user by email
  for (const r of data) {
    if (r[idxEmail] && r[idxEmail].toLowerCase() === email.toLowerCase()) {
      return {
        email: r[idxEmail] as string,
        refCode: (r[idxRefCode] as string) || "",
        referrals: Number.parseInt((r[idxReferrals] as string) || "0", 10),
        wantsClaimEmails: ((r[idxWantsEmails] as string) || "").toLowerCase() === "yes"
      }
    }
  }
  
  throw new Error('EMAIL_NOT_FOUND')
}