#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_fix_timezone.sh
set -e

python3 - << 'PYEOF'
path = "src/lib/drive/client.ts"
with open(path) as f:
    content = f.read()

old = """function folderTimestamp(d: Date): string {
  // YYYY-MM-DD HHhMMm, local time. Kept in 24-hour, zero-padded form so
  // folder names still sort correctly in Drive's alphabetical listing — a
  // 12-hour AM/PM format sorts wrong across the noon boundary (e.g.
  // "9:05am" would alphabetically land after "2:32pm" as plain text). The
  // "h"/"m" letters are just there so it visibly reads as a time instead of
  // looking like an arbitrary numeric code.
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}h${pad(d.getMinutes())}m`;
}"""

new = """function folderTimestamp(d: Date): string {
  // YYYY-MM-DD HHhMMm, always in America/New_York regardless of the
  // server's own clock. Firebase App Hosting runs the Node process in UTC,
  // so without this, folder names would be ~4-5 hours ahead of actual NYC
  // time (and near midnight could even land on the wrong calendar date
  // entirely — e.g. an 11:54 PM upload getting stamped as 03h54m the NEXT
  // day). Intl.DateTimeFormat handles the EST/EDT daylight-saving switch
  // automatically, so this doesn't need manual offset math. Kept in
  // 24-hour, zero-padded form so folder names still sort correctly in
  // Drive's alphabetical listing — a 12-hour AM/PM format sorts wrong
  // across the noon boundary (e.g. "9:05am" would alphabetically land
  // after "2:32pm" as plain text). The "h"/"m" letters are just there so it
  // visibly reads as a time instead of looking like an arbitrary numeric
  // code.
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: 'America/New_York',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).formatToParts(d);
  const get = (type: string) => parts.find((p) => p.type === type)?.value ?? '00';
  // Some environments return "24" for midnight under hour12: false instead
  // of "00" — normalize just in case.
  const hour = get('hour') === '24' ? '00' : get('hour');
  return `${get('year')}-${get('month')}-${get('day')} ${hour}h${get('minute')}m`;
}"""

if "America/New_York" in content:
    print("client.ts: folderTimestamp already uses America/New_York — nothing to do.")
elif old in content:
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print("client.ts: folderTimestamp now always formats in America/New_York time.")
else:
    raise SystemExit(
        "Expected folderTimestamp function not found in src/lib/drive/client.ts "
        "— aborting. Paste me the current file and I'll fix it by hand."
    )
PYEOF

echo ""
echo "Restart your dev server, upload a test file, and confirm the new Drive"
echo "subfolder's timestamp matches your actual NYC time. Then commit and"
echo "push (via GitHub Desktop) to trigger a new rollout."
