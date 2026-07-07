#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_file_without_review.sh
set -e

# ── 1. src/lib/types.ts — VersionDoc gets an optional `reviewed` flag ───────
python3 - << 'PYEOF'
path = "src/lib/types.ts"
with open(path) as f:
    content = f.read()

if "reviewed?: boolean" in content:
    print("types.ts: already has reviewed flag — nothing to do.")
else:
    old = """  reportHtmlUrl: string | null;
  reportPdfUrl: string | null;
}"""
    new = """  reportHtmlUrl: string | null;
  reportPdfUrl: string | null;
  // Undefined/missing is treated as true (reviewed) — every version created
  // before this field existed went through Claude analysis, so there's no
  // migration needed for old docs. Only explicitly set to false for matters
  // filed via "File for reference (no review)".
  reviewed?: boolean;
}"""
    if old not in content:
        raise SystemExit("Expected VersionDoc closing block not found in src/lib/types.ts — aborting.")
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print("types.ts: added VersionDoc.reviewed.")
PYEOF

# ── 2. src/components/intake/IntakeForm.tsx — add the review/file toggle ───
cat > "src/components/intake/IntakeForm.tsx" << 'VS_APPLY_EOF_intake'
'use client';

import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { Chip } from '@/components/ui/Chip';
import { Button } from '@/components/ui/Button';
import { Combobox } from '@/components/ui/Combobox';
import { FileDropzone } from './FileDropzone';
import { listClients, listAllContracts, getContract, findContractsByFileName } from '@/lib/firebase/firestore';
import { extractText } from '@/lib/parsing/extractText';
import { STANDING_CONCERNS } from '@/lib/types';
import type { ClientDoc, ContractDoc, DocType, VersionDoc } from '@/lib/types';
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
  /** When true, skips Claude analysis entirely — just files the contract to
   * Drive and tracks it as a matter for reference (e.g. an already-executed
   * contract, an amendment, an insurance cert). */
  skipReview: boolean;
}

const DOC_TYPES: DocType[] = ['MSA', 'SOW', 'MSA+SOW', 'Other'];

interface DuplicateMatch {
  contractId: string;
  version: VersionDoc;
  contract: ContractDoc;
}

