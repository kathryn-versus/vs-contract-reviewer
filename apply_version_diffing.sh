#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_version_diffing.sh
set -e

# ── 1. Shared text-extraction helper (deduped out of msaContext.ts) ────────
if [ -f src/lib/drive/extractDocText.ts ]; then
  echo "extractDocText.ts: already exists — nothing to do."
else
  cat > src/lib/drive/extractDocText.ts << 'EOF'
import 'server-only';

/**
 * Extracts plain text from a downloaded Drive file's raw bytes, based on
 * file extension/mimeType. Shared by anything that needs a Drive file's
 * text server-side (MSA context, version-to-version diffing) — returns null
 * (never throws) for unsupported formats like native Google Docs, since
 * callers treat missing text as "nothing to compare/pull" rather than a
 * hard failure.
 */
export async function extractDocText(buffer: Buffer, mimeType: string, name: string): Promise<string | null> {
  const lower = name.toLowerCase();

  if (lower.endsWith('.pdf') || mimeType.includes('pdf')) {
    const pdfParse = (await import('pdf-parse')).default;
    const result = await pdfParse(buffer);
    return result.text;
  }

  if (lower.endsWith('.docx') || mimeType.includes('officedocument.wordprocessingml')) {
    const mammoth = await import('mammoth');
    const result = await mammoth.extractRawText({ buffer });
    return result.value;
  }

  if (lower.endsWith('.txt') || mimeType.startsWith('text/')) {
    return buffer.toString('utf-8');
  }

  return null;
}
EOF
  echo "Wrote src/lib/drive/extractDocText.ts"
fi

# ── 2. msaContext.ts — use the shared helper instead of its own copy ───────
python3 - << 'PYEOF'
path = "src/lib/drive/msaContext.ts"
with open(path) as f:
    content = f.read()

if "extractDocText" in content:
    print("msaContext.ts: already using the shared helper — nothing to do.")
else:
    old_imports = """import 'server-only';
import { adminDb } from '@/lib/firebase/admin';
import { downloadFileBuffer } from './client';"""
    new_imports = """import 'server-only';
import { adminDb } from '@/lib/firebase/admin';
import { downloadFileBuffer } from './client';
import { extractDocText } from './extractDocText';"""

    old_call = """    const { buffer, mimeType, name } = await downloadFileBuffer(driveFileId);
    const text = await extractText(buffer, mimeType, name);
    return text ? text.slice(0, MAX_MSA_CHARS) : null;"""
    new_call = """    const { buffer, mimeType, name } = await downloadFileBuffer(driveFileId);
    const text = await extractDocText(buffer, mimeType, name);
    return text ? text.slice(0, MAX_MSA_CHARS) : null;"""

    old_fn = """
async function extractText(buffer: Buffer, mimeType: string, name: string): Promise<string | null> {
  const lower = name.toLowerCase();

  if (lower.endsWith('.pdf') || mimeType.includes('pdf')) {
    const pdfParse = (await import('pdf-parse')).default;
    const result = await pdfParse(buffer);
    return result.text;
  }

  if (lower.endsWith('.docx') || mimeType.includes('officedocument.wordprocessingml')) {
    const mammoth = await import('mammoth');
    const result = await mammoth.extractRawText({ buffer });
    return result.value;
  }

  if (lower.endsWith('.txt') || mimeType.startsWith('text/')) {
    return buffer.toString('utf-8');
  }

  // Native Google Docs (e.g. a duplicated copy) aren't binary-downloadable via
  // alt=media in a plain-text-friendly way here — skip rather than error.
  return null;
}"""

    missing = [l for l, n in [("imports", old_imports), ("call site", old_call), ("local extractText fn", old_fn)] if n not in content]
    if missing:
        raise SystemExit(f"Expected block(s) not found in msaContext.ts: {missing} — aborting.")

    content = content.replace(old_imports, new_imports).replace(old_call, new_call).replace(old_fn, "")
    with open(path, "w") as f:
        f.write(content)
    print("msaContext.ts: now uses the shared extractDocText helper.")
