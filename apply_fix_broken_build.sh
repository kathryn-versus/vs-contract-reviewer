#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_fix_broken_build.sh
set -e

# ── 1. page.tsx — move listVersionsForContract to the correct import ───────
python3 - << 'PYEOF'
path = "src/app/page.tsx"
with open(path) as f:
    content = f.read()

if "listVersionsForContract, Suspense, useState" in content:
    old_react = "import { listVersionsForContract, Suspense, useState } from 'react';"
    new_react = "import { Suspense, useState } from 'react';"

    old_firestore = """import {
  getOrCreateClient,
  createContract,
  addVersion,
  updateContractDrive,
  updateVersionDrive,
  getClient,
  getNextVersionNumber,
} from '@/lib/firebase/firestore';"""
    new_firestore = """import {
  getOrCreateClient,
  createContract,
  addVersion,
  updateContractDrive,
  updateVersionDrive,
  getClient,
  getNextVersionNumber,
  listVersionsForContract,
} from '@/lib/firebase/firestore';"""

    missing = [l for l, n in [("react import", old_react), ("firestore import", old_firestore)] if n not in content]
    if missing:
        raise SystemExit(f"Expected block(s) not found in page.tsx: {missing} — aborting.")

    content = content.replace(old_react, new_react).replace(old_firestore, new_firestore)
    with open(path, "w") as f:
        f.write(content)
    print("page.tsx: moved listVersionsForContract to the Firestore import where it belongs.")
elif "import { listVersionsForContract" in content:
    raise SystemExit("Found an unexpected variant of the broken import — paste me the current top of page.tsx and I'll fix it by hand.")
else:
    print("page.tsx: already fixed — nothing to do.")
PYEOF

# ── 2. firestore.ts — add the missing ExecutedAgreementDoc type import ─────
python3 - << 'PYEOF'
path = "src/lib/firebase/firestore.ts"
with open(path) as f:
    content = f.read()

old = "import type { ClientDoc, ContractDoc, VersionDoc, Finding, IssueThreadDoc, ThreadMessage, UserDoc, Role } from '../types';"
new = "import type { ClientDoc, ContractDoc, VersionDoc, Finding, IssueThreadDoc, ThreadMessage, UserDoc, Role, ExecutedAgreementDoc } from '../types';"

if "ExecutedAgreementDoc" in content and old not in content:
    print("firestore.ts: already fixed — nothing to do.")
elif old not in content:
    raise SystemExit("Expected type import line not found in firestore.ts — aborting.")
else:
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print("firestore.ts: added ExecutedAgreementDoc to the types import.")
PYEOF

echo ""
echo "Now verify the build actually passes before pushing again:"
echo "  npm run build"
echo ""
echo "It should complete with 'Compiled successfully' and no type errors."
echo "If it does, commit and push (via GitHub Desktop) — this should finally"
echo "produce a successful rollout in Firebase App Hosting instead of the"
echo "last 5 failed builds."
