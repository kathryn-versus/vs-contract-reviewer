'use client';

import { useState } from 'react';
import { AuthGuard } from '@/components/layout/AuthGuard';
import { AppShell } from '@/components/layout/AppShell';
import { IntakeForm, type IntakeValues } from '@/components/intake/IntakeForm';
import { LoadingScan } from '@/components/ui/LoadingScan';
import { ResultsView } from '@/components/review/ResultsView';
import { Button } from '@/components/ui/Button';
import { useAuth } from '@/hooks/useAuth';
import {
  getOrCreateClient,
  createContract,
  addVersion,
  updateContractDrive,
  getClient,
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
  } | null>(null);

  if (!user) return null;

  async function handleSubmit(values: IntakeValues) {
    setStep('loading');
    setError(null);
    try {
      // 1. Resolve/create the client record and pull any standing notes.
      const client = await getOrCreateClient(values.clientName, user!.email ?? '');
      const clientDoc = await getClient(client.id);

      // 2. Run the eight-concern analysis.
      const analyzeRes = await fetch('/api/review/analyze', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          docType: values.docType,
          counterparty: values.counterparty,
          clientName: values.clientName,
          clientNotes: clientDoc?.notes || null,
          documentText: values.documentText,
        }),
      });
      const analyzeData = await analyzeRes.json();
      if (analyzeData.error) throw new Error(analyzeData.error);
      const newFindings: Finding[] = analyzeData.findings;

      // 3. Create the contract + first version record in Firestore.
      const contractId = await createContract({
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
      });

      const versionId = await addVersion(contractId, {
        versionNumber: 1,
        uploadedBy: { name: user!.displayName ?? user!.email ?? '', email: user!.email ?? '' },
        fileName: values.file.name,
        characterCount: values.characterCount,
        findings: newFindings,
        deltaFromPrevious: null,
        reportUrl: null,
      });

      // 4. Upload the source file to Drive (server-side route).
      try {
        const form = new FormData();
        form.append('file', values.file);
        form.append('clientName', client.name);
        form.append('projectName', values.projectName);
        form.append('projectNumber', values.projectNumber);
        const driveRes = await fetch('/api/drive/upload', { method: 'POST', body: form });
        const driveData = await driveRes.json();
        if (!driveData.error) {
          await updateContractDrive(contractId, driveData);
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
        <div className="mb-6 flex items-center justify-between">
          <div>
            <h1 className="font-display text-2xl text-ink">
              {contractMeta.clientName} — {contractMeta.projectName}
            </h1>
            <p className="font-mono text-xs text-ink-faint">
              {contractMeta.projectNumber} · {contractMeta.docType} · {contractMeta.counterparty}
            </p>
          </div>
          <Button onClick={() => setStep('intake')}>New review</Button>
        </div>
        <ResultsView
          contract={contractMeta}
          contractId={contractMeta.contractId}
          versionId={contractMeta.versionId}
          findings={findings}
          clientNotes={contractMeta.clientNotes}
        />
      </div>
    );
  }

  return null;
}