PYEOF

# ── 3. prompts.ts — add buildVersionDeltaPrompt ────────────────────────────
python3 - << 'PYEOF'
path = "src/lib/claude/prompts.ts"
with open(path) as f:
    content = f.read()

if "buildVersionDeltaPrompt" in content:
    print("prompts.ts: buildVersionDeltaPrompt already present — nothing to do.")
else:
    anchor = '''Respond conversationally but concretely — when asked for revised language,
give exact clause text the user can paste into a redline.`;
}'''
    addition = '''

export function buildVersionDeltaPrompt(params: { previousText: string; newText: string }): string {
  return `${STUDIO_IDENTITY}

You are comparing two versions of the same contract document to summarize
what changed for a producer who doesn't have time to reread the whole thing.

PREVIOUS VERSION
"""
${params.previousText.slice(0, 60_000)}
"""

NEW VERSION
"""
${params.newText.slice(0, 60_000)}
"""

INSTRUCTIONS
- If the new version is substantively identical to the previous one (only
  formatting, whitespace, or non-substantive wording differs), respond with
  exactly: "No substantive changes from the previous version."
- Otherwise, summarize what changed in 1-3 sentences — focus on material
  terms (payment, scope, dates, deliverables, termination, liability) that a
  producer would actually care about. Do not describe every wording tweak.

Return plain text only — no JSON, no markdown, no preamble.`;
}'''

    if anchor not in content:
        raise SystemExit("Expected end-of-file anchor not found in prompts.ts — aborting.")
    content = content.replace(anchor, anchor + addition)
    with open(path, "w") as f:
        f.write(content)
    print("prompts.ts: added buildVersionDeltaPrompt.")
PYEOF

# ── 4. New API route: /api/review/version-delta ────────────────────────────
mkdir -p src/app/api/review/version-delta
if [ -f src/app/api/review/version-delta/route.ts ]; then
  echo "version-delta route: already exists — nothing to do."
else
  cat > src/app/api/review/version-delta/route.ts << 'EOF'
import { NextRequest, NextResponse } from 'next/server';
import { claude, CLAUDE_MODEL } from '@/lib/claude/client';
import { buildVersionDeltaPrompt } from '@/lib/claude/prompts';
import { downloadFileBuffer } from '@/lib/drive/client';
import { extractDocText } from '@/lib/drive/extractDocText';
import { adminDb } from '@/lib/firebase/admin';

// Fire-and-forget from the intake flow after a new version's Drive upload
// succeeds — compares it against the immediately-prior version's file and
// saves a short "what changed" summary onto that version's
// deltaFromPrevious field (already read by MatterCard and the review page,
// just never populated before now). Never throws back to the caller —
// worst case, deltaFromPrevious just stays null, same as today.
export async function POST(req: NextRequest) {
  try {
    const { contractId, versionId, previousDriveFileId, newDriveFileId } = await req.json();
    if (!contractId || !versionId || !previousDriveFileId || !newDriveFileId) {
      return NextResponse.json(
        { error: 'contractId, versionId, previousDriveFileId, and newDriveFileId are required.' },
        { status: 400 }
      );
    }

    const [prev, next] = await Promise.all([
      downloadFileBuffer(previousDriveFileId),
      downloadFileBuffer(newDriveFileId),
    ]);
    const [previousText, newText] = await Promise.all([
      extractDocText(prev.buffer, prev.mimeType, prev.name),
      extractDocText(next.buffer, next.mimeType, next.name),
    ]);

    if (!previousText || !newText) {
      // Can't extract one or both (e.g. a scanned PDF or a format we don't
      // parse) — nothing to compare, not an error.
      return NextResponse.json({ delta: null });
    }

    const prompt = buildVersionDeltaPrompt({ previousText, newText });
    const message = await claude().messages.create({
      model: CLAUDE_MODEL,
      max_tokens: 400,
      messages: [{ role: 'user', content: prompt }],
    });
    const textBlock = message.content.find((b) => b.type === 'text');
    const delta = textBlock && textBlock.type === 'text' ? textBlock.text.trim() : null;

    await adminDb()
      .collection('contracts')
      .doc(contractId)
      .collection('versions')
      .doc(versionId)
      .update({ deltaFromPrevious: delta });

    return NextResponse.json({ delta });
  } catch (err) {
    console.error('review/version-delta failed', err);
    return NextResponse.json({ delta: null, error: err instanceof Error ? err.message : 'Delta failed.' });
  }
}
EOF
  echo "Wrote src/app/api/review/version-delta/route.ts"