export function IntakeForm({
  user,
  onSubmit,
  submitting,
  initialClientName,
}: {
  user: User;
  onSubmit: (values: IntakeValues) => void;
  submitting: boolean;
  /** Pre-fills the Client field — used when jumping here from a client's own
   * page via "+ Upload contract", so the client doesn't need to be
   * re-selected. */
  initialClientName?: string;
}) {
  const [clients, setClients] = useState<ClientDoc[]>([]);
  const [allContracts, setAllContracts] = useState<ContractDoc[]>([]);
  const [clientName, setClientName] = useState(initialClientName ?? '');
  const [projectName, setProjectName] = useState('');
  const [projectNumber, setProjectNumber] = useState('');
  const [docType, setDocType] = useState<DocType>('SOW');
  const [counterparty, setCounterparty] = useState('');
  const [counterpartyEdited, setCounterpartyEdited] = useState(false);
  const [file, setFile] = useState<File | null>(null);
  const [documentText, setDocumentText] = useState('');
  const [characterCount, setCharacterCount] = useState<number | null>(null);
  const [parseError, setParseError] = useState<string | null>(null);
  const [duplicateMatches, setDuplicateMatches] = useState<DuplicateMatch[]>([]);
  const [skipReview, setSkipReview] = useState(false);

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
    setDuplicateMatches([]);
    try {
      const text = await extractText(f);
      setDocumentText(text);
      setCharacterCount(text.length);
    } catch (err) {
      setParseError(err instanceof Error ? err.message : 'Could not parse file.');
    }

    // Warn if this exact file name has already been reviewed somewhere —
    // catches accidentally re-uploading (or uploading under the wrong
    // client/job) a contract that's already on file. Non-fatal: failures
    // here shouldn't block the upload itself.
    try {
      const matches = await findContractsByFileName(f.name);
      const withContracts = await Promise.all(
        matches
          // Skip the job the reviewer already explicitly selected — adding a
          // new version to the SAME matter is the normal versioning flow,
          // not a duplicate.
          .filter((m) => m.contractId !== selectedContractId)
          .map(async (m) => ({ ...m, contract: await getContract(m.contractId) }))
      );
      setDuplicateMatches(withContracts.filter((m): m is DuplicateMatch => Boolean(m.contract)));
    } catch {
      // Non-fatal.
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
    // A "file for reference" upload doesn't need text extraction to have
    // succeeded — nothing is fed to Claude, so a scanned/unparsable PDF can
    // still be filed. A normal review still requires extracted text.
    (skipReview || characterCount) &&
    (selectedContractId || creatingNewJob);

  return (
    <div className="mx-auto max-w-2xl">
      <div className="mb-6 text-center">
        <h1 className="font-display text-3xl text-ink">Submit a contract for review</h1>
        <p className="mt-2 font-body text-sm text-ink-soft">
          {skipReview
            ? 'This will be saved to Drive and filed under the client for reference — no automatic review will run.'
            : `The ${STANDING_CONCERNS.length} standing concerns will be checked automatically.`}
        </p>
      </div>
      <div className="mb-6 flex justify-center gap-2">
        <button
          type="button"
          onClick={() => setSkipReview(false)}
          className={
            'rounded-full border px-3 py-1 font-mono text-xs uppercase tracking-wide transition ' +
            (!skipReview ? 'border-ink bg-ink text-paper' : 'border-rule text-ink-faint hover:border-ink-faint')
          }
        >
          Run Claude review
        </button>
        <button
          type="button"
          onClick={() => setSkipReview(true)}
          className={
            'rounded-full border px-3 py-1 font-mono text-xs uppercase tracking-wide transition ' +
            (skipReview ? 'border-ink bg-ink text-paper' : 'border-rule text-ink-faint hover:border-ink-faint')
          }
        >
          File for reference (no review)
        </button>
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
              setDuplicateMatches([]);
            }}
          />
          {parseError && (
            <p className="mt-2 text-sm text-high">
              {parseError}
              {skipReview && ' — filing without review doesn\'t need the text extracted, so you can still submit.'}
            </p>
          )}
          {duplicateMatches.length > 0 && (
            <div className="mt-2 rounded-sm border border-med bg-med-bg/40 p-3">
              <p className="font-mono text-[11px] uppercase tracking-wide text-med">
                Possible duplicate — this file name is already on file
              </p>
              <ul className="mt-1.5 space-y-1">
                {duplicateMatches.map((m) => (
                  <li key={m.version.id}>
                    <Link
                      href={`/review/${m.contractId}/${m.version.id}`}
                      className="font-mono text-xs text-accent hover:underline"
                    >
                      {m.contract.clientName} — {m.contract.projectNumber} — {m.contract.projectName} (v
                      {m.version.versionNumber}) →
                    </Link>
                  </li>
                ))}
              </ul>
              <p className="mt-1.5 font-body text-xs text-ink-soft">
                If this is the same contract, open it above instead of running a new review. If it is genuinely
                different (e.g. a same-named file for a different job), you can ignore this and continue.
              </p>
            </div>
          )}
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
              skipReview,
            })
          }
        >
          {submitting ? (skipReview ? 'Filing…' : 'Running review…') : skipReview ? 'File for reference' : 'Run Review'}
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
VS_APPLY_EOF_intake
echo "Wrote src/components/intake/IntakeForm.tsx"

