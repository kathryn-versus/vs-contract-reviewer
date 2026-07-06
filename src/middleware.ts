import { NextRequest, NextResponse } from 'next/server';

// Coarse gate: any protected route requires the session cookie to exist.
// Fine-grained role checks (admin-only /library, /settings) happen server-side
// in each route's layout/page via getServerUser(), since verifying an admin
// role requires a Firestore read that we don't want to do on every edge
// request. This mirrors the Route Protection table in the project brief.
const PROTECTED_PREFIXES = ['/', '/library', '/settings'];
const SESSION_COOKIE = 'vs_session';

export function middleware(req: NextRequest) {
  const { pathname } = req.nextUrl;

  if (pathname.startsWith('/login') || pathname.startsWith('/api')) {
    return NextResponse.next();
  }

  const isProtected = PROTECTED_PREFIXES.some(
    (p) => pathname === p || (p !== '/' && pathname.startsWith(p))
  );
  if (!isProtected) return NextResponse.next();

  const hasSession = req.cookies.has(SESSION_COOKIE);
  if (!hasSession) {
    const loginUrl = new URL('/login', req.url);
    loginUrl.searchParams.set('next', pathname);
    return NextResponse.redirect(loginUrl);
  }

  return NextResponse.next();
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|fonts).*)'],
};
