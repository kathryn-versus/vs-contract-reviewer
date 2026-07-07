#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_view_past_results.sh
# Safe to run more than once.
set -e

# ── 1. Finding gets an optional redlineText field, so drafted redlines are ──
#      saved and don't need to be redrafted when revisiting a past review.

python3 - << 'PYEOF'
path = "src/lib/types.ts"
with open(path) as f:
    content = f.read()

if "redlineText?: string;" in content:
    print("types.ts: Finding already has redlineText — nothing to do.")
else:
    old = """export interface Finding {
  uid: string;
  concernId: number;
  concernLabel: string;
  severity: Severity;
  issueTitle: string;
  quote: string;
  location: string;
  analysis: string;
  recommendation: string;
}"""

    new = """export interface Finding {
  uid: string;
  concernId: number;
  concernLabel: string;
  severity: Severity;
  issueTitle: string;
  quote: string;
  location: string;
  analysis: string;
  recommendation: string;
  // Set once a redline is drafted for this finding and persisted back to the
  // version doc — lets a past review be reopened with its drafted redlines
  // intact instead of needing them redrafted from scratch.
  redlineText?: string;
}"""

    if old not in content:
        raise SystemExit(
            "Finding block not found as expected in src/lib/types.ts — aborting so "
            "nothing is silently corrupted. Paste me the current Finding interface "
            "and I'll fix it by hand."
        )
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print("types.ts: Finding patched with redlineText.")
PYEOF

# ── 2. firestore.ts — add getContract, getVersion, updateVersionFindings ────

mkdir -p "$(dirname "src/lib/firebase/firestore.ts")"
cat > "src/lib/firebase/firestore.ts" << 'VS_APPLY_EOF_vpr1'
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

