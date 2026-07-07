#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_friendlier_timestamp.sh
set -e

python3 - << 'PYEOF'
path = "src/lib/drive/client.ts"
with open(path) as f:
    content = f.read()

if "pad(d.getHours())}h${pad(d.getMinutes())}m" in content:
    print("client.ts: already using the h/m format — nothing to do.")
else:
    old = """function folderTimestamp(d: Date): string {
  // YYYY-MM-DD HH-MM-SS, local time, colons avoided (Drive allows them, but
  // some sync tools/filesystems don't) — zero-padded so folder names still
  // sort chronologically when Drive lists them alphabetically.
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}-${pad(d.getMinutes())}-${pad(d.getSeconds())}`;
}"""

    new = """function folderTimestamp(d: Date): string {
  // YYYY-MM-DD HHhMMm, local time. Kept in 24-hour, zero-padded form so
  // folder names still sort correctly in Drive's alphabetical listing — a
  // 12-hour AM/PM format sorts wrong across the noon boundary (e.g.
  // "9:05am" would alphabetically land after "2:32pm" as plain text). The
  // "h"/"m" letters are just there so it visibly reads as a time instead of
  // looking like an arbitrary numeric code.
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}h${pad(d.getMinutes())}m`;
}"""

    if old not in content:
        raise SystemExit(
            "Expected folderTimestamp block not found in src/lib/drive/client.ts "
            "— aborting so nothing is silently corrupted. Paste me the current "
            "file and I'll fix it by hand."
        )
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print("client.ts: folder timestamps now read like '2026-07-06 14h32m'.")
PYEOF

echo ""
echo "Restart your dev server (Ctrl+C, then npm run dev) and run a fresh"
echo "review — new per-run folders will be named like '2026-07-06 14h32m'"
echo "(2:32 PM, 24-hour) instead of '2026-07-06 14-32-05'."
