#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_rating_and_report_streamline.sh
#
# Also fixes something I found while building this: generateReport.ts and
# ContractReportPdf.tsx had the OLD rust/amber/olive colors hardcoded in raw
# hex (standalone HTML/PDF files can't use the app's CSS variables), so the
# theme refresh never actually reached the exported reports. This retheme's
# them to match too.
set -e

# ── 1. New shared scoring utility ───────────────────────────────────────────
cat > "src/lib/report/scoring.ts" << 'VS_APPLY_EOF_scoring'
import type { Finding } from '@/lib/types';

export interface ReviewScore {
  score: number; // 0-100
  grade: 'A' | 'B' | 'C' | 'D' | 'F';
  summary: string;
}

/**
 * A quick, deterministic scan-friendly signal — NOT a legal risk model.
 * Highs cost the most, lows barely move the needle. Shared by the in-app
 * results view and both exported report formats so the grade/summary are
 * always consistent across all three.
 */
export function computeReviewScore(findings: Finding[]): ReviewScore {
  const high = findings.filter((f) => f.severity === 'high').length;
  const medium = findings.filter((f) => f.severity === 'medium').length;
  const low = findings.filter((f) => f.severity === 'low').length;

  const score = Math.max(0, Math.min(100, 100 - (high * 15 + medium * 7 + low * 2)));

  const grade: ReviewScore['grade'] =
    score >= 90 ? 'A' : score >= 80 ? 'B' : score >= 65 ? 'C' : score >= 45 ? 'D' : 'F';

  let summary: string;
  if (findings.length === 0) {
    summary = 'No issues found against the standing concerns.';
  } else if (high === 0 && medium === 0) {
    summary = `Generally aligned with standard terms — only ${low} minor wording issue${low === 1 ? '' : 's'} flagged.`;
  } else if (high > 0) {
    const topLabels = [...new Set(findings.filter((f) => f.severity === 'high').map((f) => f.concernLabel))].slice(0, 2);
    summary = `${high} high-severity issue${high === 1 ? '' : 's'} flagged${
      topLabels.length ? `, primarily around ${topLabels.join(' and ')}` : ''
    }${medium > 0 ? `, plus ${medium} medium-severity issue${medium === 1 ? '' : 's'}` : ''}.`;
  } else {
    summary = `${medium} medium-severity issue${medium === 1 ? '' : 's'} flagged — worth negotiating but not urgent.`;
  }

  return { score, grade, summary };
}
VS_APPLY_EOF_scoring
echo "Wrote src/lib/report/scoring.ts"

# ── 2. New in-app grade banner ──────────────────────────────────────────────
cat > "src/components/review/ReviewScoreBanner.tsx" << 'VS_APPLY_EOF_banner'
'use client';

import type { Finding } from '@/lib/types';
import { computeReviewScore } from '@/lib/report/scoring';

const GRADE_COLOR: Record<string, string> = {
  A: 'text-low',
  B: 'text-low',
  C: 'text-med',
  D: 'text-high',
  F: 'text-high',
};

export function ReviewScoreBanner({ findings }: { findings: Finding[] }) {
  const { grade, summary } = computeReviewScore(findings);
  return (
    <div className="flex items-center gap-4 rounded-sm border border-rule bg-paper px-5 py-4">
      <span className={`font-display text-4xl ${GRADE_COLOR[grade]}`}>{grade}</span>
      <p className="font-body text-sm text-ink-soft">{summary}</p>
    </div>
  );
}
VS_APPLY_EOF_banner
echo "Wrote src/components/review/ReviewScoreBanner.tsx"

# ── 3. src/components/review/ResultsView.tsx — show the banner ─────────────
python3 - << 'PYEOF'
path = "src/components/review/ResultsView.tsx"
with open(path) as f:
    content = f.read()

if "ReviewScoreBanner" in content:
    print("ResultsView.tsx: banner already wired in — nothing to do.")
