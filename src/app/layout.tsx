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
