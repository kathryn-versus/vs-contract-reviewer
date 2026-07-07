#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_dropzone_diagnostic.sh
# TEMPORARY — adds console logging so we can see exactly what's firing when
# the Finder dialog opens twice. Not a fix by itself.
set -e

mkdir -p "$(dirname "src/components/intake/FileDropzone.tsx")"
cat > "src/components/intake/FileDropzone.tsx" << 'VS_APPLY_EOF_diag1'
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
        onClick={() => {
          console.count('[dropzone] div onClick fired');
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
VS_APPLY_EOF_diag1

echo ""
echo "Done. 1 file temporarily instrumented: src/components/intake/FileDropzone.tsx"
echo ""
echo "Next steps:"
echo "  1. Restart your dev server (Ctrl+C, then npm run dev)."
echo "  2. Open the app in your browser, then open DevTools Console:"
echo "     - Chrome/Edge: Cmd+Option+J"
echo "     - Safari: Cmd+Option+C (enable Develop menu first if needed: Safari > Settings > Advanced > Show Develop menu)"
echo "  3. Click the upload area to trigger the Finder dialog."
echo "  4. Select your test PDF."
echo "  5. Copy everything that appears in the Console (from clicking through selecting) and paste it back to me."
echo ""
echo "This is temporary instrumentation only — once we find the cause I'll give you a clean fix that removes this logging."
