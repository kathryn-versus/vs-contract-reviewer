#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_payment_terms.sh
set -e

mkdir -p "$(dirname "src/lib/types.ts")"
cat > "src/lib/types.ts" << 'VS_APPLY_EOF_pay1'
// Core data model — mirrors the Firestore schema in the project brief §6.

export type Role = 'admin' | 'reviewer';

export interface UserDoc {
  uid: string;
  email: string;
  name: string;
  role: Role;
  createdAt: number; // ms epoch
  lastLoginAt: number;
}

export interface ClientDoc {
  id: string;
  name: string;
  slug: string;
  notes: string;
  msaContractId: string | null;
  createdAt: number;
  createdBy: string;
}

export type DocType = 'MSA' | 'SOW' | 'MSA+SOW' | 'Other';

export interface SubmittedBy {
  uid: string;
  name: string;
  email: string;
}

export interface ContractDoc {
  id: string;
  clientId: string;
  clientName: string;
  projectName: string;
  projectNumber: string;
  docType: DocType;
  counterparty: string;
  submittedBy: SubmittedBy;
  driveFileId: string | null;
  driveUrl: string | null;
  driveFolderUrl: string | null;
  driveFolderId: string | null;
  createdAt: number;
  latestVersionId: string | null;
}

export type Severity = 'high' | 'medium' | 'low';

export interface Finding {
  uid: string;
  concernId: number;
  concernLabel: string;
  severity: Severity;
  issueTitle: string;
  quote: string;
  location: string;
  analysis: string;
  recommendation: string;
}

export interface VersionDoc {
  id: string;
  versionNumber: number;
  uploadedAt: number;
  uploadedBy: { name: string; email: string };
  fileName: string;
  characterCount: number;
  findings: Finding[];
  deltaFromPrevious: string | null;
  reportUrl: string | null;
}

export interface ThreadMessage {
  role: 'user' | 'assistant';
  content: string;
  timestamp: number;
}

export interface IssueThreadDoc {
  id: string;
  messages: ThreadMessage[];
}

// The standing concerns — brief §5, plus additions since. Count is not fixed
// at eight anymore, so nothing downstream should hardcode a number; use
// STANDING_CONCERNS.length wherever a count needs to be displayed.
export interface Concern {
  id: number;
  label: string;
  description: string;
}

export const STANDING_CONCERNS: Concern[] = [
  {
    id: 1,
    label: 'Mutual termination for convenience',
    description:
      'Both parties should be able to terminate for convenience, not just the client.',
  },
  {
    id: 2,
    label: 'Cure period before termination for cause',
    description:
      'Termination for cause should require notice and opportunity to cure. Watch for overly broad "cause" definitions.',
  },
  {
    id: 3,
    label: 'Narrow indemnification obligations',
    description:
      "Indemnity should be tied to actual fault — not cover the client's own acts or ordinary business risk.",
  },
  {
    id: 4,
    label: 'Liability cap applies to indemnification',
    description:
      "If there's a liability cap, indemnification shouldn't be carved out (or only narrow carve-outs like IP/confidentiality should survive).",
  },
  {
    id: 5,
    label: 'Permit normal use of freelancers/subcontractors',
    description:
      'Standard production use of freelancers shouldn\'t require case-by-case prior written approval.',
  },
  {
    id: 6,
    label: 'Relax AI restrictions',
    description:
      'Restrictions should target real risk (training on client IP, undisclosed AI deliverables) — not block ordinary AI tool use in the production workflow.',
  },
  {
    id: 7,
    label: 'Portfolio use and awards submissions',
    description:
      "After public release, portfolio use and awards submissions shouldn't require separate approval each time.",
  },
  {
    id: 8,
    label: 'Standard kill fee / cancellation fee',
    description:
      'SOWs should include a defined cancellation fee structure tied to notice period or production stage.',
  },
  {
    id: 9,
    label: 'Standard payment terms',
    description:
      "Versus's standard payment terms depend on production type. Post-production/post work: 1st payment 50% NET 5 upon award of the SOW; 2nd payment 50% NET 30 following receipt of deliverables. Live-action production (per standard AICP Payment Guidelines): first payment of 75% of the contract price, due upon signing of the contract but not later than 5 business days prior to the first shoot day — due whether or not a written contract/PO/letter of agreement is in hand, since a verbal order to commence production is enough to trigger it; second payment of 25% of the contract price (plus all additional approved and invoiced overages) due upon approval of dailies but not later than airing of the commercial or 30 days from the date of the final invoice, whichever is sooner — the firm-bid portion of a cost-plus job is paid on this schedule regardless of whether the cost-plus items have been actualized yet, and cost-plus invoices are separately due within 30 days of invoice. Determine which structure applies from the nature of the deliverables/scope described in the document (post/edit/sound/animation work vs. a live-action shoot), then flag any payment schedule that requires more up-front risk from Versus than these terms, defers payment materially longer, ties payment to a condition Versus doesn't control without a fallback deadline (e.g., an undefined 'client approval' with no outside date), or omits a clear payment schedule entirely.",
  },
];

