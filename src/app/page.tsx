'use client';

import { Suspense, useState } from 'react';
import Link from 'next/link';
import { useSearchParams } from 'next/navigation';
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
  updateVersionDrive,
  getClient,
  getNextVersionNumber,
  listVersionsForContract,
  addExecutedAgreement,
} from '@/lib/firebase/firestore';
import { STANDING_CONCERNS } from '@/lib/types';
import type { Finding, InsuranceRequirement, ResolvedFinding, DocType } from '@/lib/types';

type Step = 'intake' | 'loading' | 'results' | 'filed' | 'error';

export default function ReviewerPage() {
  return (
    <AuthGuard>
      <AppShell>
        {/* useSearchParams() (used below to pre-fill the client name when
            arriving via a client page's "+ Upload contract" link) requires a
            Suspense boundary for static generation to succeed in production —
            same fix as /login. */}
        <Suspense fallback={null}>
          <ReviewerFlow />
        </Suspense>
      </AppShell>
    </AuthGuard>
  );
}

function ReviewerFlow() {
  const { user } = useAuth();
  const searchParams = useSearchParams();
  const initialClientName = searchParams.get('clientName') ?? undefined;
  const [step, setStep] = useState<Step>('intake');
  const [error, setError] = useState<string | null>(null);
  const [findings, setFindings] = useState<Finding[]>([]);
  const [insuranceRequirements, setInsuranceRequirements] = useState<InsuranceRequirement[]>([]);
  const [resolvedFindings, setResolvedFindings] = useState<ResolvedFinding[]>([]);
  const [contractMeta, setContractMeta] = useState<{
    contractId: string;
    versionId: string;
    versionNumber: number;
    clientName: string;
    projectName: string;
    projectNumber: string;
    docType: DocType;
    counterparty: string;
    clientNotes: string | null;
    fileName: string;
    driveFileId: string | null;
    driveFolderId: string | null;
  } | null>(null);
  const [filedInfo, setFiledInfo] = useState<{
    clientId: string;
    clientName: string;
    projectName: string;
    projectNumber: string;
    driveFolderUrl: string | null;
    markExecuted: boolean;
  } | null>(null);

  if (!user) return null;

  async function handleSubmit(values: IntakeValues) {
    setStep('loading');
    setError(null);
    try {
      // 1. Resolve/create the client record and pull any standing notes.
      const client = await getOrCreateClient(values.clientName, user!.email ?? '');
      const clientDoc = await getClient(client.id);

      // 2. Determine whether this is a new version of an existing matter —
      //    resolved using existingContractId directly (a brand-new matter's
      //    contractId doesn't exist yet) so the prior version, if any, is
      //    known BEFORE running analysis below.
      const isExistingMatter = Boolean(values.existingContractId);
      let priorLatest: Awaited<ReturnType<typeof listVersionsForContract>>[number] | null = null;
      if (isExistingMatter) {
        const priorVersions = await listVersionsForContract(values.existingContractId!);
        priorLatest = priorVersions.reduce<typeof priorVersions[number] | null>(
          (max, v) => (!max || v.versionNumber > max.versionNumber ? v : max),
          null
        );
      }
      const previousDriveFileId = priorLatest?.driveFileId ?? null;

      // 3. Run the standing-concerns analysis — skipped entirely when
      //    filing for reference only, since nothing needs to go to Claude.
      //    When there's a previous version on file, passing its Drive file
      //    and findings switches this into a delta-aware review: Claude
      //    confirms what's resolved vs. still open and only flags what's
      //    genuinely new, instead of a blind fresh pass every time.
      let newFindings: Finding[] = [];
      let newInsurance: InsuranceRequirement[] = [];
      let newResolvedFindings: ResolvedFinding[] = [];
      if (!values.skipReview) {
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
            previousDriveFileId,
            previousFindings: priorLatest?.findings ?? null,
          }),
        });
        const analyzeData = await analyzeRes.json();
        if (analyzeData.error) throw new Error(analyzeData.error);
        newFindings = analyzeData.findings;
        newInsurance = analyzeData.insuranceRequirements ?? [];
        newResolvedFindings = analyzeData.resolvedFindings ?? [];
      }

      // 4. Attach to the existing matter if one was picked, otherwise create
      //    a new contract + first version record in Firestore.
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
        insuranceRequirements: newInsurance,
        resolvedFindings: newResolvedFindings,
        deltaFromPrevious: null,
        reviewed: !values.skipReview,
        // Populated below once the Drive upload (and later, Google Docs /
        // report actions from the results screen) succeed.
        driveFileId: null,
        driveUrl: null,
        driveFolderId: null,
        driveFolderUrl: null,
        googleDocId: null,
        googleDocUrl: null,
        reportHtmlUrl: null,
        reportPdfUrl: null,
      });

      // 5. Upload the source file to Drive (server-side route). For a second
      //    (or later) version of an existing matter, suffix the filename so
      //    it doesn't collide with the prior version already in that folder.
      //    Links are saved on BOTH the contract (a "latest version" pointer,
      //    used e.g. for MSA context auto-pull) and this specific version
      //    (so the Library can show correct links for every past version,
      //    not just whichever was uploaded most recently).
      let driveFileId: string | null = null;
      let driveUrl: string | null = null;
      let driveFolderId: string | null = null;
      let driveFolderUrl: string | null = null;
      try {
        const form = new FormData();
        form.append('file', values.file);
        form.append('clientName', client.name);
        form.append('projectName', values.projectName);
        form.append('projectNumber', values.projectNumber);
        form.append('docType', values.docType);
        if (versionNumber > 1) form.append('versionSuffix', `v${versionNumber}`);
        const driveRes = await fetch('/api/drive/upload', { method: 'POST', body: form });
        const driveData = await driveRes.json();
        if (!driveData.error) {
          await updateContractDrive(contractId, driveData);
          await updateVersionDrive(contractId, versionId, {
            driveFileId: driveData.driveFileId ?? null,
            driveUrl: driveData.driveUrl ?? null,
            driveFolderId: driveData.driveFolderId ?? null,
            driveFolderUrl: driveData.driveFolderUrl ?? null,
          });
          driveFileId = driveData.driveFileId ?? null;
          driveUrl = driveData.driveUrl ?? null;
          driveFolderId = driveData.driveFolderId ?? null;
          driveFolderUrl = driveData.driveFolderUrl ?? null;
        }
      } catch {
        // Drive failures shouldn't block the reviewer from seeing results.
      }

      // Flagged as a fully executed/signed copy — record it as an executed
      // agreement on the client too, reusing the SAME Drive file/location
      // just uploaded above rather than uploading a second copy through the
      // separate executed-agreement route. Non-fatal: a failure here
      // shouldn't block filing from completing.
      if (values.markExecuted && values.skipReview && driveFileId) {
        try {
          await addExecutedAgreement(client.id, {
            docType: values.docType,
            label: '',
            driveFileId,
            driveUrl: driveUrl ?? '',
            driveFolderUrl,
            contractId,
            projectNumber: values.projectNumber,
            projectName: values.projectName,
            executedDate: null,
            uploadedBy: { name: user!.displayName ?? user!.email ?? '', email: user!.email ?? '' },
          });
        } catch {
          // Non-fatal — the matter/version itself already filed successfully.
        }
      }

      // Fire-and-forget: compare this version's text against the previous
      // one and save a short "what changed" summary onto deltaFromPrevious,
      // shown on the matter card and the review page. Non-blocking so it
      // never delays getting to results, and skipped entirely if there's no
      // previous version or either upload didn't make it to Drive.
      if (isExistingMatter && previousDriveFileId && driveFileId) {
        fetch('/api/review/version-delta', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ contractId, versionId, previousDriveFileId, newDriveFileId: driveFileId }),
        }).catch(() => {});
      }

      if (values.skipReview) {
        // No analysis ran, so skip the severity-counts email too — it would
        // otherwise misleadingly read as "0 issues found" rather than "not
        // reviewed at all".
        setFiledInfo({
          clientId: client.id,
          clientName: client.name,
          projectName: values.projectName,
          projectNumber: values.projectNumber,
          driveFolderUrl,
          markExecuted: values.markExecuted && values.skipReview,
        });
        setStep('filed');
        return;
      }

      // 6. Fire the email notification (recipients controlled server-side by env vars).
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
      setInsuranceRequirements(newInsurance);
      setResolvedFindings(newResolvedFindings);
      setContractMeta({
        contractId,
        versionId,
        versionNumber,
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
    return <IntakeForm user={user} onSubmit={handleSubmit} submitting={false} initialClientName={initialClientName} />;
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

  if (step === 'filed' && filedInfo) {
    return (
      <div className="mx-auto max-w-lg py-16 text-center">
        <h1 className="font-display text-2xl text-ink">Filed for reference</h1>
        <p className="mt-3 font-body text-sm text-ink-soft">
          {filedInfo.projectName} ({filedInfo.projectNumber}) was saved to Drive and filed under{' '}
          {filedInfo.clientName} — no Claude review was run.
          {filedInfo.markExecuted ? ' Also added to this client\'s Executed Agreements.' : ''}
        </p>
        <div className="mt-6 flex flex-wrap justify-center gap-3">
          {filedInfo.driveFolderUrl && (
            <a href={filedInfo.driveFolderUrl} target="_blank" rel="noopener noreferrer">
              <Button variant="ghost">Open in Drive</Button>
            </a>
          )}
          <Link href={`/library/${filedInfo.clientId}`}>
            <Button variant="ghost">View client</Button>
          </Link>
          <Button variant="primary" onClick={() => setStep('intake')}>
            + Add another
          </Button>
        </div>
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
          insuranceRequirements={insuranceRequirements}
          resolvedFindings={resolvedFindings}
          versionNumber={contractMeta.versionNumber}
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