fi

# ── 5. page.tsx — fetch the previous version's Drive file + fire the delta call ──
python3 - << 'PYEOF'
import re
path = "src/app/page.tsx"
with open(path) as f:
    content = f.read()

if "previousDriveFileId" in content:
    print("page.tsx: already wired up — nothing to do.")
else:
    # Add listVersionsForContract to whichever firestore import line already
    # imports getNextVersionNumber, regardless of its exact current shape.
    import_pattern = re.compile(r"import\s*\{[\s\S]*?getNextVersionNumber[\s\S]*?\}\s*from\s*'@/lib/firebase/firestore';")
    m = import_pattern.search(content)
    if not m:
        raise SystemExit("Could not find the firestore import line containing getNextVersionNumber — aborting.")
    import_block = m.group(0)
    if "listVersionsForContract" not in import_block:
        new_import_block = import_block.replace("{", "{ listVersionsForContract,", 1)
        content = content.replace(import_block, new_import_block)

    old_version_number = "      const versionNumber = isExistingMatter ? await getNextVersionNumber(contractId) : 1;"
    new_version_number = """      // Grab the current latest version's Drive file (if any) BEFORE adding
      // the new version below, so there's something to diff the new upload
      // against. Only relevant for an existing matter — a brand-new matter
      // has nothing prior to compare to.
      let previousDriveFileId: string | null = null;
      if (isExistingMatter) {
        const priorVersions = await listVersionsForContract(contractId);
        const priorLatest = priorVersions.reduce<typeof priorVersions[number] | null>(
          (max, v) => (!max || v.versionNumber > max.versionNumber ? v : max),
          null
        );
        previousDriveFileId = priorLatest?.driveFileId ?? null;
      }

      const versionNumber = isExistingMatter ? await getNextVersionNumber(contractId) : 1;"""

    old_catch = """      } catch {
        // Drive failures shouldn't block the reviewer from seeing results.
      }

      if (values.skipReview) {"""
    new_catch = """      } catch {
        // Drive failures shouldn't block the reviewer from seeing results.
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

      if (values.skipReview) {"""

    missing = [l for l, n in [("versionNumber line", old_version_number), ("drive catch block", old_catch)] if n not in content]
    if missing:
        raise SystemExit(f"Expected block(s) not found in page.tsx: {missing} — aborting.")

    content = content.replace(old_version_number, new_version_number).replace(old_catch, new_catch)
    with open(path, "w") as f:
        f.write(content)
    print("page.tsx: now fetches the previous version's Drive file and fires the delta computation after upload.")
PYEOF

# ── 6. Review page — "newer version exists" banner + delta callout ─────────
python3 - << 'PYEOF'
path = "src/app/review/[contractId]/[versionId]/page.tsx"
with open(path) as f:
    content = f.read()

if "versions.reduce" in content:
    print("review page: banner already present — nothing to do.")