# ── 3. src/app/page.tsx — branch on skipReview, add a "filed" confirmation ──
cat > "src/app/page.tsx" << 'VS_APPLY_EOF_page'
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
} from '@/lib/firebase/firestore';
import { STANDING_CONCERNS } from '@/lib/types';
import type { Finding, DocType } from '@/lib/types';

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
  } | null>(null);

  if (!user) return null;

  async function handleSubmit(values: IntakeValues) {
    setStep('loading');
    setError(null);
    try {
      // 1. Resolve/create the client record and pull any standing notes.
      const client = await getOrCreateClient(values.clientName, user!.email ?? '');
      const clientDoc = await getClient(client.id);

      // 2. Run the standing-concerns analysis — skipped entirely when
      //    filing for reference only, since nothing needs to go to Claude.
      let newFindings: Finding[] = [];
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
          }),
        });
        const analyzeData = await analyzeRes.json();
        if (analyzeData.error) throw new Error(analyzeData.error);
        newFindings = analyzeData.findings;
      }

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

      // 4. Upload the source file to Drive (server-side route). For a second
      //    (or later) version of an existing matter, suffix the filename so
      //    it doesn't collide with the prior version already in that folder.
      //    Links are saved on BOTH the contract (a "latest version" pointer,
      //    used e.g. for MSA context auto-pull) and this specific version
      //    (so the Library can show correct links for every past version,
      //    not just whichever was uploaded most recently).
      let driveFileId: string | null = null;
      let driveFolderId: string | null = null;
      let driveFolderUrl: string | null = null;
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
          await updateVersionDrive(contractId, versionId, {
            driveFileId: driveData.driveFileId ?? null,
            driveUrl: driveData.driveUrl ?? null,
            driveFolderId: driveData.driveFolderId ?? null,
            driveFolderUrl: driveData.driveFolderUrl ?? null,
          });
          driveFileId = driveData.driveFileId ?? null;
          driveFolderId = driveData.driveFolderId ?? null;
          driveFolderUrl = driveData.driveFolderUrl ?? null;
        }
      } catch {
        // Drive failures shouldn't block the reviewer from seeing results.
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
        });
        setStep('filed');
        return;
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
VS_APPLY_EOF_page
echo "Wrote src/app/page.tsx"

# ── 4. src/components/library/MatterCard.tsx — show "Filed — not reviewed" ──
cat > "src/components/library/MatterCard.tsx" << 'VS_APPLY_EOF_mattercard'
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
  // reviewed is optional — missing/undefined means true (see types.ts), so
  // only an explicit false marks a matter filed without review.
  const latestUnreviewed = latest ? latest.reviewed === false : false;
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
          {latestUnreviewed ? (
            <span className="rounded-full border border-rule px-2 py-0.5 font-mono text-[10px] uppercase tracking-wide text-ink-faint">
              Filed — not reviewed
            </span>
          ) : (
            counts && (
              <div className="flex gap-1">
                {counts.high > 0 && <SeverityBadge severity="high" />}
                {counts.medium > 0 && <SeverityBadge severity="medium" />}
                {counts.low > 0 && <SeverityBadge severity="low" />}
              </div>
            )
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
                {v.reviewed === false ? (
                  <span className="font-mono text-xs text-ink-faint">Filed — not reviewed</span>
                ) : (
                  <Link href={`/review/${contract.id}/${v.id}`} className="font-mono text-xs text-accent hover:underline">
                    View results
                  </Link>
                )}
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
VS_APPLY_EOF_mattercard
echo "Wrote src/components/library/MatterCard.tsx"

echo ""
echo "Done. Restart your dev server and test:"
echo "  1. Start a new upload, switch to 'File for reference (no review)',"
echo "     fill in client/job/file, submit — should land on a 'Filed for"
echo "     reference' confirmation instead of results."
echo "  2. Check that client's Library page — the matter should show a"
echo "     'Filed — not reviewed' badge instead of severity counts."
echo "  3. Confirm a normal 'Run Claude review' upload still works exactly"
echo "     as before."
echo ""
echo "Then commit and push (via GitHub Desktop) to trigger a new rollout."
