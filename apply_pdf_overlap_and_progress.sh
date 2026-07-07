#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_pdf_overlap_and_progress.sh
set -e

mkdir -p "$(dirname "src/lib/report/ContractReportPdf.tsx")"
cat > "src/lib/report/ContractReportPdf.tsx" << 'VS_APPLY_EOF_fix1'
import { Document, Page, View, Text, StyleSheet } from '@react-pdf/renderer';
import { STANDING_CONCERNS, CONCERN_SHORT_LABELS } from '@/lib/types';
import type { ContractDoc, Finding } from '@/lib/types';

const SEVERITY_COLOR: Record<string, string> = {
  high: '#8A3324',
  medium: '#A8761E',
  low: '#5A6B4F',
};

const SEVERITY_BG: Record<string, string> = {
  high: '#F3E4DF',
  medium: '#F4ECDA',
  low: '#E7ECE1',
};

// Built-in PDF fonts only (no network font registration, so generation can
// never silently fail on a bad font URL): Times-* stands in for the site's
// Georgia serif headings, Courier for its monospace labels/meta, Helvetica
// for body copy — mirroring the same three-typeface split used in the HTML
// report and the on-screen results view.
const styles = StyleSheet.create({
  page: { padding: 40, paddingBottom: 56, fontSize: 10, fontFamily: 'Helvetica', color: '#1C1B19', backgroundColor: '#F7F5F1' },

  eyebrow: { fontSize: 8, letterSpacing: 1.5, textTransform: 'uppercase', color: '#8C8777', marginBottom: 8, fontFamily: 'Courier' },
  masthead: { fontSize: 22, fontFamily: 'Times-Bold', marginBottom: 10 },
  mastheadAccent: { color: '#8A3324' },

  concernIndex: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    borderBottomWidth: 2,
    borderBottomColor: '#1C1B19',
    paddingBottom: 10,
    marginBottom: 16,
  },
  concernItem: { fontSize: 8, fontFamily: 'Courier', color: '#5B574D', marginRight: 12, marginBottom: 3 },
  concernNum: { fontFamily: 'Courier-Bold', color: '#1C1B19' },

  title: { fontSize: 16, fontFamily: 'Times-Bold', marginBottom: 4 },
  meta: { fontSize: 9, fontFamily: 'Courier', color: '#5B574D', marginBottom: 18 },

  summaryRow: { flexDirection: 'row', marginBottom: 22 },
  summaryBox: { flex: 1, borderWidth: 1, borderColor: '#D8D3C7', paddingVertical: 10, paddingHorizontal: 8, marginRight: 8, textAlign: 'center', backgroundColor: '#FFFFFF' },
  summaryNum: { fontSize: 20, fontFamily: 'Times-Bold', marginBottom: 3 },
  summaryLabel: { fontSize: 7, fontFamily: 'Courier', textTransform: 'uppercase', color: '#8C8777' },

  issue: { borderWidth: 1, borderColor: '#D8D3C7', borderLeftWidth: 4, padding: 14, marginBottom: 12, backgroundColor: '#FFFFFF' },
  issueHeaderRow: { flexDirection: 'row', alignItems: 'center', marginBottom: 8 },
  issueIndex: { fontSize: 9, fontFamily: 'Courier', color: '#8C8777', marginRight: 8 },
  severityPill: { borderWidth: 1, borderRadius: 8, paddingVertical: 2, paddingHorizontal: 7, marginRight: 8 },
  severityPillText: { fontSize: 8, fontFamily: 'Courier-Bold', textTransform: 'uppercase' },
  issueConcern: { fontSize: 8, fontFamily: 'Courier', textTransform: 'uppercase', color: '#8C8777' },

  issueTitle: { fontSize: 12.5, fontFamily: 'Times-Bold', marginBottom: 4 },
  issueLocation: { fontSize: 8, fontFamily: 'Courier', color: '#8C8777', marginBottom: 8 },

  sectionLabel: { fontSize: 7.5, fontFamily: 'Courier-Bold', textTransform: 'uppercase', letterSpacing: 0.5, color: '#8C8777', marginTop: 8, marginBottom: 3 },
  quote: { fontSize: 9.5, fontFamily: 'Times-Italic', color: '#5B574D', borderLeftWidth: 2, borderLeftColor: '#D8D3C7', paddingLeft: 10, lineHeight: 1.4 },
  body: { fontSize: 9.5, lineHeight: 1.45, fontFamily: 'Helvetica' },
  redline: { fontSize: 8.5, fontFamily: 'Courier', backgroundColor: '#EFE9DC', padding: 8, marginTop: 2, lineHeight: 1.4 },

  footer: { position: 'absolute', bottom: 20, left: 40, right: 40, flexDirection: 'row', justifyContent: 'space-between', fontSize: 7, fontFamily: 'Courier', color: '#8C8777', borderTopWidth: 1, borderTopColor: '#D8D3C7', paddingTop: 6 },
});

