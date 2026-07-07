#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_naming_and_redline_comments.sh
set -e

# ── 1. Job Number first, then Project Name, everywhere the two combine ─────

mkdir -p "$(dirname "src/app/api/drive/upload/route.ts")"
cat > "src/app/api/drive/upload/route.ts" << 'VS_APPLY_EOF_naming1'
import { NextRequest, NextResponse } from 'next/server';
import { ensureMatterFolder, ensureDatedReviewFolder, uploadFileToFolder, getFolderLink } from '@/lib/drive/client';

// Server-side only (brief §7: "All Drive API calls go through Next.js API
// routes — never direct from browser"). Accepts multipart form data with the
// original file plus client/project metadata, and returns Drive links to
// store on the contract/version Firestore docs.
export async function POST(req: NextRequest) {
  try {
    const form = await req.formData();
    const file = form.get('file') as File | null;
    const clientName = form.get('clientName') as string | null;
    const projectName = form.get('projectName') as string | null;
    const projectNumber = form.get('projectNumber') as string | null;
    const versionSuffix = (form.get('versionSuffix') as string | null) ?? '';

    if (!file || !clientName || !projectName || !projectNumber) {
      return NextResponse.json(
        { error: 'file, clientName, projectName, and projectNumber are required.' },
        { status: 400 }
      );
    }

    // Job Number first, then Project Name (e.g. "VS26153 — Eversana DSE
    // Animation") — matches how the studio refers to jobs internally.
    const projectLabel = `${projectNumber} — ${projectName}`;
    const { matterFolderId } = await ensureMatterFolder(clientName, projectLabel);
    // Nest this review's files under a dated subfolder — Contract
    // Reviews/{Client}/{Job Number — Project}/{YYYY-MM-DD}/ — so the source
    // file, its Google Doc duplicate, and the report copy all land together.
    const dateFolderId = await ensureDatedReviewFolder(matterFolderId);

    const buffer = Buffer.from(await file.arrayBuffer());
    const fileName = versionSuffix ? appendSuffix(file.name, versionSuffix) : file.name;

    const { fileId, webViewLink } = await uploadFileToFolder({
      folderId: dateFolderId,
      fileName,
      mimeType: file.type || 'application/octet-stream',
      buffer,
    });

    const driveFolderUrl = await getFolderLink(dateFolderId);

    return NextResponse.json({
      driveFileId: fileId,
      driveUrl: webViewLink,
      driveFolderUrl,
      driveFolderId: dateFolderId,
    });
  } catch (err) {
    console.error('drive/upload failed', err);
    return NextResponse.json(
      { error: err instanceof Error ? err.message : 'Drive upload failed.' },
      { status: 500 }
    );
  }
}

function appendSuffix(fileName: string, suffix: string) {
  const dot = fileName.lastIndexOf('.');
  if (dot === -1) return `${fileName} ${suffix}`;
  return `${fileName.slice(0, dot)} ${suffix}${fileName.slice(dot)}`;
}
VS_APPLY_EOF_naming1

mkdir -p "$(dirname "src/lib/report/generateReport.ts")"
cat > "src/lib/report/generateReport.ts" << 'VS_APPLY_EOF_naming2'
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
  <h2 style="font-family:Georgia,serif;font-size:18px;margin:0 0 4px;">${escapeHtml(contract.clientName)} — ${escapeHtml(contract.projectNumber)} — ${escapeHtml(contract.projectName)}</h2>
  <div class="meta">
    ${escapeHtml(contract.docType)} · Counterparty: ${escapeHtml(contract.counterparty)} · Reviewed against ${STANDING_CONCERNS.length} standing concerns · Generated ${generatedAt.toLocaleString()}
    ${fileName ? `<br />Source file: ${escapeHtml(fileName)}` : ''}
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
VS_APPLY_EOF_naming2

mkdir -p "$(dirname "src/lib/report/ContractReportPdf.tsx")"
cat > "src/lib/report/ContractReportPdf.tsx" << 'VS_APPLY_EOF_naming3'
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
VS_APPLY_EOF_naming3

# ── 2. Redlines → comments on the Google Doc ────────────────────────────────

mkdir -p "$(dirname "src/lib/drive/client.ts")"
cat >> "src/lib/drive/client.ts" << 'VS_APPLY_EOF_comment1'

