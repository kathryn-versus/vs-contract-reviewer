'use client';

import { initializeApp, getApps, getApp, type FirebaseApp } from 'firebase/app';
import {
  getAuth,
  GoogleAuthProvider,
  type Auth,
} from 'firebase/auth';
import { getFirestore, type Firestore } from 'firebase/firestore';

const firebaseConfig = {
  apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY,
  authDomain: process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN,
  projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID,
  storageBucket: process.env.NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET,
  messagingSenderId: process.env.NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID,
  appId: process.env.NEXT_PUBLIC_FIREBASE_APP_ID,
};

export const firebaseApp: FirebaseApp =
  getApps().length > 0 ? getApp() : initializeApp(firebaseConfig);

export const auth: Auth = getAuth(firebaseApp);
export const db: Firestore = getFirestore(firebaseApp);

// Domain restriction is enforced twice: here (hd hint + post-auth check) and
// in Firebase Auth console (Google sign-in method → authorized domain).
export const ALLOWED_DOMAIN =
  process.env.NEXT_PUBLIC_ALLOWED_DOMAIN ?? 'vsnyc.tv';

export function createGoogleProvider() {
  const provider = new GoogleAuthProvider();
  // Hints Google's account chooser to the Workspace domain — not a hard
  // enforcement boundary, so we still verify the returned email below.
  provider.setCustomParameters({ hd: ALLOWED_DOMAIN });
  return provider;
}

export function isAllowedDomainEmail(email: string | null | undefined) {
  if (!email) return false;
  return email.toLowerCase().endsWith(`@${ALLOWED_DOMAIN.toLowerCase()}`);
}
