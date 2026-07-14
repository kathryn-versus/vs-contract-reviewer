#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_hide_dashboard.sh
set -e

python3 - << 'PYEOF'
path = "src/components/layout/TopNav.tsx"
with open(path) as f:
    content = f.read()

old = "              {navLink('/dashboard', 'Dashboard')}\n              {navLink('/library', 'Library')}"
new = "              {navLink('/library', 'Library')}"

if "{navLink('/dashboard', 'Dashboard')}" not in content:
    print("TopNav.tsx: Dashboard link already removed — nothing to do.")
elif old not in content:
    raise SystemExit("Expected nav block not found in TopNav.tsx — aborting.")
else:
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print("TopNav.tsx: removed the Dashboard nav link (page/code left in place for later).")
PYEOF

echo ""
echo "The /dashboard page and all its code are untouched — just not linked"
echo "from the nav anymore, so it's out of the way until you want it back."
echo "To restore it later, just add back:"
echo "  {navLink('/dashboard', 'Dashboard')}"
echo "right before the Library link in src/components/layout/TopNav.tsx."
echo ""
echo "Then commit and push (via GitHub Desktop) to deploy."
