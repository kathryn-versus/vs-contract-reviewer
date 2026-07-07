'use client';

import { useState } from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import clsx from 'clsx';
import { useAuth } from '@/hooks/useAuth';

export function TopNav() {
  const { user, role, signOut } = useAuth();
  const pathname = usePathname();
  const [avatarFailed, setAvatarFailed] = useState(false);

  const navLink = (href: string, label: string) => (
    <Link
      href={href}
      className={clsx(
        'font-body text-sm transition-colors',
        pathname === href || pathname.startsWith(href + '/')
          ? 'text-ink font-medium'
          : 'text-ink-soft hover:text-ink'
      )}
    >
      {label}
    </Link>
  );

  return (
    <header className="sticky top-0 z-30 border-b border-rule bg-paper/95 backdrop-blur">
      <div className="mx-auto flex h-16 max-w-6xl items-center justify-between px-6">
        <Link href="/" className="flex items-baseline gap-2">
          <span className="font-display text-lg text-ink">VS Contract Reviewer</span>
          <span className="hidden font-mono text-[10px] uppercase tracking-widest text-ink-faint sm:inline">
            Versus Studio
          </span>
        </Link>

        <nav className="flex items-center gap-6">
          {/* Admin-only links: not just hidden, not rendered at all for reviewers. */}
          {role === 'admin' && (
            <>
              {navLink('/library', 'Library')}
              {navLink('/settings', 'Settings')}
            </>
          )}

          {user && (
            <div className="flex items-center gap-3 border-l border-rule pl-6">
              <div className="flex items-center gap-2">
                {user.photoURL && !avatarFailed ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img
                    src={user.photoURL}
                    alt=""
                    className="h-7 w-7 rounded-full"
                    referrerPolicy="no-referrer"
                    onError={() => setAvatarFailed(true)}
                  />
                ) : (
                  <div className="flex h-7 w-7 items-center justify-center rounded-full bg-ink text-xs text-paper">
                    {(user.displayName ?? user.email ?? '?')[0]?.toUpperCase()}
                  </div>
                )}
                <span className="hidden font-body text-sm text-ink-soft md:inline">
                  {user.displayName ?? user.email}
                </span>
              </div>
              <button
                onClick={signOut}
                className="font-mono text-xs uppercase tracking-wide text-ink-faint hover:text-ink"
              >
                Sign out
              </button>
            </div>
          )}
        </nav>
      </div>
    </header>
  );
}

