#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_rename_admin_env_vars.sh
set -e

mkdir -p "$(dirname "src/lib/firebase/admin.ts")"
cat > "src/lib/firebase/admin.ts" << 'VS_APPLY_EOF_admin1'
import { initializeApp, getApps, cert, type App } from 'firebase-admin/app';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';
import { getAuth, type Auth } from 'firebase-admin/auth';

// Server-only. Never import this file from a 'use client' component.
function buildAdminApp(): App {
  if (getApps().length > 0) return getApps()[0];

  // Named ADMIN_* rather than FIREBASE_ADMIN_* — Firebase App Hosting
  // reserves the FIREBASE_ prefix (along with X_GOOGLE_ and EXT_) for its
  // own internal use and refuses to let you set env vars/secrets under
  // that prefix, so these were renamed to deploy successfully.
  const projectId = process.env.ADMIN_PROJECT_ID;
  const clientEmail = process.env.ADMIN_CLIENT_EMAIL;
  // Private keys are usually stored with literal \n escapes in env files.
  const privateKey = process.env.ADMIN_PRIVATE_KEY?.replace(/\\n/g, '\n');

  if (!projectId || !clientEmail || !privateKey) {
    throw new Error(
      'Missing Firebase Admin credentials. Set ADMIN_PROJECT_ID, ' +
        'ADMIN_CLIENT_EMAIL, and ADMIN_PRIVATE_KEY in your environment ' +
        '(Firebase App Hosting secrets/config in production, .env.local in dev).'
    );
  }

  return initializeApp({
    credential: cert({ projectId, clientEmail, privateKey }),
  });
}

let _app: App | null = null;
function app(): App {
  if (!_app) _app = buildAdminApp();
  return _app;
}

export function adminDb(): Firestore {
  return getFirestore(app());
}

export function adminAuth(): Auth {
  return getAuth(app());
}
VS_APPLY_EOF_admin1

echo ""
echo "Done. src/lib/firebase/admin.ts now reads ADMIN_PROJECT_ID, ADMIN_CLIENT_EMAIL,"
echo "and ADMIN_PRIVATE_KEY instead of the FIREBASE_ADMIN_* names."
echo ""
echo "Next: manually rename those 3 variable NAMES (not values) in .env.local:"
echo "  FIREBASE_ADMIN_PROJECT_ID   -> ADMIN_PROJECT_ID"
echo "  FIREBASE_ADMIN_CLIENT_EMAIL -> ADMIN_CLIENT_EMAIL"
echo "  FIREBASE_ADMIN_PRIVATE_KEY  -> ADMIN_PRIVATE_KEY"
echo "Then restart your dev server (Ctrl+C, then npm run dev) to confirm local"
echo "dev still works before continuing the Firebase secrets setup."