/**
 * Adds a comment to a Drive file — used to attach drafted redline language to
 * the Google Doc copy of a contract. Not text-anchored: Google's Docs API/UI
 * silently ignores anchor data on Workspace editor files (confirmed platform
 * limitation, not something fixable from our side), so these land as general
 * document-level comments in the comment sidebar rather than highlighting the
 * exact flagged passage. Each comment's content includes the quoted contract
 * language so it's still easy to locate manually.
 */
export async function addComment(fileId: string, content: string): Promise<void> {
  const drive = driveClient();
  await drive.comments.create({
    fileId,
    requestBody: { content },
    fields: 'id',
  });
}
VS_APPLY_EOF_comment1

mkdir -p "$(dirname "src/app/api/drive/add-redline-comments/route.ts")"
cat > "src/app/api/drive/add-redline-comments/route.ts" << 'VS_APPLY_EOF_comment2'
import { NextRequest, NextResponse } from 'next/server';
import { addComment } from '@/lib/drive/client';

// Attaches drafted redlines to a Google Doc as comments. Google's Docs API
// has no way to create a real accept/reject "Suggestion" programmatically —
// confirmed against the current API reference, no request type exists for
// it — so this is the closest practical equivalent: one comment per
// finding, quoting the flagged language plus the suggested redline.
export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const fileId: string | undefined = body.fileId;
    const items: { issueTitle: string; quote: string; redlineText: string }[] | undefined = body.items;

    if (!fileId || !items || items.length === 0) {
      return NextResponse.json({ error: 'fileId and at least one item are required.' }, { status: 400 });
    }

    let added = 0;
    for (const item of items) {
      const content = `${item.issueTitle}\n\nFlagged language: "${item.quote}"\n\nSuggested redline:\n${item.redlineText}`;
      await addComment(fileId, content);
      added++;
    }

    return NextResponse.json({ added });
  } catch (err) {
    console.error('drive/add-redline-comments failed', err);
    return NextResponse.json(
      { error: err instanceof Error ? err.message : 'Could not add comments to the Google Doc.' },
      { status: 500 }
    );
  }
}
VS_APPLY_EOF_comment2

mkdir -p "$(dirname "src/lib/report/addRedlineComments.ts")"
cat > "src/lib/report/addRedlineComments.ts" << 'VS_APPLY_EOF_comment3'
'use client';

/**
 * Sends drafted redlines to the Google Doc copy of a contract as comments —
 * see the note in src/lib/drive/client.ts's addComment for why these aren't
 * text-anchored to the flagged passage.
 */
export async function addRedlineCommentsToDoc(params: {
  fileId: string;
  items: { issueTitle: string; quote: string; redlineText: string }[];
}): Promise<{ added: number }> {
  const res = await fetch('/api/drive/add-redline-comments', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(params),
  });
  const data = await res.json();
  if (data.error) throw new Error(data.error);
  return data;
}
VS_APPLY_EOF_comment3

mkdir -p "$(dirname "src/components/review/ResultsView.tsx")"
cat > "src/components/review/ResultsView.tsx" << 'VS_APPLY_EOF_comment4'
'use client';

import { useMemo, useState } from 'react';
import { Button } from '@/components/ui/Button';
import { SeveritySummary, type FilterValue } from './SeveritySummary';
import { IssueCard } from './IssueCard';
import { PrioritizeDrawer } from './PrioritizeDrawer';
import { RedlineDrawer } from './RedlineDrawer';
import { generateReportHtml, downloadReport } from '@/lib/report/generateReport';
import { downloadReportPdf } from '@/lib/report/generatePdf';
import { duplicateContractToGoogleDocs } from '@/lib/report/googleDocsHandoff';
import { uploadReportToDrive } from '@/lib/report/uploadToDrive';
import { addRedlineCommentsToDoc } from '@/lib/report/addRedlineComments';
import { appendIssueThreadMessages } from '@/lib/firebase/firestore';
import type { ContractDoc, Finding, ThreadMessage } from '@/lib/types';

