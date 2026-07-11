#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_fix_nav_dark_bg.sh
set -e

python3 - << 'PYEOF'
path = "src/components/layout/TopNav.tsx"
with open(path) as f:
    content = f.read()

old = '    <header className="sticky top-0 z-30 border-b-2 border-chrome-accent bg-chrome/95 backdrop-blur">'
new = (
    "    // bg-chrome (no opacity modifier) — the /95 variant silently\n"
    "    // failed to apply any background at all here, since --chrome-bg is a\n"
    "    // plain hex CSS variable rather than the space-separated R G B format\n"
    "    // Tailwind's opacity-modifier syntax needs. Full-opacity solid works\n"
    "    // fine and a sticky nav doesn't need to be see-through anyway.\n"
    '    <header className="sticky top-0 z-30 border-b-2 border-chrome-accent bg-chrome">'
)

if old not in content:
    if 'bg-chrome"' in content and 'bg-chrome/95' not in content:
        print("TopNav.tsx: already fixed — nothing to do.")
    else:
        raise SystemExit(
            "Expected header line not found in "
            "src/components/layout/TopNav.tsx — aborting. Paste me the "
            "current file and I'll fix it by hand."
        )
else:
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print("TopNav.tsx: nav background is now solid bg-chrome (no failing opacity modifier).")
PYEOF

echo ""
echo "Restart your dev server and confirm the nav is now solid near-black"
echo "with white/gold text and the gold underline. Then commit and push"
echo "(via GitHub Desktop) to deploy."
