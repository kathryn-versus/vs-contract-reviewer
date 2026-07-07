#!/bin/bash
set -e
echo "Applying updates..."

mkdir -p "$(dirname "package.json")"
cat > "package.json" << 'VS_APPLY_EOF_9f3a'
{
  "name": "vs-contract-reviewer",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "lint": "next lint",
    "typecheck": "tsc --noEmit"
  },
  "dependencies": {
    "next": "^14.2.5",
    "react": "^18.3.1",
    "react-dom": "^18.3.1",
    "firebase": "^10.12.4",
    "firebase-admin": "^12.3.0",
    "@anthropic-ai/sdk": "^0.24.3",
    "googleapis": "^140.0.1",
    "pdfjs-dist": "^4.4.168",
    "mammoth": "^1.7.2",
    "pdf-parse": "^1.1.1",
    "@react-pdf/renderer": "^3.4.4",
    "clsx": "^2.1.1",
    "nanoid": "^5.0.7"
  },
  "devDependencies": {
    "typescript": "^5.5.3",
    "@types/node": "^20.14.11",
    "@types/react": "^18.3.3",
    "@types/react-dom": "^18.3.0",
    "tailwindcss": "^3.4.6",
    "postcss": "^8.4.39",
    "autoprefixer": "^10.4.19",
    "eslint": "^8.57.0",
    "eslint-config-next": "^14.2.5"
  }
}

VS_APPLY_EOF_9f3a
echo "  wrote package.json"

mkdir -p "$(dirname "src/lib/types.ts")"
cat > "src/lib/types.ts" << 'VS_APPLY_EOF_9f3a'
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

// The eight standing concerns — brief §5.
export interface Concern {
  id: number;
  label: string;
  description: string;
}

export const EIGHT_CONCERNS: Concern[] = [
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
];

export const SEVERITY_LABELS: Record<Severity, string> = {
  high: 'Significantly one-sided or high financial/legal exposure — must negotiate',
  medium: 'Notable but not severe, or partially addressed — should negotiate',
  low: 'Minor wording issue or low practical risk — nice to have',
};

VS_APPLY_EOF_9f3a
echo "  wrote src/lib/types.ts"