export function ResultsView({
  contract,
  contractId,
  versionId,
  findings,
  clientNotes,
  driveFileId,
  driveFolderId,
  sourceFileName,
}: {
  contract: Pick<ContractDoc, 'clientName' | 'projectName' | 'projectNumber' | 'docType' | 'counterparty'>;
  contractId: string;
  versionId: string;
  findings: Finding[];
  clientNotes?: string | null;
  driveFileId?: string | null;
  driveFolderId?: string | null;
  sourceFileName?: string | null;
}) {
  const [filter, setFilter] = useState<FilterValue>('all');
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [threads, setThreads] = useState<Record<string, ThreadMessage[]>>({});
  const [redlines, setRedlines] = useState<Record<string, string>>({});
  const [prioritizeOpen, setPrioritizeOpen] = useState(false);
  const [redlineOpen, setRedlineOpen] = useState(false);
  const [docsBusy, setDocsBusy] = useState(false);
  const [docsError, setDocsError] = useState<string | null>(null);
  const [googleDocId, setGoogleDocId] = useState<string | null>(null);
  const [commentsBusy, setCommentsBusy] = useState(false);
  const [commentsError, setCommentsError] = useState<string | null>(null);
  const [commentsAdded, setCommentsAdded] = useState<number | null>(null);

  const visible = useMemo(
    () => (filter === 'all' ? findings : findings.filter((f) => f.severity === filter)),
    [findings, filter]
  );

  const selectedFindings = findings.filter((f) => selected.has(f.uid));
  const redlinedFindings = findings.filter((f) => redlines[f.uid]);

  function toggle(uid: string) {
    setSelected((s) => {
      const next = new Set(s);
      next.has(uid) ? next.delete(uid) : next.add(uid);
      return next;
    });
  }

  function selectAll() {
    setSelected(new Set(findings.map((f) => f.uid)));
  }
  function selectHigh() {
    setSelected(new Set(findings.filter((f) => f.severity === 'high').map((f) => f.uid)));
  }

  async function persistThread(uid: string, messages: ThreadMessage[]) {
    setThreads((t) => ({ ...t, [uid]: messages }));
    await appendIssueThreadMessages(contractId, versionId, uid, messages.slice(threads[uid]?.length ?? 0));
  }

  function handleShareReportHtml() {
    const html = generateReportHtml({ contract, findings, redlines, fileName: sourceFileName });
    const filename = `${contract.clientName} — ${contract.projectName} review.html`;
    downloadReport(html, filename);

    // Also stash a copy in the same dated Drive folder as the source
    // contract, if the Drive upload for this version succeeded. Failures
    // here shouldn't block the local download the reviewer already got.
    if (driveFolderId) {
      uploadReportToDrive({ blob: new Blob([html], { type: 'text/html' }), filename, folderId: driveFolderId }).catch(
        () => {}
      );
    }
  }

  async function handleDownloadPdf() {
    const filename = `${contract.clientName} — ${contract.projectName} review.pdf`;
    const blob = await downloadReportPdf({ contract, findings, redlines, filename, sourceFileName });

    if (driveFolderId) {
      uploadReportToDrive({ blob, filename, folderId: driveFolderId }).catch(() => {});
    }
  }

  async function handleGoogleDocs() {
    if (!driveFileId || !driveFolderId) return;
    setDocsBusy(true);
    setDocsError(null);
    try {
      const { docId } = await duplicateContractToGoogleDocs({
        fileId: driveFileId,
        folderId: driveFolderId,
        name: sourceFileName
          ? `${sourceFileName} (Google Doc copy)`
          : `${contract.projectNumber} — ${contract.projectName} — Google Doc copy`,
      });
      // Needed so "Add redlines as comments" knows which file to comment on —
      // comments go on the editable Google Doc copy, not the original
      // uploaded PDF/DOCX.
      setGoogleDocId(docId);
    } catch (err) {
      setDocsError(err instanceof Error ? err.message : 'Could not open in Google Docs.');
    } finally {
      setDocsBusy(false);
    }
  }

  async function handleAddRedlineComments() {
    if (!googleDocId || redlinedFindings.length === 0) return;
    setCommentsBusy(true);
    setCommentsError(null);
    setCommentsAdded(null);
    try {
      const { added } = await addRedlineCommentsToDoc({
        fileId: googleDocId,
        items: redlinedFindings.map((f) => ({
          issueTitle: f.issueTitle,
          quote: f.quote,
          redlineText: redlines[f.uid],
        })),
      });
      setCommentsAdded(added);
    } catch (err) {
      setCommentsError(err instanceof Error ? err.message : 'Could not add comments to the Google Doc.');
    } finally {
      setCommentsBusy(false);
    }
  }

  const googleDocsDisabled = !driveFileId || !driveFolderId || docsBusy;
  const addCommentsDisabled = !googleDocId || redlinedFindings.length === 0 || commentsBusy;

  return (
    <div className="space-y-6">
      <SeveritySummary findings={findings} active={filter} onChange={setFilter} />

      <div className="flex flex-wrap items-center gap-2 border-y border-rule py-3">
        <Button variant="ghost" onClick={selectAll}>Select All</Button>
        <Button variant="ghost" onClick={selectHigh}>Select High</Button>
        <div className="flex-1" />
        <Button variant="secondary" onClick={() => setPrioritizeOpen(true)} disabled={findings.length === 0}>
          Prioritize for negotiation
        </Button>
        <Button
          variant="secondary"
          onClick={() => setRedlineOpen(true)}
          disabled={selectedFindings.length === 0}
        >
          Draft redlines ({selectedFindings.length})
        </Button>
        <Button
          variant="secondary"
          onClick={handleGoogleDocs}
          disabled={googleDocsDisabled}
          title={
            !driveFileId || !driveFolderId
              ? 'Waiting on the Drive upload to finish for this matter'
              : undefined
          }
        >
          {docsBusy ? 'Opening…' : 'Open in Google Docs'}
        </Button>
        <Button
          variant="secondary"
          onClick={handleAddRedlineComments}
          disabled={addCommentsDisabled}
          title={
            !googleDocId
              ? 'Open in Google Docs first'
              : redlinedFindings.length === 0
                ? 'Draft at least one redline first'
                : undefined
          }
        >
          {commentsBusy ? 'Adding…' : `Add redlines as comments (${redlinedFindings.length})`}
        </Button>
        <Button variant="secondary" onClick={handleShareReportHtml}>
          Download HTML
        </Button>
        <Button variant="primary" onClick={handleDownloadPdf}>
          Download PDF
        </Button>
      </div>

      {docsError && <p className="text-sm text-high">{docsError}</p>}
      {commentsError && <p className="text-sm text-high">{commentsError}</p>}
      {commentsAdded != null && !commentsError && (
        <p className="text-sm text-ink-faint">
          Added {commentsAdded} comment{commentsAdded === 1 ? '' : 's'} to the Google Doc.
        </p>
      )}

      <div className="space-y-3">
        {visible.length === 0 && (
          <p className="py-12 text-center font-mono text-sm text-ink-faint">
            No issues in this filter.
          </p>
        )}
        {visible.map((f, i) => (
          <IssueCard
            key={f.uid}
            index={i}
            finding={f}
            selected={selected.has(f.uid)}
            onToggleSelect={() => toggle(f.uid)}
            clientNotes={clientNotes}
            threadMessages={threads[f.uid] ?? []}
            onPersistThread={(msgs) => persistThread(f.uid, msgs)}
            redlineText={redlines[f.uid]}
          />
        ))}
      </div>

      <PrioritizeDrawer open={prioritizeOpen} onClose={() => setPrioritizeOpen(false)} findings={findings} />
      <RedlineDrawer
        open={redlineOpen}
        onClose={() => setRedlineOpen(false)}
        findings={selectedFindings}
        onDrafted={(results) => {
          setRedlines((r) => {
            const next = { ...r };
            for (const res of results) next[res.uid] = res.redlineText;
            return next;
          });
        }}
      />
    </div>
  );
}
VS_APPLY_EOF_comment4

