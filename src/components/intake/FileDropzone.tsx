'use client';

import { useCallback, useRef, useState } from 'react';
import clsx from 'clsx';
import { Chip } from '@/components/ui/Chip';

export function FileDropzone({
  file,
  characterCount,
  onFile,
  onClear,
}: {
  file: File | null;
  characterCount: number | null;
  onFile: (file: File) => void;
  onClear: () => void;
}) {
  const [dragging, setDragging] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  const handleFiles = useCallback(
    (files: FileList | null) => {
      const f = files?.[0];
      if (f) onFile(f);
    },
    [onFile]
  );

  if (file) {
    return (
      <div className="flex items-center justify-between rounded-sm border border-rule bg-paper px-4 py-3">
        <div className="flex items-center gap-3">
          <div className="flex h-9 w-9 items-center justify-center rounded-sm bg-accent-soft/40 font-mono text-xs uppercase text-ink-soft">
            {file.name.split('.').pop()}
          </div>
          <div>
            <p className="font-body text-sm text-ink">{file.name}</p>
            <p className="font-mono text-xs text-ink-faint">
              {(file.size / 1024).toFixed(0)} KB
              {characterCount != null ? ` · ${characterCount.toLocaleString()} characters extracted` : ' · parsing…'}
            </p>
          </div>
        </div>
        <button onClick={onClear} className="font-mono text-xs text-ink-faint hover:text-high">
          Remove
        </button>
      </div>
    );
  }

  return (
    <div
      onDragOver={(e) => {
        e.preventDefault();
        setDragging(true);
      }}
      onDragLeave={() => setDragging(false)}
      onDrop={(e) => {
        e.preventDefault();
        setDragging(false);
        handleFiles(e.dataTransfer.files);
      }}
      onClick={() => inputRef.current?.click()}
      className={clsx(
        'flex cursor-pointer flex-col items-center justify-center gap-2 rounded-sm border-2 border-dashed px-6 py-10 text-center transition',
        dragging ? 'border-ink bg-accent-soft/20' : 'border-rule hover:border-ink-faint'
      )}
    >
      <input
        ref={inputRef}
        type="file"
        accept=".pdf,.docx,.txt"
        className="hidden"
        onChange={(e) => handleFiles(e.target.files)}
      />
      <p className="font-body text-sm text-ink">Drag and drop a contract, or click to browse</p>
      <Chip>PDF · DOCX · TXT</Chip>
    </div>
  );
}
