#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_fix_batchimport_build.sh
set -e

python3 - << 'PYEOF'
path = "src/components/intake/BatchImportView.tsx"
with open(path) as f:
    content = f.read()

if "insuranceRequirements: []," in content:
    print("BatchImportView.tsx: already fixed — nothing to do.")
else:
    old = """          characterCount: 0,
          findings: [],
          deltaFromPrevious: null,
          reviewed: false,"""
    new = """          characterCount: 0,
          findings: [],
          insuranceRequirements: [],
          deltaFromPrevious: null,
          reviewed: false,"""
    if old not in content:
        raise SystemExit("Expected block not found in BatchImportView.tsx — aborting.")
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print("BatchImportView.tsx: added the missing insuranceRequirements field.")
PYEOF

echo ""
echo "Run npm run build again — it should get further this time. If it hits"
echo "another missing-field error somewhere else, paste me that error and"
echo "I'll fix that spot too the same way."