echo ""
echo "Done. 7 files updated/added:"
echo "  src/app/api/drive/upload/route.ts             (Job Number now comes before Project Name in the Drive folder name)"
echo "  src/lib/report/generateReport.ts               (HTML report title reordered to match)"
echo "  src/lib/report/ContractReportPdf.tsx            (PDF report title reordered to match)"
echo "  src/lib/drive/client.ts                        (added addComment)"
echo "  src/app/api/drive/add-redline-comments/route.ts (new)"
echo "  src/lib/report/addRedlineComments.ts            (new — client helper)"
echo "  src/components/review/ResultsView.tsx           (new 'Add redlines as comments' button)"
echo ""
echo "IMPORTANT: this assumes duplicateContractToGoogleDocs() in"
echo "src/lib/report/googleDocsHandoff.ts returns { docId, docUrl } — matching"
echo "the shape duplicateAsGoogleDoc() in client.ts has always returned. If"
echo "your dev server errors on this (a TypeScript error mentioning docId),"
echo "paste me googleDocsHandoff.ts and I'll adjust to match its real return type."
echo ""
echo "No new npm packages needed — restart your dev server (Ctrl+C, then npm run dev)."
echo "Note: only NEW Drive folders will use the new Job Number-first naming —"
echo "folders already created under the old order won't be renamed automatically."
