#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_fix_doctype_build_error.sh
set -e

python3 - << 'PYEOF'
path = "src/app/page.tsx"
with open(path) as f:
    content = f.read()

if "docType: DocType;" in content:
    print("page.tsx: already fixed — nothing to do.")
else:
    old_import = "import { STANDING_CONCERNS } from '@/lib/types';\nimport type { Finding } from '@/lib/types';"
    new_import = "import { STANDING_CONCERNS } from '@/lib/types';\nimport type { Finding, DocType } from '@/lib/types';"

    old_field = "    docType: string;"
    new_field = "    docType: DocType;"

    if old_import not in content or old_field not in content:
        raise SystemExit(
            "Expected import/field not found in src/app/page.tsx — aborting so "
            "nothing is silently corrupted. Paste me the current file and I'll "
            "fix it by hand."
        )

    content = content.replace(old_import, new_import)
    content = content.replace(old_field, new_field)
    with open(path, "w") as f:
        f.write(content)
    print("page.tsx: docType now correctly typed as DocType instead of string.")
PYEOF

echo ""
echo "Restart your dev server if it's running to confirm nothing broke locally,"
echo "then commit and push (via GitHub Desktop) — that'll trigger the next"
echo "rollout automatically."
