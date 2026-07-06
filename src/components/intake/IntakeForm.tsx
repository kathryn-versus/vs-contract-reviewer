'use client';

import { useEffect, useState } from 'react';
import { Chip } from '@/components/ui/Chip';
import { Button } from '@/components/ui/Button';
import { FileDropzone } from './FileDropzone';
import { listClients } from '@/lib/firebase/firestore';
import { extractText } from '@/lib/parsing/extractText';
import type { ClientDoc, DocType } from '@/lib/types';
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
}

const DOC_TYPES: DocType[] = ['MSA', 'SOW', 'MSA+SOW', 'Other'];

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
  const [clientName, setClientName] = useState('');
  const [projectName, setProjectName] = useState('');
  const [projectNumber, setProjectNumber] = useState('');
  const [docType, setDocType] = useState<DocType>('SOW');
  const [counterparty, setCounterparty] = useState('');
  const [file, setFile] = useState<File | null>(null);
  const [documentText, setDocumentText] = useState('');
  const [characterCount, setCharacterCount] = useState<number | null>(null);
  const [parseError, setParseError] = useState<string | null>(null);

  useEffect(() => {
    listClients().then(setClients).catch(() => {});
  }, []);

  async function handleFile(f: File) {
    setFile(f);
    setCharacterCount(null);
    setParseError(null);
    try {
      const text = await extractText(f);
      setDocumentText(text);
      setCharacterCount(text.length);
    } catch (err) {
      setParseError(err instanceof Error ? err.message : 'Could not parse file.');
    }
  }

  const canSubmit =
    clientName.trim() && projectName.trim() && projectNumber.trim() && counterparty.trim() && file && characterCount;

  return (
    <div className="mx-auto max-w-2xl">
      <div className="mb-8 text-center">
        <h1 className="font-display text-3xl text-ink">Submit a contract for review</h1>
        <p className="mt-2 font-body text-sm text-ink-soft">
          The eight standing concerns will be checked automatically.
        </p>
      </div>

      <div className="mb-6 flex justify-center">
        <Chip>
          {user.displayName ?? user.email} · {user.email}
        </Chip>
      </div>

      <div className="space-y-5 rounded-sm border border-rule bg-paper p-6">
        <Field label="Client">
          <input
            list="client-options"
            value={clientName}
            onChange={(e) => setClientName(e.target.value)}
            placeholder="e.g. Walt Disney Studios"
            className="input"
          />
          <datalist id="client-options">
            {clients.map((c) => (
              <option key={c.id} value={c.name} />
            ))}
          </datalist>
        </Field>

        <div className="grid grid-cols-2 gap-4">
          <Field label="Project name">
            <input
              value={projectName}
              onChange={(e) => setProjectName(e.target.value)}
              placeholder="Moana Ocean Adventure"
              className="input"
            />
          </Field>
          <Field label="Project number">
            <input
              value={projectNumber}
              onChange={(e) => setProjectNumber(e.target.value)}
              placeholder="VS26153"
              className="input"
            />
          </Field>
        </div>

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
              onChange={(e) => setCounterparty(e.target.value)}
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
            }}
          />
          {parseError && <p className="mt-2 text-sm text-high">{parseError}</p>}
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