export function ContractReportPdf({
  contract,
  findings,
  redlines,
  generatedAt,
}: {
  contract: Pick<ContractDoc, 'clientName' | 'projectName' | 'projectNumber' | 'docType' | 'counterparty'>;
  findings: Finding[];
  redlines: Record<string, string>;
  generatedAt?: Date;
}) {
  const when = generatedAt ?? new Date();
  const counts = {
    total: findings.length,
    high: findings.filter((f) => f.severity === 'high').length,
    medium: findings.filter((f) => f.severity === 'medium').length,
    low: findings.filter((f) => f.severity === 'low').length,
  };

  return (
    <Document>
      <Page size="LETTER" style={styles.page}>
        <Text style={styles.eyebrow}>Versus Studio · Contract Review Report</Text>
        <Text style={styles.masthead}>
          Contract Review <Text style={styles.mastheadAccent}>VS</Text>
        </Text>

        <View style={styles.concernIndex}>
          {STANDING_CONCERNS.map((c) => (
            <Text key={c.id} style={styles.concernItem}>
              <Text style={styles.concernNum}>{c.id}. </Text>
              {CONCERN_SHORT_LABELS[c.id] ?? c.label}
            </Text>
          ))}
        </View>

        <Text style={styles.title}>
          {contract.clientName} — {contract.projectName} ({contract.projectNumber})
        </Text>
        <Text style={styles.meta}>
          {contract.docType} · Counterparty: {contract.counterparty} · Reviewed against {STANDING_CONCERNS.length} standing concerns{'\n'}
          Generated {when.toLocaleString()}
        </Text>

        <View style={styles.summaryRow}>
          <View style={styles.summaryBox}>
            <Text style={styles.summaryNum}>{counts.total}</Text>
            <Text style={styles.summaryLabel}>Total flagged</Text>
          </View>
          <View style={styles.summaryBox}>
            <Text style={styles.summaryNum}>{counts.high}</Text>
            <Text style={styles.summaryLabel}>High</Text>
          </View>
          <View style={styles.summaryBox}>
            <Text style={styles.summaryNum}>{counts.medium}</Text>
            <Text style={styles.summaryLabel}>Medium</Text>
          </View>
          <View style={[styles.summaryBox, { marginRight: 0 }]}>
            <Text style={styles.summaryNum}>{counts.low}</Text>
            <Text style={styles.summaryLabel}>Low</Text>
          </View>
        </View>

        {findings.length === 0 && (
          <Text style={styles.body}>No issues flagged against the {STANDING_CONCERNS.length} standing concerns.</Text>
        )}

        {findings.map((f, i) => (
          // No wrap={false} here: findings with a long drafted redline can
          // be taller than a full page, and forcing "never break across
          // pages" on a block taller than the page causes react-pdf to
          // miscalculate and overlap text instead of paginating — that was
          // the cause of the garbled/overlapping text on longer findings.
          // Letting it flow normally means a long finding just breaks
          // cleanly onto the next page instead.
          <View key={f.uid} style={[styles.issue, { borderLeftColor: SEVERITY_COLOR[f.severity] }]}>
            <View style={styles.issueHeaderRow}>
              <Text style={styles.issueIndex}>{String(i + 1).padStart(2, '0')}</Text>
              <View style={[styles.severityPill, { borderColor: SEVERITY_COLOR[f.severity], backgroundColor: SEVERITY_BG[f.severity] }]}>
                <Text style={[styles.severityPillText, { color: SEVERITY_COLOR[f.severity] }]}>{f.severity}</Text>
              </View>
              <Text style={styles.issueConcern}>
                Concern {f.concernId} · {f.concernLabel}
              </Text>
            </View>

            <Text style={styles.issueTitle}>{f.issueTitle}</Text>
            {f.location ? <Text style={styles.issueLocation}>{f.location}</Text> : null}

            <Text style={styles.sectionLabel}>Contract language</Text>
            <Text style={styles.quote}>&ldquo;{f.quote}&rdquo;</Text>

            <Text style={styles.sectionLabel}>Why it matters</Text>
            <Text style={styles.body}>{f.analysis}</Text>

            <Text style={styles.sectionLabel}>Suggested negotiation direction</Text>
            <Text style={styles.body}>{f.recommendation}</Text>

            {redlines[f.uid] && (
              <>
                <Text style={styles.sectionLabel}>Drafted redline</Text>
                <Text style={styles.redline}>{redlines[f.uid]}</Text>
              </>
            )}
          </View>
        ))}

        <View style={styles.footer} fixed>
          <Text>
            {contract.clientName} — {contract.projectName} ({contract.projectNumber})
          </Text>
          <Text
            render={({ pageNumber, totalPages }) => `Page ${pageNumber} of ${totalPages}`}
          />
        </View>
      </Page>
    </Document>
  );
}
VS_APPLY_EOF_fix1