export async function getContract(contractId: string): Promise<ContractDoc | null> {
  const snap = await getDoc(doc(db, 'contracts', contractId));
  if (!snap.exists()) return null;
  return { id: snap.id, ...(snap.data() as Omit<ContractDoc, 'id'>), createdAt: toMillis(snap.data().createdAt) };
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

export async function getVersion(contractId: string, versionId: string): Promise<VersionDoc | null> {
  const snap = await getDoc(doc(db, 'contracts', contractId, 'versions', versionId));
  if (!snap.exists()) return null;
  return { id: snap.id, ...(snap.data() as Omit<VersionDoc, 'id'>), uploadedAt: toMillis(snap.data().uploadedAt) };
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

/**
 * Updates Drive/Google Doc/report links on a SPECIFIC version, not the
 * contract as a whole — this is what lets the Library show correct links for
 * every past version instead of every version pointing at whatever the
 * latest upload happened to be.
 */
export async function updateVersionDrive(
  contractId: string,
  versionId: string,
  drive: Partial<
    Pick<
      VersionDoc,
      | 'driveFileId'
      | 'driveUrl'
      | 'driveFolderId'
      | 'driveFolderUrl'
      | 'googleDocId'
      | 'googleDocUrl'
      | 'reportHtmlUrl'
      | 'reportPdfUrl'
    >
  >
) {
  await updateDoc(doc(db, 'contracts', contractId, 'versions', versionId), drive);
}

/**
 * Persists the findings array (with any drafted redlineText merged in) back
 * to the version doc, so reopening this version's results later shows
 * previously-drafted redlines instead of needing them redrafted.
 */
export async function updateVersionFindings(contractId: string, versionId: string, findings: Finding[]) {
  await updateDoc(doc(db, 'contracts', contractId, 'versions', versionId), { findings });
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
VS_APPLY_EOF_vpr1

# ── 3. ResultsView.tsx — load saved redlines on open, persist new ones ──────

mkdir -p "$(dirname "src/components/review/ResultsView.tsx")"
cat > "src/components/review/ResultsView.tsx" << 'VS_APPLY_EOF_vpr2'
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
VS_APPLY_EOF_vpr2

# ── 4. New page: view a past review's full results ──────────────────────────

mkdir -p "$(dirname "src/app/review/[contractId]/[versionId]/page.tsx")"
cat > "src/app/review/[contractId]/[versionId]/page.tsx" << 'VS_APPLY_EOF_vpr3'
'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { AuthGuard } from '@/components/layout/AuthGuard';
import { AppShell } from '@/components/layout/AppShell';
import { ConcernIndex } from '@/components/review/ConcernIndex';
import { ResultsView } from '@/components/review/ResultsView';
import { Button } from '@/components/ui/Button';
import { getContract, getVersion, getClient } from '@/lib/firebase/firestore';
import { STANDING_CONCERNS } from '@/lib/types';
import type { ContractDoc, VersionDoc } from '@/lib/types';

// Reopens a past review straight from stored Firestore data — no re-upload
// or re-run of the Claude analysis needed. Linked from the Library's matter
// cards ("View results" per version).
export default function PastReviewPage({ params }: { params: { contractId: string; versionId: string } }) {
  return (
    <AuthGuard>
      <AppShell>
        <PastReviewView contractId={params.contractId} versionId={params.versionId} />
      </AppShell>
    </AuthGuard>
  );
}

function PastReviewView({ contractId, versionId }: { contractId: string; versionId: string }) {
  const [contract, setContract] = useState<ContractDoc | null>(null);
  const [version, setVersion] = useState<VersionDoc | null>(null);
  const [clientNotes, setClientNotes] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const [c, v] = await Promise.all([getContract(contractId), getVersion(contractId, versionId)]);
        if (cancelled) return;
        if (!c || !v) {
          setError('Could not find that review — it may have been moved or deleted.');
          return;
        }
        setContract(c);
        setVersion(v);
        const client = await getClient(c.clientId);
        if (!cancelled) setClientNotes(client?.notes ?? null);
      } catch {
        if (!cancelled) setError('Could not load that review.');
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [contractId, versionId]);

  if (error) {
    return (
      <div className="mx-auto max-w-lg py-16 text-center">
        <p className="mb-4 text-sm text-high">{error}</p>
        <Link href="/library">
          <Button>Back to Library</Button>
        </Link>
      </div>
    );
  }

  if (!contract || !version) {
    return <p className="font-mono text-sm text-ink-faint">Loading…</p>;
  }

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
          {version.fileName} · {contract.docType} · v{version.versionNumber} · Reviewed against {STANDING_CONCERNS.length}{' '}
          standing concerns
        </p>
        <Link href={`/library/${contract.clientId}`}>
          <Button>← Back to {contract.clientName}</Button>
        </Link>
      </div>
      <p className="-mt-4 mb-6 font-mono text-xs text-ink-faint">
        {contract.clientName} — {contract.projectName} ({contract.projectNumber}) · Counterparty: {contract.counterparty}
      </p>
      <ResultsView
        contract={contract}
        contractId={contractId}
        versionId={versionId}
        versionNumber={version.versionNumber}
        findings={version.findings}
        clientNotes={clientNotes}
        driveFileId={version.driveFileId}
        driveFolderId={version.driveFolderId}
        sourceFileName={version.fileName}
      />
    </div>
  );
}
VS_APPLY_EOF_vpr3

# ── 5. MatterCard.tsx — add a "View results" link per version ───────────────

mkdir -p "$(dirname "src/components/library/MatterCard.tsx")"
cat > "src/components/library/MatterCard.tsx" << 'VS_APPLY_EOF_vpr4'
'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
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
        <div className="mt-4 space-y-4 border-t border-rule pt-4">
          {versions.map((v) => (
            <div key={v.id} className="text-sm">
              <div className="flex items-center justify-between">
                <p className="text-ink">v{v.versionNumber} · {v.fileName}</p>
                <Link href={`/review/${contract.id}/${v.id}`} className="font-mono text-xs text-accent hover:underline">
                  View results
                </Link>
              </div>
              <p className="font-mono text-xs text-ink-faint">
                {new Date(v.uploadedAt).toLocaleDateString()} · uploaded by {v.uploadedBy.name}
              </p>
              {v.deltaFromPrevious && (
                <p className="mt-1 font-body text-xs text-ink-soft">Δ {v.deltaFromPrevious}</p>
              )}
              {/* Per-version Drive links — each version keeps its own, so
                  older versions still link correctly after later versions
                  are uploaded. */}
              <div className="mt-1.5 flex flex-wrap gap-x-3 gap-y-1">
                {v.driveFolderUrl && (
                  <a href={v.driveFolderUrl} target="_blank" rel="noreferrer" className="font-mono text-xs text-accent hover:underline">
                    Folder ↗
                  </a>
                )}
                {v.driveUrl && (
                  <a href={v.driveUrl} target="_blank" rel="noreferrer" className="font-mono text-xs text-accent hover:underline">
                    Source file ↗
                  </a>
                )}
                {v.googleDocUrl && (
                  <a href={v.googleDocUrl} target="_blank" rel="noreferrer" className="font-mono text-xs text-accent hover:underline">
                    Google Doc ↗
                  </a>
                )}
                {v.reportHtmlUrl && (
                  <a href={v.reportHtmlUrl} target="_blank" rel="noreferrer" className="font-mono text-xs text-accent hover:underline">
                    HTML report ↗
                  </a>
                )}
                {v.reportPdfUrl && (
                  <a href={v.reportPdfUrl} target="_blank" rel="noreferrer" className="font-mono text-xs text-accent hover:underline">
                    PDF report ↗
                  </a>
                )}
                {!v.driveUrl && !v.googleDocUrl && !v.reportHtmlUrl && !v.reportPdfUrl && (
                  <span className="font-mono text-xs text-ink-faint">No Drive links yet for this version.</span>
                )}
              </div>
            </div>
          ))}
        </div>
      )}
    </Card>
  );
}
VS_APPLY_EOF_vpr4

echo ""
echo "Done. 5 files patched/updated:"
echo "  src/lib/types.ts                       (Finding: added redlineText, patched if needed)"
echo "  src/lib/firebase/firestore.ts          (added getContract, getVersion, updateVersionFindings)"
echo "  src/components/review/ResultsView.tsx  (loads saved redlines on open, persists new ones)"
echo "  src/app/review/[contractId]/[versionId]/page.tsx (new — full past-review view)"
echo "  src/components/library/MatterCard.tsx  (added 'View results' link per version)"
echo ""
echo "Restart your dev server (Ctrl+C, then npm run dev), open Library, expand"
echo "a matter's versions, and click 'View results' on any version — including"
echo "ones from before this fix (they'll just have no drafted redlines yet)."
