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
import { appendIssueThreadMessages, updateVersionDrive, updateVersionFindings } from '@/lib/firebase/firestore';
import type { ContractDoc, Finding, ThreadMessage } from '@/lib/types';

export function ResultsView({
  contract,
  contractId,
  versionId,
  versionNumber,
  findings,
  clientNotes,
  driveFileId,
  driveFolderId,
  sourceFileName,
}: {
  contract: Pick<ContractDoc, 'clientName' | 'projectName' | 'projectNumber' | 'docType' | 'counterparty'>;
  contractId: string;
  versionId: string;
  versionNumber: number;
  findings: Finding[];
  clientNotes?: string | null;
  driveFileId?: string | null;
  driveFolderId?: string | null;
  sourceFileName?: string | null;
}) {
  const [filter, setFilter] = useState<FilterValue>('all');
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [threads, setThreads] = useState<Record<string, ThreadMessage[]>>({});
  // Seeded from any redlineText already saved on the findings — so reopening
  // a past review (via /review/[contractId]/[versionId]) shows previously
  // drafted redlines instead of requiring them to be redrafted.
  const [redlines, setRedlines] = useState<Record<string, string>>(() => {
    const init: Record<string, string> = {};
    for (const f of findings) {
      if (f.redlineText) init[f.uid] = f.redlineText;
    }
    return init;
  });
  const [prioritizeOpen, setPrioritizeOpen] = useState(false);
  const [redlineOpen, setRedlineOpen] = useState(false);
  const [docsBusy, setDocsBusy] = useState(false);
  const [docsError, setDocsError] = useState<string | null>(null);
  const [googleDocId, setGoogleDocId] = useState<string | null>(null);
  const [googleDocUrl, setGoogleDocUrl] = useState<string | null>(null);
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

  async function handleShareReportHtml() {
    const html = generateReportHtml({ contract, findings, redlines, fileName: sourceFileName });
    const filename = `${contract.clientName} — ${contract.projectName} review.html`;
    downloadReport(html, filename);

    if (driveFolderId) {
      try {
        const { driveUrl } = await uploadReportToDrive({
          blob: new Blob([html], { type: 'text/html' }),
          filename,
          folderId: driveFolderId,
        });
        await updateVersionDrive(contractId, versionId, { reportHtmlUrl: driveUrl });
      } catch {
        // Non-fatal — local download already succeeded.
      }
    }
  }

  async function handleDownloadPdf() {
    const filename = `${contract.clientName} — ${contract.projectName} review.pdf`;
    const blob = await downloadReportPdf({ contract, findings, redlines, filename, sourceFileName });

    if (driveFolderId) {
      try {
        const { driveUrl } = await uploadReportToDrive({ blob, filename, folderId: driveFolderId });
        await updateVersionDrive(contractId, versionId, { reportPdfUrl: driveUrl });
      } catch {
        // Non-fatal — local download already succeeded.
      }
    }
  }

  async function handleGoogleDocs() {
    if (!driveFileId || !driveFolderId) return;

    if (googleDocId && googleDocUrl) {
      window.open(googleDocUrl, '_blank', 'noopener,noreferrer');
      return;
    }

    setDocsBusy(true);
    setDocsError(null);
    try {
      const { docId, docUrl } = await duplicateContractToGoogleDocs({
        fileId: driveFileId,
        folderId: driveFolderId,
        name: sourceFileName
          ? `${sourceFileName} — v${versionNumber}`
          : `${contract.projectNumber} — ${contract.projectName} — v${versionNumber}`,
      });
      setGoogleDocId(docId);
      setGoogleDocUrl(docUrl);
      await updateVersionDrive(contractId, versionId, { googleDocId: docId, googleDocUrl: docUrl });
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
              : googleDocId
                ? 'Reopens the Google Doc already created for this version'
                : undefined
          }
        >
          {docsBusy ? 'Opening…' : googleDocId ? 'Reopen Google Doc' : 'Open in Google Docs'}
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

            // Persist redlines onto the version's findings so reopening this
            // review later (from the Library) shows them already drafted.
            const updatedFindings = findings.map((f) => ({ ...f, redlineText: next[f.uid] ?? f.redlineText }));
            updateVersionFindings(contractId, versionId, updatedFindings).catch(() => {});

            return next;
          });
        }}
      />
    </div>
  );
}