// Condensed labels for the always-visible concern index strip (on-screen and
// in exported reports) — short enough to fit all of them on one line, unlike
// the full concern descriptions above.
export const CONCERN_SHORT_LABELS: Record<number, string> = {
  1: 'Mutual termination',
  2: 'Cure period',
  3: 'Indemnification scope',
  4: 'Cap applies to indemnity',
  5: 'Freelancers/subs',
  6: 'AI tool use',
  7: 'Portfolio/awards',
  8: 'Kill fee structure',
  9: 'Payment terms',
};

export const SEVERITY_LABELS: Record<Severity, string> = {
  high: 'Significantly one-sided or high financial/legal exposure — must negotiate',
  medium: 'Notable but not severe, or partially addressed — should negotiate',
  low: 'Minor wording issue or low practical risk — nice to have',
};
VS_APPLY_EOF_pay1

mkdir -p "$(dirname "src/lib/claude/prompts.ts")"
cat > "src/lib/claude/prompts.ts" << 'VS_APPLY_EOF_pay2'
import { STANDING_CONCERNS, type DocType } from '@/lib/types';

export interface AnalysisPromptInput {
  docType: DocType;
  counterparty: string;
  clientName: string;
  clientNotes?: string | null;
  msaContext?: string | null;
  documentText: string; // truncated to 100,000 chars by the caller
}

const STUDIO_IDENTITY =
  'You are a contracts reviewer for Versus Studio, a creative production company ' +
  'based in Brooklyn, NY. You review MSAs, SOWs, and related agreements on behalf ' +
  'of the studio, flagging terms that create outsized risk or diverge from the ' +
  "studio's standing negotiation positions.";

const CONCERNS_BLOCK = STANDING_CONCERNS.map(
  (c) => `${c.id}. ${c.label} — ${c.description}`
).join('\n');

export function buildAnalysisPrompt(input: AnalysisPromptInput): string {
  const { docType, counterparty, clientName, clientNotes, msaContext, documentText } = input;

  return `${STUDIO_IDENTITY}

DOCUMENT CONTEXT
Type: ${docType}
Client: ${clientName}
Counterparty: ${counterparty}

${
  clientNotes
    ? `CLIENT-SPECIFIC STANDING NOTES (treat as authoritative context for this client — e.g. a note that a clause is non-negotiable means do not flag it as an issue even if it would normally concern you):\n${clientNotes}\n`
    : ''
}${
  msaContext
    ? `GOVERNING MSA (excerpt, pulled automatically from this client's Drive folder — use it to understand what's already been negotiated at the master-agreement level; a SOW that simply incorporates MSA terms is not itself an issue):\n"""\n${msaContext}\n"""\n`
    : ''
}
THE STANDING CONCERNS
Assess the document against exactly these ${STANDING_CONCERNS.length} concerns. Only return
concerns where you find an actual issue in the text — omit any concern the
document already handles acceptably.

${CONCERNS_BLOCK}

INSTRUCTIONS
- For each issue found, quote the exact verbatim clause from the document.
- Assign a severity: "high", "medium", or "low".
  - high: significantly one-sided or high financial/legal exposure — must negotiate
  - medium: notable but not severe, or partially addressed — should negotiate
  - low: minor wording issue or low practical risk — nice to have
- Write a concise "why it matters" analysis and a concrete negotiation
  recommendation for each issue.
- Note the section/location of the clause if identifiable (e.g. "Section 8.2").
- Do not invent issues that aren't supported by the text.

RESPONSE FORMAT
Return a JSON array only — no markdown code fences, no commentary before or
after. Each element:
{
  "concernId": number (1-${STANDING_CONCERNS.length}),
  "concernLabel": string,
  "severity": "high" | "medium" | "low",
  "issueTitle": string,
  "quote": string,
  "location": string,
  "analysis": string,
  "recommendation": string
}
If there are no issues at all, return [].

DOCUMENT TEXT
"""
${documentText.slice(0, 100_000)}
"""`;
}

export function buildPrioritizationPrompt(findings: unknown[]): string {
  return `${STUDIO_IDENTITY}

You are given a JSON array of flagged issues from a contract review. Group and
order them into a negotiation strategy: what to raise first, what can be
bundled together, and what to concede if needed to protect the higher-priority
items. Be concise and practical — this is read by a producer prepping for a
negotiation call, not a lawyer.

Return JSON only, no markdown fences, shape:
{
  "priorityOrder": [{ "uid": string, "rank": number, "rationale": string }],
  "strategyNotes": string
}

ISSUES
${JSON.stringify(findings, null, 2)}`;
}