else:
    old_import = "import { SeveritySummary, type FilterValue } from './SeveritySummary';"
    new_import = (
        "import { SeveritySummary, type FilterValue } from './SeveritySummary';\n"
        "import { ReviewScoreBanner } from './ReviewScoreBanner';"
    )
    old_render = '      <SeveritySummary findings={findings} active={filter} onChange={setFilter} />'
    new_render = (
        '      <ReviewScoreBanner findings={findings} />\n'
        '      <SeveritySummary findings={findings} active={filter} onChange={setFilter} />'
    )
    if old_import not in content or old_render not in content:
        raise SystemExit(
            "Expected import/render block not found in "
            "src/components/review/ResultsView.tsx — aborting. Paste me the "
            "current file and I'll fix it by hand."
        )
    content = content.replace(old_import, new_import).replace(old_render, new_render)
    with open(path, "w") as f:
        f.write(content)
    print("ResultsView.tsx: added the grade banner above the severity summary.")
PYEOF

# ── 4. src/lib/report/generateReport.ts — retheme + score + collapsible detail ──
cat > "src/lib/report/generateReport.ts" << 'VS_APPLY_EOF_htmlreport'
import { STANDING_CONCERNS, CONCERN_SHORT_LABELS } from '@/lib/types';
import type { ContractDoc, Finding } from '@/lib/types';
import { computeReviewScore } from './scoring';

const SEV_COLOR: Record<string, string> = { high: '#C0392B', medium: '#C97A22', low: '#3F7D4A' };
const SEV_BG: Record<string, string> = { high: '#F7E1DF', medium: '#F6E9D5', low: '#E3EFE2' };
const GRADE_COLOR: Record<string, string> = { A: '#3F7D4A', B: '#3F7D4A', C: '#C97A22', D: '#C0392B', F: '#C0392B' };

/**
 * Builds a self-contained, downloadable HTML report — brief §4.1 "Share
 * Report": document metadata, severity summary, all issues with quotes and
 * recommendations, and redline language if drafted. Analysis/recommendation
 * per issue sit behind a native <details> toggle (collapsed by default) so
 * the report reads as a quick scan first, full detail one click away —
 * quote and severity/concern stay visible either way.
 */
