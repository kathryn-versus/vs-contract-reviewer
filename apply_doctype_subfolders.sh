#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_doctype_subfolders.sh
set -e

# ── 1. drive/client.ts — new helper for a doc-type subfolder under a matter ──
python3 - << 'PYEOF'
path = "src/lib/drive/client.ts"
with open(path) as f:
    content = f.read()

if "ensureDocTypeFolder" in content:
    print("drive/client.ts: already present — nothing to do.")
else:
    old = """/**
 * Ensures a timestamped subfolder (down to the second) exists under a matter
 * folder, so every review run — the uploaded source file, its Google Doc
 * duplicate, and a copy of the generated report — gets its own folder
 * instead of multiple same-day runs piling into one shared date folder.
 * Makes the most recent run obvious at a glance in Drive's default
 * alphabetical sort.
 */
export async function ensureDatedReviewFolder(matterFolderId: string, when: Date = new Date()): Promise<string> {
  return findOrCreateFolder(folderTimestamp(when), matterFolderId);
}"""
    new = """/**
 * Ensures a timestamped subfolder (down to the second) exists under a matter
 * folder, so every review run — the uploaded source file, its Google Doc
 * duplicate, and a copy of the generated report — gets its own folder
 * instead of multiple same-day runs piling into one shared date folder.
 * Makes the most recent run obvious at a glance in Drive's default
 * alphabetical sort.
 */
export async function ensureDatedReviewFolder(matterFolderId: string, when: Date = new Date()): Promise<string> {
  return findOrCreateFolder(folderTimestamp(when), matterFolderId);
}

/**
 * Ensures a document-type subfolder (MSA / SOW / Change Order / etc.) exists
 * directly under a Job's matter folder — Contract Reviews/{Client}/{Job
 * Number — Project}/{Doc Type}/ — so multiple different documents filed
 * under the same job (an MSA, a SOW, several Change Orders) land in their
 * own clearly separated space instead of one flat timestamped list where
 * it's not obvious what's what. Dated review-run folders then nest one
 * level further inside this, per upload.
 */
export async function ensureDocTypeFolder(matterFolderId: string, docType: string): Promise<string> {
  return findOrCreateFolder(docType, matterFolderId);
}"""
    if old not in content:
        raise SystemExit("Expected ensureDatedReviewFolder block not found in drive/client.ts — aborting.")
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print("drive/client.ts: added ensureDocTypeFolder.")
PYEOF

# ── 2. /api/drive/upload/route.ts — nest under the doc-type folder ─────────
python3 - << 'PYEOF'
path = "src/app/api/drive/upload/route.ts"
with open(path) as f:
    content = f.read()

if "ensureDocTypeFolder" in content:
    print("upload/route.ts: already updated — nothing to do.")