export function buildRedlinePrompt(params: {
  clause: string;
  concernLabel: string;
  recommendation: string;
}): string {
  return `${STUDIO_IDENTITY}

Draft redline language for the following contract clause. Provide a strike/
replace edit: what to remove and what to insert, in standard redline
convention (strikethrough for removed text represented as [STRIKE: ...],
underline for inserted text represented as [INSERT: ...]).

CONCERN: ${params.concernLabel}
RECOMMENDATION: ${params.recommendation}

ORIGINAL CLAUSE
"""
${params.clause}
"""

Return JSON only, no markdown fences, shape:
{ "redlineText": string, "explanation": string }`;
}

export function buildIssueChatSystemPrompt(params: {
  clause: string;
  concernLabel: string;
  analysis: string;
  recommendation: string;
  clientNotes?: string | null;
}): string {
  return `${STUDIO_IDENTITY}

You are helping refine a redline for one specific issue in a contract under
review. Stay scoped to this clause and concern only.

CONCERN: ${params.concernLabel}
ORIGINAL CLAUSE: """${params.clause}"""
INITIAL ANALYSIS: ${params.analysis}
INITIAL RECOMMENDATION: ${params.recommendation}
${params.clientNotes ? `CLIENT STANDING NOTES: ${params.clientNotes}` : ''}

Respond conversationally but concretely — when asked for revised language,
give exact clause text the user can paste into a redline.`;
}
VS_APPLY_EOF_pay2

mkdir -p "$(dirname "src/lib/report/generateReport.ts")"
cat > "src/lib/report/generateReport.ts" << 'VS_APPLY_EOF_pay3'
import { STANDING_CONCERNS, CONCERN_SHORT_LABELS } from '@/lib/types';
import type { ContractDoc, Finding } from '@/lib/types';

/**
 * Builds a self-contained, downloadable HTML report — brief §4.1 "Share
 * Report": document metadata, severity summary, all issues with quotes and
 * recommendations, and redline language if drafted.
 */
