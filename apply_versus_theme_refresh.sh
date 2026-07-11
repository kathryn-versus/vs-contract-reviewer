#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_versus_theme_refresh.sh
set -e

# ── 1. src/app/globals.css — new palette + Oswald display font ─────────────
cat > "src/app/globals.css" << 'VS_APPLY_EOF_globals'
@tailwind base;
@tailwind components;
@tailwind utilities;

:root {
  /* Design tokens — refreshed to nod to the Versus brand (weareversus.tv):
     near-black chrome with a gold accent line, bolder condensed headlines,
     more saturated severity colors. The main content area stays light
     rather than going full dark-mode, since this app is used for long
     stretches of reading dense contract text — a pure black background
     would hurt legibility there even though it reads great as a hero
     treatment on a marketing site. */
  --paper: #FAFAF8;
  --ink: #141414;
  --ink-soft: #52514D;
  --ink-faint: #8C8A82;
  --rule: #DEDDD6;
  /* Deliberately darker/more muted than the nav's gold accent below — pure
     bright gold (#D9A62B) fails contrast as small link/label text on the
     light --paper background. This shade keeps the gold character while
     staying readable at font-mono text-xs sizes used throughout. */
  --accent: #A5730E;
  --accent-soft: #E8D9B0;

  --high: #C0392B;
  --high-bg: #F7E1DF;
  --med: #C97A22;
  --med-bg: #F6E9D5;
  --low: #3F7D4A;
  --low-bg: #E3EFE2;

  /* Dark chrome — used ONLY by the top nav, not the main content area. */
  --chrome-bg: #141414;
  --chrome-text: #FAFAF8;
  --chrome-text-soft: #B7B5AC;
  --chrome-accent: #D9A62B;
}

html,
body {
  background-color: var(--paper);
  color: var(--ink);
}

* {
  border-color: var(--rule);
}

.font-display {
  font-family: var(--font-oswald), 'Arial Narrow', sans-serif;
  font-weight: 600;
  letter-spacing: 0.01em;
}
.font-body {
  font-family: var(--font-inter), system-ui, sans-serif;
}
.font-mono {
  font-family: var(--font-plex-mono), 'SF Mono', monospace;
}
VS_APPLY_EOF_globals
echo "Wrote src/app/globals.css"

# ── 2. tailwind.config.ts — chrome colors + Oswald display font ────────────
cat > "tailwind.config.ts" << 'VS_APPLY_EOF_tailwind'
import type { Config } from 'tailwindcss';

const config: Config = {
  content: ['./src/**/*.{js,ts,jsx,tsx,mdx}'],
  theme: {
    extend: {
      colors: {
        paper: 'var(--paper)',
        ink: 'var(--ink)',
        'ink-soft': 'var(--ink-soft)',
        'ink-faint': 'var(--ink-faint)',
        rule: 'var(--rule)',
        accent: 'var(--accent)',
        'accent-soft': 'var(--accent-soft)',
        high: 'var(--high)',
        'high-bg': 'var(--high-bg)',
        med: 'var(--med)',
        'med-bg': 'var(--med-bg)',
        low: 'var(--low)',
        'low-bg': 'var(--low-bg)',
        chrome: 'var(--chrome-bg)',
        'chrome-text': 'var(--chrome-text)',
        'chrome-text-soft': 'var(--chrome-text-soft)',
        'chrome-accent': 'var(--chrome-accent)',
      },
      fontFamily: {
        display: ['var(--font-oswald)', 'sans-serif'],
        body: ['var(--font-inter)', 'sans-serif'],
        mono: ['var(--font-plex-mono)', 'monospace'],
      },
    },
  },
  plugins: [],
};

export default config;
VS_APPLY_EOF_tailwind
echo "Wrote tailwind.config.ts"

# ── 3. src/app/layout.tsx — swap Source Serif for Oswald ───────────────────
cat > "src/app/layout.tsx" << 'VS_APPLY_EOF_layout'
import type { Metadata } from 'next';
import { Oswald, Inter, IBM_Plex_Mono } from 'next/font/google';
import './globals.css';

// Bold condensed uppercase-friendly display face — closer to Versus's own
// headline type than the previous serif, used for headings, client/project
// names, and other font-display text throughout the app.
const oswald = Oswald({
  subsets: ['latin'],
  weight: ['500', '600', '700'],
  variable: '--font-oswald',
  display: 'swap',
});
const inter = Inter({
  subsets: ['latin'],
  variable: '--font-inter',
  display: 'swap',
});
const plexMono = IBM_Plex_Mono({
  subsets: ['latin'],
  weight: ['400', '500', '600'],
  variable: '--font-plex-mono',
  display: 'swap',
});

export const metadata: Metadata = {
  title: 'VS Contract Reviewer',
  description: 'Versus Studio — contract intake, review, and institutional memory.',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${oswald.variable} ${inter.variable} ${plexMono.variable}`}>
      <body className="font-body bg-paper text-ink antialiased">{children}</body>
    </html>
  );
}
VS_APPLY_EOF_layout
echo "Wrote src/app/layout.tsx"

# ── 4. src/components/layout/TopNav.tsx — dark chrome + gold accent ────────
cat > "src/components/layout/TopNav.tsx" << 'VS_APPLY_EOF_topnav'
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
          ? 'text-chrome-text font-medium'
          : 'text-chrome-text-soft hover:text-chrome-text'
      )}
    >
      {label}
    </Link>
  );

  return (
    <header className="sticky top-0 z-30 border-b-2 border-chrome-accent bg-chrome/95 backdrop-blur">
      <div className="mx-auto flex h-16 max-w-6xl items-center justify-between px-6">
        <Link href="/" className="flex items-baseline gap-2">
          <span className="font-display text-lg uppercase tracking-wide text-chrome-text">
            VS Contract Reviewer
          </span>
          <span className="hidden font-mono text-[10px] uppercase tracking-widest text-chrome-text-soft sm:inline">
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
            <div className="flex items-center gap-3 border-l border-chrome-text-soft/30 pl-6">
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
                  <div className="flex h-7 w-7 items-center justify-center rounded-full bg-chrome-accent text-xs font-medium text-chrome">
                    {(user.displayName ?? user.email ?? '?')[0]?.toUpperCase()}
                  </div>
                )}
                <span className="hidden font-body text-sm text-chrome-text-soft md:inline">
                  {user.displayName ?? user.email}
                </span>
              </div>
              <button
                onClick={signOut}
                className="font-mono text-xs uppercase tracking-wide text-chrome-text-soft hover:text-chrome-text"
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
VS_APPLY_EOF_topnav
echo "Wrote src/components/layout/TopNav.tsx"

echo ""
echo "Done. Restart your dev server and take a look:"
echo "  - Top nav should now be near-black with a gold underline and white"
echo "    logo text."
echo "  - Headlines/labels throughout should render in the new bold"
echo "    condensed font (Oswald) instead of the old serif."
echo "  - Links, buttons, and severity badges should reflect the new"
echo "    palette (gold links, red/amber/green severity)."
echo "  - Main content areas (forms, results, library) stay light — only"
echo "    the nav goes dark."
echo ""
echo "If anything looks off (contrast, a color that doesn't read well),"
echo "tell me exactly what and where — much easier to tune one value than"
echo "guess blind. Then commit and push (via GitHub Desktop) to deploy."