export function generateReportHtml(params: {
  contract: Pick<ContractDoc, 'clientName' | 'projectName' | 'projectNumber' | 'docType' | 'counterparty'>;
  findings: Finding[];
  redlines: Record<string, string>; // uid -> redlineText
  generatedAt?: Date;
  fileName?: string | null;
}): string {
  const { contract, findings, redlines, fileName } = params;
  const generatedAt = params.generatedAt ?? new Date();

  const counts = {
    total: findings.length,
    high: findings.filter((f) => f.severity === 'high').length,
    medium: findings.filter((f) => f.severity === 'medium').length,
    low: findings.filter((f) => f.severity === 'low').length,
  };

  const { grade, summary } = computeReviewScore(findings);

  const concernIndexHtml = STANDING_CONCERNS.map(
    (c, i) =>
      `<span style="white-space:nowrap;">${
        i > 0 ? '<span style="color:#DEDDD6;margin:0 10px;">|</span>' : ''
      }<span style="font-weight:600;color:#141414;">${c.id}.</span> ${escapeHtml(CONCERN_SHORT_LABELS[c.id] ?? c.label)}</span>`
  ).join('');

  const issuesHtml = findings
    .map(
      (f, i) => `
      <div style="border:1px solid #DEDDD6;border-left:4px solid ${SEV_COLOR[f.severity]};padding:16px;margin-bottom:16px;background:#FAFAF8;">
        <span style="display:inline-block;font-family:monospace;font-size:11px;color:#8C8A82;margin-right:10px;">${String(i + 1).padStart(2, '0')}</span>
        <span style="display:inline-block;border:1px solid ${SEV_COLOR[f.severity]};background:${SEV_BG[f.severity]};color:${SEV_COLOR[f.severity]};font-family:monospace;font-size:11px;text-transform:uppercase;padding:2px 8px;border-radius:999px;">${f.severity}</span>
        <span style="font-family:monospace;font-size:11px;color:#8C8A82;text-transform:uppercase;margin-left:8px;">Concern ${f.concernId} &middot; ${escapeHtml(f.concernLabel)}</span>
        <h3 style="font-family:'Oswald',Arial,sans-serif;font-weight:600;margin:8px 0 4px;">${escapeHtml(f.issueTitle)}</h3>
        <p style="font-family:monospace;font-size:12px;color:#8C8A82;margin:0 0 12px;">${escapeHtml(f.location || '')}</p>
        <p style="font-family:monospace;font-size:10px;text-transform:uppercase;letter-spacing:0.05em;color:#8C8A82;margin:0 0 2px;">Contract language</p>
        <p style="font-style:italic;color:#52514D;border-left:2px solid #DEDDD6;padding-left:12px;">"${escapeHtml(f.quote)}"</p>
        <details style="margin-top:12px;">
          <summary style="cursor:pointer;font-family:monospace;font-size:10px;text-transform:uppercase;letter-spacing:0.05em;color:#A5730E;">Why it matters + negotiation direction</summary>
          <p style="font-family:monospace;font-size:10px;text-transform:uppercase;letter-spacing:0.05em;color:#8C8A82;margin:10px 0 2px;">Why it matters</p>
          <p style="margin:0 0 12px;">${escapeHtml(f.analysis)}</p>
          <p style="font-family:monospace;font-size:10px;text-transform:uppercase;letter-spacing:0.05em;color:#8C8A82;margin:0 0 2px;">Suggested negotiation direction</p>
          <p style="margin:0;">${escapeHtml(f.recommendation)}</p>
        </details>
        ${
          redlines[f.uid]
            ? `<p style="font-family:monospace;font-size:10px;text-transform:uppercase;letter-spacing:0.05em;color:#8C8A82;margin:12px 0 2px;">Drafted redline</p><pre style="white-space:pre-wrap;background:#E8D9B0;padding:12px;font-family:monospace;font-size:12px;margin:0;">${escapeHtml(redlines[f.uid])}</pre>`
            : ''
        }
      </div>`
    )
    .join('\n');

  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8" />
<title>Contract Review — ${escapeHtml(contract.clientName)} — ${escapeHtml(contract.projectName)}</title>
<link href="https://fonts.googleapis.com/css2?family=Oswald:wght@500;600;700&display=swap" rel="stylesheet">
<style>
  body { font-family: Inter, system-ui, sans-serif; background:#FAFAF8; color:#141414; max-width: 820px; margin: 0 auto; padding: 40px 24px; }
  h1 { font-family: 'Oswald', Arial, sans-serif; font-weight: 700; text-transform: uppercase; letter-spacing: 0.01em; }
  .meta { font-family: monospace; font-size: 12px; color:#52514D; margin-bottom: 24px; }
  .score { display:flex; align-items:center; gap:16px; border:1px solid #DEDDD6; padding:16px 20px; margin-bottom:24px; background:#FAFAF8; }
  .score .grade { font-family:'Oswald',Arial,sans-serif; font-weight:700; font-size:40px; color:${GRADE_COLOR[grade]}; }
  .score .txt { font-size:14px; color:#52514D; }
  .summary { display:flex; gap:12px; margin-bottom: 32px; }
  .summary div { border:1px solid #DEDDD6; padding:12px 16px; flex:1; text-align:center; }
  .summary .n { font-family: 'Oswald', Arial, sans-serif; font-weight:600; font-size: 24px; }
  .summary .l { font-family: monospace; font-size: 10px; text-transform: uppercase; color:#8C8A82; }
  .concern-index { font-family: monospace; font-size: 11px; color: #52514D; border-bottom: 2px solid #141414; padding-bottom: 14px; margin-bottom: 20px; line-height: 1.8; }
</style>
</head>
<body>
  <p style="font-family:monospace;font-size:11px;text-transform:uppercase;letter-spacing:0.1em;color:#8C8A82;">Versus Studio · Contract Review Report</p>
  <h1 style="margin-bottom:2px;font-size:26px;">Contract Review <span style="color:#A5730E;">VS</span></h1>
  <div class="concern-index">${concernIndexHtml}</div>
  <h2 style="font-family:'Oswald',Arial,sans-serif;font-weight:600;font-size:18px;margin:0 0 4px;">${escapeHtml(contract.clientName)} — ${escapeHtml(contract.projectNumber)} — ${escapeHtml(contract.projectName)}</h2>
  <div class="meta">
    ${escapeHtml(contract.docType)} · Counterparty: ${escapeHtml(contract.counterparty)} · Reviewed against ${STANDING_CONCERNS.length} standing concerns · Generated ${generatedAt.toLocaleString()}
    ${fileName ? `<br />Source file: ${escapeHtml(fileName)}` : ''}
  </div>
  <div class="score">
    <span class="grade">${grade}</span>
    <span class="txt">${escapeHtml(summary)}</span>
  </div>
  <div class="summary">
    <div><div class="n">${counts.total}</div><div class="l">Total flagged</div></div>
    <div><div class="n">${counts.high}</div><div class="l">High</div></div>
    <div><div class="n">${counts.medium}</div><div class="l">Medium</div></div>
    <div><div class="n">${counts.low}</div><div class="l">Low</div></div>
  </div>
  ${issuesHtml || `<p>No issues flagged against the ${STANDING_CONCERNS.length} standing concerns.</p>`}
</body>
</html>`;
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

export function downloadReport(html: string, filename: string) {
  const blob = new Blob([html], { type: 'text/html' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}
VS_APPLY_EOF_htmlreport
echo "Wrote src/lib/report/generateReport.ts"

# ── 5. src/lib/report/ContractReportPdf.tsx — retheme + score row ──────────
cat > "src/lib/report/ContractReportPdf.tsx" << 'VS_APPLY_EOF_pdfreport'
import { Document, Page, View, Text, StyleSheet } from '@react-pdf/renderer';
import { STANDING_CONCERNS, CONCERN_SHORT_LABELS } from '@/lib/types';
import type { ContractDoc, Finding } from '@/lib/types';
import { computeReviewScore } from './scoring';

const SEVERITY_COLOR: Record<string, string> = {
  high: '#C0392B',
  medium: '#C97A22',
  low: '#3F7D4A',
};

const SEVERITY_BG: Record<string, string> = {
  high: '#F7E1DF',
  medium: '#F6E9D5',
  low: '#E3EFE2',
};

const GRADE_COLOR: Record<string, string> = {
  A: '#3F7D4A',
  B: '#3F7D4A',
  C: '#C97A22',
  D: '#C0392B',
  F: '#C0392B',
};

// Built-in PDF fonts only (no network font registration, so generation can
// never silently fail on a bad font URL): Helvetica-Bold now stands in for
// the app's bold-condensed (Oswald) headline treatment — closer to that
// bolder feel than the previous Times-Bold serif. Courier still carries
// monospace labels/meta, Helvetica still carries body copy.
const styles = StyleSheet.create({
  page: { padding: 40, paddingBottom: 56, fontSize: 10, fontFamily: 'Helvetica', color: '#141414', backgroundColor: '#FAFAF8' },

  eyebrow: { fontSize: 8, letterSpacing: 1.5, textTransform: 'uppercase', color: '#8C8A82', marginBottom: 8, fontFamily: 'Courier' },
  masthead: { fontSize: 22, fontFamily: 'Helvetica-Bold', marginBottom: 10 },
  mastheadAccent: { color: '#A5730E' },

  concernIndex: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    borderBottomWidth: 2,
    borderBottomColor: '#141414',
    paddingBottom: 10,
    marginBottom: 16,
  },
  concernItem: { fontSize: 8, fontFamily: 'Courier', color: '#52514D', marginRight: 12, marginBottom: 3 },
  concernNum: { fontFamily: 'Courier-Bold', color: '#141414' },

  title: { fontSize: 16, fontFamily: 'Helvetica-Bold', marginBottom: 4 },
  meta: { fontSize: 9, fontFamily: 'Courier', color: '#52514D', marginBottom: 14 },

  scoreRow: { flexDirection: 'row', alignItems: 'center', borderWidth: 1, borderColor: '#DEDDD6', padding: 12, marginBottom: 18, backgroundColor: '#FFFFFF' },
  scoreGrade: { fontSize: 32, fontFamily: 'Helvetica-Bold', marginRight: 14 },
  scoreText: { fontSize: 10, color: '#52514D', flex: 1, lineHeight: 1.4 },

  summaryRow: { flexDirection: 'row', marginBottom: 22 },
  summaryBox: { flex: 1, borderWidth: 1, borderColor: '#DEDDD6', paddingVertical: 10, paddingHorizontal: 8, marginRight: 8, textAlign: 'center', backgroundColor: '#FFFFFF' },
  summaryNum: { fontSize: 20, fontFamily: 'Helvetica-Bold', marginBottom: 3 },
  summaryLabel: { fontSize: 7, fontFamily: 'Courier', textTransform: 'uppercase', color: '#8C8A82' },

  issue: { borderWidth: 1, borderColor: '#DEDDD6', borderLeftWidth: 4, padding: 14, marginBottom: 12, backgroundColor: '#FFFFFF' },
  issueHeaderRow: { flexDirection: 'row', alignItems: 'center', marginBottom: 8 },
  issueIndex: { fontSize: 9, fontFamily: 'Courier', color: '#8C8A82', marginRight: 8 },
  severityPill: { borderWidth: 1, borderRadius: 8, paddingVertical: 2, paddingHorizontal: 7, marginRight: 8 },
  severityPillText: { fontSize: 8, fontFamily: 'Courier-Bold', textTransform: 'uppercase' },
  issueConcern: { fontSize: 8, fontFamily: 'Courier', textTransform: 'uppercase', color: '#8C8A82' },

  issueTitle: { fontSize: 12.5, fontFamily: 'Helvetica-Bold', marginBottom: 4 },
  issueLocation: { fontSize: 8, fontFamily: 'Courier', color: '#8C8A82', marginBottom: 8 },

  sectionLabel: { fontSize: 7.5, fontFamily: 'Courier-Bold', textTransform: 'uppercase', letterSpacing: 0.5, color: '#8C8A82', marginTop: 8, marginBottom: 3 },
  quote: { fontSize: 9.5, fontFamily: 'Times-Italic', color: '#52514D', borderLeftWidth: 2, borderLeftColor: '#DEDDD6', paddingLeft: 10, lineHeight: 1.4 },
  body: { fontSize: 9.5, lineHeight: 1.45, fontFamily: 'Helvetica' },
  redline: { fontSize: 8.5, fontFamily: 'Courier', backgroundColor: '#E8D9B0', padding: 8, marginTop: 2, lineHeight: 1.4 },

  footer: { position: 'absolute', bottom: 20, left: 40, right: 40, flexDirection: 'row', justifyContent: 'space-between', fontSize: 7, fontFamily: 'Courier', color: '#8C8A82', borderTopWidth: 1, borderTopColor: '#DEDDD6', paddingTop: 6 },
});

export function ContractReportPdf({
  contract,
  findings,
  redlines,
  generatedAt,
  fileName,
}: {
  contract: Pick<ContractDoc, 'clientName' | 'projectName' | 'projectNumber' | 'docType' | 'counterparty'>;
  findings: Finding[];
  redlines: Record<string, string>;
  generatedAt?: Date;
  fileName?: string | null;
}) {
  const when = generatedAt ?? new Date();
  const counts = {
    total: findings.length,
    high: findings.filter((f) => f.severity === 'high').length,
    medium: findings.filter((f) => f.severity === 'medium').length,
    low: findings.filter((f) => f.severity === 'low').length,
  };
  const { grade, summary } = computeReviewScore(findings);

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
          {contract.clientName} — {contract.projectNumber} — {contract.projectName}
        </Text>
        <Text style={styles.meta}>
          {contract.docType} · Counterparty: {contract.counterparty} · Reviewed against {STANDING_CONCERNS.length} standing concerns{'\n'}
          Generated {when.toLocaleString()}
          {fileName ? `\nSource file: ${fileName}` : ''}
        </Text>

        <View style={styles.scoreRow}>
          <Text style={[styles.scoreGrade, { color: GRADE_COLOR[grade] }]}>{grade}</Text>
          <Text style={styles.scoreText}>{summary}</Text>
        </View>

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
VS_APPLY_EOF_pdfreport
echo "Wrote src/lib/report/ContractReportPdf.tsx"

echo ""
echo "Done. Restart your dev server and test on any reviewed matter:"
echo "  1. Results screen should show a letter grade + one-line summary"
echo "     banner above the High/Medium/Low counts."
echo "  2. Download HTML — issues should show quote + severity always"
echo "     visible, with 'Why it matters + negotiation direction' collapsed"
echo "     behind a click, and colors/fonts matching the new theme (not the"
echo "     old rust/amber/olive)."
echo "  3. Download PDF — same grade banner + retheme, all detail visible"
echo "     (PDF can't collapse sections, so it stays fully expanded there)."
echo ""
echo "Then commit and push (via GitHub Desktop) to deploy."