mkdir -p "$(dirname "src/components/ui/LoadingScan.tsx")"
cat > "src/components/ui/LoadingScan.tsx" << 'VS_APPLY_EOF_fix2'
'use client';

import { useEffect, useState } from 'react';

const MESSAGES = [
  'Scanning document structure…',
  'Cross-referencing the standing concerns…',
  'Checking termination and cure provisions…',
  'Evaluating indemnification and liability language…',
  'Reviewing AI and subcontractor clauses…',
  'Checking payment terms against standard structures…',
  'Drafting severity assessments…',
];

// A full analysis pass is one Claude call over the whole document text, so
// there's no real server-side progress to stream (yet) — this paces a
// progress bar against a typical-duration estimate instead, easing toward
// ~95% so it visibly moves the whole time but never falsely claims "done"
// before the response actually comes back and this view unmounts.
const ESTIMATED_MS = 35_000;

export function LoadingScan() {
  const [i, setI] = useState(0);
  const [elapsed, setElapsed] = useState(0);

  useEffect(() => {
    const messageId = setInterval(() => setI((v) => (v + 1) % MESSAGES.length), 1800);
    const start = Date.now();
    const tickId = setInterval(() => setElapsed(Date.now() - start), 200);
    return () => {
      clearInterval(messageId);
      clearInterval(tickId);
    };
  }, []);

  const percent = Math.min(95, Math.round(95 * (1 - Math.exp(-elapsed / ESTIMATED_MS))));

  return (
    <div className="flex flex-col items-center justify-center gap-4 py-20 text-center">
      <div className="relative h-14 w-11 border-2 border-ink">
        <div className="absolute left-0 top-0 h-0.5 w-full animate-pulse bg-accent" />
        <div className="absolute inset-x-1.5 top-3 h-0.5 bg-rule" />
        <div className="absolute inset-x-1.5 top-6 h-0.5 bg-rule" />
        <div className="absolute inset-x-1.5 top-9 h-0.5 bg-rule" />
      </div>

      <div className="w-64">
        <div className="h-1 w-full overflow-hidden rounded-full bg-rule">
          <div
            className="h-full bg-accent transition-[width] duration-300 ease-out"
            style={{ width: `${percent}%` }}
          />
        </div>
        <p className="mt-1.5 font-mono text-[11px] text-ink-faint">{percent}%</p>
      </div>

      <p className="font-mono text-xs uppercase tracking-wide text-ink-faint transition-opacity">
        {MESSAGES[i]}
      </p>
    </div>
  );
}
VS_APPLY_EOF_fix2

echo ""
echo "Done. 2 files updated:"
echo "  src/lib/report/ContractReportPdf.tsx   (fixed overlapping text on long findings)"
echo "  src/components/ui/LoadingScan.tsx      (added a real progress bar)"
echo ""
echo "No new npm packages needed — restart your dev server (Ctrl+C, then npm run dev)."
