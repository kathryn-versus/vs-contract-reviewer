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
  // Defaults to true — filing without review is now the default path;
  // a reviewer has to actively click "Run Claude review" to opt into
  // analysis, rather than the other way around.
  const [skipReview, setSkipReview] = useState(true);

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

  // Switching FROM file-only mode INTO review mode after a file was
  // already picked needs to retroactively attempt extraction, since
  // file-only mode skips it — otherwise review mode would be stuck unable
  // to submit (it requires characterCount) without the file being re-picked.
  async function handleModeChange(next: boolean) {
    setSkipReview(next);
    if (!next && file && characterCount == null) {
      try {
        const text = await extractText(file);
        setDocumentText(text);
        setCharacterCount(text.length);
        setParseError(null);
      } catch (err) {
        setParseError(err instanceof Error ? err.message : 'Could not parse file.');
      }
    }
  }

  async function handleFile(f: File) {
    setFile(f);
    setCharacterCount(null);
    setParseError(null);
    setDuplicateMatches([]);

    // Filing without review never sends text to Claude, so there's nothing
    // to extract and no reason to reject unusual file types (old .doc,
    // scanned PDFs that won't parse cleanly, etc.) — only attempt/require
    // extraction when an actual review is going to run.
    if (!skipReview) {
      try {
        const text = await extractText(f);
        setDocumentText(text);
        setCharacterCount(text.length);
      } catch (err) {
        setParseError(err instanceof Error ? err.message : 'Could not parse file.');
      }
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
          onClick={() => handleModeChange(false)}
          className={
            'rounded-full border px-3 py-1 font-mono text-xs uppercase tracking-wide transition ' +
            (!skipReview ? 'border-ink bg-ink text-paper' : 'border-rule text-ink-faint hover:border-ink-faint')
          }
        >
          Run Claude review
        </button>
        <button
          type="button"
          onClick={() => handleModeChange(true)}
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
            accept={skipReview ? '' : '.pdf,.docx,.txt'}
            acceptLabel={skipReview ? 'Any file type' : 'PDF · DOCX · TXT'}
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
