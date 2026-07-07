#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_drive_dated_folders.sh
set -e

mkdir -p "$(dirname "src/lib/drive/client.ts")"
cat > "src/lib/drive/client.ts" << 'VS_APPLY_EOF_drive1'
import 'server-only';
import { google } from 'googleapis';

// All Drive operations run as doco@vsnyc.tv via OAuth 2.0, server-side only —
// the refresh token never reaches the browser. Brief §7.
function oauthClient() {
  const client = new google.auth.OAuth2(
    process.env.GOOGLE_CLIENT_ID,
    process.env.GOOGLE_CLIENT_SECRET,
    process.env.GOOGLE_REDIRECT_URI
  );
  client.setCredentials({ refresh_token: process.env.GOOGLE_DOCO_REFRESH_TOKEN });
  return client;
}

export function driveClient() {
  return google.drive({ version: 'v3', auth: oauthClient() });
}

export function gmailClient() {
  return google.gmail({ version: 'v1', auth: oauthClient() });
}

const ROOT_FOLDER_ID = process.env.DRIVE_ROOT_FOLDER_ID!;

async function findOrCreateFolder(name: string, parentId: string): Promise<string> {
  const drive = driveClient();
  const escaped = name.replace(/'/g, "\\'");
  const res = await drive.files.list({
    q: `'${parentId}' in parents and name = '${escaped}' and mimeType = 'application/vnd.google-apps.folder' and trashed = false`,
    fields: 'files(id, name)',
    spaces: 'drive',
  });
  const existing = res.data.files?.[0];
  if (existing?.id) return existing.id;

  const created = await drive.files.create({
    requestBody: {
      name,
      mimeType: 'application/vnd.google-apps.folder',
      parents: [parentId],
    },
    fields: 'id',
  });
  if (!created.data.id) throw new Error(`Failed to create Drive folder "${name}"`);
  return created.data.id;
}

/**
 * Ensures Contract Reviews/{Client}/{Project (Number)}/ exists and returns
 * that folder's id. Matches the folder structure in brief §7.
 */
export async function ensureMatterFolder(clientName: string, projectLabel: string): Promise<{
  clientFolderId: string;
  matterFolderId: string;
}> {
  const clientFolderId = await findOrCreateFolder(clientName, ROOT_FOLDER_ID);
  const matterFolderId = await findOrCreateFolder(projectLabel, clientFolderId);
  return { clientFolderId, matterFolderId };
}

function isoDate(d: Date): string {
  return d.toISOString().slice(0, 10); // YYYY-MM-DD
}

/**
 * Ensures a dated subfolder exists under a matter folder — Contract
 * Reviews/{Client}/{Project (Number)}/{YYYY-MM-DD}/ — so everything from one
 * review run (the uploaded source file, its Google Doc duplicate, and a copy
 * of the generated report) lands together instead of piling up flat in the
 * project folder. Reused as-is if a review already ran that day.
 */
export async function ensureDatedReviewFolder(matterFolderId: string, when: Date = new Date()): Promise<string> {
  return findOrCreateFolder(isoDate(when), matterFolderId);
}

export async function uploadFileToFolder(params: {
  folderId: string;
  fileName: string;
  mimeType: string;
  buffer: Buffer;
}): Promise<{ fileId: string; webViewLink: string }> {
  const drive = driveClient();
  const { Readable } = await import('stream');

  const res = await drive.files.create({
    requestBody: { name: params.fileName, parents: [params.folderId] },
    media: { mimeType: params.mimeType, body: Readable.from(params.buffer) },
    fields: 'id, webViewLink',
  });

  if (!res.data.id) throw new Error('Drive upload did not return a file id.');
  return { fileId: res.data.id, webViewLink: res.data.webViewLink ?? '' };
}

export async function getFolderLink(folderId: string): Promise<string> {
  const drive = driveClient();
  const res = await drive.files.get({ fileId: folderId, fields: 'webViewLink' });
  return res.data.webViewLink ?? `https://drive.google.com/drive/folders/${folderId}`;
}

export async function renameFile(fileId: string, name: string) {
  const drive = driveClient();
  await drive.files.update({ fileId, requestBody: { name } });
}

export async function moveFile(fileId: string, newParentId: string, oldParentId: string) {
  const drive = driveClient();
  await drive.files.update({ fileId, addParents: newParentId, removeParents: oldParentId });
}

/**
 * Duplicates an uploaded contract into a native, fully-editable Google Doc
 * saved alongside the source file — Drive converts supported formats (DOCX
 * reliably; PDF conversion quality varies) on copy when a Google Workspace
 * mimeType is requested.
 */
export async function duplicateAsGoogleDoc(params: {
  fileId: string;
  folderId: string;
  name: string;
}): Promise<{ docId: string; docUrl: string }> {
  const drive = driveClient();
  const res = await drive.files.copy({
    fileId: params.fileId,
    requestBody: {
      name: params.name,
      mimeType: 'application/vnd.google-apps.document',
      parents: [params.folderId],
    },
    fields: 'id, webViewLink',
  });
  if (!res.data.id) throw new Error('Drive did not return a copied document id.');
  return {
    docId: res.data.id,
    docUrl: res.data.webViewLink ?? `https://docs.google.com/document/d/${res.data.id}/edit`,
  };
}

/** Downloads a Drive file's raw bytes — used to pull MSA text for review context. */
export async function downloadFileBuffer(
  fileId: string
): Promise<{ buffer: Buffer; mimeType: string; name: string }> {
  const drive = driveClient();
  const meta = await drive.files.get({ fileId, fields: 'name, mimeType' });
  const res = await drive.files.get({ fileId, alt: 'media' }, { responseType: 'arraybuffer' });
  const buffer = Buffer.from(res.data as ArrayBuffer);
  return { buffer, mimeType: meta.data.mimeType ?? 'application/octet-stream', name: meta.data.name ?? 'file' };
}
VS_APPLY_EOF_drive1

mkdir -p "$(dirname "src/app/api/drive/upload/route.ts")"
cat > "src/app/api/drive/upload/route.ts" << 'VS_APPLY_EOF_drive2'
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

    const projectLabel = `${projectName} (${projectNumber})`;
    const { matterFolderId } = await ensureMatterFolder(clientName, projectLabel);
    // Nest this review's files under a dated subfolder — Contract
    // Reviews/{Client}/{Project (Number)}/{YYYY-MM-DD}/ — so the source file,
    // its Google Doc duplicate, and the report copy all land together.
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
VS_APPLY_EOF_drive2

mkdir -p "$(dirname "src/app/api/drive/upload-report/route.ts")"
cat > "src/app/api/drive/upload-report/route.ts" << 'VS_APPLY_EOF_drive3'
import { NextRequest, NextResponse } from 'next/server';
import { uploadFileToFolder } from '@/lib/drive/client';

// Uploads a copy of the generated HTML/PDF report into the same dated Drive
// folder as the source contract for this review (folderId comes from the
// driveFolderId returned by /api/drive/upload for this version). Fire-and-
// forget from the client — a failure here shouldn't block anyone from
// downloading their report locally.
export async function POST(req: NextRequest) {
  try {
    const form = await req.formData();
    const file = form.get('file') as File | null;
    const folderId = form.get('folderId') as string | null;

    if (!file || !folderId) {
      return NextResponse.json({ error: 'file and folderId are required.' }, { status: 400 });
    }

    const buffer = Buffer.from(await file.arrayBuffer());
    const { fileId, webViewLink } = await uploadFileToFolder({
      folderId,
      fileName: file.name,
      mimeType: file.type || 'application/octet-stream',
      buffer,
    });

    return NextResponse.json({ driveFileId: fileId, driveUrl: webViewLink });
  } catch (err) {
    console.error('drive/upload-report failed', err);
    return NextResponse.json(
      { error: err instanceof Error ? err.message : 'Report upload failed.' },
      { status: 500 }
    );
  }
}
VS_APPLY_EOF_drive3

mkdir -p "$(dirname "src/lib/report/uploadToDrive.ts")"
cat > "src/lib/report/uploadToDrive.ts" << 'VS_APPLY_EOF_drive4'
'use client';

/**
 * Uploads a copy of a generated report (HTML or PDF blob) into the Drive
 * folder for this review — the same dated folder the source contract and
 * any Google Doc duplicate already live in.
 */
export async function uploadReportToDrive(params: {
  blob: Blob;
  filename: string;
  folderId: string;
}): Promise<{ driveFileId: string; driveUrl: string }> {
  const form = new FormData();
  form.append('file', params.blob, params.filename);
  form.append('folderId', params.folderId);

  const res = await fetch('/api/drive/upload-report', { method: 'POST', body: form });
  const data = await res.json();
  if (data.error) throw new Error(data.error);
  return data;
}
VS_APPLY_EOF_drive4

mkdir -p "$(dirname "src/lib/report/generatePdf.ts")"
cat > "src/lib/report/generatePdf.ts" << 'VS_APPLY_EOF_drive5'
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
}): Promise<Blob> {
  const element = createElement(ContractReportPdf, {
    contract: params.contract,
    findings: params.findings,
    redlines: params.redlines,
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
VS_APPLY_EOF_drive5

mkdir -p "$(dirname "src/components/review/ResultsView.tsx")"
cat > "src/components/review/ResultsView.tsx" << 'VS_APPLY_EOF_drive6'
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
    const html = generateReportHtml({ contract, findings, redlines });
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
    const blob = await downloadReportPdf({ contract, findings, redlines, filename });

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
VS_APPLY_EOF_drive6

echo ""
echo "Done. 6 files updated/added:"
echo "  src/lib/drive/client.ts                    (added ensureDatedReviewFolder)"
echo "  src/app/api/drive/upload/route.ts           (source file now lands in a dated subfolder)"
echo "  src/app/api/drive/upload-report/route.ts    (new — uploads report copies)"
echo "  src/lib/report/uploadToDrive.ts             (new — client helper)"
echo "  src/lib/report/generatePdf.ts                (now returns the PDF blob)"
echo "  src/components/review/ResultsView.tsx       (Download HTML/PDF also push a copy to Drive)"
echo ""
echo "No new npm packages needed — restart your dev server (Ctrl+C, then npm run dev)."
