'use client';

import { useEffect, useState, useCallback } from 'react';
import {
  onAuthStateChanged,
  signInWithPopup,
  signOut as firebaseSignOut,
  type User,
} from 'firebase/auth';
import { doc, getDoc, setDoc, serverTimestamp } from 'firebase/firestore';
import { auth, db, createGoogleProvider, isAllowedDomainEmail } from '@/lib/firebase/client';
import type { Role, UserDoc } from '@/lib/types';

interface AuthState {
  user: User | null;
  role: Role | null;
  loading: boolean;
  error: string | null;
}

export function useAuth() {
  const [state, setState] = useState<AuthState>({
    user: null,
    role: null,
    loading: true,
    error: null,
  });

  useEffect(() => {
    const unsub = onAuthStateChanged(auth, async (user) => {
      if (!user) {
        setState({ user: null, role: null, loading: false, error: null });
        return;
      }

      if (!isAllowedDomainEmail(user.email)) {
        await firebaseSignOut(auth);
        setState({
          user: null,
          role: null,
          loading: false,
          error: 'Only @vsnyc.tv Google accounts can sign in.',
        });
        return;
      }

      const userRef = doc(db, 'users', user.uid);
      const snap = await getDoc(userRef);

      let role: Role = 'reviewer';
      if (!snap.exists()) {
        // First sign-in — create the user doc. Admins are promoted manually
        // in the Firestore console per the brief.
        const newUser: Omit<UserDoc, 'uid'> = {
          email: user.email ?? '',
          name: user.displayName ?? user.email ?? 'Unknown',
          role: 'reviewer',
          createdAt: Date.now(),
          lastLoginAt: Date.now(),
        };
        await setDoc(userRef, { ...newUser, createdAt: serverTimestamp(), lastLoginAt: serverTimestamp() });
      } else {
        role = (snap.data().role as Role) ?? 'reviewer';
        await setDoc(userRef, { lastLoginAt: serverTimestamp() }, { merge: true });
      }

      // Mint the httpOnly session cookie used by middleware / server pages.
      const idToken = await user.getIdToken();
      await fetch('/api/auth/session', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ idToken }),
      });

      setState({ user, role, loading: false, error: null });
    });

    return unsub;
  }, []);

  const signIn = useCallback(async () => {
    setState((s) => ({ ...s, error: null }));
    try {
      await signInWithPopup(auth, createGoogleProvider());
    } catch (err) {
      setState((s) => ({
        ...s,
        error: err instanceof Error ? err.message : 'Sign-in failed.',
      }));
    }
  }, []);

  const signOut = useCallback(async () => {
    await fetch('/api/auth/session', { method: 'DELETE' });
    await firebaseSignOut(auth);
  }, []);

  return { ...state, signIn, signOut, isAdmin: state.role === 'admin' };
}
