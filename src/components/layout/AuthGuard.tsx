'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/hooks/useAuth';
import type { Role } from '@/lib/types';

/**
 * Client-side defense-in-depth for route protection. Server pages already
 * gate admin routes via getServerUser()/requireAdmin(); this additionally
 * ensures admin-only UI is never rendered client-side for a reviewer, and
 * redirects if auth state changes after initial load (e.g. role revoked).
 */
export function AuthGuard({
  children,
  requireRole,
}: {
  children: React.ReactNode;
  requireRole?: Role; // 'admin' → only admins; omit → any signed-in user
}) {
  const { user, role, loading } = useAuth();
  const router = useRouter();

  useEffect(() => {
    if (loading) return;
    if (!user) {
      router.replace('/login');
      return;
    }
    if (requireRole === 'admin' && role !== 'admin') {
      router.replace('/');
    }
  }, [loading, user, role, requireRole, router]);

  if (loading) {
    return (
      <div className="flex h-[60vh] items-center justify-center text-ink-faint font-mono text-sm">
        Loading…
      </div>
    );
  }

  if (!user) return null;
  if (requireRole === 'admin' && role !== 'admin') return null;

  return <>{children}</>;
}