else:
    old_import = "import { getContract, getVersion, getClient } from '@/lib/firebase/firestore';"
    new_import = "import { getContract, getVersion, getClient, listVersionsForContract } from '@/lib/firebase/firestore';"

    old_state = """  const [clientNotes, setClientNotes] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);"""
    new_state = """  const [clientNotes, setClientNotes] = useState<string | null>(null);
  const [versions, setVersions] = useState<VersionDoc[]>([]);
  const [error, setError] = useState<string | null>(null);"""

    old_effect = """        setContract(c);
        setVersion(v);
        const client = await getClient(c.clientId);
        if (!cancelled) setClientNotes(client?.notes ?? null);
      } catch {"""
    new_effect = """        setContract(c);
        setVersion(v);
        const client = await getClient(c.clientId);
        if (!cancelled) setClientNotes(client?.notes ?? null);
        const allVersions = await listVersionsForContract(contractId);
        if (!cancelled) setVersions(allVersions);
      } catch {"""

    old_guard = """  if (!contract || !version) {
    return <p className="font-mono text-sm text-ink-faint">Loading…</p>;
  }"""
    new_guard = """  if (!contract || !version) {
    return <p className="font-mono text-sm text-ink-faint">Loading…</p>;
  }

  const latestVersion = versions.reduce<VersionDoc | null>(
    (max, v) => (!max || v.versionNumber > max.versionNumber ? v : max),
    null
  );
  const isLatest = !latestVersion || latestVersion.id === version.id;"""

    old_meta = """      <p className="-mt-4 mb-6 font-mono text-xs text-ink-faint">
        {contract.clientName} — {contract.projectName} ({contract.projectNumber}) · Counterparty: {contract.counterparty}
      </p>
      <ResultsView"""
    new_meta = """      <p className="-mt-4 mb-6 font-mono text-xs text-ink-faint">
        {contract.clientName} — {contract.projectName} ({contract.projectNumber}) · Counterparty: {contract.counterparty}
      </p>
      {!isLatest && latestVersion && (
        <div className="mb-6 border border-accent/30 bg-high-bg px-4 py-3">
          <p className="font-mono text-xs text-ink">
            A newer version (v{latestVersion.versionNumber}) of this matter is on file.{' '}
            <Link href={`/review/${contractId}/${latestVersion.id}`} className="text-accent hover:underline">
              View it →
            </Link>
          </p>
        </div>
      )}
      {version.deltaFromPrevious && (
        <div className="mb-6 border border-rule bg-paper px-4 py-3">
          <p className="font-mono text-[11px] uppercase tracking-wide text-ink-faint">What changed in this version</p>
          <p className="mt-1 font-body text-sm text-ink-soft">{version.deltaFromPrevious}</p>
        </div>
      )}
      <ResultsView"""

    missing = [
        l for l, n in [
            ("import", old_import),
            ("state", old_state),
            ("effect", old_effect),
            ("loading guard", old_guard),
            ("meta/ResultsView", old_meta),
        ] if n not in content
    ]
    if missing:
        raise SystemExit(f"Expected block(s) not found in the review page: {missing} — aborting.")

    content = (
        content.replace(old_import, new_import)
        .replace(old_state, new_state)
        .replace(old_effect, new_effect)
        .replace(old_guard, new_guard)
        .replace(old_meta, new_meta)
    )
    with open(path, "w") as f:
        f.write(content)
    print("review page: added the 'newer version exists' banner and the what-changed callout.")
PYEOF

echo ""
echo "Restart your dev server and test on a matter with 2+ versions:"
echo "  1. Upload a new version to an EXISTING matter (either review mode"
echo "     or file-without-review). Give it a few seconds after it lands on"
echo "     results/filed — the delta call runs in the background."
echo "  2. Open that matter in the Library, expand it — the new version"
echo "     should show 'Δ ...' text summarizing what changed (or 'No"
echo "     substantive changes from the previous version' if it's a near-"
echo "     duplicate re-upload)."
echo "  3. Open an OLDER version's review page directly (Library → matter →"
echo "     expand → click an older version's 'View results') — you should"
echo "     see a banner pointing to the newer version, plus the what-changed"
echo "     callout if that version has one."
echo ""
echo "Then commit and push (via GitHub Desktop) to deploy."
