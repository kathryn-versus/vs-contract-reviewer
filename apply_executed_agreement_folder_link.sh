#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_executed_agreement_folder_link.sh
set -e

# ── 1. types.ts — ExecutedAgreementDoc gets a folder link ───────────────────
python3 - << 'PYEOF'
path = "src/lib/types.ts"
with open(path) as f:
    content = f.read()

# Scoped to the ExecutedAgreementDoc block specifically — ContractDoc already
# has an unrelated field of the same name, so a plain substring check against
# the whole file would false-positive on that and skip this edit.
import re
executed_block_match = re.search(r"export interface ExecutedAgreementDoc \{[\s\S]*?\n\}", content)
already_done = executed_block_match and "driveFolderUrl" in executed_block_match.group(0)

if already_done:
    print("types.ts: already present — nothing to do.")
else:
    old = """  driveFileId: string;
  driveUrl: string;
  // Which job this is filed under — required for SOW/Change Order (always
  // job-specific), null for MSA/Other left at the client level (an MSA
  // typically governs many jobs, not just one).
  projectNumber: string | null;
  projectName: string | null;"""
    new = """  driveFileId: string;
  driveUrl: string;
  // Link to the Drive folder this was filed in — the matter's doc-type
  // folder when a project was picked, otherwise the client's doc-type
  // folder — so you can jump to what else is filed alongside it without
  // having to click through from the file itself.
  driveFolderUrl: string | null;
  // Which job this is filed under — required for SOW/Change Order (always
  // job-specific), null for MSA/Other left at the client level (an MSA
  // typically governs many jobs, not just one).
  projectNumber: string | null;
  projectName: string | null;"""
    if old not in content:
        raise SystemExit("Expected ExecutedAgreementDoc block not found in types.ts — aborting.")
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print("types.ts: added driveFolderUrl to ExecutedAgreementDoc.")
PYEOF

# ── 2. upload-executed-agreement route — also return the folder link ────────
python3 - << 'PYEOF'
path = "src/app/api/drive/upload-executed-agreement/route.ts"
with open(path) as f:
    content = f.read()

if "getFolderLink" in content:
    print("upload-executed-agreement/route.ts: already present — nothing to do.")
else:
    old_import = "import { ensureClientFolder, ensureMatterFolder, ensureDocTypeFolder, uploadFileToFolder } from '@/lib/drive/client';"
    new_import = "import { ensureClientFolder, ensureMatterFolder, ensureDocTypeFolder, uploadFileToFolder, getFolderLink } from '@/lib/drive/client';"

    old_upload = """    const { fileId, webViewLink } = await uploadFileToFolder({
      folderId: targetFolderId,
      fileName: `Executed — ${namePrefix} — ${file.name}`,
      mimeType: file.type || 'application/octet-stream',
      buffer,
    });

    return NextResponse.json({ driveFileId: fileId, driveUrl: webViewLink });"""
    new_upload = """    const { fileId, webViewLink } = await uploadFileToFolder({
      folderId: targetFolderId,
      fileName: `Executed — ${namePrefix} — ${file.name}`,
      mimeType: file.type || 'application/octet-stream',
      buffer,
    });
    const driveFolderUrl = await getFolderLink(targetFolderId);

    return NextResponse.json({ driveFileId: fileId, driveUrl: webViewLink, driveFolderUrl });"""

    missing = [l for l, n in [("import", old_import), ("upload block", old_upload)] if n not in content]
    if missing:
        raise SystemExit(f"Expected block(s) not found in upload-executed-agreement/route.ts: {missing} — aborting.")

    content = content.replace(old_import, new_import).replace(old_upload, new_upload)
    with open(path, "w") as f:
        f.write(content)
    print("upload-executed-agreement/route.ts: now returns driveFolderUrl too.")
PYEOF

# ── 3. ClientDetailView.tsx — store it and show a Folder link ───────────────
python3 - << 'PYEOF'
path = "src/components/library/ClientDetailView.tsx"
with open(path) as f:
    content = f.read()

if "a.driveFolderUrl" in content:
    print("ClientDetailView.tsx: already present — nothing to do.")
else:
    old_handler = """      await addExecutedAgreement(clientId, {
        docType: agreementDocType,
        label: agreementLabel.trim(),
        driveFileId: data.driveFileId,
        driveUrl: data.driveUrl,
        projectNumber: project?.projectNumber ?? null,
        projectName: project?.projectName ?? null,
        executedDate: null,
        uploadedBy: { name: user?.displayName ?? user?.email ?? '', email: user?.email ?? '' },
      });"""
    new_handler = """      await addExecutedAgreement(clientId, {
        docType: agreementDocType,
        label: agreementLabel.trim(),
        driveFileId: data.driveFileId,
        driveUrl: data.driveUrl,
        driveFolderUrl: data.driveFolderUrl ?? null,
        projectNumber: project?.projectNumber ?? null,
        projectName: project?.projectName ?? null,
        executedDate: null,
        uploadedBy: { name: user?.displayName ?? user?.email ?? '', email: user?.email ?? '' },
      });"""

    old_list_item = """                  <a
                    href={a.driveUrl}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="font-body text-sm text-accent hover:underline"
                  >
                    {a.label || a.docType} ↗
                  </a>
                </div>"""
    new_list_item = """                  <a
                    href={a.driveUrl}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="font-body text-sm text-accent hover:underline"
                  >
                    {a.label || a.docType} ↗
                  </a>
                  {a.driveFolderUrl && (
                    <a
                      href={a.driveFolderUrl}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="ml-2 font-mono text-[10px] text-ink-faint hover:text-ink hover:underline"
                    >
                      Folder ↗
                    </a>
                  )}
                </div>"""

    missing = [l for l, n in [("handler", old_handler), ("list item", old_list_item)] if n not in content]
    if missing:
        raise SystemExit(f"Expected block(s) not found in ClientDetailView.tsx: {missing} — aborting.")

    content = content.replace(old_handler, new_handler).replace(old_list_item, new_list_item)
    with open(path, "w") as f:
        f.write(content)
    print("ClientDetailView.tsx: executed agreements now show a Folder link next to the file link.")
PYEOF

echo ""
echo "Restart your dev server and upload a new executed agreement — the list"
echo "entry should now show both the file link and a smaller 'Folder ↗' link"
echo "next to it, pointing at the Drive folder it was filed in. Agreements"
echo "uploaded before this change won't have a folder link (nothing was"
echo "stored for them) — that's expected, only new uploads get one."
echo ""
echo "Then commit and push (via GitHub Desktop) to deploy."
