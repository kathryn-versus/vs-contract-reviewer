import 'server-only';
import { cookies } from 'next/headers';
import { adminAuth, adminDb } from './admin';
import type { UserDoc } from '../types';

const SESSION_COOKIE = 'vs_session';
const SESSION_MAX_AGE_MS = 1000 * 60 * 60 * 24 * 5; // 5 days

export async function createSessionCookie(idToken: string) {
  return adminAuth().createSessionCookie(idToken, { expiresIn: SESSION_MAX_AGE_MS });
}

export { SESSION_COOKIE, SESSION_MAX_AGE_MS };

/**
 * Server-side helper for App Router pages/layouts: verifies the session
 * cookie and loads the corresponding Firestore user doc (for role checks).
 * Returns null if there is no valid session.
 */
export async function getServerUser(): Promise<UserDoc | null> {
  const cookieStore = cookies();
  const sessionCookie = cookieStore.get(SESSION_COOKIE)?.value;
  if (!sessionCookie) return null;

  try {
    const decoded = await adminAuth().verifySessionCookie(sessionCookie, true);
    const snap = await adminDb().collection('users').doc(decoded.uid).get();
    if (!snap.exists) return null;
    return { uid: decoded.uid, ...(snap.data() as Omit<UserDoc, 'uid'>) };
  } catch {
    return null;
  }
}

export async function requireAdmin(): Promise<UserDoc | null> {
  const user = await getServerUser();
  if (!user || user.role !== 'admin') return null;
  return user;
}
