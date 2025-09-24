import type { NextRequest } from 'next/server'
import { NextResponse } from 'next/server'

export function middleware(req: NextRequest) {
  const url = req.nextUrl
  if (url.hostname === 'www.trovefi.xyz') {
    url.hostname = 'trovefi.xyz'
    return NextResponse.redirect(url, 308)
  }
  return NextResponse.next()
}
export const config = { matcher: '/:path*' }
