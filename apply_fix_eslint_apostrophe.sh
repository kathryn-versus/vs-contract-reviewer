#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_fix_eslint_apostrophe.sh
set -e

python3 - << 'PYEOF'
path = "src/components/intake/IntakeForm.tsx"
with open(path) as f:
    content = f.read()

old = "If this is the same contract, open it above instead of running a new review. If it's genuinely"
new = "If this is the same contract, open it above instead of running a new review. If it is genuinely"

if new in content and old not in content:
    print("IntakeForm.tsx: already fixed — nothing to do.")
elif old in content:
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print("IntakeForm.tsx: fixed unescaped apostrophe.")
else:
    raise SystemExit(
        "Expected sentence not found in src/components/intake/IntakeForm.tsx — "
        "aborting. Paste me the current file and I'll fix it by hand."
    )
PYEOF

echo ""
echo "Restart your dev server if it's running, then:"
echo "  git add src/components/intake/IntakeForm.tsx"
echo "  git commit -m \"Fix ESLint unescaped-entities build error\""
echo "  (push via GitHub Desktop)"
echo "This push will trigger a new App Hosting rollout automatically."
