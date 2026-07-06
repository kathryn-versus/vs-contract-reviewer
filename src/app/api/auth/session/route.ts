import { NextRequest, NextResponse } from 'next/server';
import { adminAuth } from '@/lib/firebase/admin';
import { createSessionCookie, SESSION_COOKIE, SESSION_MAX_AGE_MS } from '@/lib/firebase/session';
import { ALLOWED_DOMAIN_SERVER } from '@/lib/firebase/domain';

// Exchanges a freshly-minted Firebase ID token (from client-side Google
// sign-in) for an httpOnly session cookie that Next.js middleware and server
// components can read — client JS never touches the session cookie.
export async function POST(req: NextRequest) {
  const { idToken } = await req.json();
  if (!idToken) {
    return NextResponse.json({ error: 'Missing idToken' }, { status: 400 });
  }

  const decoded = await adminAuth().verifyIdToken(idToken);
  const email = decoded.email ?? '';
  if (!email.toLowerCase().endsWith(`@${ALLOWED_DOMAIN_SERVER}`)) {
    return NextResponse.json(
      { error: `Only @${ALLOWED_DOMAIN_SERVER} accounts may sign in.` },
      { status: 403 }
    );
  }

  const sessionCookie = await createSessionCookie(idToken);
  const res = NextResponse.json({ ok: true });
  res.cookies.set(SESSION_COOKIE, sessionCookie, {
    maxAge: SESSION_MAX_AGE_MS / 1000,
    httpOnly: true,
    secure: true,
    sameSite: 'lax',
    path: '/',
  });
  return res;
}

export async function DELETE() {
  const res = NextResponse.json({ ok: true });
  res.cookies.delete(SESSION_COOKIE);
  return res;
}
