#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_duplicate_filename_check.sh
set -e

# ── 1. firestore.ts — add findContractsByFileName (collection-group query) ──

python3 - << 'PYEOF'
path = "src/lib/firebase/firestore.ts"
with open(path) as f:
    content = f.read()

if "findContractsByFileName" in content:
    print("firestore.ts: findContractsByFileName already present — nothing to do.")
else:
    old_import = """import {
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
} from 'firebase/firestore';"""

    new_import = """import {
  collection,
  collectionGroup,
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
} from 'firebase/firestore';"""

    if old_import not in content:
        raise SystemExit("Expected firestore.ts import block not found — aborting. Paste me the current file and I'll fix it by hand.")
    content = content.replace(old_import, new_import)

    anchor = "export async function getContract(contractId: string): Promise<ContractDoc | null> {"
    if anchor not in content:
        raise SystemExit("getContract anchor not found in firestore.ts — aborting. Paste me the current file and I'll fix it by hand.")

    addition = """/**
 * Finds every version, across every contract, uploaded with this exact file
 * name — used by the intake form to warn a reviewer before they accidentally
 * re-review a contract that's already on file. A collectionGroup query, so
 * it searches every contract's versions subcollection at once rather than
 * needing to know which contract to look in ahead of time.
 */
export async function findContractsByFileName(
  fileName: string
): Promise<{ contractId: string; version: VersionDoc }[]> {
  const snap = await getDocs(query(collectionGroup(db, 'versions'), where('fileName', '==', fileName)));
  return snap.docs
    .filter((d) => d.ref.parent.parent)
    .map((d) => ({
      contractId: d.ref.parent.parent!.id,
      version: { id: d.id, ...(d.data() as Omit<VersionDoc, 'id'>), uploadedAt: toMillis(d.data().uploadedAt) },
    }));
}

""" + anchor

    content = content.replace(anchor, addition, 1)
    with open(path, "w") as f:
        f.write(content)
    print("firestore.ts: added findContractsByFileName.")
PYEOF

# ── 2. IntakeForm.tsx — check on file select, show a warning + link ────────

mkdir -p "$(dirname "src/components/intake/IntakeForm.tsx")"
cat > "src/components/intake/IntakeForm.tsx" << 'VS_APPLY_EOF_dup1'
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
}: {
  user: User;
  onSubmit: (values: IntakeValues) => void;
  submitting: boolean;
}) {
  const [clients, setClients] = useState<ClientDoc[]>([]);
  const [allContracts, setAllContracts] = useState<ContractDoc[]>([]);
  const [clientName, setClientName] = useState('');
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
    characterCount &&
    (selectedContractId || creatingNewJob);

  return (
    <div className="mx-auto max-w-2xl">
      <div className="mb-8 text-center">
        <h1 className="font-display text-3xl text-ink">Submit a contract for review</h1>
        <p className="mt-2 font-body text-sm text-ink-soft">
          The {STANDING_CONCERNS.length} standing concerns will be checked automatically.
        </p>
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
          {parseError && <p className="mt-2 text-sm text-high">{parseError}</p>}
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
                If this is the same contract, open it above instead of running a new review. If it's genuinely
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
            })
          }
        >
          {submitting ? 'Running review…' : 'Run Review'}
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
VS_APPLY_EOF_dup1

# ── 3. firestore.indexes.json — add a collection-group index for the new query ─
#      (single-field equality queries are usually auto-indexed even for
#      collectionGroup, but Firestore has been known to require this scope to
#      be explicitly enabled the first time — if you hit a "requires an
#      index" error the first time you use this feature, it's the same fix as
#      before: click the link in the error to create it in one click.)

python3 - << 'PYEOF'
import json
path = "firestore.indexes.json"
with open(path) as f:
    data = json.load(f)

target = {
    "collectionGroup": "versions",
    "queryScope": "COLLECTION_GROUP",
    "fields": [{"fieldPath": "fileName", "order": "ASCENDING"}],
}

already = any(
    idx.get("collectionGroup") == "versions"
    and idx.get("queryScope") == "COLLECTION_GROUP"
    and idx.get("fields") == target["fields"]
    for idx in data.get("indexes", [])
)

if already:
    print("firestore.indexes.json: fileName index already present — nothing to do.")
else:
    data.setdefault("indexes", []).append(target)
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    print("firestore.indexes.json: added fileName collection-group index.")
PYEOF

echo ""
echo "Done. 3 files patched/updated:"
echo "  src/lib/firebase/firestore.ts   (added findContractsByFileName)"
echo "  src/components/intake/IntakeForm.tsx  (duplicate-filename warning + link)"
echo "  firestore.indexes.json          (index for the new query, just in case)"
echo ""
echo "Restart your dev server (Ctrl+C, then npm run dev) and try uploading a"
echo "file name you've already reviewed before. If you see a 'query requires"
echo "an index' error in the terminal the first time, click the link it gives"
echo "you in the Firebase Console to create it (same one-click fix as the"
echo "earlier Firestore index issue) — after that it won't happen again."
