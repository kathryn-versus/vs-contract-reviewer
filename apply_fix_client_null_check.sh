#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_fix_client_null_check.sh
set -e

python3 - << 'PYEOF'
path = "src/components/library/ClientDetailView.tsx"
with open(path) as f:
    content = f.read()

old = """  async function handleToggleGoverningMsa(contractId: string) {
    if (client.msaContractId === contractId) {"""

new = """  async function handleToggleGoverningMsa(contractId: string) {
    if (!client) return;
    if (client.msaContractId === contractId) {"""

if "if (!client) return;" in content:
    print("ClientDetailView.tsx: already fixed — nothing to do.")
elif old in content:
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print("ClientDetailView.tsx: added null guard.")
else:
    raise SystemExit(
        "Expected function body not found in "
        "src/components/library/ClientDetailView.tsx — aborting. Paste me the "
        "current file and I'll fix it by hand."
    )
PYEOF

echo ""
echo "Restart your dev server if it's running to confirm nothing broke locally,"
echo "then commit and push (via GitHub Desktop) to trigger the next rollout."