export function generateReportHtml(params: {
  contract: Pick<ContractDoc, 'clientName' | 'projectName' | 'projectNumber' | 'docType' | 'counterparty'>;
  findings: Finding[];
  redlines: Record<string, string>; // uid -> redlineText
  generatedAt?: Date;
}): string {
  const { contract, findings, redlines } = params;
  const generatedAt = params.generatedAt ?? new Date();

  const counts = {
    total: findings.length,
    high: findings.filter((f) => f.severity === 'high').length,
    medium: findings.filter((f) => f.severity === 'medium').length,
    low: findings.filter((f) => f.severity === 'low').length,
  };

  const sevColor: Record<string, string> = { high: '#8A3324', medium: '#A8761E', low: '#5A6B4F' };
  const sevBg: Record<string, string> = { high: '#F3E4DF', medium: '#F4ECDA', low: '#E7ECE1' };

  const concernIndexHtml = STANDING_CONCERNS.map(
    (c, i) =>
      `<span style="white-space:nowrap;">${
        i > 0 ? '<span style="color:#D8D3C7;margin:0 10px;">|</span>' : ''
      }<span style="font-weight:600;color:#1C1B19;">${c.id}.</span> ${escapeHtml(CONCERN_SHORT_LABELS[c.id] ?? c.label)}</span>`
  ).join('');

  const issuesHtml = findings
    .map(
      (f, i) => `
      <div style="border-left:4px solid ${sevColor[f.severity]};border:1px solid #D8D3C7;border-left-width:4px;padding:16px;margin-bottom:16px;background:#F7F5F1;">
        <span style="display:inline-block;font-family:monospace;font-size:11px;color:#8C8777;margin-right:10px;">${String(i + 1).padStart(2, '0')}</span>
        <span style="display:inline-block;border:1px solid ${sevColor[f.severity]};background:${sevBg[f.severity]};color:${sevColor[f.severity]};font-family:monospace;font-size:11px;text-transform:uppercase;padding:2px 8px;border-radius:999px;">${f.severity}</span>
        <span style="font-family:monospace;font-size:11px;color:#8C8777;text-transform:uppercase;margin-left:8px;">Concern ${f.concernId} &middot; ${escapeHtml(f.concernLabel)}</span>
        <h3 style="font-family:Georgia,serif;margin:8px 0 4px;">${escapeHtml(f.issueTitle)}</h3>
        <p style="font-family:monospace;font-size:12px;color:#8C8777;margin:0 0 12px;">${escapeHtml(f.location || '')}</p>
        <p style="font-family:monospace;font-size:10px;text-transform:uppercase;letter-spacing:0.05em;color:#8C8777;margin:0 0 2px;">Contract language</p>
        <p style="font-style:italic;color:#5B574D;border-left:2px solid #D8D3C7;padding-left:12px;">"${escapeHtml(f.quote)}"</p>
        <p style="font-family:monospace;font-size:10px;text-transform:uppercase;letter-spacing:0.05em;color:#8C8777;margin:12px 0 2px;">Why it matters</p>
        <p style="margin:0 0 12px;">${escapeHtml(f.analysis)}</p>
        <p style="font-family:monospace;font-size:10px;text-transform:uppercase;letter-spacing:0.05em;color:#8C8777;margin:0 0 2px;">Suggested negotiation direction</p>
        <p style="margin:0;">${escapeHtml(f.recommendation)}</p>
        ${
          redlines[f.uid]
            ? `<p style="font-family:monospace;font-size:10px;text-transform:uppercase;letter-spacing:0.05em;color:#8C8777;margin:12px 0 2px;">Drafted redline</p><pre style="white-space:pre-wrap;background:#EFE9DC;padding:12px;font-family:monospace;font-size:12px;margin:0;">${escapeHtml(redlines[f.uid])}</pre>`
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
<style>
  body { font-family: Inter, system-ui, sans-serif; background:#F7F5F1; color:#1C1B19; max-width: 820px; margin: 0 auto; padding: 40px 24px; }
  h1 { font-family: Georgia, serif; }
  .meta { font-family: monospace; font-size: 12px; color:#5B574D; margin-bottom: 24px; }
  .summary { display:flex; gap:12px; margin-bottom: 32px; }
  .summary div { border:1px solid #D8D3C7; padding:12px 16px; flex:1; text-align:center; }
  .summary .n { font-family: Georgia, serif; font-size: 24px; }
  .summary .l { font-family: monospace; font-size: 10px; text-transform: uppercase; color:#8C8777; }
  .concern-index { font-family: monospace; font-size: 11px; color: #5B574D; border-bottom: 2px solid #1C1B19; padding-bottom: 14px; margin-bottom: 20px; line-height: 1.8; }
</style>
</head>
<body>
  <p style="font-family:monospace;font-size:11px;text-transform:uppercase;letter-spacing:0.1em;color:#8C8777;">Versus Studio · Contract Review Report</p>
  <h1 style="margin-bottom:2px;">Contract Review <span style="color:#8A3324;">VS</span></h1>
  <div class="concern-index">${concernIndexHtml}</div>
  <h2 style="font-family:Georgia,serif;font-size:18px;margin:0 0 4px;">${escapeHtml(contract.clientName)} — ${escapeHtml(contract.projectName)} (${escapeHtml(contract.projectNumber)})</h2>
  <div class="meta">
    ${escapeHtml(contract.docType)} · Counterparty: ${escapeHtml(contract.counterparty)} · Reviewed against ${STANDING_CONCERNS.length} standing concerns · Generated ${generatedAt.toLocaleString()}
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
VS_APPLY_EOF_pay3

mkdir -p "$(dirname "src/lib/report/ContractReportPdf.tsx")"
cat > "src/lib/report/ContractReportPdf.tsx" << 'VS_APPLY_EOF_pay4'
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
          <View key={f.uid} style={[styles.issue, { borderLeftColor: SEVERITY_COLOR[f.severity] }]} wrap={false}>
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
VS_APPLY_EOF_pay4

mkdir -p "$(dirname "src/components/review/ConcernIndex.tsx")"
cat > "src/components/review/ConcernIndex.tsx" << 'VS_APPLY_EOF_pay5'
import { STANDING_CONCERNS, CONCERN_SHORT_LABELS as SHORT_LABELS } from '@/lib/types';

/**
 * The standing concerns shown as a persistent reference strip, so it's
 * clear what was checked regardless of how many issues were actually flagged.
 */
export function ConcernIndex() {
  return (
    <div className="flex flex-wrap gap-x-4 gap-y-1.5 border-b-2 border-ink pb-4 font-mono text-xs text-ink-soft">
      {STANDING_CONCERNS.map((c, i) => (
        <span key={c.id} className="whitespace-nowrap">
          <span className="font-medium text-ink">{c.id}.</span> {SHORT_LABELS[c.id] ?? c.label}
          {i < STANDING_CONCERNS.length - 1 && <span className="ml-4 text-rule">|</span>}
        </span>
      ))}
    </div>
  );
}
VS_APPLY_EOF_pay5

mkdir -p "$(dirname "src/components/ui/LoadingScan.tsx")"
cat > "src/components/ui/LoadingScan.tsx" << 'VS_APPLY_EOF_pay6'
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

export function LoadingScan() {
  const [i, setI] = useState(0);
  useEffect(() => {
    const id = setInterval(() => setI((v) => (v + 1) % MESSAGES.length), 1800);
    return () => clearInterval(id);
  }, []);

  return (
    <div className="flex flex-col items-center justify-center gap-4 py-20 text-center">
      <div className="relative h-14 w-11 border-2 border-ink">
        <div className="absolute left-0 top-0 h-0.5 w-full animate-pulse bg-accent" />
        <div className="absolute inset-x-1.5 top-3 h-0.5 bg-rule" />
        <div className="absolute inset-x-1.5 top-6 h-0.5 bg-rule" />
        <div className="absolute inset-x-1.5 top-9 h-0.5 bg-rule" />
      </div>
      <p className="font-mono text-xs uppercase tracking-wide text-ink-faint transition-opacity">
        {MESSAGES[i]}
      </p>
    </div>
  );
}
VS_APPLY_EOF_pay6

mkdir -p "$(dirname "src/components/intake/IntakeForm.tsx")"
cat > "src/components/intake/IntakeForm.tsx" << 'VS_APPLY_EOF_pay7'
'use client';

import { useEffect, useMemo, useState } from 'react';
import { Chip } from '@/components/ui/Chip';
import { Button } from '@/components/ui/Button';
import { Combobox } from '@/components/ui/Combobox';
import { FileDropzone } from './FileDropzone';
import { listClients, listAllContracts } from '@/lib/firebase/firestore';
import { extractText } from '@/lib/parsing/extractText';
import { STANDING_CONCERNS } from '@/lib/types';
import type { ClientDoc, ContractDoc, DocType } from '@/lib/types';
import type { User } from 'firebase/auth';

export interface IntakeValues {
  clientName: string;
  projectName: string;
  projectNumber: string;
  docType: DocType;
  counterparty: string;
  file: File;
  documentText: string;
  characterCount: number;
  /** Set when the reviewer picked an existing matter instead of creating a
   * new one — the upload should attach as a new version of this contract
   * rather than creating a fresh one. */
  existingContractId?: string;
}

const DOC_TYPES: DocType[] = ['MSA', 'SOW', 'MSA+SOW', 'Other'];

export function IntakeForm({
  user,
  onSubmit,
  submitting,
}: {
  user: User;
  onSubmit: (values: IntakeValues) => void;
  submitting: boolean;
}) {
  const [clients, setClients] = useState<ClientDoc[]>([]);
  const [allContracts, setAllContracts] = useState<ContractDoc[]>([]);

  const [clientName, setClientName] = useState('');
  const [projectName, setProjectName] = useState('');
  const [projectNumber, setProjectNumber] = useState('');
  const [docType, setDocType] = useState<DocType>('SOW');
  const [counterparty, setCounterparty] = useState('');
  const [counterpartyEdited, setCounterpartyEdited] = useState(false);
  const [file, setFile] = useState<File | null>(null);
  const [documentText, setDocumentText] = useState('');
  const [characterCount, setCharacterCount] = useState<number | null>(null);
  const [parseError, setParseError] = useState<string | null>(null);

  // Job picker state: either searching, attached to an existing matter, or
  // filling in the two fields for a brand-new one.
  const [jobQuery, setJobQuery] = useState('');
  const [selectedContractId, setSelectedContractId] = useState<string | null>(null);
  const [creatingNewJob, setCreatingNewJob] = useState(false);

  useEffect(() => {
    listClients().then(setClients).catch(() => {});
    listAllContracts().then(setAllContracts).catch(() => {});
  }, []);

  // For most matters, the counterparty IS the client — so default it to
  // whatever's typed in Client and keep it in sync, unless the user has
  // manually edited Counterparty (e.g. the legal signing entity differs
  // from the client's common name, like a production subsidiary).
  useEffect(() => {
    if (!counterpartyEdited) {
      setCounterparty(clientName);
    }
  }, [clientName, counterpartyEdited]);

  async function handleFile(f: File) {
    setFile(f);
    setCharacterCount(null);
    setParseError(null);
    try {
      const text = await extractText(f);
      setDocumentText(text);
      setCharacterCount(text.length);
    } catch (err) {
      setParseError(err instanceof Error ? err.message : 'Could not parse file.');
    }
  }

  // Jobs matching the currently-typed client (if any); when no client is
  // typed yet, show every matter across all clients so a job can be found
  // and picked first, with the client filled in from it.
  const jobOptions = useMemo(() => {
    const typedClient = clientName.trim().toLowerCase();
    return allContracts
      .filter((c) => !typedClient || c.clientName.toLowerCase() === typedClient)
      .map((c) => ({
        id: c.id,
        label: `${c.projectName} (${c.projectNumber})`,
        sublabel: typedClient ? undefined : c.clientName,
      }));
  }, [allContracts, clientName]);

  function selectJob(contractId: string) {
    const c = allContracts.find((x) => x.id === contractId);
    if (!c) return;
    setSelectedContractId(c.id);
    setProjectName(c.projectName);
    setProjectNumber(c.projectNumber);
    setClientName(c.clientName);
    setCounterparty(c.counterparty);
    setCounterpartyEdited(true);
    setJobQuery('');
  }

  function resetJob() {
    setSelectedContractId(null);
    setCreatingNewJob(false);
    setProjectName('');
    setProjectNumber('');
    setJobQuery('');
  }

  const canSubmit =
    clientName.trim() &&
    projectName.trim() &&
    projectNumber.trim() &&
    counterparty.trim() &&
    file &&
    characterCount &&
    (selectedContractId || creatingNewJob);

  return (
    <div className="mx-auto max-w-2xl">
      <div className="mb-8 text-center">
        <h1 className="font-display text-3xl text-ink">Submit a contract for review</h1>
        <p className="mt-2 font-body text-sm text-ink-soft">
          The {STANDING_CONCERNS.length} standing concerns will be checked automatically.
        </p>
      </div>

      <div className="mb-6 flex justify-center">
        <Chip>
          {user.displayName ?? user.email} · {user.email}
        </Chip>
      </div>

      <div className="space-y-5 rounded-sm border border-rule bg-paper p-6">
        <Field label="Client">
          <Combobox
            value={clientName}
            onChange={setClientName}
            options={clients.map((c) => ({ id: c.id, label: c.name }))}
            onSelect={(o) => setClientName(o.label)}
            placeholder="Choose or type a client…"
          />
        </Field>

        <Field label="Job">
          {selectedContractId ? (
            <div className="flex items-center justify-between rounded-sm border border-rule bg-accent-soft/10 px-3 py-2">
              <span className="font-body text-sm text-ink">
                {projectName} <span className="font-mono text-xs text-ink-faint">({projectNumber})</span>
              </span>
              <button
                type="button"
                onClick={resetJob}
                className="font-mono text-xs uppercase tracking-wide text-ink-faint hover:text-ink"
              >
                Change
              </button>
            </div>
          ) : creatingNewJob ? (
            <div className="space-y-2">
              <div className="grid grid-cols-2 gap-4">
                <input
                  value={projectName}
                  onChange={(e) => setProjectName(e.target.value)}
                  placeholder="Project name — e.g. Moana Ocean Adventure"
                  className="input"
                  autoFocus
                />
                <input
                  value={projectNumber}
                  onChange={(e) => setProjectNumber(e.target.value)}
                  placeholder="Project number — e.g. VS26153"
                  className="input"
                />
              </div>
              <button
                type="button"
                onClick={resetJob}
                className="font-mono text-xs uppercase tracking-wide text-ink-faint hover:text-ink"
              >
                ← Search existing jobs instead
              </button>
            </div>
          ) : (
            <Combobox
              value={jobQuery}
              onChange={setJobQuery}
              options={jobOptions}
              onSelect={(o) => selectJob(o.id)}
              placeholder="Search an existing job, or create a new one…"
              onCreateNew={() => {
                setCreatingNewJob(true);
                setProjectName(jobQuery.trim());
              }}
              createNewLabel="+ Create new job"
            />
          )}
        </Field>

        <div className="grid grid-cols-2 gap-4">
          <Field label="Document type">
            <select value={docType} onChange={(e) => setDocType(e.target.value as DocType)} className="input">
              {DOC_TYPES.map((t) => (
                <option key={t} value={t}>
                  {t === 'MSA+SOW' ? 'MSA + SOW (combined)' : t}
                </option>
              ))}
            </select>
          </Field>
          <Field label="Counterparty">
            <input
              value={counterparty}
              onChange={(e) => {
                setCounterparty(e.target.value);
                setCounterpartyEdited(true);
              }}
              placeholder="Legal entity name"
              className="input"
            />
          </Field>
        </div>

        <Field label="Contract file">
          <FileDropzone
            file={file}
            characterCount={characterCount}
            onFile={handleFile}
            onClear={() => {
              setFile(null);
              setCharacterCount(null);
              setDocumentText('');
            }}
          />
          {parseError && <p className="mt-2 text-sm text-high">{parseError}</p>}
        </Field>

        <Button
          variant="primary"
          className="w-full"
          disabled={!canSubmit || submitting}
          onClick={() =>
            file &&
            onSubmit({
              clientName: clientName.trim(),
              projectName: projectName.trim(),
              projectNumber: projectNumber.trim(),
              docType,
              counterparty: counterparty.trim(),
              file,
              documentText,
              characterCount: characterCount ?? 0,
              existingContractId: selectedContractId ?? undefined,
            })
          }
        >
          {submitting ? 'Running review…' : 'Run Review'}
        </Button>
      </div>

      <style jsx global>{`
        .input {
          width: 100%;
          border: 1px solid var(--rule);
          background: var(--paper);
          padding: 0.5rem 0.75rem;
          font-family: var(--font-inter);
          font-size: 0.875rem;
          color: var(--ink);
          border-radius: 2px;
        }
        .input:focus {
          outline: none;
          border-color: var(--ink);
        }
      `}</style>
    </div>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="block">
      <span className="mb-1.5 block font-mono text-xs uppercase tracking-wide text-ink-faint">{label}</span>
      {children}
    </label>
  );
}
VS_APPLY_EOF_pay7

mkdir -p "$(dirname "src/app/page.tsx")"
cat > "src/app/page.tsx" << 'VS_APPLY_EOF_pay8'
'use client';

import { useState } from 'react';
import { AuthGuard } from '@/components/layout/AuthGuard';
import { AppShell } from '@/components/layout/AppShell';
import { IntakeForm, type IntakeValues } from '@/components/intake/IntakeForm';
import { LoadingScan } from '@/components/ui/LoadingScan';
import { ResultsView } from '@/components/review/ResultsView';
import { ConcernIndex } from '@/components/review/ConcernIndex';
import { Button } from '@/components/ui/Button';
import { useAuth } from '@/hooks/useAuth';
import {
  getOrCreateClient,
  createContract,
  addVersion,
  updateContractDrive,
  getClient,
  getNextVersionNumber,
} from '@/lib/firebase/firestore';
import { STANDING_CONCERNS } from '@/lib/types';
import type { Finding } from '@/lib/types';

type Step = 'intake' | 'loading' | 'results' | 'error';

export default function ReviewerPage() {
  return (
    <AuthGuard>
      <AppShell>
        <ReviewerFlow />
      </AppShell>
    </AuthGuard>
  );
}

function ReviewerFlow() {
  const { user } = useAuth();
  const [step, setStep] = useState<Step>('intake');
  const [error, setError] = useState<string | null>(null);
  const [findings, setFindings] = useState<Finding[]>([]);
  const [contractMeta, setContractMeta] = useState<{
    contractId: string;
    versionId: string;
    clientName: string;
    projectName: string;
    projectNumber: string;
    docType: string;
    counterparty: string;
    clientNotes: string | null;
    fileName: string;
    driveFileId: string | null;
    driveFolderId: string | null;
  } | null>(null);

  if (!user) return null;

  async function handleSubmit(values: IntakeValues) {
    setStep('loading');
    setError(null);
    try {
      // 1. Resolve/create the client record and pull any standing notes.
      const client = await getOrCreateClient(values.clientName, user!.email ?? '');
      const clientDoc = await getClient(client.id);

      // 2. Run the standing-concerns analysis. Passing clientId lets the server
      //    auto-pull the client's governing MSA from Drive as extra context.
      const analyzeRes = await fetch('/api/review/analyze', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          docType: values.docType,
          counterparty: values.counterparty,
          clientName: values.clientName,
          clientId: client.id,
          clientNotes: clientDoc?.notes || null,
          documentText: values.documentText,
        }),
      });
      const analyzeData = await analyzeRes.json();
      if (analyzeData.error) throw new Error(analyzeData.error);
      const newFindings: Finding[] = analyzeData.findings;

      // 3. Attach to the existing matter if one was picked, otherwise create
      //    a new contract + first version record in Firestore.
      const isExistingMatter = Boolean(values.existingContractId);
      const contractId = isExistingMatter
        ? values.existingContractId!
        : await createContract({
            clientId: client.id,
            clientName: client.name,
            projectName: values.projectName,
            projectNumber: values.projectNumber,
            docType: values.docType,
            counterparty: values.counterparty,
            submittedBy: { uid: user!.uid, name: user!.displayName ?? user!.email ?? '', email: user!.email ?? '' },
            driveFileId: null,
            driveUrl: null,
            driveFolderUrl: null,
            driveFolderId: null,
          });

      const versionNumber = isExistingMatter ? await getNextVersionNumber(contractId) : 1;

      const versionId = await addVersion(contractId, {
        versionNumber,
        uploadedBy: { name: user!.displayName ?? user!.email ?? '', email: user!.email ?? '' },
        fileName: values.file.name,
        characterCount: values.characterCount,
        findings: newFindings,
        deltaFromPrevious: null,
        reportUrl: null,
      });

      // 4. Upload the source file to Drive (server-side route). For a second
      //    (or later) version of an existing matter, suffix the filename so
      //    it doesn't collide with the prior version already in that folder.
      let driveFileId: string | null = null;
      let driveFolderId: string | null = null;
      try {
        const form = new FormData();
        form.append('file', values.file);
        form.append('clientName', client.name);
        form.append('projectName', values.projectName);
        form.append('projectNumber', values.projectNumber);
        if (versionNumber > 1) form.append('versionSuffix', `v${versionNumber}`);
        const driveRes = await fetch('/api/drive/upload', { method: 'POST', body: form });
        const driveData = await driveRes.json();
        if (!driveData.error) {
          await updateContractDrive(contractId, driveData);
          driveFileId = driveData.driveFileId ?? null;
          driveFolderId = driveData.driveFolderId ?? null;
        }
      } catch {
        // Drive failures shouldn't block the reviewer from seeing results.
      }

      // 5. Fire the email notification (recipients controlled server-side by env vars).
      const counts = {
        high: newFindings.filter((f) => f.severity === 'high').length,
        medium: newFindings.filter((f) => f.severity === 'medium').length,
        low: newFindings.filter((f) => f.severity === 'low').length,
      };
      fetch('/api/gmail/notify', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          clientName: client.name,
          projectName: values.projectName,
          severityCounts: counts,
          submittedBy: { name: user!.displayName ?? user!.email ?? '', email: user!.email ?? '' },
          docType: values.docType,
          counterparty: values.counterparty,
          topHighIssues: newFindings.filter((f) => f.severity === 'high'),
          reportDriveUrl: '',
          libraryUrl: `https://vs-contracts.web.app/library/${client.id}`,
        }),
      }).catch(() => {});

      setFindings(newFindings);
      setContractMeta({
        contractId,
        versionId,
        clientName: client.name,
        projectName: values.projectName,
        projectNumber: values.projectNumber,
        docType: values.docType,
        counterparty: values.counterparty,
        clientNotes: clientDoc?.notes || null,
        fileName: values.file.name,
        driveFileId,
        driveFolderId,
      });
      setStep('results');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Something went wrong running the review.');
      setStep('error');
    }
  }

  if (step === 'intake') {
    return <IntakeForm user={user} onSubmit={handleSubmit} submitting={false} />;
  }

  if (step === 'loading') {
    return <LoadingScan />;
  }

  if (step === 'error') {
    return (
      <div className="mx-auto max-w-lg py-16 text-center">
        <p className="mb-4 text-sm text-high">{error}</p>
        <Button onClick={() => setStep('intake')}>Try again</Button>
      </div>
    );
  }

  if (step === 'results' && contractMeta) {
    return (
      <div>
        <div className="mb-4 flex items-baseline justify-between">
          <h1 className="font-display text-3xl text-ink">
            Contract Review <span className="text-accent">VS</span>
          </h1>
          <div className="text-right font-mono text-xs uppercase tracking-wide text-ink-faint">
            Versus Studio
          </div>
        </div>

        <ConcernIndex />

        <div className="mb-6 mt-4 flex items-center justify-between">
          <p className="font-mono text-xs uppercase tracking-wide text-ink-faint">
            {contractMeta.fileName} · {contractMeta.docType} · Reviewed against {STANDING_CONCERNS.length} standing concerns
          </p>
          <Button onClick={() => setStep('intake')}>↻ New review</Button>
        </div>

        <p className="-mt-4 mb-6 font-mono text-xs text-ink-faint">
          {contractMeta.clientName} — {contractMeta.projectName} ({contractMeta.projectNumber}) · Counterparty:{' '}
          {contractMeta.counterparty}
        </p>

        <ResultsView
          contract={contractMeta}
          contractId={contractMeta.contractId}
          versionId={contractMeta.versionId}
          findings={findings}
          clientNotes={contractMeta.clientNotes}
          driveFileId={contractMeta.driveFileId}
          driveFolderId={contractMeta.driveFolderId}
          sourceFileName={contractMeta.fileName}
        />
      </div>
    );
  }

  return null;
}
VS_APPLY_EOF_pay8

echo ""
echo "Done. 8 files updated:"
echo "  src/lib/types.ts                       (added Payment Terms as concern #9)"
echo "  src/lib/claude/prompts.ts"
echo "  src/lib/report/generateReport.ts"
echo "  src/lib/report/ContractReportPdf.tsx"
echo "  src/components/review/ConcernIndex.tsx"
echo "  src/components/ui/LoadingScan.tsx"
echo "  src/components/intake/IntakeForm.tsx"
echo "  src/app/page.tsx"
echo ""
echo "No new npm packages needed — restart your dev server (Ctrl+C, then npm run dev)."
