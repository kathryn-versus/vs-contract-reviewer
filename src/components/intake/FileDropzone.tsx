'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
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

  // TEMP DIAGNOSTIC — remove once the double-picker bug is found.
  useEffect(() => {
    console.log('[dropzone] mounted');
    return () => console.log('[dropzone] UNMOUNTED');
  }, []);

  const handleFiles = useCallback(
    (files: FileList | null) => {
      console.log('[dropzone] handleFiles called, count:', files?.length, files?.[0]?.name);
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
    <>
      <input
        ref={inputRef}
        type="file"
        accept=".pdf,.docx,.txt"
        className="hidden"
        onChange={(e) => {
          console.log('[dropzone] input onChange fired');
          handleFiles(e.target.files);
        }}
      />
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
        onClick={(e) => {
          // TEMP DIAGNOSTIC — logs whether each firing is a real physical
          // click (isTrusted: true) or code calling .click() programmatically
          // (isTrusted: false), plus the full call stack so we can see what
          // triggered it.
          console.log(
            '[dropzone] div onClick fired — isTrusted:',
            e.isTrusted,
            'target:',
            (e.target as HTMLElement)?.tagName,
            (e.target as HTMLElement)?.className
          );
          console.trace('[dropzone] call stack');
          inputRef.current?.click();
        }}
        className={clsx(
          'flex cursor-pointer flex-col items-center justify-center gap-2 rounded-sm border-2 border-dashed px-6 py-10 text-center transition',
          dragging ? 'border-ink bg-accent-soft/20' : 'border-rule hover:border-ink-faint'
        )}
      >
        <p className="font-body text-sm text-ink">Drag and drop a contract, or click to browse</p>
        <Chip>PDF · DOCX · TXT</Chip>
      </div>
    </>
  );
}