mkdir -p "$(dirname "src/app/api/drive/upload/route.ts")"
cat > "src/app/api/drive/upload/route.ts" << 'VS_APPLY_EOF_9f3a'
import { NextRequest, NextResponse } from 'next/server';
import { ensureMatterFolder, uploadFileToFolder, getFolderLink } from '@/lib/drive/client';

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

    const buffer = Buffer.from(await file.arrayBuffer());
    const fileName = versionSuffix ? appendSuffix(file.name, versionSuffix) : file.name;

    const { fileId, webViewLink } = await uploadFileToFolder({
      folderId: matterFolderId,
      fileName,
      mimeType: file.type || 'application/octet-stream',
      buffer,
    });

    const driveFolderUrl = await getFolderLink(matterFolderId);

    return NextResponse.json({
      driveFileId: fileId,
      driveUrl: webViewLink,
      driveFolderUrl,
      driveFolderId: matterFolderId,
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

VS_APPLY_EOF_9f3a
echo "  wrote src/app/api/drive/upload/route.ts"

mkdir -p "$(dirname "src/lib/firebase/firestore.ts")"
cat > "src/lib/firebase/firestore.ts" << 'VS_APPLY_EOF_9f3a'
'use client';

import {
  collection,
  doc,
  getDoc,
  getDocs,
  addDoc,
  setDoc,
  updateDoc,
  query,
  where,
  orderBy,
  limit as fsLimit,
  serverTimestamp,
  Timestamp,
  onSnapshot,
} from 'firebase/firestore';
import { db } from './client';
import type { ClientDoc, ContractDoc, VersionDoc, Finding, IssueThreadDoc, ThreadMessage, UserDoc, Role } from '../types';

function slugify(name: string) {
  return name
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/(^-|-$)/g, '');
}

function toMillis(v: unknown): number {
  if (v instanceof Timestamp) return v.toMillis();
  if (typeof v === 'number') return v;
  return Date.now();
}

// ── Clients ──────────────────────────────────────────────────────────────

export async function listClients(): Promise<ClientDoc[]> {
  const snap = await getDocs(query(collection(db, 'clients'), orderBy('name')));
  return snap.docs.map((d) => ({ id: d.id, ...(d.data() as Omit<ClientDoc, 'id'>), createdAt: toMillis(d.data().createdAt) }));
}

export function subscribeClients(cb: (clients: ClientDoc[]) => void) {
  return onSnapshot(query(collection(db, 'clients'), orderBy('name')), (snap) => {
    cb(snap.docs.map((d) => ({ id: d.id, ...(d.data() as Omit<ClientDoc, 'id'>), createdAt: toMillis(d.data().createdAt) })));
  });
}

export async function getOrCreateClient(name: string, createdBy: string): Promise<ClientDoc> {
  const slug = slugify(name);
  const existing = await getDocs(query(collection(db, 'clients'), where('slug', '==', slug), fsLimit(1)));
  if (!existing.empty) {
    const d = existing.docs[0];
    return { id: d.id, ...(d.data() as Omit<ClientDoc, 'id'>), createdAt: toMillis(d.data().createdAt) };
  }
  const ref = await addDoc(collection(db, 'clients'), {
    name,
    slug,
    notes: '',
    msaContractId: null,
    createdAt: serverTimestamp(),
    createdBy,
  });
  const snap = await getDoc(ref);
  return { id: ref.id, ...(snap.data() as Omit<ClientDoc, 'id'>), createdAt: Date.now() };
}

export async function updateClientNotes(clientId: string, notes: string) {
  await updateDoc(doc(db, 'clients', clientId), { notes });
}

export async function getClient(clientId: string): Promise<ClientDoc | null> {
  const snap = await getDoc(doc(db, 'clients', clientId));
  if (!snap.exists()) return null;
  return { id: snap.id, ...(snap.data() as Omit<ClientDoc, 'id'>), createdAt: toMillis(snap.data().createdAt) };
}

// ── Contracts & Versions ─────────────────────────────────────────────────

export async function createContract(input: Omit<ContractDoc, 'id' | 'createdAt' | 'latestVersionId'>): Promise<string> {
  const ref = await addDoc(collection(db, 'contracts'), {
    ...input,
    createdAt: serverTimestamp(),
    latestVersionId: null,
  });
  return ref.id;
}

export async function addVersion(
  contractId: string,
  input: Omit<VersionDoc, 'id' | 'uploadedAt'>
): Promise<string> {
  const versionsRef = collection(db, 'contracts', contractId, 'versions');
  const ref = await addDoc(versionsRef, { ...input, uploadedAt: serverTimestamp() });
  await updateDoc(doc(db, 'contracts', contractId), { latestVersionId: ref.id });
  return ref.id;
}

export async function listVersionsForContract(contractId: string): Promise<VersionDoc[]> {
  const snap = await getDocs(
    query(collection(db, 'contracts', contractId, 'versions'), orderBy('versionNumber', 'desc'))
  );
  return snap.docs.map((d) => ({ id: d.id, ...(d.data() as Omit<VersionDoc, 'id'>), uploadedAt: toMillis(d.data().uploadedAt) }));
}

export async function listContractsForClient(clientId: string): Promise<ContractDoc[]> {
  const snap = await getDocs(
    query(collection(db, 'contracts'), where('clientId', '==', clientId), orderBy('createdAt', 'desc'))
  );
  return snap.docs.map((d) => ({ id: d.id, ...(d.data() as Omit<ContractDoc, 'id'>), createdAt: toMillis(d.data().createdAt) }));
}

// All matters across every client — used by the intake form's job picker so
// a job can be searched/selected before (or instead of) picking a client.
export async function listAllContracts(): Promise<ContractDoc[]> {
  const snap = await getDocs(query(collection(db, 'contracts'), orderBy('createdAt', 'desc')));
  return snap.docs.map((d) => ({ id: d.id, ...(d.data() as Omit<ContractDoc, 'id'>), createdAt: toMillis(d.data().createdAt) }));
}

// Next version number for an existing matter — used when a reviewer picks an
// existing job from the intake form instead of creating a new one.
export async function getNextVersionNumber(contractId: string): Promise<number> {
  const versions = await listVersionsForContract(contractId);
  return (versions[0]?.versionNumber ?? 0) + 1;
}

export async function updateContractDrive(
  contractId: string,
  drive: { driveFileId: string; driveUrl: string; driveFolderUrl: string; driveFolderId?: string }
) {
  await updateDoc(doc(db, 'contracts', contractId), drive);
}

export async function moveContract(
  contractId: string,
  updates: Partial<Pick<ContractDoc, 'clientId' | 'clientName' | 'projectName'>>
) {
  await updateDoc(doc(db, 'contracts', contractId), updates);
}

// Marks a contract as the client's governing MSA — feeds automatic MSA
// context into future SOW reviews for that client (brief §11, Phase 2).
export async function setGoverningMsa(clientId: string, contractId: string) {
  await updateDoc(doc(db, 'clients', clientId), { msaContractId: contractId });
}

export async function clearGoverningMsa(clientId: string) {
  await updateDoc(doc(db, 'clients', clientId), { msaContractId: null });
}

// ── Issue threads (redline chat) ─────────────────────────────────────────

export async function getIssueThread(
  contractId: string,
  versionId: string,
  issueUid: string
): Promise<ThreadMessage[]> {
  const ref = doc(db, 'contracts', contractId, 'versions', versionId, 'issueThreads', issueUid);
  const snap = await getDoc(ref);
  if (!snap.exists()) return [];
  return (snap.data() as IssueThreadDoc).messages ?? [];
}

export async function appendIssueThreadMessages(
  contractId: string,
  versionId: string,
  issueUid: string,
  newMessages: ThreadMessage[]
) {
  const ref = doc(db, 'contracts', contractId, 'versions', versionId, 'issueThreads', issueUid);
  const existing = await getDoc(ref);
  const prior: ThreadMessage[] = existing.exists() ? (existing.data() as IssueThreadDoc).messages ?? [] : [];
  await setDoc(ref, { messages: [...prior, ...newMessages] }, { merge: true });
}

// ── Users / admin management ─────────────────────────────────────────────

export async function listUsers(): Promise<UserDoc[]> {
  const snap = await getDocs(query(collection(db, 'users'), orderBy('email')));
  return snap.docs.map((d) => ({
    uid: d.id,
    ...(d.data() as Omit<UserDoc, 'uid'>),
    createdAt: toMillis(d.data().createdAt),
    lastLoginAt: toMillis(d.data().lastLoginAt),
  }));
}

export async function setUserRole(uid: string, role: Role) {
  await updateDoc(doc(db, 'users', uid), { role });
}

VS_APPLY_EOF_9f3a
echo "  wrote src/lib/firebase/firestore.ts"

mkdir -p "$(dirname "src/components/review/ConcernIndex.tsx")"
cat > "src/components/review/ConcernIndex.tsx" << 'VS_APPLY_EOF_9f3a'
import { EIGHT_CONCERNS } from '@/lib/types';

// Condensed labels for the always-visible strip — short enough to fit eight
// across one line, unlike the full concern descriptions.
const SHORT_LABELS: Record<number, string> = {
  1: 'Mutual termination',
  2: 'Cure period',
  3: 'Indemnification scope',
  4: 'Cap applies to indemnity',
  5: 'Freelancers/subs',
  6: 'AI tool use',
  7: 'Portfolio/awards',
  8: 'Kill fee structure',
};

/**
 * The eight standing concerns shown as a persistent reference strip, so it's
 * clear what was checked regardless of how many issues were actually flagged.
 */
export function ConcernIndex() {
  return (
    <div className="flex flex-wrap gap-x-4 gap-y-1.5 border-b-2 border-ink pb-4 font-mono text-xs text-ink-soft">
      {EIGHT_CONCERNS.map((c, i) => (
        <span key={c.id} className="whitespace-nowrap">
          <span className="font-medium text-ink">{c.id}.</span> {SHORT_LABELS[c.id] ?? c.label}
          {i < EIGHT_CONCERNS.length - 1 && <span className="ml-4 text-rule">|</span>}
        </span>
      ))}
    </div>
  );
}

VS_APPLY_EOF_9f3a
echo "  wrote src/components/review/ConcernIndex.tsx"

mkdir -p "$(dirname "src/components/review/IssueCard.tsx")"
cat > "src/components/review/IssueCard.tsx" << 'VS_APPLY_EOF_9f3a'
'use client';

import { useState } from 'react';
import clsx from 'clsx';
import { SeverityBadge } from '@/components/ui/SeverityBadge';
import { RedlineChat } from './RedlineChat';
import type { Finding, ThreadMessage } from '@/lib/types';

const borderColor: Record<Finding['severity'], string> = {
  high: 'border-l-high',
  medium: 'border-l-med',
  low: 'border-l-low',
};

export function IssueCard({
  index,
  finding,
  selected,
  onToggleSelect,
  clientNotes,
  threadMessages,
  onPersistThread,
  redlineText,
}: {
  index: number;
  finding: Finding;
  selected: boolean;
  onToggleSelect: () => void;
  clientNotes?: string | null;
  threadMessages: ThreadMessage[];
  onPersistThread: (messages: ThreadMessage[]) => void;
  redlineText?: string | null;
}) {
  const [expanded, setExpanded] = useState(true);
  const [chatOpen, setChatOpen] = useState(false);

  return (
    <div className={clsx('rounded-sm border border-rule border-l-4 bg-paper', borderColor[finding.severity])}>
      <div className="flex items-start gap-3 p-4">
        <span className="mt-0.5 font-mono text-xs text-ink-faint">{String(index + 1).padStart(2, '0')}</span>
        <input
          type="checkbox"
          checked={selected}
          onChange={onToggleSelect}
          className="mt-1 h-4 w-4 accent-ink"
          aria-label="Select for redline"
        />
        <button className="flex-1 text-left" onClick={() => setExpanded((v) => !v)}>
          <p className="font-mono text-[11px] uppercase tracking-wide text-ink-faint">
            Concern {finding.concernId} · {finding.concernLabel}
          </p>
          <p className="mt-1.5 font-display text-base text-ink">{finding.issueTitle}</p>
          {finding.location && (
            <p className="mt-0.5 font-mono text-xs text-ink-faint">{finding.location}</p>
          )}
        </button>
        <SeverityBadge severity={finding.severity} />
        <button
          onClick={() => setExpanded((v) => !v)}
          aria-label={expanded ? 'Collapse' : 'Expand'}
          className="mt-0.5 font-mono text-xs text-ink-faint hover:text-ink"
        >
          {expanded ? '▲' : '▼'}
        </button>
      </div>

      {expanded && (
        <div className="space-y-4 border-t border-rule px-4 pb-4 pt-4">
          <div>
            <p className="mb-1 font-mono text-[11px] uppercase tracking-wide text-ink-faint">
              Contract language
            </p>
            <blockquote className="border-l-2 border-rule pl-3 font-body text-sm italic text-ink-soft">
              “{finding.quote}”
            </blockquote>
          </div>
          <div>
            <p className="mb-1 font-mono text-[11px] uppercase tracking-wide text-ink-faint">
              Why it matters
            </p>
            <p className="font-body text-sm text-ink">{finding.analysis}</p>
          </div>
          <div>
            <p className="mb-1 font-mono text-[11px] uppercase tracking-wide text-ink-faint">
              Suggested negotiation direction
            </p>
            <p className="font-body text-sm text-ink">{finding.recommendation}</p>
          </div>

          {redlineText && (
            <div>
              <p className="mb-1 font-mono text-[11px] uppercase tracking-wide text-ink-faint">
                Drafted redline
              </p>
              <p className="whitespace-pre-wrap rounded-sm bg-accent-soft/15 p-3 font-mono text-xs text-ink">
                {redlineText}
              </p>
            </div>
          )}

          <button
            onClick={() => setChatOpen((v) => !v)}
            className="font-mono text-xs uppercase tracking-wide text-accent hover:underline"
          >
            {chatOpen ? 'Hide redline chat' : 'Refine this redline →'}
          </button>

          {chatOpen && (
            <RedlineChat
              issue={finding}
              clientNotes={clientNotes}
              initialMessages={threadMessages}
              onPersist={onPersistThread}
            />
          )}
        </div>
      )}
    </div>
  );
}

VS_APPLY_EOF_9f3a
echo "  wrote src/components/review/IssueCard.tsx"

mkdir -p "$(dirname "src/components/review/ResultsView.tsx")"
cat > "src/components/review/ResultsView.tsx" << 'VS_APPLY_EOF_9f3a'
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
    downloadReport(html, `${contract.clientName} — ${contract.projectName} review.html`);
  }

  async function handleDownloadPdf() {
    await downloadReportPdf({
      contract,
      findings,
      redlines,
      filename: `${contract.clientName} — ${contract.projectName} review.pdf`,
    });
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

VS_APPLY_EOF_9f3a
echo "  wrote src/components/review/ResultsView.tsx"

mkdir -p "$(dirname "src/lib/report/ContractReportPdf.tsx")"
cat > "src/lib/report/ContractReportPdf.tsx" << 'VS_APPLY_EOF_9f3a'
import { Document, Page, View, Text, StyleSheet } from '@react-pdf/renderer';
import type { ContractDoc, Finding } from '@/lib/types';

const SEVERITY_COLOR: Record<string, string> = {
  high: '#8A3324',
  medium: '#A8761E',
  low: '#5A6B4F',
};

const styles = StyleSheet.create({
  page: { padding: 36, fontSize: 10, fontFamily: 'Helvetica', color: '#1C1B19' },
  eyebrow: { fontSize: 8, letterSpacing: 1, textTransform: 'uppercase', color: '#8C8777', marginBottom: 4 },
  title: { fontSize: 18, marginBottom: 4 },
  meta: { fontSize: 9, color: '#5B574D', marginBottom: 16 },
  summaryRow: { flexDirection: 'row', marginBottom: 20 },
  summaryBox: { flex: 1, borderWidth: 1, borderColor: '#D8D3C7', padding: 8, marginRight: 8, textAlign: 'center' },
  summaryNum: { fontSize: 16, marginBottom: 2 },
  summaryLabel: { fontSize: 7, textTransform: 'uppercase', color: '#8C8777' },
  issue: { borderWidth: 1, borderColor: '#D8D3C7', borderLeftWidth: 3, padding: 10, marginBottom: 10 },
  issueMeta: { fontSize: 8, textTransform: 'uppercase', color: '#8C8777', marginBottom: 3 },
  issueTitle: { fontSize: 12, marginBottom: 6 },
  sectionLabel: { fontSize: 7, textTransform: 'uppercase', color: '#8C8777', marginTop: 6, marginBottom: 2 },
  quote: { fontSize: 9, fontStyle: 'italic', color: '#5B574D' },
  body: { fontSize: 9, lineHeight: 1.4 },
  redline: { fontSize: 8, fontFamily: 'Courier', backgroundColor: '#EFE9DC', padding: 6, marginTop: 2 },
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
        <Text style={styles.title}>
          {contract.clientName} — {contract.projectName} ({contract.projectNumber})
        </Text>
        <Text style={styles.meta}>
          {contract.docType} · Counterparty: {contract.counterparty} · Generated {when.toLocaleString()}
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
          <View style={styles.summaryBox}>
            <Text style={styles.summaryNum}>{counts.low}</Text>
            <Text style={styles.summaryLabel}>Low</Text>
          </View>
        </View>

        {findings.length === 0 && (
          <Text style={styles.body}>No issues flagged against the eight standing concerns.</Text>
        )}

        {findings.map((f) => (
          <View key={f.uid} style={[styles.issue, { borderLeftColor: SEVERITY_COLOR[f.severity] }]} wrap={false}>
            <Text style={styles.issueMeta}>
              {f.severity.toUpperCase()} · Concern {f.concernId} · {f.concernLabel}
            </Text>
            <Text style={styles.issueTitle}>{f.issueTitle}</Text>
            {f.location ? <Text style={styles.issueMeta}>{f.location}</Text> : null}

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
      </Page>
    </Document>
  );
}

VS_APPLY_EOF_9f3a
echo "  wrote src/lib/report/ContractReportPdf.tsx"

mkdir -p "$(dirname "src/lib/report/generatePdf.ts")"
cat > "src/lib/report/generatePdf.ts" << 'VS_APPLY_EOF_9f3a'
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
}) {
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
}

VS_APPLY_EOF_9f3a
echo "  wrote src/lib/report/generatePdf.ts"

mkdir -p "$(dirname "src/lib/drive/client.ts")"
cat > "src/lib/drive/client.ts" << 'VS_APPLY_EOF_9f3a'
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

VS_APPLY_EOF_9f3a
echo "  wrote src/lib/drive/client.ts"

mkdir -p "$(dirname "src/app/api/drive/duplicate-to-docs/route.ts")"
cat > "src/app/api/drive/duplicate-to-docs/route.ts" << 'VS_APPLY_EOF_9f3a'
import { NextRequest, NextResponse } from 'next/server';
import { duplicateAsGoogleDoc } from '@/lib/drive/client';

// "Open in Google Docs" — duplicates the source contract file (already in
// Drive from the original upload) into a native Google Doc saved in the same
// matter folder, so the reviewer gets a fully editable copy of the whole
// contract rather than just the drafted redline excerpts.
export async function POST(req: NextRequest) {
  try {
    const { fileId, folderId, name } = await req.json();
    if (!fileId || !folderId) {
      return NextResponse.json({ error: 'fileId and folderId are required.' }, { status: 400 });
    }

    const { docId, docUrl } = await duplicateAsGoogleDoc({
      fileId,
      folderId,
      name: name || 'Contract copy',
    });

    return NextResponse.json({ docId, docUrl });
  } catch (err) {
    console.error('drive/duplicate-to-docs failed', err);
    return NextResponse.json(
      { error: err instanceof Error ? err.message : 'Could not duplicate into Google Docs.' },
      { status: 500 }
    );
  }
}

VS_APPLY_EOF_9f3a
echo "  wrote src/app/api/drive/duplicate-to-docs/route.ts"

mkdir -p "$(dirname "src/lib/report/googleDocsHandoff.ts")"
cat > "src/lib/report/googleDocsHandoff.ts" << 'VS_APPLY_EOF_9f3a'
// "Open in Google Docs" duplicates the full source contract (not just
// drafted redlines) into a native Google Doc saved in the matter's Drive
// folder, via /api/drive/duplicate-to-docs. Requires the contract to already
// have a driveFileId + driveFolderId (i.e. the Drive upload step succeeded).
export async function duplicateContractToGoogleDocs(params: {
  fileId: string;
  folderId: string;
  name: string;
}): Promise<{ docUrl: string }> {
  const res = await fetch('/api/drive/duplicate-to-docs', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(params),
  });
  const data = await res.json();
  if (data.error) throw new Error(data.error);

  window.open(data.docUrl, '_blank', 'noopener,noreferrer');
  return { docUrl: data.docUrl };
}

VS_APPLY_EOF_9f3a
echo "  wrote src/lib/report/googleDocsHandoff.ts"

mkdir -p "$(dirname "src/components/library/MatterCard.tsx")"
cat > "src/components/library/MatterCard.tsx" << 'VS_APPLY_EOF_9f3a'
'use client';

import { useEffect, useState } from 'react';
import { Card } from '@/components/ui/Card';
import { SeverityBadge } from '@/components/ui/SeverityBadge';
import { listVersionsForContract } from '@/lib/firebase/firestore';
import type { ContractDoc, VersionDoc } from '@/lib/types';

export function MatterCard({
  contract,
  onEdit,
  isGoverningMsa,
  onToggleGoverningMsa,
}: {
  contract: ContractDoc;
  onEdit: () => void;
  isGoverningMsa?: boolean;
  onToggleGoverningMsa?: () => void;
}) {
  const [versions, setVersions] = useState<VersionDoc[]>([]);
  const [expanded, setExpanded] = useState(false);

  useEffect(() => {
    listVersionsForContract(contract.id).then(setVersions).catch(() => {});
  }, [contract.id]);

  const latest = versions[0];
  const counts = latest
    ? {
        high: latest.findings.filter((f) => f.severity === 'high').length,
        medium: latest.findings.filter((f) => f.severity === 'medium').length,
        low: latest.findings.filter((f) => f.severity === 'low').length,
      }
    : null;

  return (
    <Card className="p-5">
      <div className="flex items-start justify-between">
        <div>
          <p className="font-display text-lg text-ink">
            {contract.projectName} <span className="font-mono text-sm text-ink-faint">({contract.projectNumber})</span>
            {isGoverningMsa && (
              <span className="ml-2 rounded-full border border-accent/30 bg-high-bg px-2 py-0.5 align-middle font-mono text-[10px] uppercase tracking-wide text-accent">
                Governing MSA
              </span>
            )}
          </p>
          <p className="font-mono text-xs text-ink-faint">
            {contract.docType} · Counterparty: {contract.counterparty}
          </p>
        </div>
        <div className="flex items-center gap-3">
          {onToggleGoverningMsa && contract.docType !== 'SOW' && (
            <button
              onClick={onToggleGoverningMsa}
              className="font-mono text-xs text-ink-faint hover:text-ink"
            >
              {isGoverningMsa ? 'Unset as MSA' : 'Set as governing MSA'}
            </button>
          )}
          {counts && (
            <div className="flex gap-1">
              {counts.high > 0 && <SeverityBadge severity="high" />}
              {counts.medium > 0 && <SeverityBadge severity="medium" />}
              {counts.low > 0 && <SeverityBadge severity="low" />}
            </div>
          )}
          <button onClick={onEdit} className="font-mono text-xs text-ink-faint hover:text-ink">
            Edit
          </button>
          <button
            onClick={() => setExpanded((v) => !v)}
            className="font-mono text-xs text-ink-faint hover:text-ink"
          >
            {expanded ? 'Hide versions' : `${versions.length} version${versions.length === 1 ? '' : 's'}`}
          </button>
        </div>
      </div>

      {expanded && (
        <div className="mt-4 space-y-3 border-t border-rule pt-4">
          {versions.map((v) => (
            <div key={v.id} className="flex items-center justify-between text-sm">
              <div>
                <p className="text-ink">v{v.versionNumber} · {v.fileName}</p>
                <p className="font-mono text-xs text-ink-faint">
                  {new Date(v.uploadedAt).toLocaleDateString()} · uploaded by {v.uploadedBy.name}
                </p>
                {v.deltaFromPrevious && (
                  <p className="mt-1 font-body text-xs text-ink-soft">Δ {v.deltaFromPrevious}</p>
                )}
              </div>
              {contract.driveUrl && (
                <a
                  href={contract.driveUrl}
                  target="_blank"
                  rel="noreferrer"
                  className="font-mono text-xs text-accent hover:underline"
                >
                  Drive ↗
                </a>
              )}
            </div>
          ))}
        </div>
      )}
    </Card>
  );
}

VS_APPLY_EOF_9f3a
echo "  wrote src/components/library/MatterCard.tsx"

mkdir -p "$(dirname "src/components/library/ClientDetailView.tsx")"
cat > "src/components/library/ClientDetailView.tsx" << 'VS_APPLY_EOF_9f3a'
'use client';

import { useEffect, useState } from 'react';
import { Card } from '@/components/ui/Card';
import { Button } from '@/components/ui/Button';
import { MatterCard } from './MatterCard';
import {
  getClient,
  listContractsForClient,
  updateClientNotes,
  moveContract,
  listClients,
  setGoverningMsa,
  clearGoverningMsa,
} from '@/lib/firebase/firestore';
import type { ClientDoc, ContractDoc } from '@/lib/types';

export function ClientDetailView({ clientId }: { clientId: string }) {
  const [client, setClient] = useState<ClientDoc | null>(null);
  const [contracts, setContracts] = useState<ContractDoc[]>([]);
  const [allClients, setAllClients] = useState<ClientDoc[]>([]);
  const [notes, setNotes] = useState('');
  const [savingNotes, setSavingNotes] = useState(false);
  const [editing, setEditing] = useState<ContractDoc | null>(null);

  useEffect(() => {
    getClient(clientId).then((c) => {
      setClient(c);
      setNotes(c?.notes ?? '');
    });
    listContractsForClient(clientId).then(setContracts);
    listClients().then(setAllClients);
  }, [clientId]);

  if (!client) {
    return <p className="font-mono text-sm text-ink-faint">Loading client…</p>;
  }

  const msaContract = contracts.find((c) => c.id === client.msaContractId);

  async function saveNotes() {
    setSavingNotes(true);
    try {
      await updateClientNotes(clientId, notes);
    } finally {
      setSavingNotes(false);
    }
  }

  async function handleReassign(contractId: string, newClientId: string, newProjectName: string) {
    const target = allClients.find((c) => c.id === newClientId);
    if (!target) return;
    await moveContract(contractId, { clientId: target.id, clientName: target.name, projectName: newProjectName });
    setEditing(null);
    listContractsForClient(clientId).then(setContracts);
  }

  async function handleToggleGoverningMsa(contractId: string) {
    if (client.msaContractId === contractId) {
      await clearGoverningMsa(clientId);
    } else {
      await setGoverningMsa(clientId, contractId);
    }
    getClient(clientId).then(setClient);
  }

  return (
    <div className="space-y-8">
      <div>
        <h1 className="font-display text-2xl text-ink">{client.name}</h1>
        <p className="font-mono text-xs text-ink-faint">{contracts.length} matters on file</p>
      </div>

      {msaContract && (
        <Card className="border-l-4 border-l-accent p-5">
          <p className="font-mono text-[11px] uppercase tracking-wide text-ink-faint">Governing MSA</p>
          <p className="mt-1 font-display text-base text-ink">
            {msaContract.projectName} ({msaContract.projectNumber})
          </p>
          <p className="mt-2 font-body text-sm text-ink-soft">
            Its text is automatically pulled from Drive and given to Claude as context on every
            future SOW review for {client.name} — no manual setup needed per review.
          </p>
        </Card>
      )}

      <Card className="p-5">
        <p className="mb-2 font-mono text-[11px] uppercase tracking-wide text-ink-faint">
          Client notes — fed to Claude as context on future reviews
        </p>
        <textarea
          value={notes}
          onChange={(e) => setNotes(e.target.value)}
          rows={3}
          placeholder='e.g. "Disney: AI clause non-negotiable per WDA amendment, do not flag as high"'
          className="w-full border border-rule bg-paper p-3 font-body text-sm outline-none focus:border-ink"
        />
        <div className="mt-2 flex justify-end">
          <Button variant="primary" onClick={saveNotes} disabled={savingNotes}>
            {savingNotes ? 'Saving…' : 'Save notes'}
          </Button>
        </div>
      </Card>

      <div className="space-y-3">
        <p className="font-mono text-[11px] uppercase tracking-wide text-ink-faint">Matters</p>
        {contracts.map((c) => (
          <MatterCard
            key={c.id}
            contract={c}
            onEdit={() => setEditing(c)}
            isGoverningMsa={client.msaContractId === c.id}
            onToggleGoverningMsa={() => handleToggleGoverningMsa(c.id)}
          />
        ))}
        {contracts.length === 0 && (
          <p className="py-8 text-center font-mono text-sm text-ink-faint">No matters yet.</p>
        )}
      </div>

      {editing && (
        <EditMatterModal
          contract={editing}
          clients={allClients}
          onClose={() => setEditing(null)}
          onSave={handleReassign}
        />
      )}
    </div>
  );
}

function EditMatterModal({
  contract,
  clients,
  onClose,
  onSave,
}: {
  contract: ContractDoc;
  clients: ClientDoc[];
  onClose: () => void;
  onSave: (contractId: string, newClientId: string, newProjectName: string) => void;
}) {
  const [clientId, setClientId] = useState(contract.clientId);
  const [projectName, setProjectName] = useState(contract.projectName);

  return (
    <div className="fixed inset-0 z-40 flex items-center justify-center bg-ink/30 p-6">
      <Card className="w-full max-w-md p-6">
        <h3 className="font-display text-lg text-ink">Edit matter</h3>
        <div className="mt-4 space-y-4">
          <label className="block">
            <span className="mb-1 block font-mono text-xs uppercase text-ink-faint">Client</span>
            <select
              value={clientId}
              onChange={(e) => setClientId(e.target.value)}
              className="w-full border border-rule px-3 py-2 text-sm"
            >
              {clients.map((c) => (
                <option key={c.id} value={c.id}>{c.name}</option>
              ))}
            </select>
          </label>
          <label className="block">
            <span className="mb-1 block font-mono text-xs uppercase text-ink-faint">Project name</span>
            <input
              value={projectName}
              onChange={(e) => setProjectName(e.target.value)}
              className="w-full border border-rule px-3 py-2 text-sm"
            />
          </label>
        </div>
        <div className="mt-6 flex justify-end gap-2">
          <Button variant="ghost" onClick={onClose}>Cancel</Button>
          <Button variant="primary" onClick={() => onSave(contract.id, clientId, projectName)}>
            Save & move Drive folder
          </Button>
        </div>
      </Card>
    </div>
  );
}

VS_APPLY_EOF_9f3a
echo "  wrote src/components/library/ClientDetailView.tsx"

mkdir -p "$(dirname "src/lib/drive/msaContext.ts")"
cat > "src/lib/drive/msaContext.ts" << 'VS_APPLY_EOF_9f3a'
import 'server-only';
import { adminDb } from '@/lib/firebase/admin';
import { downloadFileBuffer } from './client';

const MAX_MSA_CHARS = 20_000;

/**
 * If the given client has a governing MSA on file (marked via Library →
 * matter → "Set as governing MSA"), pull its text straight from Drive so it
 * can be fed to Claude as context on this review — no manual re-entry of
 * standing positions required. Returns null (never throws) if there's no
 * governing MSA set, the file can't be found, or extraction fails — MSA
 * context is a nice-to-have and should never block a review.
 */
export async function getGoverningMsaContext(clientId: string): Promise<string | null> {
  try {
    const clientSnap = await adminDb().collection('clients').doc(clientId).get();
    if (!clientSnap.exists) return null;
    const msaContractId = clientSnap.data()?.msaContractId as string | null | undefined;
    if (!msaContractId) return null;

    const contractSnap = await adminDb().collection('contracts').doc(msaContractId).get();
    if (!contractSnap.exists) return null;
    const driveFileId = contractSnap.data()?.driveFileId as string | null | undefined;
    if (!driveFileId) return null;

    const { buffer, mimeType, name } = await downloadFileBuffer(driveFileId);
    const text = await extractText(buffer, mimeType, name);
    return text ? text.slice(0, MAX_MSA_CHARS) : null;
  } catch (err) {
    console.error('getGoverningMsaContext failed', err);
    return null;
  }
}

async function extractText(buffer: Buffer, mimeType: string, name: string): Promise<string | null> {
  const lower = name.toLowerCase();

  if (lower.endsWith('.pdf') || mimeType.includes('pdf')) {
    const pdfParse = (await import('pdf-parse')).default;
    const result = await pdfParse(buffer);
    return result.text;
  }

  if (lower.endsWith('.docx') || mimeType.includes('officedocument.wordprocessingml')) {
    const mammoth = await import('mammoth');
    const result = await mammoth.extractRawText({ buffer });
    return result.value;
  }

  if (lower.endsWith('.txt') || mimeType.startsWith('text/')) {
    return buffer.toString('utf-8');
  }

  // Native Google Docs (e.g. a duplicated copy) aren't binary-downloadable via
  // alt=media in a plain-text-friendly way here — skip rather than error.
  return null;
}

VS_APPLY_EOF_9f3a
echo "  wrote src/lib/drive/msaContext.ts"

mkdir -p "$(dirname "src/lib/claude/prompts.ts")"
cat > "src/lib/claude/prompts.ts" << 'VS_APPLY_EOF_9f3a'
import { EIGHT_CONCERNS, type DocType } from '@/lib/types';

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

const CONCERNS_BLOCK = EIGHT_CONCERNS.map(
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
THE EIGHT STANDING CONCERNS
Assess the document against exactly these eight concerns. Only return concerns
where you find an actual issue in the text — omit any concern the document
already handles acceptably.

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
  "concernId": number (1-8),
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

VS_APPLY_EOF_9f3a
echo "  wrote src/lib/claude/prompts.ts"

mkdir -p "$(dirname "src/app/api/review/analyze/route.ts")"
cat > "src/app/api/review/analyze/route.ts" << 'VS_APPLY_EOF_9f3a'
import { NextRequest, NextResponse } from 'next/server';
import { nanoid } from 'nanoid';
import { claude, CLAUDE_MODEL, MAX_TOKENS, parseJsonResponse } from '@/lib/claude/client';
import { buildAnalysisPrompt } from '@/lib/claude/prompts';
import { getGoverningMsaContext } from '@/lib/drive/msaContext';
import type { Finding, Severity } from '@/lib/types';

interface RawFinding {
  concernId: number;
  concernLabel: string;
  severity: Severity;
  issueTitle: string;
  quote: string;
  location: string;
  analysis: string;
  recommendation: string;
}

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { docType, counterparty, clientName, clientId, clientNotes, documentText } = body ?? {};

    if (!docType || !counterparty || !clientName || !documentText) {
      return NextResponse.json(
        { error: 'docType, counterparty, clientName, and documentText are required.' },
        { status: 400 }
      );
    }

    // Auto-pull the client's governing MSA text from Drive, if one is on
    // file — never blocks the review if it's missing or fails to extract.
    const msaContext = clientId ? await getGoverningMsaContext(clientId) : null;

    const prompt = buildAnalysisPrompt({ docType, counterparty, clientName, clientNotes, msaContext, documentText });

    const message = await claude().messages.create({
      model: CLAUDE_MODEL,
      max_tokens: MAX_TOKENS.analysis,
      messages: [{ role: 'user', content: prompt }],
    });

    const textBlock = message.content.find((b) => b.type === 'text');
    if (!textBlock || textBlock.type !== 'text') {
      throw new Error('No text response from Claude.');
    }

    const raw = parseJsonResponse<RawFinding[]>(textBlock.text);
    const findings: Finding[] = raw.map((f) => ({ uid: `issue-${nanoid(8)}`, ...f }));

    return NextResponse.json({ findings });
  } catch (err) {
    console.error('review/analyze failed', err);
    return NextResponse.json(
      { error: err instanceof Error ? err.message : 'Analysis failed.' },
      { status: 500 }
    );
  }
}

VS_APPLY_EOF_9f3a
echo "  wrote src/app/api/review/analyze/route.ts"

mkdir -p "$(dirname "src/app/page.tsx")"
cat > "src/app/page.tsx" << 'VS_APPLY_EOF_9f3a'
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

      // 2. Run the eight-concern analysis. Passing clientId lets the server
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
            {contractMeta.fileName} · {contractMeta.docType} · Reviewed against 8 standing concerns
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

VS_APPLY_EOF_9f3a
echo "  wrote src/app/page.tsx"

mkdir -p "$(dirname "src/components/layout/TopNav.tsx")"
cat > "src/components/layout/TopNav.tsx" << 'VS_APPLY_EOF_9f3a'
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

VS_APPLY_EOF_9f3a
echo "  wrote src/components/layout/TopNav.tsx"

echo "Installing new dependencies (@react-pdf/renderer, pdf-parse)..."
npm install
echo "Done. Restart your dev server (Ctrl+C, then npm run dev)."