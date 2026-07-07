#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_fix_last_tsc_errors.sh
set -e

# ── 1. mammoth/mammoth.browser has no shipped types (same as pdf-parse) ─────

mkdir -p "src/types"
cat > "src/types/mammoth-browser.d.ts" << 'VS_APPLY_EOF_mammoth'
// mammoth's browser build doesn't ship its own TypeScript types under this
// subpath — same situation as pdf-parse. Declaring it as untyped (implicit
// any) is enough to satisfy the stricter production build's type check.
declare module 'mammoth/mammoth.browser';
VS_APPLY_EOF_mammoth

echo "Added src/types/mammoth-browser.d.ts"

# ── 2. react-pdf's pdf() has an overly-strict type signature ────────────────

python3 - << 'PYEOF'
path = "src/lib/report/generatePdf.ts"
with open(path) as f:
    content = f.read()

old = "  const blob = await pdf(element).toBlob();"
new = """  // react-pdf's pdf() type signature expects a <Document> element directly.
  // ContractReportPdf is a component that renders one internally, so what it
  // produces at runtime is correct, but its own prop types don't structurally
  // match DocumentProps — a known friction point with this library. Cast to
  // bypass the overly strict check rather than fight react-pdf's types.
  const blob = await pdf(element as Parameters<typeof pdf>[0]).toBlob();"""

if "Parameters<typeof pdf>[0]" in content:
    print("generatePdf.ts: already fixed — nothing to do.")
elif old in content:
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print("generatePdf.ts: cast added.")
else:
    raise SystemExit(
        "Expected line not found in src/lib/report/generatePdf.ts — aborting. "
        "Paste me the current file and I'll fix it by hand."
    )
PYEOF

echo ""
echo "Now run 'npx tsc --noEmit' again to confirm zero errors remain, then"
echo "restart your dev server to confirm nothing broke locally, then commit"
echo "and push (via GitHub Desktop) to trigger the next rollout."
