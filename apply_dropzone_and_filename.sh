#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_dropzone_and_filename.sh
set -e

mkdir -p "$(dirname "src/components/intake/FileDropzone.tsx")"
cat > "src/components/intake/FileDropzone.tsx" << 'VS_APPLY_EOF_dz1'
'use client';

import { useCallback, useRef, useState } from 'react';
import clsx from 'clsx';
import { Chip } from '@/components/ui/Chip';

export function FileDropzone({
  file,
  characterCount,
  onFile,
  onClear,
}: {
  file: File | null;
  characterCount: number | null;
  onFile: (file: File) => void;
  onClear: () => void;
}) {
  const [dragging, setDragging] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  const handleFiles = useCallback(
    (files: FileList | null) => {
      const f = files?.[0];
      if (f) onFile(f);
    },
    [onFile]
  );

  if (file) {
    return (
      <div className="flex items-center justify-between rounded-sm border border-rule bg-paper px-4 py-3">
        <div className="flex items-center gap-3">
          <div className="flex h-9 w-9 items-center justify-center rounded-sm bg-accent-soft/40 font-mono text-xs uppercase text-ink-soft">
            {file.name.split('.').pop()}
          </div>
          <div>
            <p className="font-body text-sm text-ink">{file.name}</p>
            <p className="font-mono text-xs text-ink-faint">
              {(file.size / 1024).toFixed(0)} KB
              {characterCount != null ? ` · ${characterCount.toLocaleString()} characters extracted` : ' · parsing…'}
            </p>
          </div>
        </div>
        <button onClick={onClear} className="font-mono text-xs text-ink-faint hover:text-high">
          Remove
        </button>
      </div>
    );
  }

  return (
    <>
      {/* Kept as a sibling, not a descendant, of the clickable dropzone
          below. Nesting it inside meant the programmatic .click() call
          fired a native click that bubbled back up into the dropzone's own
          onClick, which called .click() again — triggering the Finder
          dialog a second time and requiring the file to be chosen twice. */}
      <input
        ref={inputRef}
        type="file"
        accept=".pdf,.docx,.txt"
        className="hidden"
        onChange={(e) => handleFiles(e.target.files)}
      />
      <div
        onDragOver={(e) => {
          e.preventDefault();
          setDragging(true);
        }}
        onDragLeave={() => setDragging(false)}
        onDrop={(e) => {
          e.preventDefault();
          setDragging(false);
          handleFiles(e.dataTransfer.files);
        }}
        onClick={() => inputRef.current?.click()}
        className={clsx(
          'flex cursor-pointer flex-col items-center justify-center gap-2 rounded-sm border-2 border-dashed px-6 py-10 text-center transition',
          dragging ? 'border-ink bg-accent-soft/20' : 'border-rule hover:border-ink-faint'
        )}
      >
        <p className="font-body text-sm text-ink">Drag and drop a contract, or click to browse</p>
        <Chip>PDF · DOCX · TXT</Chip>
      </div>
    </>
  );
}
VS_APPLY_EOF_dz1

mkdir -p "$(dirname "src/lib/report/generateReport.ts")"
cat > "src/lib/report/generateReport.ts" << 'VS_APPLY_EOF_dz2'
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
  <h2 style="font-family:Georgia,serif;font-size:18px;margin:0 0 4px;">${escapeHtml(contract.clientName)} — ${escapeHtml(contract.projectName)} (${escapeHtml(contract.projectNumber)})</h2>
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
VS_APPLY_EOF_dz2

mkdir -p "$(dirname "src/lib/report/ContractReportPdf.tsx")"
cat > "src/lib/report/ContractReportPdf.tsx" << 'VS_APPLY_EOF_dz3'
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
          {contract.clientName} — {contract.projectName} ({contract.projectNumber})
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
VS_APPLY_EOF_dz3

mkdir -p "$(dirname "src/lib/report/generatePdf.ts")"
cat > "src/lib/report/generatePdf.ts" << 'VS_APPLY_EOF_dz4'
'use client';

import { createElement } from 'react';
import { pdf } from '@react-pdf/renderer';
import { ContractReportPdf } from './ContractReportPdf';
import type { ContractDoc, Finding } from '@/lib/types';

export async function downloadReportPdf(params: {
  contract: Pick<ContractDoc, 'clientName' | 'projectName' | 'projectNumber' | 'docType' | 'counterparty'>;
  findings: Finding[];
  redlines: Record<string, string>;
  filename: string;
  sourceFileName?: string | null;
}): Promise<Blob> {
  const element = createElement(ContractReportPdf, {
    contract: params.contract,
    findings: params.findings,
    redlines: params.redlines,
    fileName: params.sourceFileName,
  });
  const blob = await pdf(element).toBlob();

  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = params.filename;
  a.click();
  URL.revokeObjectURL(url);

  // Returned so callers can also stash a copy in Drive without re-rendering.
  return blob;
}
VS_APPLY_EOF_dz4

mkdir -p "$(dirname "src/components/review/ResultsView.tsx")"
cat > "src/components/review/ResultsView.tsx" << 'VS_APPLY_EOF_dz5'
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

  const visible = useMemo(
    () => (filter === 'all' ? findings : findings.filter((f) => f.severity === filter)),
    [findings, filter]
  );

  const selectedFindings = findings.filter((f) => selected.has(f.uid));

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
      await duplicateContractToGoogleDocs({
        fileId: driveFileId,
        folderId: driveFolderId,
        name: sourceFileName ? `${sourceFileName} (Google Doc copy)` : `${contract.projectName} (${contract.projectNumber}) — Google Doc copy`,
      });
    } catch (err) {
      setDocsError(err instanceof Error ? err.message : 'Could not open in Google Docs.');
    } finally {
      setDocsBusy(false);
    }
  }

  const googleDocsDisabled = !driveFileId || !driveFolderId || docsBusy;

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
        <Button variant="secondary" onClick={handleShareReportHtml}>
          Download HTML
        </Button>
        <Button variant="primary" onClick={handleDownloadPdf}>
          Download PDF
        </Button>
      </div>

      {docsError && <p className="text-sm text-high">{docsError}</p>}

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
VS_APPLY_EOF_dz5

echo ""
echo "Done. 5 files updated:"
echo "  src/components/intake/FileDropzone.tsx   (fixed double file-picker prompt)"
echo "  src/lib/report/generateReport.ts         (HTML report now shows source file name)"
echo "  src/lib/report/ContractReportPdf.tsx     (PDF report now shows source file name)"
echo "  src/lib/report/generatePdf.ts"
echo "  src/components/review/ResultsView.tsx"
echo ""
echo "No new npm packages needed — restart your dev server (Ctrl+C, then npm run dev)."
