#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_fix_login_suspense.sh
set -e

mkdir -p "$(dirname "src/app/login/page.tsx")"
cat > "src/app/login/page.tsx" << 'VS_APPLY_EOF_login1'
'use client';

import { Suspense, useEffect } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { useAuth } from '@/hooks/useAuth';

// useSearchParams() requires a Suspense boundary for static generation to
// succeed in production (Next.js "missing-suspense-with-csr-bailout") — this
// wasn't caught locally since `next dev` doesn't statically prerender pages
// the same way `next build` does.
function LoginPageInner() {
  const { user, loading, error, signIn } = useAuth();
  const router = useRouter();
  const params = useSearchParams();

  useEffect(() => {
    if (!loading && user) {
      router.replace(params.get('next') || '/');
    }
  }, [loading, user, router, params]);

  return (
    <div className="flex min-h-screen items-center justify-center bg-paper">
      <div className="w-full max-w-sm border border-rule bg-paper p-10 text-center shadow-sm">
        <p className="font-mono text-xs uppercase tracking-widest text-ink-faint">
          Versus Studio
        </p>
        <h1 className="mt-2 font-display text-2xl text-ink">VS Contract Reviewer</h1>
        <p className="mt-3 text-sm text-ink-soft">
          Sign in with your @vsnyc.tv Google account to continue.
        </p>

        {error && (
          <p className="mt-4 rounded border border-high bg-high-bg px-3 py-2 text-sm text-high">
            {error}
          </p>
        )}

        <button
          onClick={signIn}
          disabled={loading}
          className="mt-6 w-full border border-ink bg-ink px-4 py-2.5 font-body text-sm font-medium text-paper transition hover:bg-ink-soft disabled:opacity-50"
        >
          Continue with Google
        </button>
      </div>
    </div>
  );
}

export default function LoginPage() {
  return (
    <Suspense fallback={null}>
      <LoginPageInner />
    </Suspense>
  );
}
VS_APPLY_EOF_login1

echo ""
echo "Restart your dev server if it's running to confirm the login page still"
echo "works locally, then commit and push (via GitHub Desktop) to trigger the"
echo "next rollout."
