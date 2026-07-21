'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { AuthGuard } from '@/components/layout/AuthGuard';
import { AppShell } from '@/components/layout/AppShell';
import { ConcernIndex } from '@/components/review/ConcernIndex';
import { ResultsView } from '@/components/review/ResultsView';
import { Button } from '@/components/ui/Button';
import { getContract, getVersion, getClient, listVersionsForContract } from '@/lib/firebase/firestore';
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
  const [versions, setVersions] = useState<VersionDoc[]>([]);
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
        const allVersions = await listVersionsForContract(contractId);
        if (!cancelled) setVersions(allVersions);
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

  const latestVersion = versions.reduce<VersionDoc | null>(
    (max, v) => (!max || v.versionNumber > max.versionNumber ? v : max),
    null
  );
  const isLatest = !latestVersion || latestVersion.id === version.id;

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
      {!isLatest && latestVersion && (
        <div className="mb-6 border border-accent/30 bg-high-bg px-4 py-3">
          <p className="font-mono text-xs text-ink">
            A newer version (v{latestVersion.versionNumber}) of this contract is on file.{' '}
            <Link href={`/review/${contractId}/${latestVersion.id}`} className="text-accent hover:underline">
              View it →
            </Link>
          </p>
        </div>
      )}
      {version.deltaFromPrevious && (
        <div className="mb-6 border border-rule bg-paper px-4 py-3">
          <p className="font-mono text-[11px] uppercase tracking-wide text-ink-faint">What changed in this version</p>
          <p className="mt-1 font-body text-sm text-ink-soft">{version.deltaFromPrevious}</p>
        </div>
      )}
      <ResultsView
        contract={contract}
        contractId={contractId}
        versionId={versionId}
        versionNumber={version.versionNumber}
        findings={version.findings}
        insuranceRequirements={version.insuranceRequirements ?? []}
        resolvedFindings={version.resolvedFindings ?? []}
        clientNotes={clientNotes}
        driveFileId={version.driveFileId}
        driveFolderId={version.driveFolderId}
        sourceFileName={version.fileName}
      />
    </div>
  );
}
