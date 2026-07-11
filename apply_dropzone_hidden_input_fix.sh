#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_dropzone_hidden_input_fix.sh
set -e

python3 - << 'PYEOF'
path = "src/components/intake/FileDropzone.tsx"
with open(path) as f:
    content = f.read()

if "clip: 'rect(0,0,0,0)'" in content:
    print("FileDropzone.tsx: visually-hidden fix already applied — nothing to do.")
else:
    # ── Remove the TEMP DIAGNOSTIC mount/unmount effect ─────────────────────
    old_effect = """  const [dragging, setDragging] = useState(false);
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
  );"""
    new_effect = """  const [dragging, setDragging] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  const handleFiles = useCallback(
    (files: FileList | null) => {
      const f = files?.[0];
      if (f) onFile(f);
    },
    [onFile]
  );"""

    # ── Replace display:none hidden input with a visually-hidden (but not
    # display:none) input — the likely real cause of the double-dialog bug,
    # since Chrome can mishandle .click() on a fully display:none file input
    # (the native OS picker's focus/blur handshake has nothing to attach to,
    # which on some Chrome/macOS builds causes it to reopen). "clip" hiding
    # keeps the element genuinely present in layout/focus terms while still
    # being invisible and non-interactive to the user. ─────────────────────
    old_input = """      <input
        ref={inputRef}
        type="file"
        accept={accept}
        className="hidden"
        onChange={(e) => {
          console.log('[dropzone] input onChange fired');
          handleFiles(e.target.files);
        }}
      />"""
    new_input = """      <input
        ref={inputRef}
        type="file"
        accept={accept}
        style={{
          position: 'absolute',
          width: 1,
          height: 1,
          padding: 0,
          margin: -1,
          overflow: 'hidden',
          clip: 'rect(0,0,0,0)',
          whiteSpace: 'nowrap',
          border: 0,
        }}
        onChange={(e) => {
          handleFiles(e.target.files);
        }}
      />"""

    old_click = """        onClick={(e) => {
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
        }}"""
    new_click = """        onClick={() => {
          inputRef.current?.click();
        }}"""

    missing = [
        l for l, n in [
            ("mount/unmount diagnostic effect", old_effect),
            ("hidden input", old_input),
            ("onClick diagnostic", old_click),
        ] if n not in content
    ]
    if missing:
        raise SystemExit(
            f"Expected block(s) not found in src/components/intake/FileDropzone.tsx: {missing} "
            "— aborting. Paste me the current file and I'll fix it by hand."
        )

    content = (
        content.replace(old_effect, new_effect)
        .replace(old_input, new_input)
        .replace(old_click, new_click)
    )

    # useEffect is no longer used now that the diagnostic effect is gone.
    content = content.replace(
        "import { useCallback, useEffect, useRef, useState } from 'react';",
        "import { useCallback, useRef, useState } from 'react';",
    )

    with open(path, "w") as f:
        f.write(content)
    print("FileDropzone.tsx: swapped display:none input for a visually-hidden one, removed temp diagnostics.")
PYEOF

echo ""
echo "Restart your dev server (or wait for the live deploy), then test on the"
echo "LIVE site exactly like before — click the dropzone, pick a file, and"
echo "confirm only ONE picker window opens and the file is captured on the"
echo "first try."
echo ""
echo "If it still double-opens after this, it's not the display:none issue —"
echo "next thing to check would be your Chrome version (chrome://version) in"
echo "case it's a known Chromium bug fixed in a later release."
echo ""
echo "Then commit and push (via GitHub Desktop) to deploy."
