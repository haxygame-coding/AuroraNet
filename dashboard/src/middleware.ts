import { NextResponse } from 'next/server'
import type { NextRequest } from 'next/server'

export function middleware(request: NextRequest) {
  const hasSession = request.cookies.has('aura_session')
  const { pathname } = request.nextUrl
  const isLoginPage = pathname === '/login'

  // If no session and not on login page, redirect to login
  if (!hasSession && !isLoginPage) {
    return NextResponse.redirect(new URL('/login', request.url))
  }

  // If session exists and on login page, redirect to home
  if (hasSession && isLoginPage) {
    return NextResponse.redirect(new URL('/', request.url))
  }

  return NextResponse.next()
}

export const config = {
  matcher: ['/((?!api|_next/static|_next/image|favicon.ico).*)'],
}