else:
    old_import = "import { ensureMatterFolder, ensureDatedReviewFolder, uploadFileToFolder, getFolderLink } from '@/lib/drive/client';"
    new_import = "import { ensureMatterFolder, ensureDocTypeFolder, ensureDatedReviewFolder, uploadFileToFolder, getFolderLink } from '@/lib/drive/client';"

    old_fields = """    const projectNumber = form.get('projectNumber') as string | null;
    const versionSuffix = (form.get('versionSuffix') as string | null) ?? '';"""
    new_fields = """    const projectNumber = form.get('projectNumber') as string | null;
    const versionSuffix = (form.get('versionSuffix') as string | null) ?? '';
    const docType = (form.get('docType') as string | null) ?? null;"""

    old_folders = """    const projectLabel = `${projectNumber} — ${projectName}`;
    const { matterFolderId } = await ensureMatterFolder(clientName, projectLabel);
    // Nest this review's files under a dated subfolder — Contract
    // Reviews/{Client}/{Job Number — Project}/{YYYY-MM-DD}/ — so the source
    // file, its Google Doc duplicate, and the report copy all land together.
    const dateFolderId = await ensureDatedReviewFolder(matterFolderId);"""
    new_folders = """    const projectLabel = `${projectNumber} — ${projectName}`;
    const { matterFolderId } = await ensureMatterFolder(clientName, projectLabel);
    // Nest under a doc-type subfolder first — Contract Reviews/{Client}/{Job
    // Number — Project}/{Doc Type}/ — so an MSA, a SOW, and however many
    // Change Orders end up filed under the same job land in clearly
    // separated folders rather than one undifferentiated pile. Falls back
    // to the matter folder itself if no docType was sent (keeps this route
    // working for any caller that hasn't been updated to send one yet).
    const docTypeFolderId = docType ? await ensureDocTypeFolder(matterFolderId, docType) : matterFolderId;
    // Then nest THIS review's files under a dated subfolder — .../{Doc
    // Type}/{YYYY-MM-DD HHhMMm}/ — so the source file, its Google Doc
    // duplicate, and the report copy all land together per upload.
    const dateFolderId = await ensureDatedReviewFolder(docTypeFolderId);"""

    missing = [l for l, n in [("import", old_import), ("form fields", old_fields), ("folder chain", old_folders)] if n not in content]
    if missing:
        raise SystemExit(f"Expected block(s) not found in upload/route.ts: {missing} — aborting.")

    content = content.replace(old_import, new_import).replace(old_fields, new_fields).replace(old_folders, new_folders)
    with open(path, "w") as f:
        f.write(content)
    print("upload/route.ts: now nests uploads under a doc-type subfolder before the dated run folder.")
PYEOF

# ── 3. page.tsx — send docType along with the upload ────────────────────────
python3 - << 'PYEOF'
path = "src/app/page.tsx"
with open(path) as f:
    content = f.read()

if "form.append('docType'" in content:
    print("page.tsx: already sends docType — nothing to do.")
else:
    old = """        form.append('projectNumber', values.projectNumber);
        if (versionNumber > 1) form.append('versionSuffix', `v${versionNumber}`);"""
    new = """        form.append('projectNumber', values.projectNumber);
        form.append('docType', values.docType);
        if (versionNumber > 1) form.append('versionSuffix', `v${versionNumber}`);"""
    if old not in content:
        raise SystemExit("Expected form-append block not found in page.tsx — aborting.")
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print("page.tsx: now sends docType to the Drive upload route.")
PYEOF

# ── 4. BatchImportView.tsx — same, best-effort (won't break the rest if the shape differs) ──
python3 - << 'PYEOF'
import re
path = "src/components/intake/BatchImportView.tsx"
with open(path) as f:
    content = f.read()

if "form.append('docType'" in content:
    print("BatchImportView.tsx: already sends docType — nothing to do.")
else:
    m = re.search(r"form\.append\('projectNumber',[^)]*\);", content)
    if not m:
        print("NOTE: could not find the projectNumber form.append(...) line in BatchImportView.tsx —")
        print("      skipping this one file. Batch-imported files will still land under the matter")
        print("      folder without a doc-type subfolder until this is added by hand.")
    else:
        anchor = m.group(0)
        # Try the common field name first; fall back to a generic guess and
        # say so, since this file's exact row-state shape wasn't confirmed.
        guess = "form.append('docType', row.docType);"
        new_anchor = anchor + "\n        " + guess
        content = content.replace(anchor, new_anchor, 1)
        with open(path, "w") as f:
            f.write(content)
        print("BatchImportView.tsx: added a docType append guessing the field is 'row.docType' —")
        print("      if `npm run build` errors on this line, tell me the actual field name and I'll fix it.")
PYEOF

echo ""
echo "Run npm run build locally before pushing. Then test on the live site:"
echo "  1. Run a normal SOW review for a job — in Drive, confirm the path is"
echo "     now Contract Reviews/{Client}/{Job Number — Project}/SOW/{dated"
echo "     folder}/, not directly .../{Job Number — Project}/{dated folder}/."
echo "  2. Run (or simulate) a Change Order upload under the same job number"
echo "     — it should land in a sibling 'Change Order' folder next to 'SOW',"
echo "     same job, cleanly separated."
echo ""
echo "Then commit and push (via GitHub Desktop) to deploy."
