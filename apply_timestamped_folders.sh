#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_timestamped_folders.sh
set -e

python3 - << 'PYEOF'
path = "src/lib/drive/client.ts"
with open(path) as f:
    content = f.read()

if "folderTimestamp" in content:
    print("client.ts: already using timestamped folders — nothing to do.")
else:
    old = """function isoDate(d: Date): string {
  return d.toISOString().slice(0, 10); // YYYY-MM-DD
}

/**
 * Ensures a dated subfolder exists under a matter folder so everything from
 * one review run (the uploaded source file, its Google Doc duplicate, and a
 * copy of the generated report) lands together instead of piling up flat in
 * the project folder. Reused as-is if a review already ran that day.
 */
export async function ensureDatedReviewFolder(matterFolderId: string, when: Date = new Date()): Promise<string> {
  return findOrCreateFolder(isoDate(when), matterFolderId);
}"""

    new = """function folderTimestamp(d: Date): string {
  // YYYY-MM-DD HH-MM-SS, local time, colons avoided (Drive allows them, but
  // some sync tools/filesystems don't) — zero-padded so folder names still
  // sort chronologically when Drive lists them alphabetically.
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}-${pad(d.getMinutes())}-${pad(d.getSeconds())}`;
}

/**
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

    if old not in content:
        raise SystemExit(
            "Expected isoDate/ensureDatedReviewFolder block not found in "
            "src/lib/drive/client.ts — aborting so nothing is silently "
            "corrupted. Paste me the current file and I'll fix it by hand."
        )
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print("client.ts: folders are now timestamped down to the second.")
PYEOF

echo ""
echo "Restart your dev server (Ctrl+C, then npm run dev) and run a fresh"
echo "review — the per-run Drive folder under the job's folder will now be"
echo "named like '2026-07-06 14-32-05' instead of just '2026-07-06', so"
echo "multiple runs on the same day each get their own folder and the newest"
echo "one is always obvious."
echo ""
echo "Note: this only affects NEW review runs — folders already created with"
echo "just a date (no time) are untouched."
