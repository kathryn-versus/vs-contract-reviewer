#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_file_type_fix.sh
set -e

# ── 1. FileDropzone.tsx — accept/label become configurable ─────────────────
python3 - << 'PYEOF'
path = "src/components/intake/FileDropzone.tsx"
with open(path) as f:
    content = f.read()

if "acceptLabel" in content:
    print("FileDropzone.tsx: already configurable — nothing to do.")
else:
    old_sig = """export function FileDropzone({
  file,
  characterCount,
  onFile,
  onClear,
}: {
  file: File | null;
  characterCount: number | null;
  onFile: (file: File) => void;
  onClear: () => void;
}) {"""
    new_sig = """export function FileDropzone({
  file,
  characterCount,
  onFile,
  onClear,
  accept = '.pdf,.docx,.txt',
  acceptLabel = 'PDF · DOCX · TXT',
}: {
  file: File | null;
  characterCount: number | null;
  onFile: (file: File) => void;
  onClear: () => void;
  /** Empty string means "any file type" (matches the native <input accept>
   * behavior when the attribute is blank) — used when filing without
   * review, since no text extraction is needed so any format is fine. */
  accept?: string;
  acceptLabel?: string;
}) {"""

    old_input = '        accept=".pdf,.docx,.txt"'
    new_input = '        accept={accept}'

    old_chip = '        <Chip>PDF · DOCX · TXT</Chip>'
    new_chip = '        <Chip>{acceptLabel}</Chip>'

    missing = [l for l, n in [("sig", old_sig), ("input", old_input), ("chip", old_chip)] if n not in content]
    if missing:
        raise SystemExit(f"Expected block(s) not found in FileDropzone.tsx: {missing} — aborting.")

    content = content.replace(old_sig, new_sig).replace(old_input, new_input).replace(old_chip, new_chip)
    with open(path, "w") as f:
        f.write(content)
    print("FileDropzone.tsx: accept/acceptLabel are now props.")
PYEOF

# ── 2. IntakeForm.tsx — skip extraction + widen accept in file-only mode ───
python3 - << 'PYEOF'
path = "src/components/intake/IntakeForm.tsx"
with open(path) as f:
    content = f.read()

if "handleModeChange" in content:
    print("IntakeForm.tsx: already updated — nothing to do.")
else:
    old_handle_file = """  async function handleFile(f: File) {
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

    // Warn if this exact file name has already been reviewed somewhere —"""
    new_handle_file = """  async function handleFile(f: File) {
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

    // Warn if this exact file name has already been reviewed somewhere —"""

    old_toggle_block = """      <div className="mb-6 flex justify-center gap-2">
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
      </div>"""
    new_toggle_block = """      <div className="mb-6 flex justify-center gap-2">
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
      </div>"""

    old_dropzone = """          <FileDropzone
            file={file}
            characterCount={characterCount}
            onFile={handleFile}
            onClear={() => {
              setFile(null);
              setCharacterCount(null);
              setDocumentText('');
              setDuplicateMatches([]);
            }}
          />"""
    new_dropzone = """          <FileDropzone
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
          />"""

    missing = [
        l for l, n in [
            ("handleFile", old_handle_file),
            ("toggle buttons", old_toggle_block),
            ("FileDropzone render", old_dropzone),
        ] if n not in content
    ]
    if missing:
        raise SystemExit(
            f"Expected block(s) not found in src/components/intake/IntakeForm.tsx: {missing} "
            "— aborting. Paste me the current file and I'll fix it by hand."
        )

    content = (
        content.replace(old_handle_file, new_handle_file)
        .replace(old_toggle_block, new_toggle_block)
        .replace(old_dropzone, new_dropzone)
    )

    # Add handleModeChange itself, right before handleFile.
    anchor = "  async function handleFile(f: File) {"
    mode_change_fn = """  // Switching FROM file-only mode INTO review mode after a file was
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

"""
    if anchor not in content:
        raise SystemExit("Could not find anchor to insert handleModeChange — aborting.")
    content = content.replace(anchor, mode_change_fn + anchor)

    with open(path, "w") as f:
        f.write(content)
    print("IntakeForm.tsx: file-only mode skips extraction/type restrictions; switching back to review mode re-attempts extraction if needed.")
PYEOF

echo ""
echo "Restart your dev server and test:"
echo "  1. Switch to 'File for reference', pick a .doc (or any odd file"
echo "     type) — no red warning should appear, dropzone label should say"
echo "     'Any file type', and 'File for reference' should submit cleanly."
echo "  2. Switch to 'Run Claude review' with a .pdf/.docx/.txt — should"
echo "     still work exactly as before, including the unsupported-type"
echo "     warning for anything else."
echo ""
echo "Then commit and push (via GitHub Desktop) to deploy."
